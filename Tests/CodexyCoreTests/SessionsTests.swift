import XCTest
@testable import CodexyCore

// Rollout lines in the shapes codex-rs writes (rollout/src/recorder.rs), anonymised and trimmed.
final class SessionsTests: XCTestCase {
    let t0 = CodexParser.iso("2026-10-21T14:00:00.000Z")!

    func state(_ lines: [String]) -> RolloutState {
        var s = RolloutState(); RolloutState.parse(lines.joined(separator: "\n"), into: &s); return s
    }
    let meta = #"{"timestamp":"2026-10-21T14:00:00.000Z","type":"session_meta","payload":{"id":"t-1","cwd":"/demo/web-app","originator":"codex_cli_rs","source":"cli"}}"#
    let ctx = #"{"timestamp":"2026-10-21T14:00:01.000Z","type":"turn_context","payload":{"cwd":"/demo/web-app","approval_policy":"on-request","model":"m"}}"#
    let started = #"{"timestamp":"2026-10-21T14:00:01.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"1"}}"#
    let call = #"{"timestamp":"2026-10-21T14:00:10.000Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{}","call_id":"c1"}}"#
    let output = #"{"timestamp":"2026-10-21T14:00:12.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"c1","output":"ok"}}"#
    let complete = #"{"timestamp":"2026-10-21T14:00:20.000Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"1"}}"#

    func testHeaderAndIdleAfterTheTurn() {
        let s = state([meta, ctx, started, call, output, complete])
        XCTAssertEqual(s.thread, "t-1"); XCTAssertEqual(s.cwd, "/demo/web-app")
        XCTAssertFalse(s.hidden); XCTAssertFalse(s.inTurn); XCTAssertTrue(s.open.isEmpty)
        let v = s.verdict(now: t0.addingTimeInterval(60), lastWrite: t0.addingTimeInterval(20), newestChild: nil)
        XCTAssertFalse(v.busy); XCTAssertFalse(v.waiting)
    }

    func testThinkingIsWorking() {
        let s = state([meta, ctx, started])
        let v = s.verdict(now: t0.addingTimeInterval(30), lastWrite: t0.addingTimeInterval(1), newestChild: nil)
        XCTAssertTrue(v.busy); XCTAssertFalse(v.waiting)
    }

    func testCommandWithNoProcessAndQuietFileIsWaiting() {
        let s = state([meta, ctx, started, call])
        XCTAssertEqual(s.open.map(\.name), ["exec_command"])
        let at = t0.addingTimeInterval(10)
        // Just written: give it a moment before calling it a prompt.
        XCTAssertTrue(s.verdict(now: at.addingTimeInterval(1), lastWrite: at, newestChild: nil).busy)
        XCTAssertTrue(s.verdict(now: at.addingTimeInterval(5), lastWrite: at, newestChild: nil).waiting)
        // A process started for the call: the command runs.
        XCTAssertTrue(s.verdict(now: at.addingTimeInterval(60), lastWrite: at, newestChild: at.addingTimeInterval(0.2)).busy)
        // An old child (an MCP server from the start) does not count.
        XCTAssertTrue(s.verdict(now: at.addingTimeInterval(60), lastWrite: at, newestChild: t0).waiting)
    }

    func testNeverAskMeansNeverWaiting() {
        let never = ctx.replacingOccurrences(of: "on-request", with: "never")
        let s = state([meta, never, started, call])
        XCTAssertFalse(s.approvals)
        XCTAssertTrue(s.verdict(now: t0.addingTimeInterval(99), lastWrite: t0.addingTimeInterval(10), newestChild: nil).busy)
    }

    func testQuestionToTheUserIsWaitingAtOnce() {
        let ask = #"{"timestamp":"2026-10-21T14:00:10.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","arguments":"{}","call_id":"q1"}}"#
        let s = state([meta, ctx, started, ask])
        XCTAssertTrue(s.verdict(now: t0.addingTimeInterval(10), lastWrite: t0.addingTimeInterval(10), newestChild: nil).waiting)
    }

