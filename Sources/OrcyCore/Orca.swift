import Foundation

// Orca (the agent orchestrator, an Electron app) and what Orcy reads from it, all read-only:
// - live: `orca worktree ps --json`, through the CLI inside the app bundle (~0.13 s of CPU a call);
// - history: orca-stats.json (agent starts and stops) and orchestration.db (tasks, dispatches, questions).
// The same answers carry prompts, agent messages, tool input and terminal previews: never read into the model, never kept.

/// Orca's agent states (its own list: working, monitoring, waiting, blocked, done, idle, unverifiable), folded into three.
public enum AgentPhase: String, Sendable, CaseIterable {
    case working, waiting, idle

    public init(orcaState s: String) {
        switch s {
        case "working", "monitoring", "running", "thinking": self = .working
        case "waiting", "blocked": self = .waiting
        default: self = .idle
        }
    }
}

public struct OrcaAgent: Equatable, Sendable {
    public var type: String          // "codex", "claude", …
    public var state: String         // Orca's own word
    public var since: Date?
    public var phase: AgentPhase { AgentPhase(orcaState: state) }
    public init(type: String, state: String, since: Date?) { self.type = type; self.state = state; self.since = since }
}

/// What a worktree is doing, most urgent first: an agent that needs you, one that works, a terminal left open, nothing.
public enum WorktreePhase: Int, Sendable, Comparable, CaseIterable {
    case waiting, working, open, closed
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

public struct OrcaWorktree: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var repo: String
    public var branch: String
    public var liveTerminals: Int
    public var lastOutput: Date?
    public var isMain: Bool
    public var agents: [OrcaAgent]
    /// Set by the parser: terminal output this recent counts as work even without an agent status (a tool, a build).
    public var outputActive = false

    public init(id: String, name: String, repo: String, branch: String, liveTerminals: Int, lastOutput: Date?,
                isMain: Bool, agents: [OrcaAgent], outputActive: Bool = false) {
        self.id = id; self.name = name; self.repo = repo; self.branch = branch; self.liveTerminals = liveTerminals
        self.lastOutput = lastOutput; self.isMain = isMain; self.agents = agents; self.outputActive = outputActive
    }

    public var phase: WorktreePhase {
        if agents.contains(where: { $0.phase == .waiting }) { return .waiting }
        if agents.contains(where: { $0.phase == .working }) || outputActive { return .working }
        return liveTerminals > 0 ? .open : .closed
    }
}

public struct OrcaLive: Equatable, Sendable {
    public var worktrees: [OrcaWorktree]
    public var at: Date
    public init(worktrees: [OrcaWorktree], at: Date) { self.worktrees = worktrees; self.at = at }

    /// Most urgent first, then the most recent output.
    public var sorted: [OrcaWorktree] {
        worktrees.sorted { ($0.phase, -($0.lastOutput?.timeIntervalSince1970 ?? 0)) < ($1.phase, -($1.lastOutput?.timeIntervalSince1970 ?? 0)) }
    }
    public func count(_ p: WorktreePhase) -> Int { worktrees.filter { $0.phase == p }.count }
    /// Agents doing something now: those Orca says work, plus a worktree whose terminal is busy without a status.
    public var working: Int {
        worktrees.reduce(0) { n, w in
            let a = w.agents.filter { $0.phase == .working }.count
            return n + (a > 0 ? a : (w.outputActive && w.phase == .working ? 1 : 0))
        }
    }
    public var waiting: Int { worktrees.reduce(0) { $0 + $1.agents.filter { $0.phase == .waiting }.count } }
}

public enum OrcaParser {
    /// Terminal output within this long, with no agent status, counts as work.
    public static let outputActiveSeconds: TimeInterval = 90

    /// `{"ok":true,"result":{"worktrees":[…]}}`; archived worktrees are left out. nil when it is not that shape.
    public static func worktreePs(_ data: Data, now: Date = Date()) -> OrcaLive? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], j["ok"] as? Bool == true,
              let rows = (j["result"] as? [String: Any])?["worktrees"] as? [[String: Any]] else { return nil }
        func date(_ v: Any?) -> Date? { (v as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) } }
        let list: [OrcaWorktree] = rows.compactMap { r in
            guard let id = r["worktreeId"] as? String, r["isArchived"] as? Bool != true else { return nil }
            let agents = (r["agents"] as? [[String: Any]] ?? []).map {
                OrcaAgent(type: $0["agentType"] as? String ?? "agent", state: $0["state"] as? String ?? "unverifiable",
                          since: date($0["stateStartedAt"]))
            }
            let last = date(r["lastOutputAt"])
            let terminals = (r["liveTerminalCount"] as? NSNumber)?.intValue ?? 0
            var w = OrcaWorktree(id: id, name: r["displayName"] as? String ?? r["branch"] as? String ?? id,
                                 repo: r["repo"] as? String ?? "", branch: r["branch"] as? String ?? "",
                                 liveTerminals: terminals, lastOutput: last,
                                 isMain: r["isMainWorktree"] as? Bool ?? false, agents: agents)
            w.outputActive = agents.isEmpty && terminals > 0 && last.map { now.timeIntervalSince($0) < outputActiveSeconds } == true
            return w
        }
        return OrcaLive(worktrees: list, at: now)
    }

    /// The `error.message` of a failed answer, cut short.
    public static func error(_ data: Data) -> String? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any], j["ok"] as? Bool == false else { return nil }
        return ((j["error"] as? [String: Any])?["message"] as? String).map { String($0.prefix(160)) }
    }
}

/// The CLI that ships inside Orca.app (the /usr/local/bin link may be broken; the bundled one always matches the app).
public enum OrcaCLI {
    public static let bundleId = "com.stablyai.orca"
    public static let path: String? = ["/Applications/Orca.app", NSHomeDirectory() + "/Applications/Orca.app"]
        .map { $0 + "/Contents/Resources/bin/orca" }
        .first { FileManager.default.isExecutableFile(atPath: $0) }

    public enum LiveResult: Sendable { case ok(OrcaLive), failed(String) }

    public static func live(now: Date = Date()) -> LiveResult {
        guard let exe = path else { return .failed("Orca.app not found") }
        guard let r = run(exe, ["worktree", "ps", "--json"]) else { return .failed("orca did not answer") }
        if let l = OrcaParser.worktreePs(r, now: now) { return .ok(l) }
        let why = OrcaParser.error(r) ?? "unexpected answer"
        OrcyLog.write("worktree ps failed: \(why)")
        return .failed(why)
    }

    /// stdout of a short run, with an argument array (never a shell). A bare PATH is enough: the script finds its app.
    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 15) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
        p.environment = env
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); killer.cancel()
        return d.isEmpty ? nil : d
    }

    /// ~/Library/Application Support/orca: Orca's own data folder.
    public static var dataDir: String { NSHomeDirectory() + "/Library/Application Support/orca" }
}

/// ~/Library/Logs/Orcy.log, so failures can be read without a debugger.
public enum OrcyLog {
    public static func write(_ s: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Orcy.log")
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss xx"
        let line = "\(f.string(from: Date())) \(s)\n"
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}
