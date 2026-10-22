import XCTest
@testable import CodexyCore

final class PetTests: XCTestCase {
    let raw = """
    ---
    name: Dot
    a: #FF0000
    b: #00FF00
    ---
    [normal]
    a.................
    .b................
    """

    func testParseColoursMoodsAndFallbacks() throws {
        let p = try XCTUnwrap(PetParser.parse(raw, id: "Dot"))
        XCTAssertEqual(p.id, "dot"); XCTAssertEqual(p.name, "Dot")
        XCTAssertEqual(p.rows("crit"), p.rows("normal"))     // a missing mood borrows normal
        let px = p.pixels("normal", frame: ClawdFrame())
        XCTAssertEqual(px.map(\.color), ["#00FF00", "#FF0000"])
        XCTAssertEqual(px[1].rects, [PRect(0, 0, 1, 1)])
    }

    func testMovesShiftLowerAndClip() throws {
        let p = try XCTUnwrap(PetParser.parse(raw, id: "dot"))
        var f = ClawdFrame(); f.x = 1; f.off = 1
        XCTAssertEqual(p.pixels("normal", frame: f).first { $0.color == "#FF0000" }?.rects, [PRect(2, 4, 1, 1)])
        f = ClawdFrame(); f.x = -1                          // shifted out of the frame: clipped
        XCTAssertNil(p.pixels("normal", frame: f).first { $0.color == "#FF0000" })
    }

    func testNoArtIsNoPet() {
        XCTAssertNil(PetParser.parse("---\nname: x\n---\n", id: "x"))
    }

    /// The built-in files: every mood 12 rows of 18, and every letter has a colour.
    func testBuiltInPetsAreWellFormed() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/CodexyUsage/pets")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "txt" }
        XCTAssertEqual(Set(files.map { $0.deletingPathExtension().lastPathComponent }), ["heeler", "bit", "owl", "book"])
        for f in files {
            let p = try XCTUnwrap(PetParser.parse(try String(contentsOf: f, encoding: .utf8), id: f.lastPathComponent))
            for (mood, rows) in p.art {
                XCTAssertEqual(rows.count, 12, "\(p.id) \(mood)")
                for r in rows {
                    XCTAssertEqual(r.count, 18, "\(p.id) \(mood) \(r)")
                    for ch in r where ch != "." { XCTAssertNotNil(p.colors[String(ch)], "\(p.id) \(mood) '\(ch)'") }
                }
            }
        }
    }
}
