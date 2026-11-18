import AVFoundation
import CoreGraphics
import Foundation
import ScreenCaptureKit

public struct TimelineMarker: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case kill, death, assist, dragon, baron, tower, multikill, ace, steal, manual }
    public let kind: Kind
    public let gameTime: Double
    public let videoTime: Double
    public let label: String
    public var id: String { "\(kind.rawValue)-\(gameTime)" }

    public init(kind: Kind, gameTime: Double, videoTime: Double, label: String) {
        self.kind = kind
        self.gameTime = gameTime
        self.videoTime = videoTime
        self.label = label
    }
}

public struct ClipMetadata: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case clip, fullGame }
    public var kind: Kind
    public var title: String
    public var createdAt: Date
    public var duration: Double
    public var championId: Int?
    public var kills: Int?
    public var deaths: Int?
    public var assists: Int?
    public var queueName: String?
    public var favorite: Bool
    public var markers: [TimelineMarker]

    public init(kind: Kind, title: String, createdAt: Date = .now, duration: Double = 0, championId: Int? = nil,
                kills: Int? = nil, deaths: Int? = nil, assists: Int? = nil, queueName: String? = nil,
                favorite: Bool = false, markers: [TimelineMarker] = []) {
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.championId = championId
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.queueName = queueName
        self.favorite = favorite
        self.markers = markers
    }

    public var kda: Double? {
        guard let kills, let deaths, let assists else { return nil }
        return Double(kills + assists) / Double(max(1, deaths))
    }
}

public enum RecorderError: LocalizedError {
    case permissionDenied
    case nothingToCapture
    case notRecording

    public var errorDescription: String? {
        switch self {
        case .permissionDenied: "Bildschirmaufnahme ist nicht erlaubt. Systemeinstellungen → Datenschutz & Sicherheit → Bildschirmaufnahme."
        case .nothingToCapture: "Kein League-Fenster oder Bildschirm gefunden."
        case .notRecording: "Es läuft keine Aufnahme."
        }
    }
}

/// Background match recorder: ScreenCaptureKit capture → segmented hardware encoding,
/// instant-replay ring buffer, auto-clips and full-game export with timeline markers.
@MainActor
@Observable
public final class ScreenCaptureRecorder {
    public enum State: Equatable { case idle, starting, recording, saving }

    public private(set) var state: State = .idle
    public private(set) var lastError: String?
    public private(set) var markers: [TimelineMarker] = []
    public var fps = 60
    public var useHEVC = true
    public var replaySeconds: Double = 90
    public var recordFullGames = true

    private var stream: SCStream?
    private var writer: SegmentedWriter?
    private var startedAt: Date?
    private var startGameTime: Double?
    private let library: RecordingLibrary

    public init(library: RecordingLibrary) {
        self.library = library
    }

    public static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult public static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    public var isRecording: Bool { state == .recording }

    /// Starts capturing the League game window (falls back to the main display).
    public func start(gameTime: Double? = nil) async {
        guard state == .idle else { return }
        guard Self.hasPermission else {
            lastError = RecorderError.permissionDenied.localizedDescription
            return
        }
        state = .starting
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let gameWindow = content.windows.first { window in
                let app = window.owningApplication?.applicationName ?? ""
                return app.contains("League of Legends") && !app.contains("Client") && window.frame.width > 600
            }
            let filter: SCContentFilter
            let size: CGSize
            if let gameWindow {
                filter = SCContentFilter(desktopIndependentWindow: gameWindow)
                size = gameWindow.frame.size
            } else if let display = content.displays.first {
                filter = SCContentFilter(display: display, excludingWindows: [])
                size = CGSize(width: display.width, height: display.height)
            } else {
                throw RecorderError.nothingToCapture
            }

            let scale = Double(filter.pointPixelScale)
            var width = Int(size.width * scale) & ~1
            var height = Int(size.height * scale) & ~1
            if width > 2560 { height = Int(Double(height) * 2560 / Double(width)) & ~1; width = 2560 }

            let config = SCStreamConfiguration()
            config.width = width
            config.height = height
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            config.queueDepth = 6
            config.showsCursor = true
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true

            let directory = AppPaths.recordings.appendingPathComponent(".buffer", isDirectory: true)
            let writer = SegmentedWriter(settings: .init(
                width: width, height: height, fps: fps,
                bitrate: Int(Double(width * height) * Double(fps) * (useHEVC ? 0.07 : 0.1)),
                hevc: useHEVC, segmentSeconds: 6,
                keepSeconds: recordFullGames ? nil : replaySeconds, directory: directory))
            writer.removeAllSegments()
            writer.onError = { message in
                Task { @MainActor in DebugLog.shared.add("recording", message, error: true) }
            }

            let stream = SCStream(filter: filter, configuration: config, delegate: writer)
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: writer.queue)
            try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: writer.queue)
            try await stream.startCapture()

            self.stream = stream
            self.writer = writer
            startedAt = .now
            startGameTime = gameTime
            markers = []
            state = .recording
            lastError = nil
            DebugLog.shared.add("recording", "Aufnahme gestartet (\(width)×\(height) @\(fps) fps, \(useHEVC ? "HEVC" : "H.264"))")
        } catch {
            state = .idle
            lastError = error.localizedDescription
            DebugLog.shared.add("recording", "Start fehlgeschlagen: \(error.localizedDescription)", error: true)
        }
    }

    /// Seconds since the recording started for a given game time.
    func videoTime(forGameTime gameTime: Double) -> Double {
        guard let startGameTime else { return Date().timeIntervalSince(startedAt ?? .now) }
        return max(0, gameTime - startGameTime)
    }

    public func addMarker(_ kind: TimelineMarker.Kind, gameTime: Double, label: String) {
        guard state == .recording else { return }
        if startGameTime == nil { startGameTime = gameTime - Date().timeIntervalSince(startedAt ?? .now) }
        markers.append(TimelineMarker(kind: kind, gameTime: gameTime, videoTime: videoTime(forGameTime: gameTime), label: label))
    }

    /// Instant replay / auto-clip: saves the last `seconds` (optionally waiting `delay` to include the aftermath).
    public func saveClip(lastSeconds seconds: Double? = nil, delay: Double = 0, metadata: ClipMetadata) async {
        guard state == .recording, let writer else { return }
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        let window = seconds ?? replaySeconds
        let segments = writer.flush()
        let end = Date()
        let relevant = segments.filter { $0.wallEnd > end.addingTimeInterval(-window - 1) }
        guard !relevant.isEmpty else { return }
        var meta = metadata
        meta.kind = .clip
        await library.export(segments: relevant, trimTo: window, metadata: meta)
    }

    /// Stops capturing and – if enabled – exports the whole match as a full-game recording.
    public func stop(fullGameMetadata: ClipMetadata?) async {
        guard let stream, let writer else { state = .idle; return }
        state = .saving
        try? await stream.stopCapture()
        let segments = writer.flush()
        if recordFullGames, var meta = fullGameMetadata, !segments.isEmpty {
            meta.kind = .fullGame
            meta.markers = markers
            await library.export(segments: segments, trimTo: nil, metadata: meta)
        }
        writer.removeAllSegments()
        self.stream = nil
        self.writer = nil
        state = .idle
        DebugLog.shared.add("recording", "Aufnahme beendet")
    }
}
