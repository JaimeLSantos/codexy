import Foundation
#if canImport(Darwin)
import Darwin
#endif

// Codex keeps no registry of running sessions like Claude Code's ~/.claude/sessions/<pid>.json.
// What it does have: a live thread keeps its rollout file open for appending, and flushes each line
// (codex-rs/rollout/src/recorder.rs, JsonlWriter). So a codex process holding an open
// sessions/YYYY/MM/DD/rollout-*.jsonl is a running session, and the end of that file says what it is doing.
// The approval prompt itself is never written to the file (rollout/src/policy.rs: ExecApprovalRequest,
// RequestUserInput... are "transient"), so "waiting for you" is inferred: see `RolloutState.verdict`.

/// What the tail of one rollout file says.
public struct RolloutState: Equatable, Sendable {
    public var thread = ""
    public var cwd = ""
    /// A sub-agent, a guardian review or an internal job: part of another session, not shown on its own.
    public var hidden = false
    /// A turn started and has not completed or been aborted.
    public var inTurn = false
    /// False when the last turn ran with approval_policy "never": nothing can stop to ask.
    public var approvals = true
    /// Tool calls written to the file with no output yet, oldest first.
    public var open: [Call] = []

    public struct Call: Equatable, Sendable {
        public var id: String
        public var name: String
        public var at: Date
    }

    public init() {}

    /// Tools that can stop and ask the user: shell commands and patches (approval), and the plan-mode question.
    /// Anything else that runs long (sub-agents, MCP tools, `wait`, `write_stdin`) counts as working.
    static let asking: Set<String> = ["exec_command", "shell", "shell_command", "container.exec", "local_shell",
                                      "apply_patch", "request_permissions"]
    static let question: Set<String> = ["request_user_input"]

    /// Reads the lines in order; `text` may start in the middle of the file (the first, partial line is skipped by the caller).
    public static func parse(_ text: String, into s: inout RolloutState) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.first == "{",
                  let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let p = j["payload"] as? [String: Any] else { continue }
            let at = (j["timestamp"] as? String).flatMap(CodexParser.iso) ?? .distantPast
            switch j["type"] as? String {
            case "session_meta":
                s.thread = p["id"] as? String ?? s.thread
                s.cwd = p["cwd"] as? String ?? s.cwd
                s.hidden = isHidden(p)
            case "turn_context":
                // A string ("on-request", "never"...) or an object for the granular policy.
                s.approvals = (p["approval_policy"] as? String) != "never"
            case "event_msg":
                switch p["type"] as? String {
                case "task_started", "turn_started": s.inTurn = true; s.open = []
                case "task_complete", "turn_complete", "turn_aborted": s.inTurn = false; s.open = []
                default: break
                }
            case "response_item":
                let t = p["type"] as? String ?? ""
                let id = p["call_id"] as? String ?? p["id"] as? String ?? ""
                if t == "function_call" || t == "custom_tool_call" || t == "local_shell_call" {
                    s.open.append(Call(id: id, name: t == "local_shell_call" ? "local_shell" : p["name"] as? String ?? "", at: at))
                } else if t.hasSuffix("_output") {
                    s.open.removeAll { $0.id == id }
                }
            default: break
            }
        }
    }

    static func isHidden(_ meta: [String: Any]) -> Bool {
        if meta["parent_thread_id"] is String { return true }
        if let ts = meta["thread_source"] as? String, ts != "user" { return true }
        // "cli", "vscode", "exec", "mcp" are strings; sub-agents and internal jobs are objects ({"subagent": ...}).
        if let src = meta["source"], !(src is String) { return true }
        return false
    }

    /// Working, waiting for you, or idle.
    /// - lastWrite: when the file last changed. A prompt stops the writing; a command that runs keeps a child process.
    /// - newestChild: start time of the newest process under the session's process (nil: none).
    public func verdict(now: Date, lastWrite: Date, newestChild: Date?) -> (busy: Bool, waiting: Bool) {
        guard inTurn else { return (false, false) }
        if open.contains(where: { Self.question.contains($0.name) }) { return (false, true) }
        if approvals, let c = open.first(where: { Self.asking.contains($0.name) }),
           now.timeIntervalSince(max(lastWrite, c.at)) >= 3,
           (newestChild ?? .distantPast) < c.at.addingTimeInterval(-1) {
            return (false, true)          // the call sits there, nothing runs it: an approval prompt is up
        }
        return (true, false)
    }
}

