import Foundation
import os

public enum AppPaths {
    /// `~/Library/Application Support/Riftsight`
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let url = base.appendingPathComponent("Riftsight", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func directory(_ name: String) -> URL {
        let url = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `~/Movies/Riftsight` for recordings and clips.
    public static var recordings: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        let url = movies.appendingPathComponent("Riftsight", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Bundled sample JSONs: `Riftsight.app/Contents/Resources/SampleData`, or `macOS-App/Resources/SampleData`
    /// when running from `.build` during development.
    public static var sampleData: URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("SampleData"),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments.first ?? ".").resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("Resources/SampleData")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }
}

public enum Log {
    public static let subsystem = "app.riftsight"
    public static let lcu = Logger(subsystem: subsystem, category: "lcu")
    public static let live = Logger(subsystem: subsystem, category: "live")
    public static let data = Logger(subsystem: subsystem, category: "data")
    public static let recording = Logger(subsystem: subsystem, category: "recording")
    public static let overlay = Logger(subsystem: subsystem, category: "overlay")
}

/// In-app log ring buffer shown in the Debug/Logs view.
@MainActor
@Observable
public final class DebugLog {
    public struct Entry: Identifiable, Hashable, Sendable {
        public let id = UUID()
        public let date: Date
        public let category: String
        public let message: String
        public let isError: Bool
    }

    public static let shared = DebugLog()
    public private(set) var entries: [Entry] = []

    public func add(_ category: String, _ message: String, error: Bool = false) {
        entries.append(Entry(date: .now, category: category, message: message, isError: error))
        if entries.count > 500 { entries.removeFirst(entries.count - 500) }
    }
}

/// Downloads JSON with a per-key disk cache. Cached copies are used when offline.
public struct JSONFetcher: Sendable {
    public let cacheDirectory: URL
    let session: URLSession

    public init(cacheDirectory: URL = AppPaths.directory("Cache"), session: URLSession = .shared) {
        self.cacheDirectory = cacheDirectory
        self.session = session
    }

    public enum Policy: Sendable {
        /// Use the cached file if present (static per-patch data).
        case cacheFirst
        /// Try the network, fall back to the cached file.
        case networkFirst
    }

    public func data(from url: URL, cacheKey: String, policy: Policy) async throws -> Data {
        let file = cacheDirectory.appendingPathComponent(cacheKey)
        if policy == .cacheFirst, let cached = try? Data(contentsOf: file) {
            return cached
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return data
        } catch {
            if let cached = try? Data(contentsOf: file) { return cached }
            throw error
        }
    }

    public func decode<T: Decodable & Sendable>(_ type: T.Type, from url: URL, cacheKey: String,
                                                policy: Policy = .cacheFirst) async throws -> T {
        let data = try await self.data(from: url, cacheKey: cacheKey, policy: policy)
        return try await Self.decodeOffMain(type, data: data)
    }

    @concurrent
    public static func decodeOffMain<T: Decodable & Sendable>(_ type: T.Type, data: Data) async throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
