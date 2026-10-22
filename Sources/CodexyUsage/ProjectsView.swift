import SwiftUI
import CodexyCore

// The parts of Details that come from the rollout files (RolloutScanner): turns and sessions,
// projects (click one for its models and busiest hours), models, and the heatmap.
// They follow the period switch: the last 24 hours, or the 7 days scanned.

@MainActor private func since(_ model: AppModel, _ period: String) -> Int {
    period == "day" ? Int(model.now.timeIntervalSince1970 / 3600) - 24 : Int.min
}

/// "412 turns · 9 sessions" of the period, big and light like Claudy's requests and sessions.
struct ActivityStats: View {
    let model: AppModel
    let period: String

    var body: some View {
        if let p = model.projects {
            let s = since(model, period), turns = p.turnCount(sinceHour: s), sessions = p.sessionCount(sinceHour: s)
            HStack(alignment: .top, spacing: 26) {
                stat(turns, L.word("turn", turns))
                stat(sessions, L.word("session", sessions))
                Spacer(minLength: 0)
            }
            .help(L.t("thisComputer.tip"))
        }
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(n.formatted()).font(.system(size: 22, weight: .light)).foregroundStyle(T.textHi).monospacedDigit()
            Text(label).font(.system(size: 10)).foregroundStyle(T.dim)
        }
    }
}

struct ActivityView: View {
    let model: AppModel
    let period: String
    @State private var heatOpen = ProcessInfo.processInfo.environment["CODEXY_HEAT"] != nil   // snapshots
    @State private var openProject: String? = ProcessInfo.processInfo.environment["CODEXY_PROJECT"]   // snapshots

    var body: some View {
        let s = since(model, period)
        VStack(alignment: .leading, spacing: 6) {
            heading(period == "day" ? L.t("projects1") : L.t("projects7")).help(L.t("projects.tip"))
            if let p = model.projects {
                let top = p.ranked(sinceHour: s).prefix(4)
                if top.isEmpty { Text(L.t("nothingYet")).font(.system(size: 10.5)).foregroundStyle(T.dim) }
                ForEach(Array(top), id: \.name) { t in
                    Button { withAnimation(.easeOut(duration: 0.15)) { openProject = openProject == t.name ? nil : t.name } } label: {
                        row(Redact.name(t.name, "project"), Int(t.share.rounded()), Color(hex: 0xD77757), help: Redact.on ? nil : p.paths[t.name])
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    if openProject == t.name { projectDetail(p, t.name, s) }
                }
            } else {
                Text(L.t("counting")).font(.system(size: 10.5)).foregroundStyle(T.dim)
            }
        }
        if let p = model.projects {
            let models = p.models(sinceHour: s)
            if !models.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    heading(period == "day" ? L.t("models1") : L.t("models7")).help(L.t("projects.tip"))
                    ForEach(models, id: \.family) { row(Self.modelLabel($0.family), Int($0.share.rounded()), T.purple) }
                }
            }
        }
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeOut(duration: 0.15)) { heatOpen.toggle() } } label: {
                HStack(spacing: 4) {
                    Image(systemName: heatOpen ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                    Text(L.t("heat.title")).font(.system(size: 10.5))
                }
                .foregroundStyle(T.accent)
            }
            .buttonStyle(.plain)
            if heatOpen { HeatmapView(model: model) }
        }
    }

    static func modelLabel(_ key: String) -> String { key == "other" ? L.t("family.other") : CodexModel.display(key) }

    /// Click a project: its model mix and the hours of the day it was busiest.
    private func projectDetail(_ p: ProjectUsage, _ name: String, _ since: Int) -> some View {
        let fams = p.families(of: name, sinceHour: since).map { "\(Self.modelLabel($0.family)) \(Int($0.share.rounded()))%" }.joined(separator: " · ")
        let hours = p.busiestHours(of: name, sinceHour: since).map { String(format: "%02d:00", $0) }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 2) {
            Text(fams)
            Text(L.t("proj.hours", hours))
        }
        .font(.system(size: 10)).foregroundStyle(T.dim).padding(.leading, 8)
    }

    private func heading(_ s: String) -> some View {
        Text(s).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(T.dim)
    }

    /// label, a thin bar, the percentage: aligned columns so the eye can compare rows.
    private func row(_ label: String, _ pct: Int, _ color: Color, help: String? = nil) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(T.text2).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 4)
            ZStack(alignment: .leading) {
                Capsule().fill(T.track)
                Capsule().fill(color.opacity(0.85)).frame(width: 64 * CGFloat(min(max(pct, 0), 100)) / 100)
            }
            .frame(width: 64, height: 4)
            Text("\(pct)%").font(.system(size: 11)).foregroundStyle(T.muted).monospacedDigit()
                .frame(width: 32, alignment: .trailing)
        }
        .help(help ?? label)
    }
}
