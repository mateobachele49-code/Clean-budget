import SwiftUI
import WidgetKit

/// Complications du cadran : ce qu'il te reste aujourd'hui, ou ton solde.
/// Les chiffres sont posés par l'app de la montre dans le groupe partagé à chaque mise à jour venue de l'iPhone.

private let cbGroup = "group.com.mateobachele.cleanbudget"

struct CEntry: TimelineEntry {
    let date: Date
    let left: Double?      // reste aujourd'hui
    let budget: Double?    // budget du jour
    let solde: String
    let soldeNeg: Bool
    let pet: String
    let cur: String
    let hide: Bool
    let empty: Bool
}

private func cMoney(_ v: Double, _ cur: String, short: Bool = false) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale(identifier: "fr_FR")
    f.currencyCode = cur
    f.maximumFractionDigits = short || abs(v) >= 100 ? 0 : 2
    f.minimumFractionDigits = 0
    return f.string(from: NSNumber(value: v)) ?? String(format: "%.0f €", v)
}

private func cLoad(at date: Date) -> CEntry {
    let d = UserDefaults(suiteName: cbGroup)
    guard let data = d?.data(forKey: "wsum"),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return CEntry(date: date, left: nil, budget: nil, solde: "—", soldeNeg: false, pet: "🐷", cur: "EUR", hide: false, empty: true)
    }
    let saved = d?.object(forKey: "wsumAt") as? Date ?? date
    let b = o["liveB"] as? Double
    var s = o["liveS"] as? Double ?? 0
    if !Calendar.current.isDate(saved, inSameDayAs: date) { s = 0 }   // nouveau jour : le compteur repart de zéro
    return CEntry(date: date,
                  left: b.map { $0 - s },
                  budget: b,
                  solde: o["solde"] as? String ?? "—",
                  soldeNeg: o["soldeNeg"] as? Bool ?? false,
                  pet: o["pet"] as? String ?? "🐷",
                  cur: o["cur"] as? String ?? "EUR",
                  hide: o["hide"] as? Bool ?? false,
                  empty: false)
}

struct CProvider: TimelineProvider {
    func placeholder(in context: Context) -> CEntry {
        CEntry(date: Date(), left: 18, budget: 25, solde: "1 254 €", soldeNeg: false, pet: "🐷", cur: "EUR", hide: false, empty: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (CEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : cLoad(at: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        completion(Timeline(entries: [cLoad(at: now), cLoad(at: midnight)], policy: .after(midnight.addingTimeInterval(60))))
    }
}

private func cColor(_ e: CEntry) -> Color {
    guard let l = e.left, let b = e.budget, b > 0 else { return .orange }
    if l < 0 { return .red }
    return l / b < 0.25 ? .orange : .green
}

private func cFrac(_ e: CEntry) -> Double {
    guard let l = e.left, let b = e.budget, b > 0 else { return 0 }
    return min(max(l / b, 0), 1)
}

struct CView: View {
    @Environment(\.widgetFamily) var family
    let e: CEntry

    private var leftText: String {
        if e.hide { return "•••" }
        guard let l = e.left else { return "—" }
        return cMoney(l, e.cur, short: true)
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: cFrac(e)) {
                Text(e.pet)
            } currentValueLabel: {
                Text(leftText).font(.system(size: 13, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircular)
            .tint(cColor(e))
            .widgetAccentable()
        case .accessoryCorner:
            Text(e.pet).font(.system(size: 22))
                .widgetLabel {
                    Gauge(value: cFrac(e)) { Text("") } currentValueLabel: { Text(leftText) }
                        .tint(cColor(e))
                }
        case .accessoryInline:
            Text(e.empty ? "Clean Budget" : "\(e.pet) \(leftText) aujourd’hui")
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(e.pet)
                    Text((e.left ?? 0) < 0 ? "Budget du jour dépassé" : "Reste aujourd’hui")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
                Text(leftText)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(cColor(e))
                    .widgetAccentable()
                Text(e.hide ? "Solde •••" : "Solde \(e.solde)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(e.soldeNeg ? .red : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@main
struct CleanBudgetComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBComplication", provider: CProvider()) { e in
            CView(e: e).containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Clean Budget")
        .description("Ce qu’il te reste à dépenser aujourd’hui.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
