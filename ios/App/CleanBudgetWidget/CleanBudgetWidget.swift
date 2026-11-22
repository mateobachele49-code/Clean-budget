import WidgetKit
import SwiftUI
import UIKit

// MARK: - Données

struct CBEntry: TimelineEntry {
    let date: Date
    let s: CBShared.Summary
    let empty: Bool
    let night: Bool
    let done: Int?      // bouton de saisie rapide qui vient d'être touché
}

func sleepHours() -> (Int, Int) {
    let s = CBShared.summary()
    return (s?.sleepA ?? 22, s?.sleepB ?? 7)
}

func isNight(_ d: Date) -> Bool {
    let (a, b) = sleepHours()
    if a == b { return false }
    let h = Calendar.current.component(.hour, from: d)
    return a > b ? (h >= a || h < b) : (h >= a && h < b)
}

func nextSwitch(after d: Date) -> Date {
    let (a, b) = sleepHours()
    let cal = Calendar.current
    let x = cal.nextDate(after: d, matching: DateComponents(hour: b, minute: 0), matchingPolicy: .nextTime) ?? d.addingTimeInterval(3600)
    let y = cal.nextDate(after: d, matching: DateComponents(hour: a, minute: 0), matchingPolicy: .nextTime) ?? d.addingTimeInterval(3600)
    return min(x, y)
}

struct CBProvider: TimelineProvider {
    private func make(_ d: Date, _ s: CBShared.Summary?, done: Int? = nil, preview: Bool = false) -> CBEntry {
        CBEntry(date: d, s: s ?? CBShared.sample, empty: s == nil && !preview, night: isNight(d), done: done)
    }
    func placeholder(in context: Context) -> CBEntry {
        CBEntry(date: Date(), s: CBShared.sample, empty: false, night: false, done: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (CBEntry) -> Void) {
        completion(make(Date(), CBShared.summary(), preview: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CBEntry>) -> Void) {
        let now = Date()
        let s = CBShared.summary()
        var done: Int? = nil
        if let q = CBShared.defaults?.dictionary(forKey: "quickDone"),
           let at = q["at"] as? Double, now.timeIntervalSince1970 - at < 4 {
            done = q["i"] as? Int
        }
        var entries = [make(now, s, done: done)]
        if done != nil { entries.append(make(now.addingTimeInterval(2.5), s)) }
        let sw = nextSwitch(after: now)
        if sw < now.addingTimeInterval(3600) { entries.append(make(sw, s)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3600))))
    }
}

// MARK: - Couleurs et petits éléments

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        let v = UInt64(h, radix: 16) ?? 0xdbe9ff
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

// Couleurs qui s'adaptent au mode clair / sombre
let ink = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor.white : UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1) })
let soft = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.6) : UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 0.6) })
let red = Color(red: 0.86, green: 0.2, blue: 0.2)
let blue = Color(hex: "#2563eb")
let card = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.10) : UIColor(white: 0.45, alpha: 0.10) })

func money(_ s: CBShared.Summary, _ v: String) -> String { s.hide ? "•••" : v }
func short(_ v: String) -> String { v.replacingOccurrences(of: ",00", with: "") }
func pctText(_ p: Double) -> String { "\(Int((p * 100).rounded())) %" }
func barColor(_ c: CBShared.Cat) -> Color {
    guard let p = c.pct else { return Color(hex: c.col) }
    return p >= 1 ? red : p >= 0.8 ? Color(hex: "#f59e0b") : Color(hex: c.col)
}

/// Style des widgets : « app » = noir en mode sombre, blanc en mode clair (comme l'app) ; « pet » = couleurs de la mascotte.
func petStyle(_ s: CBShared.Summary) -> Bool { s.wst == "pet" }

struct CBBackground: View {
    @Environment(\.colorScheme) var scheme
    let s: CBShared.Summary
    var body: some View {
        if petStyle(s) {
            LinearGradient(colors: [Color(hex: s.bg1), Color(hex: s.bg2)], startPoint: .top, endPoint: .bottom)
        } else {
            scheme == .dark ? Color(hex: "#0b0b0d") : Color.white
        }
    }
}

