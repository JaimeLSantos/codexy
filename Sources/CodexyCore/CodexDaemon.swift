import Foundation
#if os(macOS)
import Darwin
#endif

// The exact state of each loaded Codex thread, from the app-server daemon the TUI starts
// (`codex app-server --listen unix://`, socket `~/.codex/app-server-control/app-server-control.sock`).
// It speaks WebSocket JSON-RPC: `thread/loaded/list` gives the ids, `thread/read` (no turns) gives
// `status`: notLoaded | idle | systemError | {active, activeFlags: [waitingOnApproval, waitingOnUserInput]}.
// Replaces the guess from the rollout file when the daemon answers; read-only, no prompt is read.

public enum CodexDaemon {
    public struct State: Equatable, Sendable {
        public var busy: Bool
        public var waiting: Bool
    }

    /// A loaded thread: its state and where it works. `name` is the title Codex gave it, never the prompt.
    public struct Thread: Equatable, Sendable {
        public var state: State
        public var cwd: String
        public var name: String?
        /// Sub-agents, guardian reviews and internal jobs: not a session the user opened.
        public var hidden: Bool
    }

    static func thread(_ th: [String: Any]) -> Thread? {
        guard let st = th["status"] as? [String: Any], let s = state(st) else { return nil }
        let user = (th["threadSource"] as? String).map { $0 == "user" } ?? true
        let hidden = th["parentThreadId"] is String || !(th["source"] is String) || !user || th["ephemeral"] as? Bool == true
        let name = (th["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return Thread(state: s, cwd: th["cwd"] as? String ?? "", name: name, hidden: hidden)
    }

    public static func socketPath(home: String = CodexCLI.home) -> String { home + "/app-server-control/app-server-control.sock" }

    /// A thread's `status` object as a session state; nil when it says nothing useful (not loaded).
    static func state(_ status: [String: Any]) -> State? {
        switch status["type"] as? String {
        case "idle", "systemError": return State(busy: false, waiting: false)
        case "active":
            let flags = status["activeFlags"] as? [String] ?? []
            let waits = flags.contains("waitingOnApproval") || flags.contains("waitingOnUserInput")
            return State(busy: !waits, waiting: waits)
        default: return nil
        }
    }

    /// Thread id -> thread for every loaded thread, or nil when the daemon is not there or does not answer in time.
    public static func threads(home: String = CodexCLI.home, timeout: TimeInterval = 2) -> [String: Thread]? {
        #if os(macOS)
        guard let c = Conn(path: socketPath(home: home), timeout: timeout) else { return nil }
        defer { c.close() }
        guard c.handshake(),
              c.send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["clientInfo": ["name": "codexy", "version": "0"]]]),
              c.send(["jsonrpc": "2.0", "method": "initialized"]),
              c.send(["jsonrpc": "2.0", "id": 2, "method": "thread/loaded/list", "params": [:]]),
              let list = c.answer(id: 2), let ids = (list["result"] as? [String: Any])?["data"] as? [String] else { return nil }
        var out: [String: Thread] = [:]
        for (n, id) in ids.enumerated() {
            let rid = 10 + n
            guard c.send(["jsonrpc": "2.0", "id": rid, "method": "thread/read", "params": ["threadId": id, "includeTurns": false]]),
                  let r = c.answer(id: rid), let res = r["result"] as? [String: Any] else { continue }
            let th = res["thread"] as? [String: Any] ?? res
            if let t = thread(th) { out[id] = t }
        }
        return out
        #else
        return nil
        #endif
    }
}

#if os(macOS)
/// One blocking client connection with the WebSocket framing we need: masked text frames out, whole text frames in.
private final class Conn {
    let fd: Int32
    var buf = Data()

    init?(path: String, timeout: TimeInterval) {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { p in for (i, b) in bytes.enumerated() { p[i] = b } }
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard ok == 0 else { Darwin.close(fd); return nil }
    }

    func close() { Darwin.close(fd) }

    private func write(_ d: Data) -> Bool {
        var off = 0
        return d.withUnsafeBytes { p in
            while off < d.count { let n = Darwin.write(fd, p.baseAddress! + off, d.count - off); if n <= 0 { return false }; off += n }
            return true
        }
    }

    private func fill(_ n: Int) -> Bool {
        while buf.count < n {
            var tmp = [UInt8](repeating: 0, count: 65536)
            let r = read(fd, &tmp, tmp.count)
            if r <= 0 { return false }                       // closed, or the timeout ran out
            buf.append(contentsOf: tmp[..<r])
        }
        return true
    }

    func handshake() -> Bool {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let req = "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: \(key)\r\nSec-WebSocket-Version: 13\r\n\r\n"
        guard write(Data(req.utf8)) else { return false }
        let end = Data("\r\n\r\n".utf8)
        while buf.range(of: end) == nil { if !fill(buf.count + 1) { return false } }
        let r = buf.range(of: end)!
        let head = String(decoding: buf[..<r.lowerBound], as: UTF8.self)
        buf.removeSubrange(..<r.upperBound)
        return head.hasPrefix("HTTP/1.1 101")
    }

    func send(_ obj: [String: Any]) -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return false }
        var f = Data([0x81])
        if d.count < 126 { f.append(UInt8(0x80 | d.count)) }
        else if d.count < 65536 { f.append(0x80 | 126); f.append(UInt8(d.count >> 8)); f.append(UInt8(d.count & 0xFF)) }
        else { f.append(0x80 | 127); for s in stride(from: 56, through: 0, by: -8) { f.append(UInt8((d.count >> s) & 0xFF)) } }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        f.append(contentsOf: mask)
        f.append(contentsOf: d.enumerated().map { $0.element ^ mask[$0.offset % 4] })
        return write(f)
    }

    /// Reads frames until the JSON-RPC answer with this id; notifications and other answers are skipped.
    func answer(id: Int) -> [String: Any]? {
        while true {
            guard fill(2) else { return nil }
            let op = buf[buf.startIndex] & 0x0F
            var len = Int(buf[buf.startIndex + 1] & 0x7F), head = 2
            if len == 126 { guard fill(4) else { return nil }; len = Int(buf[buf.startIndex + 2]) << 8 | Int(buf[buf.startIndex + 3]); head = 4 }
            else if len == 127 {
                guard fill(10) else { return nil }
                len = (2..<10).reduce(0) { $0 << 8 | Int(buf[buf.startIndex + $1]) }; head = 10
            }
            guard fill(head + len) else { return nil }
            let payload = buf[(buf.startIndex + head)..<(buf.startIndex + head + len)]
            buf.removeSubrange(..<(buf.startIndex + head + len))
            if op == 0x8 { return nil }                      // close
            guard op == 0x1, let j = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { continue }
            if (j["id"] as? NSNumber)?.intValue == id { return j }
        }
    }
}
#endif
