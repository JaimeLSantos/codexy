import SwiftUI
import AppKit
import CodexyCore

// OpenAI's status (Codex only) and the credits Codex reports: the words for the model, and the two panel rows.

extension AppModel {
    var statusColor: Color {
        switch status?.level {
        case .ok: T.ok; case .minor: T.warn; case .major: T.crit; default: T.dim
        }
    }

    var statusText: String {
        guard let s = status else { return statusFailed ? L.t("status.offline") : L.t("status.loading") }
        if s.onlyOthersAffected { return L.t("status.others") }
        switch s.level {
        case .ok: return L.t("status.ok")
        case .unknown: return L.t("status.unknown")
        default: return s.text.isEmpty ? L.t(s.level == .major ? "status.major" : "status.minor") : s.text
        }
    }

    /// Lines under the status: the other open Codex incidents, then each Codex component that is off, in our words.
    var statusDetail: [String] {
        guard let s = status else { return [] }
        return s.detail.filter { $0 != s.text } + s.affected.filter(\.important).map { "\($0.name): \(Self.componentWord($0.status))" }
    }

    /// Hover text: every component that is off, Codex or not.
    var statusTip: String {
        let off = status?.affected.map { "\($0.name): \(Self.componentWord($0.status))" } ?? []
        return ([L.t("status.open")] + off).joined(separator: "\n")
    }

    static func componentWord(_ status: String) -> String {
        let k = "status.c." + status
        let w = L.t(k)
        return w == k ? status.replacingOccurrences(of: "_", with: " ") : w
    }

    /// "1 reset credit · expires in 9d 0h · 125.5 credits": only what is there, nil when there is nothing.
    var creditsText: String? {
        guard let u = usage else { return nil }
        var parts: [String] = []
        if let r = u.resetCredits, r.available > 0 {
            parts.append(L.count("resetCredit", r.available))
            if let e = r.nextExpiry, let span = Format.span(to: e, now: now) { parts.append(L.t("resetCredit.expires", span)) }
        }
        if let c = u.credits, c.worthShowing {
            parts.append(c.unlimited ? L.t("credits.unlimited") : L.t("credits.balance", c.balance ?? "?"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Dot + headline + Codex details; a click opens status.openai.com.
struct StatusRow: View {
    let model: AppModel

    var body: some View {
        Button { NSWorkspace.shared.open(URL(string: StatusFetcher.pageURL)!) } label: {
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(model.statusColor).frame(width: 7, height: 7).padding(.top, 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.statusText).font(.system(size: 12)).foregroundStyle(T.muted)
                    ForEach(model.statusDetail, id: \.self) {
                        Text($0).font(.system(size: 10.5)).foregroundStyle(T.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(model.statusTip)
    }
}

/// Reset credits and paid credits, under the week row. Hidden when Codex reports none.
struct CreditsLine: View {
    let model: AppModel

    var body: some View {
        if let t = model.creditsText {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise.circle").font(.system(size: 10))
                Text(t).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .foregroundStyle(T.muted)
            .help(L.t("credits.tip"))
        }
    }
}