/// Fond du widget : dégradé de la mascotte sur l'écran d'accueil, transparent sur l'écran verrouillé.
struct CBContainer<Content: View>: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    let colors: [String]?
    let content: Content

    init(_ e: CBEntry, colors: [String]? = nil, @ViewBuilder content: () -> Content) {
        self.e = e
        self.colors = colors
        self.content = content()
    }

    @ViewBuilder private var bg: some View {
        if let c = colors, c.count == 2, petStyle(e.s) {
            LinearGradient(colors: [Color(hex: c[0]), Color(hex: c[1])], startPoint: .top, endPoint: .bottom)
        } else {
            CBBackground(s: e.s)
        }
    }

    private var lock: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }

    @ViewBuilder private var inner: some View {
        if e.empty && !lock {
            VStack(spacing: 6) {
                Text(e.s.pet).font(.system(size: 34))
                Text("Ouvre Clean Budget une fois pour afficher tes chiffres")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(soft)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if petStyle(e.s) && !lock {
            content.environment(\.colorScheme, .light)
        } else {
            content
        }
    }

    var body: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            inner.cbRoll().containerBackground(for: .widget) {
                if lock { Color.clear } else { bg }
            }
        } else if lock {
            inner
        } else {
            inner.padding().background(bg)
        }
    }
}

struct CBBar: View {
    let pct: Double
    var color: Color = ink
    var gold = false
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.12))
                if gold {
                    Capsule().fill(LinearGradient(colors: [Color(hex: "#ffd34d"), Color(hex: "#f5a524")], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(height, g.size.width * min(max(pct, 0), 1)))
                } else {
                    Capsule().fill(color)
                        .frame(width: max(height, g.size.width * min(max(pct, 0), 1)))
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Animations à chaque mise à jour (iOS 17+) : chiffres qui défilent, barres qui glissent, mascotte en fondu

extension View {
    /// Les montants roulent jusqu'à leur nouvelle valeur quand le widget se met à jour.
    @ViewBuilder func cbRoll() -> some View {
        if #available(iOSApplicationExtension 16.0, *) {
            self.contentTransition(.numericText())
        } else {
            self
        }
    }
}

/// Image de la mascotte dessinée par l'app (jour / nuit), ou son emoji en attendant.
struct CBPetImage: View {
    let e: CBEntry
    var body: some View {
        pet.id(e.night ? "night" : "day").transition(.opacity)
    }
    @ViewBuilder private var pet: some View {
        if let img = load(e.night ? "pet-night.png" : "pet-day.png") ?? load("pet-day.png") {
            if #available(iOSApplicationExtension 18.0, *) {
                Image(uiImage: img).resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFit()
            } else {
                Image(uiImage: img).resizable().scaledToFit()
            }
        } else {
            Text(e.s.pet).font(.system(size: 60)).minimumScaleFactor(0.3)
        }
    }
    private func load(_ name: String) -> UIImage? {
        guard let u = CBShared.fileURL(name) else { return nil }
        return UIImage(contentsOfFile: u.path)
    }
}

/// Courbe du solde jour par jour.
struct CBCurve: View {
    let v: [Double]
    let days: Int
    var color: Color = blue
    var body: some View {
        GeometryReader { g in
            let mn = v.min() ?? 0
            let mx = v.max() ?? 1
            let rng = max(mx - mn, 1)
            let w = g.size.width
            let h = g.size.height
            let n = CGFloat(max(days - 1, 1))
            let pts: [CGPoint] = v.enumerated().map { i, x in
                CGPoint(x: w * CGFloat(i) / n, y: h * 0.92 - h * 0.84 * CGFloat((x - mn) / rng))
            }
            ZStack(alignment: .topLeading) {
                Path { p in
                    guard let f = pts.first, let l = pts.last else { return }
                    p.move(to: CGPoint(x: f.x, y: h))
                    pts.forEach { p.addLine(to: $0) }
                    p.addLine(to: CGPoint(x: l.x, y: h))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    guard let f = pts.first else { return }
                    p.move(to: f)
                    pts.dropFirst().forEach { p.addLine(to: $0) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - 0.5))
                    p.addLine(to: CGPoint(x: w, y: h - 0.5))
                }
                .stroke(ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let l = pts.last {
                    Circle().fill(Color.white).frame(width: 10, height: 10).position(l)
                    Circle().fill(color).frame(width: 6, height: 6).position(l)
                }
            }
        }
    }
}

let wdays = ["L", "M", "M", "J", "V", "S", "D"]

// MARK: - 1 · Solde (le widget d'origine + anneau budget)

