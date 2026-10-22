import Foundation

// A mascot drawn from a text file instead of Clawd's glyphs. Same 18 x 12 pixel grid, so the mascot brain
// (walking, hops, burrowing, lying on its back) and the skins work unchanged.
//
//   ---
//   name: Bit
//   b: #8E9AAF          one letter per colour; '.' is empty
//   ---
//   [normal]            12 rows of 18
//   [slack]             low use (optional, falls back to normal)
//   [crit]              near the limit (optional)
//   [sleep]             eyes closed (optional, falls back to slack)
//   [walk1] [walk2]     side view facing right, two steps (optional); mirrored when walking left
//   [sit]               side view facing right, sitting while idle (optional)

public struct Pet: Equatable, Sendable {
    /// Ticks of standing still before sitting down: about 3 s at 90 ms a tick.
    public static let sitAfter = 33
    public var id: String
    public var name: String
    public var colors: [String: String]
    public var art: [String: [String]]

    /// normal, slack, crit or sleep; a missing mood borrows the closest one.
    public func rows(_ mood: String) -> [String] {
        art[mood] ?? (mood == "sleep" ? art["slack"] : nil) ?? art["normal"] ?? []
    }

    /// Rects per colour for one frame. `off` (rows of 4 px) and `dig` lower it, `x` shifts it in cells,
    /// `flip` lays it on its back: the same moves Clawd makes. Anything outside the frame is clipped.
    public func pixels(_ mood: String, frame f: ClawdFrame, pose: String? = nil, mirror: Bool = false) -> [(color: String, rects: [PRect])] {
        let W = Clawd.W, H = Clawd.H
        let oy = 4 * f.off + f.dig, ox = 2 * f.x
        let lim = f.dig > 0 ? H - 2 : H
        var by: [String: [PRect]] = [:]
        let art = pose.flatMap { self.art[$0] } ?? rows(mood)
        for (y, row) in art.prefix(H).enumerated() {
            for (x, ch) in row.prefix(W).enumerated() {
                guard let c = colors[String(ch)] else { continue }
                let sy = (f.flip ? H - 1 - y : y) + oy, sx = (mirror ? W - 1 - x : x) + ox
                guard sx >= 0, sx < W, sy >= 0, sy < lim else { continue }
                by[c, default: []].append(PRect(Double(sx), Double(sy), 1, 1))
            }
        }
        return by.keys.sorted().map { ($0, by[$0]!) }
    }

    /// Which pose the brain's frame asks for: a side step while walking, sitting once it has stood still a while
    /// (idle or waiting for you), else the face. Only poses the file has; `mirror` when facing left.
    public func pose(_ f: ClawdFrame, mood: String, lift: Double, stillTicks: Int = .max) -> (pose: String?, mirror: Bool) {
        guard !f.flip, f.dig == 0, f.off == 0 else { return (nil, false) }
        if f.feet != "both", art["walk1"] != nil {
            return (f.feet == "left" ? "walk1" : (art["walk2"] != nil ? "walk2" : "walk1"), f.look < 0)
        }
        if ["idle", "doze", "wait"].contains(mood), stillTicks >= Pet.sitAfter, lift == 0, art["sit"] != nil { return ("sit", f.look < 0) }
        return (nil, false)
    }
}

public enum PetParser {
    public static func parse(_ raw: String, id: String) -> Pet? {
        let lines = raw.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\r"))) }
        guard let first = lines.firstIndex(where: { !$0.isEmpty }), lines[first] == "---",
              let close = lines[(first + 1)...].firstIndex(of: "---") else { return nil }
        var p = Pet(id: id.lowercased(), name: id, colors: [:], art: [:])
        for line in lines[(first + 1)..<close] {
            guard let c = line.firstIndex(of: ":") else { continue }
            let k = line[..<c].trimmingCharacters(in: .whitespaces), v = line[line.index(after: c)...].trimmingCharacters(in: .whitespaces)
            if k == "name" { p.name = v }
            else if k.count == 1, k != ".", v.range(of: "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$", options: .regularExpression) != nil { p.colors[k] = v }
        }
        var mood: String?
        for line in lines[(close + 1)...] where !line.isEmpty {
            if line.hasPrefix("["), line.hasSuffix("]") { mood = String(line.dropFirst().dropLast()); continue }
            if let m = mood { p.art[m, default: []].append(line) }
        }
        return p.art["normal"]?.isEmpty == false ? p : nil
    }
}
