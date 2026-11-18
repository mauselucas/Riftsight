import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

/// An augment card recognised on screen; `frame` is normalised (0…1, origin top-left).
public struct DetectedAugment: Sendable, Hashable, Identifiable {
    public let augmentId: Int
    public let name: String
    public let frame: CGRect
    public var id: Int { augmentId }

    public init(augmentId: Int, name: String, frame: CGRect) {
        self.augmentId = augmentId
        self.name = name
        self.frame = frame
    }
}

/// Finds the three offered augments (ARAM Mayhem / Arena) by OCR on a screenshot of the game.
/// The Live Client API does not expose augment choices; this only reads what is visible on screen.
public enum AugmentDetector {
    @concurrent
    public static func detect(names: [Int: String]) async throws -> [DetectedAugment] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter: SCContentFilter
        if let window = content.windows.first(where: {
            let app = $0.owningApplication?.applicationName ?? ""
            return app.contains("League of Legends") && !app.contains("Client") && $0.frame.width > 600
        }) {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else if let display = content.displays.first {
            filter = SCContentFilter(display: display, excludingWindows: [])
        } else {
            return []
        }
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try recognize(in: image, names: names)
    }

    public static func recognize(in image: CGImage, names: [Int: String]) throws -> [DetectedAugment] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["de-DE", "en-US"]
        request.usesLanguageCorrection = false
        // Augment titles sit in the upper-middle band of the screen.
        request.regionOfInterest = CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.55)
        try VNImageRequestHandler(cgImage: image).perform([request])

        let normalizedNames = names.mapValues(normalize)
        var hits: [DetectedAugment] = []
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first?.string else { continue }
            let candidate = normalize(text)
            guard candidate.count >= 4 else { continue }
            var best: (id: Int, score: Double)?
            for (id, name) in normalizedNames {
                let score = similarity(candidate, name)
                if score > (best?.score ?? 0.78) { best = (id, score) }
            }
            if let best, !hits.contains(where: { $0.augmentId == best.id }) {
                let box = observation.boundingBox
                hits.append(DetectedAugment(augmentId: best.id, name: names[best.id] ?? text,
                                            frame: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)))
            }
        }
        return Array(hits.sorted { $0.frame.minX < $1.frame.minX }.prefix(3))
    }

    static func normalize(_ text: String) -> String {
        text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            .filter { $0.isLetter || $0.isNumber || $0 == " " }
            .trimmingCharacters(in: .whitespaces)
    }

    /// Levenshtein similarity ratio (0…1).
    static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}