struct CBBudgetView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let s = e.s
        switch family {
        case .accessoryInline:
            Text("\(s.pet) Reste \(money(s, s.solde))")
        case .accessoryCircular:
            if let p = s.budgetPct {
                Gauge(value: min(max(p, 0), 1)) {
                    Image(systemName: "eurosign")
                } currentValueLabel: {
                    Text("\(Int((p * 100).rounded()))")
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text("Reste").font(.system(size: 9))
                        Text(short(money(s, s.solde))).font(.system(size: 12, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    }
                    .padding(4)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.pet) Il te reste").font(.caption2)
                Text(money(s, s.solde)).font(.system(.title3, design: .rounded)).bold().minimumScaleFactor(0.6)
                Text("Dépensé \(money(s, s.dep))").font(.caption2).opacity(0.75)
            }
        case .systemMedium:
            CBMediumView(e: e)
        default:
            CBSmallView(e: e)
        }
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
            Text("Il te reste").font(.system(size: 12, weight: .medium)).foregroundColor(soft)
            Text(money(s, s.solde))
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(s.soldeNeg && !s.hide ? red : ink)
                .minimumScaleFactor(0.5).lineLimit(1)
            if let p = s.goalPct {
                CBBar(pct: p, gold: true).padding(.top, 4)
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
                Text(money(s, s.solde))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(s.soldeNeg && !s.hide ? red : ink)
                    .minimumScaleFactor(0.5).lineLimit(1)
                if let p = s.goalPct {
                    CBBar(pct: p, gold: true).padding(.top, 4)
                    Text("Objectif d’épargne : \(pctText(p))").font(.system(size: 10)).foregroundColor(soft)
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
                        .background(Capsule().fill(card))
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

struct CBBudgetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBBudget", provider: CBProvider()) { e in
            CBContainer(e) { CBBudgetView(e: e) }
        }
        .configurationDisplayName("Solde")
        .description("Ce qu’il te reste à dépenser. Sur l’écran verrouillé : l’anneau du budget du mois.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 2 · Mascotte (+ anneau épargne)

struct CBPetView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let s = e.s
        switch family {
        case .accessoryCircular:
            if let p = s.goalPct {
                Gauge(value: min(max(p, 0), 1)) { Text(s.pet) } currentValueLabel: { Text(s.pet) }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetAccentable()
            } else {
                ZStack { AccessoryWidgetBackground(); Text(s.pet).font(.title2) }
            }
        case .systemMedium:
            HStack(spacing: 12) {
                CBPetImage(e: e).frame(width: 128)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.month.capitalized).font(.system(size: 13, weight: .semibold)).foregroundColor(soft)
                    Spacer(minLength: 0)
                    Text("Il te reste").font(.system(size: 12, weight: .medium)).foregroundColor(soft)
                    Text(money(s, s.solde))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(s.soldeNeg && !s.hide ? red : ink)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    if let p = s.goalPct {
                        CBBar(pct: p, gold: true).padding(.top, 2)
                        Text(s.hide ? "Objectif : \(pctText(p))" : (s.goalLabel ?? "") + " · " + pctText(p))
                            .font(.system(size: 10)).foregroundColor(soft).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Text("Épargné ce mois : \(money(s, s.sav))").font(.system(size: 11)).foregroundColor(soft).lineLimit(1)
                    }
                }
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        case .systemLarge:
            CBPetLargeView(e: e)
        default:
            VStack(spacing: 4) {
                CBPetImage(e: e).frame(maxWidth: .infinity, maxHeight: .infinity)
                if let p = s.goalPct {
                    CBBar(pct: p, gold: true, height: 7)
                    Text("\(pctText(p)) de l’objectif").font(.system(size: 11, weight: .semibold)).foregroundColor(soft).lineLimit(1)
                } else {
                    Text(money(s, s.solde)).font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(s.soldeNeg && !s.hide ? red : ink).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        }
    }
}

struct CBPetWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBPet", provider: CBProvider()) { e in
            CBContainer(e) { CBPetView(e: e) }
        }
        .configurationDisplayName("Mascotte")
        .description("Ta mascotte, son humeur et ton objectif d’épargne. Elle dort la nuit.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular])
    }
}

// MARK: - 4 · Catégories (+ catégorie à surveiller)

struct CBCatRow: View {
    let c: CBShared.Cat
    let hide: Bool
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            HStack(spacing: 4) {
                Text("\(c.ic ?? "") \(c.n)").font(.system(size: compact ? 11 : 12, weight: .semibold)).foregroundColor(ink).lineLimit(1)
                Spacer(minLength: 4)
                Text(hide ? "•••" : (c.l.map { short(c.v) + " / " + short($0) } ?? short(c.v)))
                    .font(.system(size: compact ? 10 : 11, weight: .medium, design: .rounded))
                    .foregroundColor((c.pct ?? 0) >= 1 ? red : soft).lineLimit(1)
            }
            CBBar(pct: c.pct ?? 1, color: c.pct == nil ? Color(hex: c.col).opacity(0.35) : barColor(c), height: compact ? 6 : 7)
        }
    }
}

