import Foundation

// Which projects and models used Codex, and when: counted from the rollout files Codex writes for every
// thread (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl, older ones .jsonl.zst, archived ones in
// ~/.codex/archived_sessions). Only three kinds of line are parsed, picked by their start so a line of
// conversation is never decoded: `session_meta` (folder, repo, fork), `turn_context` (model) and the
// `token_count` events (token totals). The result fills the same `ProjectUsage` Claudy draws.

/// Model ids as Codex writes them ("gpt-5.1-codex-max") and how they read ("GPT-5.1 Codex Max").
public enum CodexModel {
    /// Lowercased, without a date suffix ("-2026-01-15" or "-20260115"). Empty is "other".
    public static func key(_ id: String) -> String {
        var s = id.lowercased().trimmingCharacters(in: .whitespaces)
        if let r = s.range(of: #"-(\d{4}-\d{2}-\d{2}|\d{8})$"#, options: .regularExpression) { s.removeSubrange(r) }
        return s.isEmpty ? "other" : s
    }

    public static func display(_ key: String) -> String {
        let parts = key.split(separator: "-").map(String.init)
        guard let first = parts.first else { return key }
        func cap(_ w: String) -> String { w.prefix(1).uppercased() + w.dropFirst() }
        if first == "gpt", parts.count > 1 {
            return (["GPT-" + parts[1]] + parts.dropFirst(2).map(cap)).joined(separator: " ")
        }
        return ([first] + parts.dropFirst().map(cap)).joined(separator: " ")
    }

    // Relative price, as a weight: small models spend less of the limit for the same tokens.
    // ponytail: two tiers only; OpenAI does not publish how each model counts against the plan.
    static func factor(_ key: String) -> Double {
        key.contains("nano") ? 0.04 : key.contains("mini") ? 0.2 : 1
    }
}

/// One token count as Codex reports it. `input` includes `cached`; `output` includes the reasoning tokens.
struct Tokens: Equatable {
    var input = 0.0, cached = 0.0, output = 0.0, total = 0.0

    init(input: Double = 0, cached: Double = 0, output: Double = 0, total: Double = 0) {
        self.input = input; self.cached = cached; self.output = output; self.total = total
    }

    init?(_ d: Any?) {
        guard let d = d as? [String: Any] else { return nil }
        func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
        self.init(input: n("input_tokens"), cached: n("cached_input_tokens"), output: n("output_tokens"), total: n("total_tokens"))
    }

    var isZero: Bool { input == 0 && cached == 0 && output == 0 }

    /// What happened since `prev`, when the totals only grew; nil when they went down (Codex rewrote them).
    func minus(_ prev: Tokens) -> Tokens? {
        guard input >= prev.input, cached >= prev.cached, output >= prev.output else { return nil }
        return Tokens(input: input - prev.input, cached: cached - prev.cached, output: output - prev.output, total: total - prev.total)
    }

    // Cached input and output relative to fresh input, as in OpenAI's price list (0.1x and 8x).
    var weight: Double { max(0, input - cached) + 0.1 * cached + 8 * output }
}

/// Reads the rollout files. Plain files are read from where the last scan stopped; compressed ones once.
/// Not thread safe: one scan at a time.
public final class RolloutScanner: @unchecked Sendable {
    struct Event {
        var hour: Int
        var family: String
        var weight: Double
        var key: String          // the thread's running totals: a fork copies them, so a copy is counted once
    }

    struct FileCache {
        var pos: UInt64 = 0                 // bytes read (plain files) or the size that was read (.zst)
        var id: String?
        var cwd: String?
        var repoURL: String?
        var forked = false
        var firstAt: Date?
        var model = ""
        var prev: Tokens?
        var events: [Event] = []
        var turns: [(hour: Int, id: String?)] = []
        var lastHour: Int?
    }

    var cache: [String: FileCache] = [:]
    let lock = NSLock()
    public init() {}

