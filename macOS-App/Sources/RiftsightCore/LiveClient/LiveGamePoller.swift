import Foundation

/// Polls the official Live Client Data API (`https://127.0.0.1:2999/liveclientdata/allgamedata`)
/// every ~1 s during a match. Read-only, no memory access.
@MainActor
@Observable
public final class LiveGamePoller {
    public private(set) var data: LiveAllGameData?
    public private(set) var isInGame = false
    public private(set) var lastError: String?

    /// Fires for every successful poll.
    public var onUpdate: ((LiveAllGameData) -> Void)?
    /// Fires with events that were not seen before (kills, objectives, multikills …).
    public var onNewEvents: (([LiveEvent], LiveAllGameData) -> Void)?
    public var onGameEnded: (() -> Void)?

    public var interval: Duration = .seconds(1)
    private var task: Task<Void, Never>?
    private var lastEventId = -1
    private var failures = 0
    static let endpoint = URL(string: "https://127.0.0.1:2999/liveclientdata/allgamedata")!

    public init() {}

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                try? await Task.sleep(for: self.isInGame ? self.interval : .seconds(3))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func poll() async {
        do {
            var request = URLRequest(url: Self.endpoint)
            request.timeoutInterval = 2
            let (payload, response) = try await LocalSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let snapshot = try await JSONFetcher.decodeOffMain(LiveAllGameData.self, data: payload)
            failures = 0
            if !isInGame {
                isInGame = true
                lastEventId = -1
                DebugLog.shared.add("live", "Live-Spiel erkannt (\(snapshot.gameData.gameMode))")
            }
            data = snapshot
            let fresh = (snapshot.events?.Events ?? []).filter { $0.EventID > lastEventId }
            if let maxId = fresh.map(\.EventID).max() { lastEventId = maxId }
            onUpdate?(snapshot)
            if !fresh.isEmpty { onNewEvents?(fresh, snapshot) }
        } catch {
            failures += 1
            if isInGame && failures >= 4 {
                isInGame = false
                data = nil
                DebugLog.shared.add("live", "Live-Spiel beendet")
                onGameEnded?()
            }
        }
    }

    /// Feeds a snapshot manually (demo mode / tests).
    public func inject(_ snapshot: LiveAllGameData) {
        data = snapshot
        isInGame = true
        onUpdate?(snapshot)
    }
}