struct CBCatsView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let s = e.s
        switch family {
        case .accessoryRectangular:
            if let w = s.watch {
                VStack(alignment: .leading, spacing: 2) {
                    Text((w.pct ?? 0) >= 1 ? "⚠︎ Plafond dépassé" : "⚠︎ À surveiller").font(.caption2).lineLimit(1)
                    Text("\(w.ic ?? "") \(w.n)").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().opacity(0.25)
                            Capsule().frame(width: max(5, g.size.width * CGFloat(min(w.pct ?? 0, 1))))
                        }
                    }
                    .frame(height: 5)
                    .widgetAccentable()
                    Text(s.hide ? "•••" : short(w.v) + (w.l.map { " sur " + short($0) } ?? ""))
                        .font(.caption2).lineLimit(1).minimumScaleFactor(0.7).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Catégories").font(.caption2)
                    Text("Tout est sous contrôle 👌").font(.headline).minimumScaleFactor(0.7)
                    Text("Aucun plafond presque atteint").font(.caption2).opacity(0.75)
                }
            }
        default:
            let big = family == .systemLarge
            let list = Array((s.cats ?? []).prefix(big ? 6 : 3))
            VStack(alignment: .leading, spacing: big ? 12 : 8) {
                HStack {
                    Text("📊 Catégories · \(s.month)").font(.system(size: 13, weight: .semibold)).foregroundColor(soft).lineLimit(1)
                    Spacer()
                    Text(money(s, s.dep)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(ink)
                }
                if list.isEmpty {
                    Spacer()
                    Text("Aucune dépense ce mois-ci").font(.system(size: 13)).foregroundColor(soft).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(list, id: \.self) { c in CBCatRow(c: c, hide: s.hide, compact: !big) }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        }
    }
}

struct CBCatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBCats", provider: CBProvider()) { e in
            CBContainer(e) { CBCatsView(e: e) }
        }
        .configurationDisplayName("Catégories")
        .description("Tes catégories et leurs plafonds. Sur l’écran verrouillé : celle à surveiller.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - 5 · Évolution (courbe du solde + semaine)

struct CBCurveView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let s = e.s
        switch family {
        case .accessoryRectangular:
            let w = s.week ?? Array(repeating: 0, count: 7)
            let t = s.weekToday ?? -1
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Cette semaine").font(.caption2)
                    Spacer()
                    Text(money(s, s.weekTotal ?? "")).font(.caption2.bold())
                }
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        VStack(spacing: 1) {
                            RoundedRectangle(cornerRadius: 2)
                                .frame(height: max(2, 24 * CGFloat(i < w.count ? w[i] : 0)))
                                .opacity(i == t ? 1 : 0.5)
                            Text(wdays[i]).font(.system(size: 8, weight: i == t ? .bold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .widgetAccentable()
            }
        default:
            let c = s.curve ?? []
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("📈 Solde · \(s.month)").font(.system(size: 13, weight: .semibold)).foregroundColor(soft).lineLimit(1)
                    Spacer()
                    Text(money(s, s.solde)).font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(s.soldeNeg && !s.hide ? red : ink).lineLimit(1).minimumScaleFactor(0.6)
                }
                if c.count >= 2 {
                    CBCurve(v: c, days: s.curveDays ?? c.count)
                } else {
                    Spacer()
                    Text("La courbe apparaît après quelques jours").font(.system(size: 12)).foregroundColor(soft).frame(maxWidth: .infinity)
                    Spacer()
                }
                HStack {
                    Text("Début").font(.system(size: 9)).foregroundColor(soft)
                    Spacer()
                    Text("Dépensé \(money(s, s.dep))").font(.system(size: 9, weight: .medium)).foregroundColor(soft)
                    Spacer()
                    Text("Fin").font(.system(size: 9)).foregroundColor(soft)
                }
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        }
    }
}

