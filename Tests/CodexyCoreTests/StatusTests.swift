import XCTest
@testable import CodexyCore

// Shapes from status.openai.com (incident.io), 2026-10-22, trimmed to the keys we read.
final class StatusTests: XCTestCase {
    func page(affected: String, incidents: String = "[]") -> Data {
        Data("""
        {"summary":{"name":"OpenAI","components":[
          {"id":"c1","name":"Responses"},{"id":"c2","name":"ChatGPT Work"},{"id":"c3","name":"Codex in ChatGPT Desktop"},
          {"id":"c4","name":"Codex Web"},{"id":"c5","name":"CLI"},{"id":"c6","name":"VS Code extension"}],
         "structure":{"items":[
          {"group":{"id":"g1","name":"APIs","components":[{"component_id":"c1","name":"Responses"}]}},
          {"group":{"id":"g2","name":"ChatGPT","components":[{"component_id":"c2","name":"ChatGPT Work"},{"component_id":"c3","name":"Codex in ChatGPT Desktop"}]}},
          {"group":{"id":"g3","name":"Codex","components":[{"component_id":"c4","name":"Codex Web"},{"component_id":"c5","name":"CLI"},{"component_id":"c6","name":"VS Code extension"}]}}]},
         "affected_components":\(affected),
         "ongoing_incidents":\(incidents),
         "scheduled_maintenances":[]}}
        """.utf8)
    }

    func testAllFine() throws {
        let s = try XCTUnwrap(StatusFetcher.parsePage(page(affected: "[]")))
        XCTAssertEqual(s.level, .ok)
        XCTAssertFalse(s.onlyOthersAffected)
    }

    func testCodexDegraded() throws {
        let inc = #"[{"id":"i1","name":"Degraded performance in Codex and ChatGPT Work","status":"identified","affected_components":[{"component_id":"c3","status":"degraded_performance"},{"component_id":"c2","status":"degraded_performance"}]}]"#
        let s = try XCTUnwrap(StatusFetcher.parsePage(page(affected: #"[{"component_id":"c3","status":"degraded_performance"},{"component_id":"c2","status":"degraded_performance"}]"#, incidents: inc)))
        XCTAssertEqual(s.level, .minor)
        XCTAssertEqual(s.text, "Degraded performance in Codex and ChatGPT Work")
        XCTAssertEqual(s.affected.filter(\.important).map(\.name), ["Codex in ChatGPT Desktop"])
    }

    func testCliOutageIsMajor() throws {
        let s = try XCTUnwrap(StatusFetcher.parsePage(page(affected: #"[{"component_id":"c5","status":"full_outage"},{"component_id":"c4","status":"degraded_performance"}]"#)))
        XCTAssertEqual(s.level, .major)
    }

    func testOnlyOthers() throws {
        let inc = #"[{"id":"i2","name":"Errors in Responses","affected_components":[{"component_id":"c1","status":"partial_outage"}]}]"#
        let s = try XCTUnwrap(StatusFetcher.parsePage(page(affected: #"[{"component_id":"c1","status":"partial_outage"}]"#, incidents: inc)))
        XCTAssertEqual(s.level, .ok)
        XCTAssertTrue(s.onlyOthersAffected)
        XCTAssertEqual(s.detail, [])     // an incident that does not touch Codex is not listed
    }

    func testSummaryFallbackWithoutCodexUsesIndicator() throws {
        let d = Data(#"{"page":{},"status":{"indicator":"minor","description":"Partially Degraded Service"},"components":[{"name":"Responses","status":"degraded_performance"}]}"#.utf8)
        let s = try XCTUnwrap(StatusFetcher.parseSummary(d))
        XCTAssertEqual(s.level, .minor)
        XCTAssertEqual(s.text, "Partially Degraded Service")
    }

    func testSummaryWithCodexComponent() throws {
        let d = Data(#"{"status":{"indicator":"minor","description":"x"},"components":[{"name":"Codex in ChatGPT Desktop","status":"operational"},{"name":"Responses","status":"degraded_performance"}]}"#.utf8)
        let s = try XCTUnwrap(StatusFetcher.parseSummary(d))
        XCTAssertEqual(s.level, .ok)
        XCTAssertTrue(s.onlyOthersAffected)
    }

    func testGarbage() {
        XCTAssertNil(StatusFetcher.parsePage(Data("<html>".utf8)))
        XCTAssertNil(StatusFetcher.parseSummary(Data("{}".utf8)))
    }
}
