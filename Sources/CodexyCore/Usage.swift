import Foundation

// Codex plan limits. First choice: `codex app-server` over stdio, method `account/rateLimits/read`
// (the same numbers the Codex UI shows, no model call). Fallback: the last `token_count` event in the
// newest rollout file under ~/.codex/sessions, which carries a copy of the limits as of that turn.

/// What the UI draws for one limit: a whole percent and when it starts over.
public struct UsageLine: Equatable, Sendable {
    public var percent: Int
    public var reset: Date?
    public init(percent: Int, reset: Date?) { self.percent = percent; self.reset = reset }
}

/// One rate-limit window as Codex reports it.
public struct CodexLimit: Equatable, Sendable {
    public var windowMinutes: Int
    public var usedPercent: Double
    public var resetsAt: Date?
    public init(windowMinutes: Int, usedPercent: Double, resetsAt: Date?) {
        self.windowMinutes = windowMinutes; self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }
    /// "5h", "week", or the minutes when Codex sends a window we do not know.
    public var name: String { windowMinutes == 300 ? "5h" : windowMinutes == 10080 ? "week" : "\(windowMinutes)m" }
    public var line: UsageLine { UsageLine(percent: Int(usedPercent.rounded()), reset: resetsAt) }
}

/// Paid credits for use past the plan (`rateLimits.credits`). The balance is a decimal string, kept as Codex sends it.
public struct CodexCredits: Equatable, Sendable {
    public var hasCredits: Bool
    public var unlimited: Bool
    public var balance: String?
    public init(hasCredits: Bool, unlimited: Bool, balance: String?) { self.hasCredits = hasCredits; self.unlimited = unlimited; self.balance = balance }
    /// Worth a line in the panel: unlimited, or a balance above zero.
    public var worthShowing: Bool { unlimited || (hasCredits && (Double(balance ?? "") ?? 0) > 0) }
}

/// Reset credits (`rateLimitResetCredits`, app-server only): each one starts the limits over early.
/// Codexy only counts them; redeeming one is done in Codex itself.
public struct ResetCredits: Equatable, Sendable {
    public var available: Int
    /// The soonest expiry among the listed credits, when Codex lists them.
    public var nextExpiry: Date?
    public init(available: Int, nextExpiry: Date?) { self.available = available; self.nextExpiry = nextExpiry }
}

public struct CodexLimits: Equatable, Sendable {
    public enum Source: String, Sendable { case appServer, sessionFile }
    public var limits: [CodexLimit]
    public var plan: String?
    public var source: Source
    /// When the numbers were true: now for the app-server, the event time for a session file.
    public var asOf: Date?
    public var credits: CodexCredits?
    public var resetCredits: ResetCredits?
    public init(limits: [CodexLimit], plan: String?, source: Source, asOf: Date?,
                credits: CodexCredits? = nil, resetCredits: ResetCredits? = nil) {
        self.limits = limits; self.plan = plan; self.source = source; self.asOf = asOf
        self.credits = credits; self.resetCredits = resetCredits
    }
    // Picked by length, not by primary/secondary: the order is Codex's choice and could change.
    public var session: UsageLine? { limits.first { $0.windowMinutes <= 24 * 60 }?.line }
    public var week: UsageLine? { limits.first { $0.windowMinutes > 24 * 60 }?.line }
}

/// The UI was written for Claudy's `Usage`; the Codex model fills the same role.
public typealias Usage = CodexLimits