struct CBCurveWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBCurve", provider: CBProvider()) { e in
            CBContainer(e) { CBCurveView(e: e) }
        }
        .configurationDisplayName("Évolution")
        .description("La courbe de ton solde sur le mois. Sur l’écran verrouillé : tes dépenses de la semaine.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

// MARK: - 6 · Calendrier des dépenses

private let heat: [Color] = [ink.opacity(0.08), Color(hex: "#ffe3c2"), Color(hex: "#ffb36b"), Color(hex: "#f97316"), Color(hex: "#c2410c")]

struct CBCalView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        let cal = s.cal ?? []
        let first = s.calFirst ?? 0
        let today = s.calToday ?? 0
        let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("🗓️ \((s.calMonth ?? s.month).capitalized)").font(.system(size: 15, weight: .bold)).foregroundColor(ink)
                Spacer()
                Text("Dépensé \(money(s, s.dep))").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(soft)
            }
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
                    Text(wdays[i]).font(.system(size: 10, weight: .semibold)).foregroundColor(soft).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: cols, spacing: 5) {
                ForEach(0..<(first + cal.count), id: \.self) { k in
                    if k < first {
                        Color.clear.frame(height: 26)
                    } else {
                        let d = k - first + 1
                        let lv = cal[k - first]
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(lv < 0 ? ink.opacity(0.04) : heat[min(max(lv, 0), 4)])
                            .frame(height: 26)
                            .overlay(
                                Text("\(d)").font(.system(size: 10, weight: d == today ? .bold : .medium))
                                    .foregroundColor(lv >= 3 ? .white : ink.opacity(lv < 0 ? 0.3 : 0.75))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(ink, lineWidth: d == today ? 2 : 0)
                            )
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Text("Moins").font(.system(size: 9)).foregroundColor(soft)
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(heat[i]).frame(width: 12, height: 12)
                }
                Text("Plus").font(.system(size: 9)).foregroundColor(soft)
                Spacer()
                Text("\(s.pet)").font(.system(size: 14))
            }
        }
        .widgetURL(URL(string: "cleanbudget://open"))
    }
}

struct CBCalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBCal", provider: CBProvider()) { e in
            CBContainer(e) { CBCalView(e: e) }
        }
        .configurationDisplayName("Calendrier")
        .description("Chaque jour du mois, coloré selon ce que tu as dépensé.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - 7 · Reste par jour

struct CBPerDayView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let s = e.s
        let v = s.perDay ?? "—"
        switch family {
        case .accessoryInline:
            Text("\(s.pet) \(short(money(s, v)))/jour · reste \(short(money(s, s.solde)))")
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text(short(money(s, v))).font(.system(size: 14, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                    Text("/ jour").font(.system(size: 9))
                }
                .padding(4)
            }
            .widgetAccentable()
        default:
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(s.pet).font(.system(size: 22))
                    Spacer()
                    Image(systemName: "calendar").font(.system(size: 16, weight: .semibold)).foregroundColor(soft)
                }
                Spacer(minLength: 2)
                Text("Tu peux dépenser").font(.system(size: 11, weight: .medium)).foregroundColor(soft)
                Text(short(money(s, v)))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(ink).minimumScaleFactor(0.5).lineLimit(1)
                Text("par jour").font(.system(size: 13, weight: .semibold)).foregroundColor(ink)
                Text(s.perNote ?? "").font(.system(size: 10)).foregroundColor(soft).lineLimit(2).minimumScaleFactor(0.8)
            }
            .widgetURL(URL(string: "cleanbudget://add"))
        }
    }
}

struct CBPerDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBPerDay", provider: CBProvider()) { e in
            CBContainer(e) { CBPerDayView(e: e) }
        }
        .configurationDisplayName("Reste par jour")
        .description("Combien tu peux dépenser chaque jour jusqu’à ta prochaine paie ou la fin du mois.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: - 8 · Prochains prélèvements

struct CBBillsView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let s = e.s
        let up = s.upcoming ?? []
        switch family {
        case .accessoryRectangular:
            if let b = up.first {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Prochain prélèvement").font(.caption2)
                    Text(b.n).font(.headline).lineLimit(1)
                    Text("\(b.w) · \(money(s, b.a))").font(.caption2).opacity(0.8)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Prélèvements").font(.caption2)
                    Text("Rien de prévu").font(.headline)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 7) {
                Text("📅 Prochains prélèvements").font(.system(size: 13, weight: .semibold)).foregroundColor(soft)
                if up.isEmpty {
                    Spacer()
                    Text("Aucun prélèvement programmé.\nAjoute tes opérations récurrentes dans l’app.")
                        .font(.system(size: 12)).foregroundColor(soft).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    ForEach(up.prefix(3), id: \.self) { b in
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(card)
                                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 12, weight: .bold)).foregroundColor(ink.opacity(0.7))
                            }
                            .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(b.n).font(.system(size: 13, weight: .semibold)).foregroundColor(ink).lineLimit(1)
                                Text(b.w).font(.system(size: 10)).foregroundColor(b.w == "Aujourd’hui" || b.w == "Demain" ? red : soft)
                            }
                            Spacer()
                            Text(money(s, b.a)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(ink).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        }
    }
}

