import Foundation

/// One `OnJsonApiEvent` pushed by the LCU over WAMP.
public struct LCUEvent: Sendable {
    public let uri: String
    public let eventType: String
    public let data: Data?

    public func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// LCU WebSocket (`wss://127.0.0.1:<port>`, WAMP 1.0). Subscribes to the given API paths and streams events.
public enum LCUWebSocketClient {
    /// `/lol-champ-select/v1/session` → `OnJsonApiEvent_lol-champ-select_v1_session`
    public static func topic(for path: String) -> String {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return "OnJsonApiEvent_" + trimmed.replacingOccurrences(of: "/", with: "_")
    }

    public static func events(credentials: LCUCredentials, paths: [String],
                              session: URLSession = LocalSession.shared) -> AsyncThrowingStream<LCUEvent, Error> {
        AsyncThrowingStream { continuation in
            var request = URLRequest(url: credentials.webSocketURL)
            request.setValue(credentials.authorization, forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 10
            let task = session.webSocketTask(with: request)
            task.maximumMessageSize = 64 * 1024 * 1024
            task.resume()

            let receiver = Task {
                do {
                    for path in paths {
                        try await task.send(.string("[5, \"\(topic(for: path))\"]"))
                    }
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        let text: String
                        switch message {
                        case let .string(value): text = value
                        case let .data(value): text = String(decoding: value, as: UTF8.self)
                        @unknown default: continue
                        }
                        if let event = parse(text) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                receiver.cancel()
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }

    /// `[8, "OnJsonApiEvent_…", {"data": …, "eventType": "Update", "uri": "/lol-…"}]`
    static func parse(_ text: String) -> LCUEvent? {
        guard let array = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any], array.count >= 3,
              (array[0] as? Int) == 8, let payload = array[2] as? [String: Any],
              let uri = payload["uri"] as? String else { return nil }
        var data: Data?
        if let value = payload["data"], !(value is NSNull) {
            data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        }
        return LCUEvent(uri: uri, eventType: payload["eventType"] as? String ?? "Update", data: data)
    }
}
