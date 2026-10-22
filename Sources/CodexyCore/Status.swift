import Foundation

// OpenAI's status page (status.openai.com, hosted by incident.io). Plain HTTP, no keys.
// First choice: the JSON the page itself loads (`/proxy/status.openai.com`): it has the component groups,
// so "Codex" is the page's own group, not a guess by name. Fallback: the Statuspage-style
// `/api/v2/summary.json`, which (seen 2026-10-22) lists only part of the components and no incidents.

public struct ServiceStatus: Equatable, Sendable {
    public enum Level: Sendable { case ok, minor, major, unknown }
    public struct Component: Equatable, Sendable {
        public var name: String
        public var status: String       // the page's own word: degraded_performance, partial_outage, full_outage, under_maintenance
        public var important: Bool      // part of Codex: what a session depends on
        public init(name: String, status: String, important: Bool) { self.name = name; self.status = status; self.important = important }
    }
    public var level: Level             // only the important components set it
    public var text: String             // the page's own headline when it has one; empty means the UI words the level
    public var detail: [String]         // names of the open incidents that touch Codex
    public var affected: [Component]    // components that are not operational
    public init(level: Level, text: String, detail: [String], affected: [Component] = []) {
        self.level = level; self.text = text; self.detail = detail; self.affected = affected
    }
    /// Something else (ChatGPT, the API) is off while Codex is fine.
    public var onlyOthersAffected: Bool { level == .ok && !affected.isEmpty }
}

public enum StatusFetcher {
    public static let pageURL = "https://status.openai.com"

    public static func fetch() async -> ServiceStatus? {
        if let d = await get(pageURL + "/proxy/status.openai.com"), let s = parsePage(d) { return s }
        if let d = await get(pageURL + "/api/v2/summary.json"), let s = parseSummary(d) { return s }
        return nil
    }

    static func get(_ s: String) async -> Data? {
        guard let url = URL(string: s), let (data, resp) = try? await URLSession.shared.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode ?? 200 < 400 else { return nil }
        return data
    }

    static func severity(_ status: String) -> ServiceStatus.Level {
        switch status {
        case "operational": .ok
        case "major_outage", "full_outage": .major
        default: .minor                 // degraded performance, partial outage, maintenance
        }
    }

    /// Codex components by name, for the summary that has no groups: "Codex Web", "Codex API",
    /// "Codex in ChatGPT Desktop", and the two generic names that only exist in the Codex group.
    static func codexByName(_ n: String) -> Bool { n.contains("Codex") || n == "CLI" || n == "VS Code extension" }

    /// Worst level of the important components: a major outage beats anything minor.
    static func level(_ affected: [ServiceStatus.Component]) -> ServiceStatus.Level {
        var worst = ServiceStatus.Level.ok
        for c in affected where c.important {
            let s = severity(c.status)
            if s == .major { return .major }
            if s == .minor { worst = .minor }
        }
        return worst
    }

    /// The page's own JSON: `summary.components` (id, name), `summary.structure.items[].group` (name, components[].component_id),
    /// `summary.affected_components` (component_id, status), `summary.ongoing_incidents` (name, affected_components).
    public static func parsePage(_ data: Data) -> ServiceStatus? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let s = j["summary"] as? [String: Any], let comps = s["components"] as? [[String: Any]] else { return nil }
        var names: [String: String] = [:]
        for c in comps { if let id = c["id"] as? String, let n = c["name"] as? String { names[id] = n } }
        var codex = Set<String>()
        let items = (s["structure"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
        for item in items {
            guard let g = item["group"] as? [String: Any], (g["name"] as? String)?.contains("Codex") == true else { continue }
            for c in g["components"] as? [[String: Any]] ?? [] { if let id = c["component_id"] as? String { codex.insert(id) } }
        }
        // No Codex group found (the page was reorganised): fall back to the names.
        func important(_ id: String) -> Bool { codex.isEmpty ? codexByName(names[id] ?? "") : codex.contains(id) || (names[id] ?? "").contains("Codex") }

        var affected: [ServiceStatus.Component] = []
        for a in s["affected_components"] as? [[String: Any]] ?? [] {
            guard let id = a["component_id"] as? String, let st = a["status"] as? String, st != "operational" else { continue }
            affected.append(.init(name: names[id] ?? id, status: st, important: important(id)))
        }
        let incidents = (s["ongoing_incidents"] as? [[String: Any]] ?? []).compactMap { i -> String? in
            let ids = (i["affected_components"] as? [[String: Any]] ?? []).compactMap { $0["component_id"] as? String }
            return ids.contains(where: important) ? i["name"] as? String : nil
        }
        return ServiceStatus(level: level(affected), text: incidents.first ?? "", detail: incidents, affected: affected)
    }

    /// Statuspage v2 `summary.json` (the same shape Claudy reads from status.claude.com).
    public static func parseSummary(_ data: Data) -> ServiceStatus? {
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let st = j["status"] as? [String: Any] else { return nil }
        let comps = j["components"] as? [[String: Any]] ?? []
        var affected: [ServiceStatus.Component] = []
        var sawCodex = false
        for c in comps {
            guard let n = c["name"] as? String, let s = c["status"] as? String else { continue }
            if codexByName(n) { sawCodex = true }
            if s != "operational" { affected.append(.init(name: n, status: s, important: codexByName(n))) }
        }
        var lv = level(affected)
        // Codex not in the list: the page's overall indicator is all we know.
        if !sawCodex {
            switch st["indicator"] as? String {
            case "none": lv = .ok
            case "minor", "maintenance": lv = .minor
            case "major", "critical": lv = .major
            default: lv = .unknown
            }
        }
        let incidents = (j["incidents"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        return ServiceStatus(level: lv, text: lv == .ok ? "" : st["description"] as? String ?? "", detail: incidents, affected: affected)
    }
}