public enum CodexSessions {
    /// Running Codex sessions, one per open rollout file. Never reads prompts or answers: only the
    /// session header (id, cwd), turn markers and tool-call names and ids.
    public static func list(home: String = CodexCLI.home, now: Date = Date()) -> [AgentSession] {
        #if os(macOS)
        let root = URL(fileURLWithPath: home + "/sessions").resolvingSymlinksInPath().path + "/"
        let procs = Proc.all()
        let names = threadNames(home: home)
        var seen = Set<String>(), out: [AgentSession] = []
        for p in procs where p.comm.lowercased().contains("codex") {
            for path in Proc.openFiles(p.pid) where path.hasPrefix(root) && path.hasSuffix(".jsonl")
                && (path as NSString).lastPathComponent.hasPrefix("rollout-") {
                guard !seen.contains(path), let s = read(path) else { continue }
                seen.insert(path)
                if s.hidden { continue }
                let mtime = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date ?? now
                let v = s.verdict(now: now, lastWrite: mtime, newestChild: Proc.newestDescendant(of: p.pid, in: procs))
                var name = names[s.thread] ?? ""
                if name.isEmpty { name = (s.cwd as NSString).lastPathComponent }
                out.append(AgentSession(pid: p.pid, name: name, cwd: s.cwd, busy: v.busy, waiting: v.waiting,
                                        git: s.cwd.isEmpty ? nil : Git.info(cwd: s.cwd), thread: s.thread))
            }
        }
        return out.sorted { ($0.pid, $0.thread) < ($1.pid, $1.thread) }
        #else
        return []
        #endif
    }

    /// The header line and the last 256 KB (1 MB when no turn marker shows up in the first window).
    static func read(_ path: String) -> RolloutState? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var s = RolloutState()
        // The header (session_meta) is the first line; it holds the base instructions, so it can be long.
        let head = h.readData(ofLength: 512 * 1024)
        if let nl = head.firstIndex(of: UInt8(ascii: "\n")) {
            RolloutState.parse(String(decoding: head[..<nl], as: UTF8.self), into: &s)
        }
        guard !s.thread.isEmpty else { return nil }
        let size = (try? h.seekToEnd()) ?? 0
        var t = s
        for window: UInt64 in [256 * 1024, 1024 * 1024] {
            t = s
            let from = size > window ? size - window : 0
            try? h.seek(toOffset: from)
            var data = h.readDataToEndOfFile()
            if from > 0, let nl = data.firstIndex(of: UInt8(ascii: "\n")) { data = data[(nl + 1)...] }
            let text = String(decoding: data, as: UTF8.self)
            RolloutState.parse(text, into: &t)
            if from == 0 || text.contains("\"task_") || text.contains("\"turn_") { break }
        }
        return t
    }

    /// session_index.jsonl: names given to threads, append-only, the last entry wins.
    static func threadNames(home: String) -> [String: String] {
        let path = home + "/session_index.jsonl"
        guard let h = FileHandle(forReadingAtPath: path) else { return [:] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 1_048_576 ? size - 1_048_576 : 0)
        var out: [String: String] = [:]
        for line in String(decoding: h.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n") {
            guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = j["id"] as? String, let n = j["thread_name"] as? String else { continue }
            out[id] = n
        }
        return out
    }
}

#if os(macOS)
/// The user's processes and their open files, through sysctl and libproc (no `ps`/`lsof` every few seconds).
struct Proc {
    var pid: Int32
    var ppid: Int32
    var start: Date
    var comm: String

    static func all() -> [Proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: getuid())]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var buf = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = buf.count * stride
        guard sysctl(&mib, 4, &buf, &size, nil, 0) == 0 else { return [] }
        return buf.prefix(size / stride).map { k in
            let t = k.kp_proc.p_un.__p_starttime
            let comm = withUnsafeBytes(of: k.kp_proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            return Proc(pid: k.kp_proc.p_pid, ppid: k.kp_eproc.e_ppid,
                        start: Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000), comm: comm)
        }
    }

    /// Paths of the files a process has open.
    static func openFiles(_ pid: Int32) -> [String] {
        let need = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard need > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(need) / stride + 8)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard got > 0 else { return [] }
        var out: [String] = []
        for fd in fds.prefix(Int(got) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var v = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &v, size) == size else { continue }
            out.append(withUnsafeBytes(of: v.pvip.vip_path) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
        }
        return out
    }

    /// The newest process started under `pid` (children, grandchildren...): a command Codex is running.
    static func newestDescendant(of pid: Int32, in procs: [Proc]) -> Date? {
        var kids: [Int32: [Proc]] = [:]
        for p in procs { kids[p.ppid, default: []].append(p) }
        var stack = kids[pid] ?? [], newest: Date?, seen = Set<Int32>()
        while let p = stack.popLast() {
            guard seen.insert(p.pid).inserted else { continue }
            if newest == nil || p.start > newest! { newest = p.start }
            stack += kids[p.pid] ?? []
        }
        return newest
    }
}
#endif
