import SwiftUI
import CodexyCore

/// "Tokens per day": real token counts by model, from the rollout files (the same scan as Details, 30 days).
/// A window of its own: the chart wants more room than the panel has.
struct TokensView: View {
    let model: AppModel
    @State private var period = 30
    @State private var hover: Int?
    private let palette: [Color] = [Color(hex: 0x7CB7FF), Color(hex: 0x5FD68A), Color(hex: 0xB79CFF), Color(hex: 0xFFC24B), Color(hex: 0xD77757), T.muted]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let u = model.tokenUsage {
                let d = u.tokenDays(days: period)
                if d.lines.isEmpty {
                    Text(L.t(u.incomplete ? "activity.unavailable" : "tokens.none")).font(.system(size: 12)).foregroundStyle(T.muted)
                } else {
                    chart(d)
                    models(d)
                    if u.incomplete {
                        Text(L.t("activity.partial")).font(.system(size: 12)).foregroundStyle(T.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(L.t("tokens.loading")).font(.system(size: 12)).foregroundStyle(T.muted)
            }
            Text(L.t("tokens.note")).font(.system(size: 10)).foregroundStyle(T.dim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(22).frame(width: 560, alignment: .topLeading).background(T.bg)
        .onAppear { model.refreshTokens() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(L.t("tokens.title")).font(.system(size: 14, weight: .semibold)).foregroundStyle(T.textHi)
            Spacer()
            ForEach([(L.t("tokens.d7"), 7), (L.t("tokens.d30"), 30)], id: \.1) { p in
                Chip(text: p.0, selected: period == p.1) { period = p.1 }
            }
        }
    }

    private func color(_ i: Int) -> Color { palette[min(i, palette.count - 1)] }
    private func label(_ key: String) -> String { key == "other" ? L.t("tokens.others") : CodexModel.display(key) }
    private func dayText(_ d: Date, _ format: String = "d MMM") -> String {
        let f = DateFormatter(); f.locale = L.locale; f.dateFormat = format
        return f.string(from: d)
    }

    /// One stacked bar per day, a model per colour.
    private func chart(_ d: TokenDays) -> some View {
        let n = d.days.count
        let sums = (0..<n).map { i in d.lines.reduce(0) { $0 + $1.values[i] } }
        let peak = max(1, sums.max() ?? 1)
        let left: CGFloat = 46, h: CGFloat = 170
        return GeometryReader { geo in
            let w = geo.size.width - left, slot = w / CGFloat(max(1, n)), bar = max(2, slot * 0.7)
            Canvas { ctx, _ in
                for f in [0.0, 0.5, 1.0] {
                    let y = h - 4 - (h - 8) * CGFloat(f)
                    ctx.fill(Path(CGRect(x: left, y: y, width: w, height: 1)), with: .color(Color.white.opacity(0.07)))
                    ctx.draw(Text(Format.tokens(Int(peak * f))).font(.system(size: 9)).foregroundColor(T.faint), at: CGPoint(x: left - 6, y: y), anchor: .trailing)
                }
                let every = n <= 8 ? 1 : 7
                for i in 0..<n {
                    let x = left + slot * CGFloat(i) + (slot - bar) / 2
                    var base = h - 4
                    for (li, l) in d.lines.enumerated() where l.values[i] > 0 {
                        let bh = (h - 8) * CGFloat(l.values[i] / peak)
                        ctx.fill(Path(CGRect(x: x, y: base - bh, width: bar, height: bh)), with: .color(color(li)))
                        base -= bh
                    }
                    if (n - 1 - i) % every == 0 {
                        ctx.draw(Text(dayText(d.days[i], n <= 8 ? "EEE d" : "d MMM")).font(.system(size: 9)).foregroundColor(T.faint),
                                 at: CGPoint(x: x + bar / 2, y: h + 10), anchor: i == 0 ? .leading : .center)
                    }
                }
                if let i = hover, i < n { ctx.fill(Path(CGRect(x: left + slot * CGFloat(i), y: 0, width: slot, height: h)), with: .color(Color.white.opacity(0.08))) }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase, n > 0, p.x >= left { hover = min(max(Int((p.x - left) / slot), 0), n - 1) } else { hover = nil }
            }
            .overlay(alignment: .topTrailing) { if let i = hover, i < n { tip(d, i, sums[i]) } }
        }
        .frame(height: h + 20)
    }

    private func tip(_ d: TokenDays, _ i: Int, _ sum: Double) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(dayText(d.days[i])) · \(Format.tokens(Int(sum)))").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.textHi)
            ForEach(Array(d.lines.enumerated()), id: \.offset) { li, l in
                if l.values[i] > 0 { Text("\(label(l.key)) \(Format.tokens(Int(l.values[i])))").font(.system(size: 10)).foregroundStyle(color(li)) }
            }
        }
        .padding(6).background(RoundedRectangle(cornerRadius: 6).fill(T.card))
    }

    /// The period's totals by model: in (with the cached part) and out.
    private func models(_ d: TokenDays) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 10) {
            ForEach(Array(d.lines.enumerated()), id: \.offset) { li, l in
                if let t = d.totals[l.key] {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Circle().fill(color(li)).frame(width: 7, height: 7)
                            Text(label(l.key)).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.textHi)
                            Text(L.t("tokens.total", Format.tokens(Int(t.total)))).font(.system(size: 11)).foregroundStyle(T.dim)
                        }
                        Text(L.t("tokens.io", Format.tokens(Int(t.input)), Format.tokens(Int(t.output)))).font(.system(size: 10)).foregroundStyle(T.dim)
                        Text(L.t("tokens.cached", Format.tokens(Int(t.cached)))).font(.system(size: 10)).foregroundStyle(T.dim)
                    }
                }
            }
        }
    }
}
