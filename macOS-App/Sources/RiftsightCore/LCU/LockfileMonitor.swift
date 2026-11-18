import Foundation

/// Finds the LCU port and password: first via the League `lockfile`, then via the `LeagueClientUx` process arguments.
public enum LockfileLocator {
    public static var candidatePaths: [String] {
        [
            "/Applications/League of Legends.app/Contents/LoL/lockfile",
            NSHomeDirectory() + "/Applications/League of Legends.app/Contents/LoL/lockfile",
        ]
    }

    public static func locate() -> LCUCredentials? {
        for path in candidatePaths {
            if let text = try? String(contentsOfFile: path, encoding: .utf8), let creds = parse(lockfile: text),
               isAlive(pid: creds.pid) {
                return creds
            }
        }
        return fromProcessList()
    }

    /// `LeagueClient:<pid>:<port>:<password>:<protocol>`
    public static func parse(lockfile text: String) -> LCUCredentials? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 5, let port = Int(parts[2]) else { return nil }
        return LCUCredentials(pid: Int(parts[1]), port: port, password: String(parts[3]), scheme: String(parts[4]))
    }

    /// Parses `--app-port=` / `--remoting-auth-token=` from `LeagueClientUx` command lines.
    public static func parse(processArguments args: String) -> LCUCredentials? {
        guard args.contains("LeagueClientUx") else { return nil }
        func value(_ key: String) -> String? {
            guard let range = args.range(of: "--\(key)=") else { return nil }
            let rest = args[range.upperBound...]
            let end = rest.firstIndex { $0 == " " || $0 == "\"" } ?? rest.endIndex
            return String(rest[..<end])
        }
        guard let portText = value("app-port"), let port = Int(portText), let token = value("remoting-auth-token") else {
            return nil
        }
        return LCUCredentials(pid: value("app-pid").flatMap(Int.init), port: port, password: token)
    }

    static func fromProcessList() -> LCUCredentials? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-A", "-ww", "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        for line in output.split(separator: "\n") where line.contains("LeagueClientUx") && line.contains("--app-port=") {
            if let creds = parse(processArguments: String(line)) { return creds }
        }
        return nil
    }

    static func isAlive(pid: Int?) -> Bool {
        guard let pid, pid > 0 else { return true }
        return kill(pid_t(pid), 0) == 0 || errno == EPERM
    }
}

/// Polls for the League client every 2 s and publishes the current credentials (zero-setup detection).
@MainActor
@Observable
public final class LockfileMonitor {
    public private(set) var credentials: LCUCredentials?
    /// Called on the main actor whenever the client appears, disappears or restarts.
    public var onChange: ((LCUCredentials?) -> Void)?
    private var task: Task<Void, Never>?

    public init() {}

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let found = await Self.scan()
                guard let self else { return }
                if found != self.credentials {
                    self.credentials = found
                    self.onChange?(found)
                    DebugLog.shared.add("lcu", found == nil ? "League-Client geschlossen" : "League-Client gefunden (Port \(found!.port))")
                }
                try? await Task.sleep(for: .seconds(found == nil ? 3 : 5))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    @concurrent
    static func scan() async -> LCUCredentials? { LockfileLocator.locate() }
}
