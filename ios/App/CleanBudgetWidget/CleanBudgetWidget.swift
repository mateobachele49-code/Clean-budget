import WidgetKit
import SwiftUI

// MARK: - Données

struct CBEntry: TimelineEntry {
    let date: Date
    let s: CBShared.Summary
    let empty: Bool
}

struct CBProvider: TimelineProvider {
    func placeholder(in context: Context) -> CBEntry {
        CBEntry(date: Date(), s: CBShared.sample, empty: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (CBEntry) -> Void) {
        let s = CBShared.summary()
        completion(CBEntry(date: Date(), s: s ?? CBShared.sample, empty: s == nil && !context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CBEntry>) -> Void) {
        let s = CBShared.summary()
        let e = CBEntry(date: Date(), s: s ?? CBShared.sample, empty: s == nil)
        completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(3600))))
    }
}

// MARK: - Couleurs

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt64(h, radix: 16) ?? 0xdbe9ff
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

private let ink = Color(red: 0.11, green: 0.11, blue: 0.14)
private let soft = Color(red: 0.11, green: 0.11, blue: 0.14).opacity(0.6)
private let red = Color(red: 0.86, green: 0.2, blue: 0.2)

private func money(_ s: CBShared.Summary, _ v: String) -> String { s.hide ? "•••" : v }

// MARK: - Vues

struct CBBackground: View {
    let s: CBShared.Summary
    var body: some View {
        LinearGradient(colors: [Color(hex: s.bg1), Color(hex: s.bg2)], startPoint: .top, endPoint: .bottom)
    }
}

struct CBGoalBar: View {
    let pct: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [Color(hex: "#ffd34d"), Color(hex: "#f5a524")], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, g.size.width * min(max(pct, 0), 1)))
            }
        }
        .frame(height: 8)
    }
}

struct CBSmallView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(s.pet).font(.system(size: 26))
                Spacer()
                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundColor(ink.opacity(0.75))
            }
            Spacer(minLength: 2)
            Text(e.empty ? "Ouvre l’app" : "Il te reste").font(.system(size: 12, weight: .medium)).foregroundColor(soft)
            Text(e.empty ? "Clean Budget" : money(s, s.solde))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(s.soldeNeg && !s.hide ? red : ink)
                .minimumScaleFactor(0.5).lineLimit(1)
            if let p = s.goalPct, !e.empty {
                CBGoalBar(pct: p).padding(.top, 4)
            } else {
                Text("Dépensé : \(money(s, s.dep))").font(.system(size: 11)).foregroundColor(soft).lineLimit(1)
            }
        }
        .widgetURL(URL(string: "cleanbudget://add"))
    }
}

struct CBMediumView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.pet)  \(s.month.capitalized)").font(.system(size: 13, weight: .semibold)).foregroundColor(soft).lineLimit(1)
                Spacer(minLength: 2)
                Text("Il te reste").font(.system(size: 12, weight: .medium)).foregroundColor(soft)
                Text(e.empty ? "—" : money(s, s.solde))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(s.soldeNeg && !s.hide ? red : ink)
                    .minimumScaleFactor(0.5).lineLimit(1)
                if let p = s.goalPct {
                    CBGoalBar(pct: p).padding(.top, 4)
                    Text("Objectif d’épargne : \(Int((p * 100).rounded())) %").font(.system(size: 10)).foregroundColor(soft)
                }
            }
            VStack(spacing: 8) {
                Link(destination: URL(string: "cleanbudget://add")!) {
                    Label("Dépense", systemImage: "minus.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Capsule().fill(red))
                }
                Link(destination: URL(string: "cleanbudget://add?t=s")!) {
                    Label("Épargne", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(ink)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Capsule().fill(Color.white.opacity(0.7)))
                }
                VStack(spacing: 1) {
                    Text("Dépensé").font(.system(size: 10)).foregroundColor(soft)
                    Text(money(s, s.dep)).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(ink).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .frame(width: 118)
        }
        .widgetURL(URL(string: "cleanbudget://open"))
    }
}

struct CBWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CBEntry
    var body: some View {
        let s = entry.s
        switch family {
        case .accessoryInline:
            Text("\(s.pet) Reste \(money(s, s.solde))")
        case .accessoryCircular:
            if let p = s.goalPct {
                Gauge(value: min(max(p, 0), 1)) { Text(s.pet) } currentValueLabel: { Text(s.pet) }
                    .gaugeStyle(.accessoryCircularCapacity)
            } else {
                ZStack { AccessoryWidgetBackground(); Text(s.pet).font(.title2) }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.pet) Il te reste").font(.caption2)
                Text(money(s, s.solde)).font(.system(.title3, design: .rounded)).bold().minimumScaleFactor(0.6)
                Text("Dépensé \(money(s, s.dep))").font(.caption2).opacity(0.75)
            }
        case .systemMedium:
            CBMediumView(e: entry)
        default:
            CBSmallView(e: entry)
        }
    }
}

// MARK: - Widget

struct CBBudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBBudget", provider: CBProvider()) { entry in
            if #available(iOSApplicationExtension 17.0, *) {
                CBWidgetView(entry: entry).containerBackground(for: .widget) { CBBackground(s: entry.s) }
            } else {
                CBWidgetView(entry: entry).padding().background(CBBackground(s: entry.s))
            }
        }
        .configurationDisplayName("Clean Budget")
        .description("Ce qu’il te reste à dépenser, et un raccourci pour ajouter une dépense.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct CleanBudgetWidgets: WidgetBundle {
    var body: some Widget {
        CBBudgetWidget()
    }
}