public enum CodexParser {
    /// A `rate_limits` / `rateLimits` object, snake_case (session files) or camelCase (app-server).
    /// A window whose reset is already past has started over since: 0%, no reset time.
    public static func limits(_ rl: [String: Any], source: CodexLimits.Source, asOf: Date?, now: Date = Date()) -> CodexLimits? {
        func num(_ d: [String: Any], _ keys: String...) -> Double? {
            keys.lazy.compactMap { (d[$0] as? NSNumber)?.doubleValue }.first
        }
        var out: [CodexLimit] = []
        for key in ["primary", "secondary"] {
            guard let w = rl[key] as? [String: Any],
                  let used = num(w, "usedPercent", "used_percent"),
                  let mins = num(w, "windowDurationMins", "window_minutes") else { continue }
            var reset = num(w, "resetsAt", "resets_at").map { Date(timeIntervalSince1970: $0) }
            var pct = used
            if let r = reset, r <= now { pct = 0; reset = nil }
            out.append(CodexLimit(windowMinutes: Int(mins), usedPercent: pct, resetsAt: reset))
        }
        guard !out.isEmpty else { return nil }
        let plan = (rl["planType"] ?? rl["plan_type"]) as? String
        return CodexLimits(limits: out, plan: plan, source: source, asOf: asOf, credits: credits(rl["credits"]))
    }

    /// `{hasCredits, unlimited, balance}` (app-server) or `{has_credits, unlimited, balance}` (session files).
    static func credits(_ any: Any?) -> CodexCredits? {
        guard let c = any as? [String: Any] else { return nil }
        let has = (c["hasCredits"] ?? c["has_credits"]) as? Bool ?? false
        let balance = (c["balance"] as? String) ?? (c["balance"] as? NSNumber)?.stringValue
        return CodexCredits(hasCredits: has, unlimited: c["unlimited"] as? Bool ?? false, balance: balance)
    }

    /// `{availableCount, credits: [{expiresAt, status, ...}] | null}`; only credits still available count for the expiry.
    static func resetCredits(_ any: Any?, now: Date) -> ResetCredits? {
        guard let r = any as? [String: Any], let n = (r["availableCount"] as? NSNumber)?.intValue else { return nil }
        let expiries = (r["credits"] as? [[String: Any]] ?? [])
            .filter { ($0["status"] as? String ?? "available") == "available" }
            .compactMap { ($0["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } }
            .filter { $0 > now }
        return ResetCredits(available: n, nextExpiry: expiries.min())
    }

    /// The JSON-RPC answer to `account/rateLimits/read`.
    public static func appServer(_ data: Data, now: Date = Date()) -> CodexLimits? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let r = j["result"] as? [String: Any], let rl = r["rateLimits"] as? [String: Any],
              var l = limits(rl, source: .appServer, asOf: now, now: now) else { return nil }
        l.resetCredits = resetCredits(r["rateLimitResetCredits"], now: now)
        return l
    }

    /// The last `event_msg` / `token_count` line that carries rate limits, read from the end.
    public static func sessionFile(_ text: String, now: Date = Date()) -> CodexLimits? {
        for line in text.split(separator: "\n").reversed() where line.contains("\"token_count\"") && line.contains("rate_limits") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let p = j["payload"] as? [String: Any], let rl = p["rate_limits"] as? [String: Any] else { continue }
            let at = (j["timestamp"] as? String).flatMap(iso)
            if let l = limits(rl, source: .sessionFile, asOf: at, now: now) { return l }
        }
        return nil
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}

/// Where `codex` lives and how to ask it. A menu bar app launched from Finder has a bare PATH.
public enum CodexCLI {
    public static let path: String? = find("codex", extra: ["\(NSHomeDirectory())/.codex/bin/codex", "/Applications/Codex.app/Contents/Resources/codex"])
    static let zstd: String? = find("zstd", extra: [])

    static func find(_ name: String, extra: [String]) -> String? {
        let home = NSHomeDirectory()
        return (["\(home)/.local/bin/\(name)", "/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)"] + extra)
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var home: String { ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex" }

    public enum ProbeResult: Sendable { case ok(CodexLimits), failed(String) }

    /// App-server first; when it fails, the newest session file, so the bars still show something.
    public static func fetchUsage() -> ProbeResult {
        let live = appServer()
        if case .ok = live { return live }
        if let l = SessionFiles.latest() { return .ok(l) }
        return live
    }

    /// Starts `codex app-server`, sends initialize + initialized + account/rateLimits/read, waits for the answer, stops it.
    public static func appServer(timeout: TimeInterval = 20) -> ProbeResult {
        guard let exe = path else { return .failed("codex not found") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = ["app-server"]
        p.environment = env()
        let inp = Pipe(), out = Pipe()
        p.standardInput = inp; p.standardOutput = out; p.standardError = FileHandle.nullDevice
        let box = LineBox()
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; box.finish() } else { box.append(d) }
        }
        do { try p.run() } catch { return .failed("could not start codex") }
        defer {
            out.fileHandleForReading.readabilityHandler = nil
            try? inp.fileHandleForWriting.close()
            if p.isRunning { p.terminate() }
        }
        let msgs: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize",
             "params": ["clientInfo": ["name": "codexy", "title": "Codexy", "version": "0.1.0"]]],
            ["jsonrpc": "2.0", "method": "initialized"],
            ["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read"],
        ]
        for m in msgs { inp.fileHandleForWriting.write((try! JSONSerialization.data(withJSONObject: m)) + Data("\n".utf8)) }
        guard let answer = box.wait(id: 2, timeout: timeout) else {
            let why = "app-server gave no answer in \(Int(timeout)) s"
            Log.write("usage probe failed: \(why)")
            return .failed(why)
        }
        if let l = CodexParser.appServer(answer) { return .ok(l) }
        // An error object (not logged in, old codex): keep its message, never the whole line.
        let msg = ((try? JSONSerialization.jsonObject(with: answer) as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
        let why = "app-server: " + (msg.map { String($0.prefix(120)) } ?? "unexpected answer")
        Log.write("usage probe failed: \(why)")
        return .failed(why)
    }

    static func env() -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        e["HOME"] = NSHomeDirectory(); e["USER"] = NSUserName(); e["LOGNAME"] = NSUserName()
        e["PATH"] = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        return e
    }

    /// stdout of a short run, with an argument array (never a shell).
    static func run(_ exe: String, _ args: [String], timeout: TimeInterval = 15) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice; p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit(); killer.cancel()
        return p.terminationStatus == 0 ? d : nil
    }
}

/// The rollout files: `sessions/YYYY/MM/DD/rollout-*.jsonl`, older ones compressed to `.jsonl.zst`.
public enum SessionFiles {
    /// The newest few files by date; the first one with a token_count event wins.
    public static func latest(root: String = CodexCLI.home + "/sessions", tries: Int = 5, now: Date = Date()) -> CodexLimits? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let u as URL in e where u.lastPathComponent.hasPrefix("rollout-") {
            let d = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            files.append((u, d))
        }
        for (u, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(tries) {
            guard let text = read(u), let l = CodexParser.sessionFile(text, now: now) else { continue }
            return l
        }
        return nil
    }

