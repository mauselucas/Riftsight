import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// One finished (or in-progress) chunk of the recording.
public struct RecordingSegment: Sendable, Hashable {
    public let url: URL
    public let wallStart: Date
    public var wallEnd: Date
    public var duration: Double
}

/// Receives ScreenCaptureKit buffers and writes rolling MP4 segments with the hardware HEVC/H.264 encoder
/// (AVAssetWriter → VideoToolbox on Apple silicon). All mutable state lives on `queue`.
final class SegmentedWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    struct Settings: Sendable {
        var width: Int
        var height: Int
        var fps: Int
        var bitrate: Int
        var hevc: Bool
        var segmentSeconds: Double
        var keepSeconds: Double?   // nil = keep everything (full-game recording)
        var directory: URL
    }

    let queue = DispatchQueue(label: "app.riftsight.recording.writer")
    private var settings: Settings
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var segmentStartPTS: CMTime = .invalid
    private var segmentWallStart = Date()
    private var segments: [RecordingSegment] = []
    private var pendingRotate = false
    private var counter = 0
    var onError: (@Sendable (String) -> Void)?

    init(settings: Settings) {
        self.settings = settings
        try? FileManager.default.createDirectory(at: settings.directory, withIntermediateDirectories: true)
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            guard Self.isCompleteFrame(sampleBuffer) else { return }
            handleVideo(sampleBuffer)
        case .audio:
            if let input = audioInput, writer?.status == .writing, input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onError?("Aufnahme gestoppt: \(error.localizedDescription)")
    }

    static func isCompleteFrame(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first,
              let raw = first[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    private func handleVideo(_ buffer: CMSampleBuffer) {
        let pts = buffer.presentationTimeStamp
        if writer == nil { startSegment(at: pts) }
        if pendingRotate || (segmentStartPTS.isValid && (pts - segmentStartPTS).seconds >= settings.segmentSeconds) {
            pendingRotate = false
            finishSegment()
            startSegment(at: pts)
        }
        if let input = videoInput, writer?.status == .writing, input.isReadyForMoreMediaData {
            input.append(buffer)
        }
    }

    private func startSegment(at pts: CMTime) {
        counter += 1
        let url = settings.directory.appendingPathComponent(String(format: "segment-%05d.mp4", counter))
        try? FileManager.default.removeItem(at: url)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: settings.hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
                AVVideoWidthKey: settings.width,
                AVVideoHeightKey: settings.height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: settings.bitrate,
                    AVVideoExpectedSourceFrameRateKey: settings.fps,
                    AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
                ],
            ])
            video.expectsMediaDataInRealTime = true
            let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000,
            ])
            audio.expectsMediaDataInRealTime = true
            if writer.canAdd(video) { writer.add(video) }
            if writer.canAdd(audio) { writer.add(audio) }
            writer.startWriting()
            writer.startSession(atSourceTime: pts)
            self.writer = writer
            videoInput = video
            audioInput = audio
            segmentStartPTS = pts
            segmentWallStart = Date()
            segments.append(RecordingSegment(url: url, wallStart: segmentWallStart, wallEnd: segmentWallStart, duration: 0))
        } catch {
            onError?("Encoder konnte nicht starten: \(error.localizedDescription)")
        }
    }

    private func finishSegment() {
        guard let writer else { return }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        let group = DispatchGroup()
        group.enter()
        writer.finishWriting { group.leave() }
        group.wait()
        if var last = segments.popLast() {
            last.wallEnd = Date()
            last.duration = last.wallEnd.timeIntervalSince(last.wallStart)
            segments.append(last)
        }
        self.writer = nil
        videoInput = nil
        audioInput = nil
        segmentStartPTS = .invalid
        pruneOldSegments()
    }

    private func pruneOldSegments() {
        guard let keep = settings.keepSeconds else { return }
        let cutoff = Date().addingTimeInterval(-keep - settings.segmentSeconds)
        while let first = segments.first, first.wallEnd < cutoff, segments.count > 1 {
            try? FileManager.default.removeItem(at: first.url)
            segments.removeFirst()
        }
    }

    // MARK: Control (called from any thread)

    /// Closes the current segment and returns all finished segments.
    func flush() -> [RecordingSegment] {
        queue.sync {
            finishSegment()
            return segments.filter { $0.duration > 0.2 }
        }
    }

    func requestRotate() {
        queue.async { self.pendingRotate = true }
    }

    func setKeepSeconds(_ value: Double?) {
        queue.async { self.settings.keepSeconds = value }
    }

    func removeAllSegments() {
        queue.sync {
            for segment in segments { try? FileManager.default.removeItem(at: segment.url) }
            segments.removeAll()
        }
    }
}
