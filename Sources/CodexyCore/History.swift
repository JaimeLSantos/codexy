import Foundation

// Two things for the "last 7 days" part of the panel (ported from lib/history.ps1):
//  - the history of the 5h and week percentages, one sample per limits read;
//  - which projects and models spent the most, counted from Codex's rollout files (`RolloutScanner`, Projects.swift).

// MARK: percentages over time

public struct HistorySample: Equatable, Sendable {
    public var minute: Int          // unix minutes
    public var session: Int         // -1: no value
    public var week: Int
    public init(minute: Int, session: Int, week: Int) { self.minute = minute; self.session = session; self.week = week }
}

public struct UsageHistory: Equatable, Sendable {
    public static let keepDays = 8
    public static let stepMinutes = 5      // an unchanged value is sampled this often
    public static let gapMinutes = 20      // a longer pause between samples: the app was off, the line breaks

    public var samples: [HistorySample] = []
    public init() {}

    public static func minute(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 60) }

    /// Adds a sample unless it repeats the last one within the step. Returns whether anything changed.
    @discardableResult
    public mutating func add(session: Int?, week: Int?, now: Date = Date()) -> Bool {
        let s = HistorySample(minute: Self.minute(now), session: session ?? -1, week: week ?? -1)
        if let last = samples.last, last.session == s.session, last.week == s.week, s.minute - last.minute < Self.stepMinutes {
            return false
        }
        samples.append(s)
        let cut = s.minute - Self.keepDays * 1440
        if let first = samples.firstIndex(where: { $0.minute >= cut }), first > 0 { samples.removeFirst(first) }
        return true
    }

    /// The sample at or just before `minute`, if it is recent enough to still describe that moment.
    public func sample(at minute: Int) -> HistorySample? {
        var lo = 0, hi = samples.count - 1, hit: HistorySample?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if samples[mid].minute <= minute { hit = samples[mid]; lo = mid + 1 } else { hi = mid - 1 }
        }
        guard let h = hit, minute - h.minute <= Self.gapMinutes else { return nil }
        return h
    }

    // Same file shape as the original: {"samples":[[minute, session, week], ...]}.
    public func encoded() -> Data {
        let rows = samples.map { "[\($0.minute),\($0.session),\($0.week)]" }.joined(separator: ",")
        return Data("{\"samples\":[\(rows)]}".utf8)
    }

    public static func decode(_ data: Data) -> UsageHistory {
        var h = UsageHistory()
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = j["samples"] as? [[Int]] else { return h }
        h.samples = rows.filter { $0.count == 3 }.map { HistorySample(minute: $0[0], session: $0[1], week: $0[2]) }
        return h
    }

    public static var fileURL: URL {
        let dir = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support/Codexy")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-history.json")
    }

    public static func load() -> UsageHistory { (try? Data(contentsOf: fileURL)).map(decode) ?? UsageHistory() }
    public func save() { try? encoded().write(to: Self.fileURL, options: .atomic) }
}

// MARK: projects, from the rollout files

public struct ProjectUsage: Equatable, Sendable {
    /// unix hour -> project -> model family -> weight. Everything below is a sum over this.
    public var hourly: [Int: [String: [String: Double]]] = [:]
    public var paths: [String: String] = [:]            // project -> folder, for the hover text
    public var turns: [Int: Int] = [:]                  // unix hour -> turns started (a prompt and the work it led to)
    public var threads: [String: Int] = [:]             // thread id -> last unix hour it was used
    public init(hourly: [Int: [String: [String: Double]]] = [:], paths: [String: String] = [:],
                turns: [Int: Int] = [:], threads: [String: Int] = [:]) {
        self.hourly = hourly; self.paths = paths; self.turns = turns; self.threads = threads
    }

    public func turnCount(sinceHour: Int = .min) -> Int { turns.filter { $0.key >= sinceHour }.values.reduce(0, +) }
    /// Threads used at least once in the period.
    public func sessionCount(sinceHour: Int = .min) -> Int { threads.values.filter { $0 >= sinceHour }.count }

    private func rows(since: Int) -> [(hour: Int, project: String, family: String, w: Double)] {
        hourly.filter { $0.key >= since }.flatMap { h, ps in ps.flatMap { p, fs in fs.map { (h, p, $0.key, $0.value) } } }
    }

    /// Weight by project over the whole scan.
    public var total: [String: Double] { total(sinceHour: .min) }
    public func total(sinceHour: Int) -> [String: Double] {
        var t: [String: Double] = [:]
        for r in rows(since: sinceHour) { t[r.project, default: 0] += r.w }
        return t
    }

    /// Share of the period by project, biggest first.
    public func ranked(sinceHour: Int = .min) -> [(name: String, share: Double)] {
        let t = total(sinceHour: sinceHour), sum = t.values.reduce(0, +)
        guard sum > 0 else { return [] }
        return t.sorted { $0.value > $1.value }.map { ($0.key, 100 * $0.value / sum) }
    }

    /// Weight per day and hour for the last `days` days, oldest day first, 24 hours each (local time).
    /// The last row is today. For the heatmap: one cell is one real hour, no two days are merged.
    public func heat(days: Int = 7, now: Date = Date(), calendar: Calendar = .current) -> [[Double]] {
        let today = calendar.startOfDay(for: now)
        var grid = Array(repeating: Array(repeating: 0.0, count: 24), count: days)
        for (h, ps) in hourly {
            let t = Date(timeIntervalSince1970: TimeInterval(h) * 3600)
            let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: t), to: today).day ?? 99
            guard back >= 0, back < days else { continue }
            grid[days - 1 - back][calendar.component(.hour, from: t)] += ps.values.flatMap(\.values).reduce(0, +)
        }
        return grid
    }

    /// Model families over all projects, share of the period, biggest first. A family under 1% is left out
    /// ("other" is often just a synthetic or unknown model).
    public func models(sinceHour: Int = .min) -> [(family: String, share: Double)] {
        var t: [String: Double] = [:]
        for r in rows(since: sinceHour) { t[r.family, default: 0] += r.w }
        let sum = t.values.reduce(0, +)
        guard sum > 0 else { return [] }
        return t.sorted { $0.value > $1.value }.map { ($0.key, 100 * $0.value / sum) }.filter { $0.1 >= 1 }
    }

    /// Model families of one project, share of that project.
    public func families(of project: String, sinceHour: Int = .min) -> [(family: String, share: Double)] {
        var t: [String: Double] = [:]
        for r in rows(since: sinceHour) where r.project == project { t[r.family, default: 0] += r.w }
        let sum = t.values.reduce(0, +)
        guard sum > 0 else { return [] }
        return t.sorted { $0.value > $1.value }.map { ($0.key, 100 * $0.value / sum) }
    }

    /// The hours of the day (local, 0...23) where a project used the most, busiest first.
    public func busiestHours(of project: String, sinceHour: Int = .min, count: Int = 3, calendar: Calendar = .current) -> [Int] {
        var t: [Int: Double] = [:]
        for r in rows(since: sinceHour) where r.project == project {
            t[calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(r.hour) * 3600)), default: 0] += r.w
        }
        return t.sorted { $0.value > $1.value }.prefix(count).map(\.key)
    }

    public func busiest(hour: Int) -> String? {
        hourly[hour]?.max { $0.value.values.reduce(0, +) < $1.value.values.reduce(0, +) }?.key
    }
}