    static func read(_ u: URL) -> String? {
        if u.pathExtension == "zst" {
            // ponytail: needs the zstd tool; without it compressed files are skipped (the live one is plain .jsonl).
            guard let z = CodexCLI.zstd, let d = CodexCLI.run(z, ["-dc", u.path]) else { return nil }
            return String(decoding: d, as: UTF8.self)
        }
        return try? String(contentsOf: u, encoding: .utf8)
    }
}

/// Collects stdout lines and hands over the response with a given id.
final class LineBox: @unchecked Sendable {
    private let cond = NSCondition()
    private var buf = Data()
    private var done = false

    func append(_ d: Data) { cond.lock(); buf.append(d); cond.broadcast(); cond.unlock() }
    func finish() { cond.lock(); done = true; cond.broadcast(); cond.unlock() }

    func wait(id: Int, timeout: TimeInterval) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        cond.lock(); defer { cond.unlock() }
        while true {
            for line in buf.split(separator: UInt8(ascii: "\n")) {
                if let j = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                   (j["id"] as? NSNumber)?.intValue == id { return Data(line) }
            }
            if done || !cond.wait(until: deadline) { return nil }
        }
    }
}

/// ~/Library/Logs/Codexy.log, so failures can be read without a debugger.
public enum Log {
    public static func write(_ s: String) {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Codexy.log")
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss xx"
        let line = "\(f.string(from: Date())) \(s)\n"
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 200_000 {
            try? FileManager.default.removeItem(at: url)
        }
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
    }
}