struct CBBillsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBBills", provider: CBProvider()) { e in
            CBContainer(e) { CBBillsView(e: e) }
        }
        .configurationDisplayName("Prélèvements")
        .description("Tes prochaines opérations récurrentes : loyer, abonnements…")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

// MARK: - 9 · Tableau de bord

struct CBDashTile: View {
    let t: String
    let v: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 10, weight: .medium)).foregroundColor(soft)
            Text(v).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(ink).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(card))
    }
}

struct CBDashView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        let c = s.curve ?? []
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                CBPetImage(e: e).frame(width: 70, height: 58)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.month.capitalized).font(.system(size: 12, weight: .semibold)).foregroundColor(soft)
                    Text("Il te reste").font(.system(size: 11)).foregroundColor(soft)
                    Text(money(s, s.solde)).font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(s.soldeNeg && !s.hide ? red : ink).lineLimit(1).minimumScaleFactor(0.5)
                }
                Spacer(minLength: 0)
                Link(destination: URL(string: "cleanbudget://add")!) {
                    Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundColor(.white)
                        .frame(width: 40, height: 40).background(Circle().fill(red))
                }
            }
            HStack(spacing: 6) {
                CBDashTile(t: "Dépensé", v: money(s, s.dep))
                CBDashTile(t: "Épargné", v: money(s, s.sav))
                CBDashTile(t: "Par jour", v: short(money(s, s.perDay ?? "—")))
            }
            if c.count >= 2 {
                CBCurve(v: c, days: s.curveDays ?? c.count).frame(height: 52)
            }
            ForEach(Array((s.cats ?? []).prefix(3)), id: \.self) { cat in CBCatRow(c: cat, hide: s.hide, compact: true) }
            Spacer(minLength: 0)
            if let b = s.upcoming?.first {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11, weight: .bold)).foregroundColor(soft)
                    Text("\(b.n) · \(b.w)").font(.system(size: 11, weight: .medium)).foregroundColor(soft).lineLimit(1)
                    Spacer()
                    Text(money(s, b.a)).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(ink)
                }
            }
        }
        .widgetURL(URL(string: "cleanbudget://open"))
    }
}

struct CBDashWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBDash", provider: CBProvider()) { e in
            CBContainer(e) { CBDashView(e: e) }
        }
        .configurationDisplayName("Tableau de bord")
        .description("Tout ton mois d’un coup d’œil : solde, courbe, catégories et prochain prélèvement.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - 10 · Bouton du Centre de contrôle (iOS 18)

@available(iOSApplicationExtension 18.0, *)
struct CBAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mateobachele.cleanbudget.add") {
            ControlWidgetButton(action: OpenAddExpenseIntent()) {
                Label("Dépense", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Ajouter une dépense")
        .description("Ouvre Clean Budget sur l’ajout d’une dépense.")
    }
}

// MARK: - Ensemble des widgets
// Un groupe de widgets ne peut pas en lister plus de 10 d'un coup : on les range en sous-groupes.

@main
struct CleanBudgetWidgets: WidgetBundle {
    var body: some Widget {
        homeWidgets
        moreWidgets
        if #available(iOSApplicationExtension 17.0, *) {
            CBCatPickWidget()
        }
        if #available(iOSApplicationExtension 17.0, *) {
            CBAccountWidget()
        }
        if #available(iOSApplicationExtension 18.0, *) {
            CBAddControl()
        }
        if #available(iOSApplicationExtension 16.1, *) {
            CBLiveWidget()
        }
    }

    @WidgetBundleBuilder
    var homeWidgets: some Widget {
        CBBudgetWidget()
        CBPetWidget()
        CBCatsWidget()
        CBCurveWidget()
        CBCalWidget()
        CBPerDayWidget()
        CBBillsWidget()
        CBDashWidget()
    }

    @WidgetBundleBuilder
    var moreWidgets: some Widget {
        CBGoalWidget()
        CBRecentWidget()
        CBCompareWidget()
        CBAccountsWidget()
        CBChallengeWidget()
        CBTipWidget()
        CBPayWidget()
        CBTodayWidget()
    }
}