    // The line starts with {"timestamp":"…","type":"…": these are looked for in the first bytes only, so a
    // quoted copy inside a message (written as \"type\") never matches.
    static let metaMarker = Data(#""type":"session_meta""#.utf8)
    static let turnMarker = Data(#""type":"turn_context""#.utf8)
    static let countMarker = Data(#""type":"event_msg","payload":{"type":"token_count""#.utf8)
    static let head = 200

    /// A fork writes the parent's lines again at its start: the lines of its first seconds are not new use.
    static let forkCopySeconds: TimeInterval = 2

    /// "https://github.com/me/web-app.git", "git@github.com:me/web-app.git" -> "web-app".
    public static func repoName(_ url: String) -> String? {
        var s = url.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix(".git") { s.removeLast(4) }
        let name = s.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Project name of a thread: its git remote, else the repo of its folder, else the folder. Home is "~".
    public static func projectName(cwd: String?, repoURL: String?, home: String = NSHomeDirectory()) -> String {
        if let u = repoURL, let n = repoName(u) { return n }
        guard var c = cwd, !c.isEmpty else { return "?" }
        if c.hasSuffix("/"), c.count > 1 { c.removeLast() }
        if c == home { return "~" }
        if let g = Git.info(cwd: c) { return g.repo }
        let last = (c as NSString).lastPathComponent
        return last.isEmpty ? c : last
    }

    /// Every rollout file under the Codex folder, live and archived.
    static func files(home: String) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        for sub in ["sessions", "archived_sessions"] {
            let root = home + "/" + sub
            guard let en = fm.enumerator(atPath: root) else { continue }
            for case let rel as String in en where (rel as NSString).lastPathComponent.hasPrefix("rollout-")
                && (rel.hasSuffix(".jsonl") || rel.hasSuffix(".jsonl.zst")) {
                out.append(root + "/" + rel)
            }
        }
        return out
    }

    public func scan(home: String = CodexCLI.home, since: Date, now: Date = Date()) -> ProjectUsage {
        lock.lock(); defer { lock.unlock() }
        let fm = FileManager.default
        var seen = Set<String>()
        for path in Self.files(home: home) {
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let mod = attrs[.modificationDate] as? Date, mod >= since,
                  let size = (attrs[.size] as? NSNumber)?.uint64Value else { continue }
            seen.insert(path)
            var c = cache[path] ?? FileCache()
            if size < c.pos { c = FileCache() }                 // rewritten
            if size == c.pos { cache[path] = c; continue }
            if path.hasSuffix(".zst") {
                // Compressed files do not grow: read the whole thing again only if it changed.
                guard let z = CodexCLI.zstd, let data = CodexCLI.run(z, ["-dc", path], timeout: 30) else { continue }
                c = FileCache()
                read(data, into: &c)
                c.pos = size
            } else {
                guard let fh = FileHandle(forReadingAtPath: path) else { continue }
                defer { try? fh.close() }
                try? fh.seek(toOffset: c.pos)
                guard var data = try? fh.readToEnd(), let nl = data.lastIndex(of: 0x0A) else { continue }   // a line still being written waits
                data = data.prefix(through: nl)
                c.pos += UInt64(data.count)
                read(data, into: &c)
            }
            cache[path] = c
        }
        for k in cache.keys where !seen.contains(k) { cache.removeValue(forKey: k) }   // fell out of the week, or moved
        return Self.merge(Array(cache.values), since: since)
    }

    /// Adds the lines in `data` (whole lines only) to one file's state.
    func read(_ data: Data, into c: inout FileCache) {
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let start = line.prefix(Self.head)
            if start.range(of: Self.countMarker) != nil { tokenCount(Data(line), &c) }
            else if start.range(of: Self.turnMarker) != nil { turn(Data(line), &c) }
            else if start.range(of: Self.metaMarker) != nil, c.id == nil { meta(Data(line), &c) }
        }
    }

    private func object(_ line: Data) -> (at: Date?, payload: [String: Any])? {
        guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let p = o["payload"] as? [String: Any] else { return nil }
        return ((o["timestamp"] as? String).flatMap(CodexParser.iso), p)
    }

    private func meta(_ line: Data, _ c: inout FileCache) {
        guard let o = object(line) else { return }
        let at = o.at, p = o.payload
        c.id = p["id"] as? String
        c.cwd = p["cwd"] as? String
        c.repoURL = (p["git"] as? [String: Any])?["repository_url"] as? String
        c.forked = p["forked_from_id"] is String || p["parent_thread_id"] is String
        c.firstAt = c.firstAt ?? at
    }

    /// Lines written while a fork copies its parent: not new use.
    private func copied(_ at: Date, _ c: FileCache) -> Bool {
        guard c.forked, let first = c.firstAt else { return false }
        return at.timeIntervalSince(first) <= Self.forkCopySeconds
    }

    private func turn(_ line: Data, _ c: inout FileCache) {
        guard let o = object(line) else { return }
        let p = o.payload
        if let m = p["model"] as? String, !m.isEmpty { c.model = m }
        if c.cwd == nil { c.cwd = p["cwd"] as? String }
        guard let at = o.at, !copied(at, c) else { return }
        let hour = Int(at.timeIntervalSince1970 / 3600)
        c.turns.append((hour, p["turn_id"] as? String))
        c.lastHour = max(c.lastHour ?? hour, hour)
    }

    private func tokenCount(_ line: Data, _ c: inout FileCache) {
        guard let o = object(line), let at = o.at, let info = o.payload["info"] as? [String: Any],
              let total = Tokens(info["total_token_usage"]) else { return }
        let last = Tokens(info["last_token_usage"]) ?? Tokens()
        defer { c.prev = total }
        // The first count of a fork carries the parent's totals too: it only sets the baseline.
        if copied(at, c) || (c.forked && c.prev == nil) { return }
        let delta = c.prev.map { total.minus($0) ?? last } ?? total
        guard !delta.isZero else { return }                     // the same count sent again
        let family = CodexModel.key(c.model)
        let hour = Int(at.timeIntervalSince1970 / 3600)
        let key = "\(Int(total.input))/\(Int(total.cached))/\(Int(total.output))/\(Int(total.total))"
        c.events.append(Event(hour: hour, family: family, weight: delta.weight * CodexModel.factor(family), key: key))
        c.lastHour = max(c.lastHour ?? hour, hour)
    }

    /// All files into one `ProjectUsage`, a token count or turn that appears in two files counted once.
    static func merge(_ files: [FileCache], since: Date) -> ProjectUsage {
        let firstHour = Int(since.timeIntervalSince1970 / 3600)
        var r = ProjectUsage()
        var keys = Set<String>(), turnIds = Set<String>()
        // The oldest first, so the original keeps a count and the copy drops it.
        for c in files.sorted(by: { ($0.firstAt ?? .distantPast) < ($1.firstAt ?? .distantPast) }) {
            let name = projectName(cwd: c.cwd, repoURL: c.repoURL)
            var used = false
            for e in c.events where e.hour >= firstHour && keys.insert(e.key).inserted {
                r.hourly[e.hour, default: [:]][name, default: [:]][e.family, default: 0] += e.weight
                used = true
            }
            for t in c.turns where t.hour >= firstHour {
                if let id = t.id, !turnIds.insert(id).inserted { continue }
                r.turns[t.hour, default: 0] += 1
                used = true
            }
            if used {
                if let cwd = c.cwd { r.paths[name] = cwd }
                if let id = c.id, let h = c.lastHour { r.threads[id] = max(r.threads[id] ?? h, h) }
            }
        }
        return r
    }
}