    func testOtherLongToolsAreWorking() {
        let wait = #"{"timestamp":"2026-10-21T14:00:10.000Z","type":"response_item","payload":{"type":"function_call","name":"wait","arguments":"{}","call_id":"w1"}}"#
        let s = state([meta, ctx, started, wait])
        XCTAssertTrue(s.verdict(now: t0.addingTimeInterval(300), lastWrite: t0.addingTimeInterval(10), newestChild: nil).busy)
    }

    func testPatchAndAbort() {
        let patch = #"{"timestamp":"2026-10-21T14:00:10.000Z","type":"response_item","payload":{"type":"custom_tool_call","name":"apply_patch","input":"x","call_id":"p1"}}"#
        let aborted = #"{"timestamp":"2026-10-21T14:00:30.000Z","type":"event_msg","payload":{"type":"turn_aborted","reason":"interrupted"}}"#
        XCTAssertEqual(state([meta, ctx, started, patch]).open.map(\.name), ["apply_patch"])
        let s = state([meta, ctx, started, patch, aborted])
        XCTAssertFalse(s.inTurn); XCTAssertTrue(s.open.isEmpty)
    }

    func testSubAgentsAndInternalJobsAreHidden() {
        let sub = #"{"timestamp":"2026-10-21T14:00:00.000Z","type":"session_meta","payload":{"id":"t-2","cwd":"/demo","source":{"subagent":"review"}}}"#
        let child = #"{"timestamp":"2026-10-21T14:00:00.000Z","type":"session_meta","payload":{"id":"t-3","cwd":"/demo","source":"cli","parent_thread_id":"t-1"}}"#
        XCTAssertTrue(state([sub]).hidden)
        XCTAssertTrue(state([child]).hidden)
        XCTAssertFalse(state([meta]).hidden)
    }

    func testReadsHeaderAndTailOfAFileAndNames() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("codexy-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("rollout-2026-10-21T14-00-00-t-1.jsonl")
        // A long turn: the start marker sits far before the last 256 KB.
        let filler = #"{"timestamp":"2026-10-21T14:00:05.000Z","type":"response_item","payload":{"type":"reasoning","summary":[],"encrypted_content":""# + String(repeating: "x", count: 1000) + #""}}"#
        let lines = [meta, ctx, started] + Array(repeating: filler, count: 400) + [call]
        try (lines.joined(separator: "\n") + "\n").write(to: f, atomically: true, encoding: .utf8)
        let s = try XCTUnwrap(CodexSessions.read(f.path))
        XCTAssertEqual(s.thread, "t-1"); XCTAssertTrue(s.inTurn); XCTAssertEqual(s.open.map(\.id), ["c1"])

        try (#"{"id":"t-1","thread_name":"old","updated_at":"x"}"# + "\n" + #"{"id":"t-1","thread_name":"login fix","updated_at":"y"}"# + "\n")
            .write(to: dir.appendingPathComponent("session_index.jsonl"), atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexSessions.threadNames(home: dir.path)["t-1"], "login fix")
    }

    func testDaemonThreadStatus() {
        typealias D = CodexDaemon
        XCTAssertEqual(D.state(["type": "idle"]), D.State(busy: false, waiting: false))
        XCTAssertEqual(D.state(["type": "active", "activeFlags": []]), D.State(busy: true, waiting: false))
        XCTAssertEqual(D.state(["type": "active", "activeFlags": ["waitingOnApproval"]]), D.State(busy: false, waiting: true))
        XCTAssertEqual(D.state(["type": "active", "activeFlags": ["waitingOnUserInput"]]), D.State(busy: false, waiting: true))
        XCTAssertNil(D.state(["type": "notLoaded"]))
        let th: [String: Any] = ["status": ["type": "idle"], "source": "vscode", "threadSource": "user", "parentThreadId": NSNull(), "cwd": "/demo/web", "name": NSNull()]
        XCTAssertEqual(D.thread(th), D.Thread(state: D.State(busy: false, waiting: false), cwd: "/demo/web", name: nil, hidden: false))
        XCTAssertEqual(D.thread(th.merging(["parentThreadId": "p1"]) { $1 })?.hidden, true)        // a sub-agent
        XCTAssertEqual(D.thread(th.merging(["source": ["subAgent": "review"]]) { $1 })?.hidden, true)
        // No daemon socket: nil, so the caller keeps the guess from the file.
        XCTAssertNil(D.threads(home: "/nonexistent-\(UUID())"))
    }
}
