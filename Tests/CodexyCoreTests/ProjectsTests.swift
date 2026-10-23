import XCTest
@testable import CodexyCore

// Made-up rollout lines in the shape Codex writes them (no real prompts, paths or ids).
final class ProjectsTests: XCTestCase {
    let since = CodexParser.iso("2026-10-19T00:00:00Z")!

    /// A fresh Codex folder with one day of sessions, removed after the test.
    func makeHome() throws -> String {
        let home = NSTemporaryDirectory() + "codexy-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/sessions/2026/10/19", withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(atPath: home) }
        return home
    }

    func write(_ home: String, _ name: String, _ lines: [String], append: Bool = false) throws {
        let path = home + "/sessions/2026/10/19/" + name
        let text = lines.map { $0 + "\n" }.joined()
        if append, let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try h.close()
        } else {
            try text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func meta(_ at: String, id: String, cwd: String, repo: String? = nil, forkedFrom: String? = nil) -> String {
        let git = repo.map { #","git":{"branch":"main","repository_url":"\#($0)"}"# } ?? ""
        let fork = forkedFrom.map { #","forked_from_id":"\#($0)""# } ?? ""
        return #"{"timestamp":"\#(at)","type":"session_meta","payload":{"id":"\#(id)","timestamp":"\#(at)","cwd":"\#(cwd)","originator":"codex_cli_rs","cli_version":"0.163.0","base_instructions":null\#(fork)\#(git)}}"#
    }

    func turn(_ at: String, model: String, id: String) -> String {
        #"{"timestamp":"\#(at)","type":"turn_context","payload":{"turn_id":"\#(id)","cwd":"/demo/x","approval_policy":"on-request","model":"\#(model)"}}"#
    }

    func count(_ at: String, total: (Int, Int, Int), last: (Int, Int, Int)) -> String {
        func u(_ t: (Int, Int, Int)) -> String {
            #"{"input_tokens":\#(t.0),"cached_input_tokens":\#(t.1),"output_tokens":\#(t.2),"reasoning_output_tokens":0,"total_tokens":\#(t.0 + t.2)}"#
        }
        return #"{"timestamp":"\#(at)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":\#(u(total)),"last_token_usage":\#(u(last)),"model_context_window":272000},"rate_limits":null}}"#
    }

    // A message that quotes the markers: escaped inside the JSON string, so it must never be read as one.
    let chatter = #"{"timestamp":"2026-10-19T14:00:30.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\"}} {\"type\":\"turn_context\"}"}]}}"#

    func testCompressedRolloutIsReadOnce() throws {
        guard let zstd = CodexCLI.zstd else { throw XCTSkip("zstd not installed") }
        let home = try makeHome()
        let name = "rollout-2026-10-19T14-00-00-z.jsonl"
        try write(home, name, [
            meta("2026-10-19T14:00:00.000Z", id: "z1", cwd: "/demo/web", repo: "git@github.com:me/web-app.git"),
            turn("2026-10-19T14:00:01.000Z", model: "gpt-5.1-codex", id: "u1"),
            count("2026-10-19T14:01:00.000Z", total: (1000, 200, 100), last: (1000, 200, 100)),
        ])
        let path = home + "/sessions/2026/10/19/" + name
        XCTAssertNotNil(CodexCLI.run(zstd, ["-q", "--rm", path, "-o", path + ".zst"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        let s = RolloutScanner()
        let u = s.scan(home: home, since: since)
        XCTAssertEqual(u.total["web-app"] ?? 0, 1620, accuracy: 0.001)    // (1000-200) + 0.1*200 + 8*100
        XCTAssertEqual(u.turnCount(), 1)
        // Unchanged: the same answer without reading it again.
        XCTAssertEqual(s.scan(home: home, since: since).total["web-app"] ?? 0, 1620, accuracy: 0.001)
    }

    func testTokensPerDayByModel() throws {
        let home = try makeHome()
        try write(home, "rollout-2026-10-19T14-00-00-a.jsonl", [
            meta("2026-10-19T14:00:00.000Z", id: "t1", cwd: "/demo/web"),
            turn("2026-10-19T14:00:01.000Z", model: "gpt-5.1-codex", id: "u1"),
            count("2026-10-19T14:01:00.000Z", total: (1000, 200, 100), last: (1000, 200, 100)),
            count("2026-10-19T14:01:01.000Z", total: (1000, 200, 100), last: (1000, 200, 100)),    // sent again
            turn("2026-10-19T14:02:00.000Z", model: "gpt-5.1-codex-mini", id: "u2"),
            count("2026-10-19T14:03:00.000Z", total: (1500, 300, 150), last: (500, 100, 50)),
        ])
        let u = RolloutScanner().scan(home: home, since: since)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = CodexParser.iso("2026-10-20T10:00:00Z")!
        let d = u.tokenDays(days: 2, maxModels: 1, now: now, calendar: cal)
        XCTAssertEqual(d.days.count, 2)
        // The biggest model keeps its line; the other goes to "other". Total is input + output.
        XCTAssertEqual(d.lines.map(\.key), ["gpt-5.1-codex", "other"])
        XCTAssertEqual(d.lines[0].values, [1100, 0])
        XCTAssertEqual(d.lines[1].values, [550, 0])
        XCTAssertEqual(d.totals["gpt-5.1-codex"], TokenCount(input: 1000, cached: 200, output: 100))
        XCTAssertEqual(d.totals["other"], TokenCount(input: 500, cached: 100, output: 50))
    }

    func testCountsDeltasOnceAndNamesTheProject() throws {
        let home = try makeHome()
        try write(home, "rollout-2026-10-19T14-00-00-a.jsonl", [
            meta("2026-10-19T14:00:00.000Z", id: "t1", cwd: "/demo/web", repo: "git@github.com:me/web-app.git"),
            turn("2026-10-19T14:00:01.000Z", model: "gpt-5.1-codex", id: "u1"),
            chatter,
            count("2026-10-19T14:01:00.000Z", total: (1000, 200, 100), last: (1000, 200, 100)),
            count("2026-10-19T14:01:01.000Z", total: (1000, 200, 100), last: (1000, 200, 100)),    // sent again
            count("2026-10-19T14:02:00.000Z", total: (3000, 1200, 300), last: (2000, 1000, 200)),
        ])
        let s = RolloutScanner()
        let u = s.scan(home: home, since: since)
        // (1000-200) + 0.1*200 + 8*100 = 1620; then (2000-1000) + 0.1*1000 + 8*200 = 2700
        XCTAssertEqual(u.total["web-app"] ?? 0, 4320, accuracy: 0.001)
        XCTAssertEqual(u.models().map(\.family), ["gpt-5.1-codex"])
        XCTAssertEqual(u.turnCount(), 1)
        XCTAssertEqual(u.sessionCount(), 1)
        XCTAssertEqual(u.paths["web-app"], "/demo/web")

        // A second scan reads only what was added.
        try write(home, "rollout-2026-10-19T14-00-00-a.jsonl", [
            turn("2026-10-19T15:00:00.000Z", model: "gpt-5.1-codex-mini", id: "u2"),
            count("2026-10-19T15:01:00.000Z", total: (4000, 1200, 400), last: (1000, 0, 100)),
        ], append: true)
        let v = s.scan(home: home, since: since)
        // (1000 + 800) * 0.2 for the mini model
        XCTAssertEqual(v.total["web-app"] ?? 0, 4320 + 360, accuracy: 0.001)
        XCTAssertEqual(v.turnCount(), 2)
        XCTAssertEqual(Set(v.models().map(\.family)), ["gpt-5.1-codex", "gpt-5.1-codex-mini"])
        XCTAssertEqual(v.heat(now: CodexParser.iso("2026-10-19T20:00:00Z")!).flatMap { $0 }.reduce(0, +), 4680, accuracy: 0.001)
    }

    func testForkCopiesAreNotCountedTwice() throws {
        let home = try makeHome()
        try write(home, "rollout-2026-10-19T14-00-00-p.jsonl", [
            meta("2026-10-19T14:00:00.000Z", id: "p", cwd: "/demo/api"),
            turn("2026-10-19T14:00:01.000Z", model: "gpt-5.1-codex", id: "u1"),
            count("2026-10-19T14:01:00.000Z", total: (1000, 0, 100), last: (1000, 0, 100)),
        ])
        // The fork starts with a copy of the parent's lines, then does its own turn.
        try write(home, "rollout-2026-10-19T16-00-00-f.jsonl", [
            meta("2026-10-19T16:00:00.000Z", id: "f", cwd: "/demo/api", forkedFrom: "p"),
            turn("2026-10-19T16:00:00.200Z", model: "gpt-5.1-codex", id: "u1"),
            count("2026-10-19T16:00:00.300Z", total: (1000, 0, 100), last: (1000, 0, 100)),
            turn("2026-10-19T16:05:00.000Z", model: "gpt-5.1-codex", id: "u2"),
            count("2026-10-19T16:06:00.000Z", total: (1500, 0, 150), last: (500, 0, 50)),
        ])
        let u = RolloutScanner().scan(home: home, since: since)
        // parent 1000 + 800; fork only its own 500 + 400
        XCTAssertEqual(u.total["api"] ?? 0, 1800 + 900, accuracy: 0.001)
        XCTAssertEqual(u.turnCount(), 2)
        XCTAssertEqual(u.sessionCount(), 2)
    }

    func testForkWhoseParentIsNotReadStartsFromItsFirstCount() throws {
        let home = try makeHome()
        try write(home, "rollout-2026-10-19T16-00-00-f.jsonl", [
            meta("2026-10-19T16:00:00.000Z", id: "f", cwd: "/demo/api", forkedFrom: "old"),
            turn("2026-10-19T16:05:00.000Z", model: "gpt-5.1-codex", id: "u2"),
            count("2026-10-19T16:06:00.000Z", total: (9000, 0, 900), last: (500, 0, 50)),   // carries the parent's totals
            count("2026-10-19T16:07:00.000Z", total: (9100, 0, 910), last: (100, 0, 10)),
        ])
        let u = RolloutScanner().scan(home: home, since: since)
        XCTAssertEqual(u.total["api"] ?? 0, 100 + 80, accuracy: 0.001)
    }

    func testOldEventsAreLeftOut() throws {
        let home = try makeHome()
        try write(home, "rollout-2026-10-18T10-00-00-o.jsonl", [
            meta("2026-10-18T10:00:00.000Z", id: "o", cwd: "/demo/old"),
            turn("2026-10-18T10:00:01.000Z", model: "gpt-5.1-codex", id: "u1"),
            count("2026-10-18T10:01:00.000Z", total: (1000, 0, 100), last: (1000, 0, 100)),
        ])
        let u = RolloutScanner().scan(home: home, since: since)
        XCTAssertTrue(u.hourly.isEmpty)
        XCTAssertEqual(u.turnCount(), 0)
        XCTAssertEqual(u.sessionCount(), 0)
    }

    func testNames() {
        XCTAssertEqual(CodexModel.key("GPT-5-2025-08-07"), "gpt-5")
        XCTAssertEqual(CodexModel.key(""), "other")
        XCTAssertEqual(CodexModel.display("gpt-5.1-codex-max"), "GPT-5.1 Codex Max")
        XCTAssertEqual(CodexModel.display("gpt-5"), "GPT-5")
        XCTAssertEqual(CodexModel.display("o4-mini"), "o4 Mini")
        XCTAssertEqual(RolloutScanner.repoName("https://github.com/me/web-app.git"), "web-app")
        XCTAssertEqual(RolloutScanner.repoName("git@github.com:me/web-app.git"), "web-app")
        XCTAssertEqual(RolloutScanner.repoName("https://github.com/me/web-app/"), "web-app")
        XCTAssertEqual(RolloutScanner.projectName(cwd: "/Users/me", repoURL: nil, home: "/Users/me"), "~")
        XCTAssertEqual(RolloutScanner.projectName(cwd: "/demo/notes/", repoURL: nil, home: "/Users/me"), "notes")
    }
}
