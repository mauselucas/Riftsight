import AppKit
import AVFoundation
import Foundation

public struct RecordingItem: Sendable, Hashable, Identifiable {
    public let url: URL
    public var metadata: ClipMetadata
    public let fileSize: Int64
    public var thumbnail: URL?
    public var id: URL { url }
}

/// Clips and full games under `~/Movies/Riftsight`, with JSON sidecars and cached thumbnails.
@MainActor
@Observable
public final class RecordingLibrary {
    public private(set) var items: [RecordingItem] = []
    public var storageQuotaGB: Double = 20

    public init() {}

    public var clipsDirectory: URL { Self.folder("Clips") }
    public var fullGamesDirectory: URL { Self.folder("Full Games") }

    static func folder(_ name: String) -> URL {
        let url = AppPaths.recordings.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public var usedBytes: Int64 { items.reduce(0) { $0 + $1.fileSize } }

    public func reload() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var found: [RecordingItem] = []
        for dir in [clipsDirectory, fullGamesDirectory] {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey])) ?? []
            for file in files where file.pathExtension == "mp4" {
                let sidecar = file.deletingPathExtension().appendingPathExtension("json")
                let meta = (try? Data(contentsOf: sidecar)).flatMap { try? decoder.decode(ClipMetadata.self, from: $0) }
                    ?? ClipMetadata(kind: dir == clipsDirectory ? .clip : .fullGame, title: file.deletingPathExtension().lastPathComponent,
                                    createdAt: (try? file.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now)
                let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                let thumb = file.deletingPathExtension().appendingPathExtension("jpg")
                found.append(RecordingItem(url: file, metadata: meta, fileSize: size,
                                           thumbnail: FileManager.default.fileExists(atPath: thumb.path) ? thumb : nil))
            }
        }
        items = found.sorted { $0.metadata.createdAt > $1.metadata.createdAt }
    }

    public func toggleFavorite(_ item: RecordingItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items[index].metadata.favorite.toggle()
        writeSidecar(items[index].metadata, for: item.url)
    }

    public func delete(_ item: RecordingItem) {
        for ext in ["mp4", "json", "jpg"] {
            try? FileManager.default.removeItem(at: item.url.deletingPathExtension().appendingPathExtension(ext))
        }
        items.removeAll { $0.url == item.url }
    }

    func writeSidecar(_ meta: ClipMetadata, for video: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(meta) {
            try? data.write(to: video.deletingPathExtension().appendingPathExtension("json"), options: .atomic)
        }
    }

    /// Concatenates segments (passthrough, no re-encode), optionally keeping only the last `trimTo` seconds.
    public func export(segments: [RecordingSegment], trimTo: Double?, metadata: ClipMetadata) async {
        let directory = metadata.kind == .clip ? clipsDirectory : fullGamesDirectory
        let stamp = ISO8601DateFormatter().string(from: metadata.createdAt).replacingOccurrences(of: ":", with: "-")
        let safeTitle = metadata.title.replacingOccurrences(of: "/", with: "-").prefix(60)
        let output = directory.appendingPathComponent("\(stamp) \(safeTitle).mp4")
        do {
            let duration = try await Self.concatenate(segments.map(\.url), trimTo: trimTo, output: output)
            var meta = metadata
            meta.duration = duration
            writeSidecar(meta, for: output)
            await Self.writeThumbnail(for: output)
            DebugLog.shared.add("recording", "Gespeichert: \(output.lastPathComponent)")
            reload()
        } catch {
            DebugLog.shared.add("recording", "Export fehlgeschlagen: \(error.localizedDescription)", error: true)
        }
    }

    @concurrent
    static func concatenate(_ urls: [URL], trimTo: Double?, output: URL) async throws -> Double {
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw URLError(.cannotCreateFile)
        }
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        var cursor = CMTime.zero
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let duration = try? await asset.load(.duration), duration.seconds > 0 else { continue }
            let range = CMTimeRange(start: .zero, duration: duration)
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(range, of: track, at: cursor)
            }
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                try? audioTrack?.insertTimeRange(range, of: track, at: cursor)
            }
            cursor = cursor + duration
        }
        var timeRange = CMTimeRange(start: .zero, duration: cursor)
        if let trimTo, cursor.seconds > trimTo {
            let start = CMTime(seconds: cursor.seconds - trimTo, preferredTimescale: 600)
            timeRange = CMTimeRange(start: start, end: cursor)
        }
        try? FileManager.default.removeItem(at: output)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw URLError(.cannotCreateFile)
        }
        session.timeRange = timeRange
        try await session.export(to: output, as: .mp4)
        return timeRange.duration.seconds
    }

    @concurrent
    static func writeThumbnail(for video: URL) async {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        guard let (image, _) = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
            try? data.write(to: video.deletingPathExtension().appendingPathExtension("jpg"))
        }
    }
}
