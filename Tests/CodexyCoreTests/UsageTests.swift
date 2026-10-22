import XCTest
@testable import CodexyCore

// Fixtures follow the real shapes seen from codex-cli 0.163 (app-server and rollout files), anonymised.
final class UsageTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_600_000)

    func testAppServerAnswer() throws {
        let line = #"{"id":2,"result":{"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","limitName":null,"primary":{"usedPercent":42,"windowDurationMins":300,"resetsAt":1792610000},"secondary":{"usedPercent":7.6,"windowDurationMins":10080,"resetsAt":1793000000},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus"}}}"#
        let l = try XCTUnwrap(CodexParser.appServer(Data(line.utf8), now: now))
        XCTAssertEqual(l.source, .appServer)
        XCTAssertEqual(l.plan, "plus")
        XCTAssertEqual(l.limits.map(\.name), ["5h", "week"])
        XCTAssertEqual(l.session, UsageLine(percent: 42, reset: Date(timeIntervalSince1970: 1_792_610_000)))
        XCTAssertEqual(l.week?.percent, 8)
    }

    func testErrorAnswerGivesNothing() {
        XCTAssertNil(CodexParser.appServer(Data(#"{"id":2,"error":{"code":-32600,"message":"not logged in"}}"#.utf8)))
    }

    func testWindowsArePickedByLengthNotOrder() throws {
        let rl: [String: Any] = ["primary": ["usedPercent": 3, "windowDurationMins": 10080, "resetsAt": 1793000000],
                                 "secondary": ["usedPercent": 50, "windowDurationMins": 300, "resetsAt": 1792610000]]
        let l = try XCTUnwrap(CodexParser.limits(rl, source: .appServer, asOf: now, now: now))
        XCTAssertEqual(l.session?.percent, 50)
        XCTAssertEqual(l.week?.percent, 3)
    }

    func testSessionFileTakesTheLastTokenCountAndZeroesPastResets() throws {
        let text = """
        {"timestamp":"2026-10-19T14:00:00.000Z","type":"session_meta","payload":{"id":"x","cwd":"/demo"}}
        {"timestamp":"2026-10-19T14:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":5.0,"window_minutes":300,"resets_at":1792610000},"plan_type":"plus"}}}
        {"timestamp":"2026-10-19T14:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{},"rate_limits":{"limit_id":"codex","primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1792500000},"secondary":{"used_percent":5.0,"window_minutes":10080,"resets_at":1793000000},"plan_type":"plus"}}}
        {"timestamp":"2026-10-19T14:03:00.000Z","type":"event_msg","payload":{"type":"agent_message"}}
        """
        let l = try XCTUnwrap(CodexParser.sessionFile(text, now: now))
        XCTAssertEqual(l.source, .sessionFile)
        XCTAssertEqual(l.asOf, CodexParser.iso("2026-10-19T14:02:00.000Z"))
        // The 5h reset (1792500000) is before `now`: that window has started over since the event.
        XCTAssertEqual(l.session, UsageLine(percent: 0, reset: nil))
        XCTAssertEqual(l.week?.percent, 5)
    }

    func testSessionFileWithoutLimits() {
        XCTAssertNil(CodexParser.sessionFile(#"{"type":"session_meta","payload":{}}"#, now: now))
    }

    func testLatestReadsNewestPlainFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("codexy-\(UUID())/2026/10/19")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()) }
        let ev = #"{"timestamp":"2026-10-19T14:02:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":33,"window_minutes":300,"resets_at":1792610000}}}}"#
        try ev.write(to: dir.appendingPathComponent("rollout-a.jsonl"), atomically: true, encoding: .utf8)
        let root = dir.deletingLastPathComponent().deletingLastPathComponent().path
        XCTAssertEqual(SessionFiles.latest(root: root, now: now)?.session?.percent, 33)
    }

    func testCreditsAndResetCredits() throws {
        // Shape from codex-rs app-server-protocol v2 (GetAccountRateLimitsResponse), anonymised.
        let line = #"{"id":2,"result":{"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":1792610000},"credits":{"hasCredits":true,"unlimited":false,"balance":"125.5"},"planType":"pro"},"rateLimitsByLimitId":null,"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"a","resetType":"codexRateLimits","status":"available","grantedAt":1792000000,"expiresAt":1793500000,"title":null,"description":null},{"id":"b","resetType":"codexRateLimits","status":"redeemed","grantedAt":1792000000,"expiresAt":1792700000,"title":null,"description":null},{"id":"c","resetType":"codexRateLimits","status":"available","grantedAt":1792000000,"expiresAt":null,"title":null,"description":null}]},"accountId":null,"rateLimitUpsell":null}}"#
        let l = try XCTUnwrap(CodexParser.appServer(Data(line.utf8), now: now))
        XCTAssertEqual(l.credits, CodexCredits(hasCredits: true, unlimited: false, balance: "125.5"))
        XCTAssertEqual(l.credits?.worthShowing, true)
        // The redeemed one does not count for the expiry; the one without expiry has none.
        XCTAssertEqual(l.resetCredits, ResetCredits(available: 2, nextExpiry: Date(timeIntervalSince1970: 1_793_500_000)))
    }

    func testNoCreditsWorthShowing() throws {
        let line = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":1792610000},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"}},"rateLimitResetCredits":{"availableCount":0,"credits":null}}}"#
        let l = try XCTUnwrap(CodexParser.appServer(Data(line.utf8), now: now))
        XCTAssertEqual(l.credits?.worthShowing, false)
        XCTAssertEqual(l.resetCredits, ResetCredits(available: 0, nextExpiry: nil))
        // An older codex without the field: nothing, not zero.
        let old = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":1792610000}}}}"#
        XCTAssertNil(try XCTUnwrap(CodexParser.appServer(Data(old.utf8), now: now)).resetCredits)
    }

    func testExtraLimitsAndReached() throws {
        let line = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1792610000},"rateLimitReachedType":"rate_limit_reached"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1792610000}},"spark":{"limitId":"spark","limitName":"GPT-Spark","primary":{"usedPercent":12,"windowDurationMins":300,"resetsAt":1792610000},"secondary":{"usedPercent":3,"windowDurationMins":10080,"resetsAt":1793000000}}}}}"#
        let l = try XCTUnwrap(CodexParser.appServer(Data(line.utf8), now: now))
        XCTAssertEqual(l.reachedType, "rate_limit_reached")
        XCTAssertEqual(l.extras.map(\.name), ["GPT-Spark"])
        XCTAssertEqual(l.extras.first?.week?.percent, 3)
    }

    func testVersion() {
        XCTAssertEqual(CodexVersion.parse("codex-cli 0.163.0\n"), "0.163.0")
        XCTAssertEqual(CodexVersion.parse("rust-v0.170.1"), "0.170.1")
        XCTAssertTrue(CodexVersion.isNewer("0.170.0", than: "0.163.2"))
        XCTAssertFalse(CodexVersion.isNewer("0.163.0", than: "0.163.0"))
    }

    func testSessionFileCredits() throws {
        let text = #"{"timestamp":"2026-10-19T14:02:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1792610000},"credits":{"has_credits":true,"unlimited":true,"balance":null},"plan_type":"plus"}}}"#
        let l = try XCTUnwrap(CodexParser.sessionFile(text, now: now))
        XCTAssertEqual(l.credits, CodexCredits(hasCredits: true, unlimited: true, balance: nil))
        XCTAssertNil(l.resetCredits)
    }
}
