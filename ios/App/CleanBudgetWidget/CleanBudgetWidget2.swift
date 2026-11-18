import WidgetKit
import SwiftUI
import AppIntents
#if canImport(ActivityKit)
import ActivityKit
#endif

// Widgets 17 à 28 : objectif, dernières dépenses, comparaison, comptes, défi, conseil,
// mascotte géante, paie, aujourd'hui, et les deux widgets réglables.

func cbEntry(_ d: Date = Date(), preview: Bool = false) -> CBEntry {
    let s = CBShared.summary()
    return CBEntry(date: d, s: s ?? CBShared.sample, empty: s == nil && !preview, night: isNight(d), done: nil)
}

struct CBRing: View {
    let p: Double
    var color: Color = Color(hex: "#f5a524")
    var width: CGFloat = 9
    var label: String
    var size: CGFloat = 15
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: width)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.001, min(p, 1))))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label).font(.system(size: size, weight: .heavy, design: .rounded)).foregroundColor(ink)
                .minimumScaleFactor(0.6).lineLimit(1).padding(width)
        }
    }
}

struct CBHint: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 12, weight: .medium)).foregroundColor(soft)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 23 · Mascotte géante (grand)

struct CBPetLargeView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        VStack(spacing: 10) {
            HStack {
                Text(s.month.capitalized).font(.system(size: 14, weight: .bold)).foregroundColor(soft)
                Spacer()
                Text("Épargné \(money(s, s.sav))").font(.system(size: 12, weight: .semibold)).foregroundColor(soft)
            }
            CBPetImage(e: e).frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .firstTextBaseline) {
                Text("Il te reste").font(.system(size: 13)).foregroundColor(soft)
                Spacer()
                Text(money(s, s.solde)).font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(s.soldeNeg && !s.hide ? red : ink).lineLimit(1).minimumScaleFactor(0.5)
            }
            if let p = s.goalPct {
                CBBar(pct: p, gold: true, height: 10)
                Text(s.hide ? "Objectif d’épargne : \(pctText(p))" : "Objectif d’épargne : \(s.goalLabel ?? "") · \(pctText(p))")
                    .font(.system(size: 12)).foregroundColor(soft).frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
            } else if let pd = s.perDay {
                Text("Tu peux dépenser \(short(money(s, pd))) par jour").font(.system(size: 12)).foregroundColor(soft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "cleanbudget://open"))
    }
}

// MARK: - 17 · Objectif d'épargne

struct CBGoalView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let s = e.s
        if let g = s.goalT {
            if family == .systemMedium {
                HStack(spacing: 18) {
                    CBRing(p: g.p, label: pctText(g.p), size: 17).frame(width: 108, height: 108)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(g.t).font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#6b4e00"))
                        Text(short(money(s, g.v))).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(ink).lineLimit(1).minimumScaleFactor(0.6)
                        Text(s.hide ? "de ton objectif" : "sur \(short(g.of)) · encore \(short(g.rest))").font(.system(size: 12)).foregroundColor(soft).lineLimit(1).minimumScaleFactor(0.7)
                        if !g.eta.isEmpty {
                            Text(g.eta).font(.system(size: 12, weight: .semibold)).foregroundColor(ink).padding(.top, 3).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        if !g.rate.isEmpty && !s.hide {
                            Text(short(g.rate)).font(.system(size: 11)).foregroundColor(soft).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .widgetURL(URL(string: "cleanbudget://open"))
            } else {
                VStack(spacing: 6) {
                    Text(g.t).font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#6b4e00"))
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                    CBRing(p: g.p, label: pctText(g.p)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text(s.hide ? "•••" : "\(short(g.v)) sur \(short(g.of))").font(.system(size: 11)).foregroundColor(soft).lineLimit(1).minimumScaleFactor(0.7)
                }
                .widgetURL(URL(string: "cleanbudget://open"))
            }
        } else {
            CBHint(text: "Fixe un objectif d’épargne dans l’app pour le suivre ici")
        }
    }
}

struct CBGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBGoal", provider: CBProvider()) { e in
            CBContainer(e, colors: ["#fff6dc", "#ffe6a8"]) { CBGoalView(e: e) }
        }
        .configurationDisplayName("Objectif d’épargne")
        .description("Où tu en es de ton objectif, et quand tu l’atteindras à ce rythme.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - 18 · Dernières dépenses

struct CBRecentView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        let list = Array((s.recent ?? []).prefix(4))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dernières dépenses").font(.system(size: 13, weight: .bold)).foregroundColor(soft)
                Spacer()
                Link(destination: URL(string: "cleanbudget://add")!) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                        .frame(width: 28, height: 28).background(Circle().fill(red))
                }
            }
            if list.isEmpty {
                CBHint(text: "Aucune dépense pour l’instant")
            } else {
                ForEach(list, id: \.self) { r in
                    HStack(spacing: 6) {
                        Text(r.ic).font(.system(size: 13))
                        Text(r.n).font(.system(size: 13, weight: .semibold)).foregroundColor(ink).lineLimit(1)
                        Text("· \(r.w)").font(.system(size: 11)).foregroundColor(soft).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(money(s, r.a)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(ink).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "cleanbudget://open"))
    }
}

struct CBRecentWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBRecent", provider: CBProvider()) { e in
            CBContainer(e) { CBRecentView(e: e) }
        }
        .configurationDisplayName("Dernières dépenses")
        .description("Tes 4 dernières dépenses, et un bouton pour en ajouter une.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 19 · Comparé au mois dernier

struct CBCompareView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        if let c = s.cmp {
            let col = c.less ? Color(hex: "#0f6b43") : red
            VStack(alignment: .leading, spacing: 4) {
                Text("Ce mois-ci").font(.system(size: 12, weight: .semibold)).foregroundColor(soft)
                Spacer(minLength: 0)
                Text(s.hide ? "•••" : short(c.d)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundColor(col).lineLimit(1).minimumScaleFactor(0.5)
                Text(c.less ? "de moins qu’en \(c.prev)" : "de plus qu’en \(c.prev)").font(.system(size: 11)).foregroundColor(soft).lineLimit(1).minimumScaleFactor(0.7)
                GeometryReader { g in
                    HStack(alignment: .bottom, spacing: 10) {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 6).fill(col.opacity(0.3))
                                .frame(height: max(4, (g.size.height - 14) * CGFloat(c.pr)))
                            Text(String(c.prev.prefix(3)) + ".").font(.system(size: 10)).foregroundColor(soft)
                        }
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 6).fill(col)
                                .frame(height: max(4, (g.size.height - 14) * CGFloat(c.cr)))
                            Text(String(c.cm.prefix(3)) + ".").font(.system(size: 10)).foregroundColor(soft)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(height: 46)
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        } else {
            CBHint(text: "Disponible après un mois de dépenses")
        }
    }
}

struct CBCompareWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBCompare", provider: CBProvider()) { e in
            CBContainer(e, colors: ["#e0f7ec", "#bfeed6"]) { CBCompareView(e: e) }
        }
        .configurationDisplayName("Comparé au mois dernier")
        .description("Tu dépenses plus ou moins que le mois dernier, à la même date ?")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 20 · Mes comptes

struct CBAccountsView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        let list = Array((s.accts ?? []).prefix(4))
        if list.isEmpty {
            CBHint(text: "Active « Comptes » dans les réglages de l’app pour voir chaque compte ici")
        } else {
            let tot = max(list.reduce(0) { $0 + max($1.raw, 0) }, 1)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Mes comptes").font(.system(size: 13, weight: .bold)).foregroundColor(soft)
                    Spacer()
                    Text(money(s, s.acctTotal ?? "")).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(ink)
                }
                ForEach(list, id: \.self) { a in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: a.col)).frame(width: 10, height: 10)
                        Text(a.n).font(.system(size: 13)).foregroundColor(ink).lineLimit(1)
                        Spacer()
                        Text(money(s, short(a.v))).font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(a.raw < 0 && !s.hide ? red : ink).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                GeometryReader { g in
                    HStack(spacing: 0) {
                        ForEach(list, id: \.self) { a in
                            Rectangle().fill(Color(hex: a.col)).frame(width: g.size.width * CGFloat(max(a.raw, 0) / tot))
                        }
                    }
                }
                .frame(height: 8).clipShape(Capsule())
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        }
    }
}

struct CBAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBAccounts", provider: CBProvider()) { e in
            CBContainer(e) { CBAccountsView(e: e) }
        }
        .configurationDisplayName("Mes comptes")
        .description("Le solde de chacun de tes comptes, et le total.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 21 · Défi de la semaine

struct CBChallengeView: View {
    let e: CBEntry
    var body: some View {
        let s = e.s
        if let c = s.chal {
            VStack(alignment: .leading, spacing: 4) {
                Text("Défi · \(short(money(s, c.tg))) cette semaine").font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#7a2645")).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    CBPetImage(e: e).frame(width: 58, height: 48)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(c.ok ? "Plus que" : "Dépassé").font(.system(size: 11)).foregroundColor(Color(hex: "#7a2645"))
                        Text(c.ok ? short(money(s, c.left)) : "😬").font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(ink).lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                Spacer(minLength: 0)
                CBBar(pct: c.p, color: c.ok ? Color(hex: "#e0457b") : red)
                Text(c.msg).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#7a2645"))
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        } else {
            CBHint(text: "Ton premier défi arrive après quelques semaines de dépenses")
        }
    }
}

struct CBChallengeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBChallenge", provider: CBProvider()) { e in
            CBContainer(e, colors: ["#ffe3ec", "#ffc6d8"]) { CBChallengeView(e: e) }
        }
        .configurationDisplayName("Défi de la semaine")
        .description("Dépense 10 % de moins que d’habitude cette semaine : ta mascotte t’encourage.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - 22 · Conseil du jour

struct CBTipView: View {
    let e: CBEntry
    var body: some View {
        if let t = e.s.tip {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.7))
                    Image(systemName: "lightbulb.fill").font(.system(size: 22)).foregroundColor(Color(hex: "#6d3fd6"))
                }
                .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Conseil du jour").font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#4b2a99"))
                    Text(e.s.hide ? "Ouvre l’app pour voir ton conseil" : t.t).font(.system(size: 15, weight: .bold)).foregroundColor(ink)
                        .lineLimit(3).minimumScaleFactor(0.75)
                    if !e.s.hide {
                        Text(t.s).font(.system(size: 12)).foregroundColor(Color(hex: "#4a3a6e")).lineLimit(3).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .widgetURL(URL(string: "cleanbudget://open"))
        } else {
            CBHint(text: "Ajoute quelques dépenses pour recevoir des conseils")
        }
    }
}

struct CBTipWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBTip", provider: CBProvider()) { e in
            CBContainer(e, colors: ["#efe6ff", "#dccbff"]) { CBTipView(e: e) }
        }
        .configurationDisplayName("Conseil du jour")
        .description("Chaque jour, une astuce tirée de tes propres chiffres.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - 24 · Jours avant la paie

struct CBPayView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let p = e.s.pay
        let paie = p?.paie ?? false
        let what = paie ? "paie" : "fin du mois"
        let days = p?.d ?? 0
        let plural = days > 1 ? "s" : ""
        let title: String = p == nil ? "En attente de ta paie" : (paie ? "Paie dans \(days) jour\(plural)" : "Fin du mois dans \(days) jour\(plural)")
        let ring: String = p == nil ? "…" : "\(days) j"
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Gauge(value: p?.p ?? 0) { Text(what) }
                    .gaugeStyle(.accessoryLinearCapacity).widgetAccentable()
                Text("\(short(money(e.s, e.s.perDay ?? "—"))) par jour d’ici là").font(.caption2).opacity(0.8).lineLimit(1)
            }
        default:
            Gauge(value: p?.p ?? 0) {
                Text(what)
            } currentValueLabel: {
                Text(ring)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        }
    }
}

struct CBPayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBPay", provider: CBProvider()) { e in
            CBContainer(e) { CBPayView(e: e) }
        }
        .configurationDisplayName("Avant la paie")
        .description("Le nombre de jours avant ta prochaine paie (ou la fin du mois).")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - 25 · Dépensé aujourd'hui

struct CBTodayView: View {
    @Environment(\.widgetFamily) var family
    let e: CBEntry
    var body: some View {
        let v = short(money(e.s, e.s.todaySp ?? "0 €"))
        switch family {
        case .accessoryInline:
            Text("Aujourd’hui : \(v) dépensés")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("aujourd’hui").font(.system(size: 8))
                    Text(v).font(.system(size: 15, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                }
                .padding(4)
            }
            .widgetAccentable()
        }
    }
}

struct CBTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CBToday", provider: CBProvider()) { e in
            CBContainer(e) { CBTodayView(e: e) }
        }
        .configurationDisplayName("Dépensé aujourd’hui")
        .description("Ce que tu as dépensé depuis ce matin.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

// MARK: - 27 · Catégorie au choix (réglable)

@available(iOSApplicationExtension 17.0, *)
struct CBPickEntry: TimelineEntry {
    let date: Date
    let e: CBEntry
    let pick: String?
    let showGoal: Bool
}

@available(iOSApplicationExtension 17.0, *)
struct CBCatPickProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CBPickEntry {
        CBPickEntry(date: Date(), e: cbEntry(preview: true), pick: nil, showGoal: true)
    }
    func snapshot(for configuration: CBCategoryWidgetConfig, in context: Context) async -> CBPickEntry {
        CBPickEntry(date: Date(), e: cbEntry(preview: context.isPreview), pick: configuration.category?.id, showGoal: true)
    }
    func timeline(for configuration: CBCategoryWidgetConfig, in context: Context) async -> Timeline<CBPickEntry> {
        let now = Date()
        let en = CBPickEntry(date: now, e: cbEntry(now), pick: configuration.category?.id, showGoal: true)
        return Timeline(entries: [en], policy: .after(now.addingTimeInterval(3600)))
    }
}

@available(iOSApplicationExtension 17.0, *)
struct CBCatPickView: View {
    @Environment(\.widgetFamily) var family
    let en: CBPickEntry
    var body: some View {
        let s = en.e.s
        let all = s.catsAll ?? s.cats ?? []
        let c = all.first(where: { $0.id != nil && $0.id == en.pick }) ?? s.watch ?? all.first
        if let c = c {
            let p = min(c.pct ?? 0, 1)
            let detail = s.hide ? "•••" : short(c.v) + (c.l.map { " sur " + short($0) } ?? " ce mois-ci")
            switch family {
            case .accessoryCircular:
                if c.pct != nil {
                    Gauge(value: p) { Text(c.ic ?? "") } currentValueLabel: { Text(c.ic ?? "") }
                        .gaugeStyle(.accessoryCircularCapacity).widgetAccentable()
                } else {
                    ZStack {
                        AccessoryWidgetBackground()
                        VStack(spacing: 0) {
                            Text(c.ic ?? "").font(.system(size: 12))
                            Text(s.hide ? "•••" : short(c.v)).font(.system(size: 12, weight: .bold, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
                        }
                        .padding(4)
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(c.ic ?? "") \(c.n)").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().opacity(0.25)
                            Capsule().frame(width: max(5, g.size.width * CGFloat(c.pct == nil ? 0 : p)))
                        }
                    }
                    .frame(height: 5)
                    .widgetAccentable()
                    Text(detail).font(.caption2).lineLimit(1).minimumScaleFactor(0.7).opacity(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(c.ic ?? "") \(c.n)").font(.system(size: 14, weight: .bold)).foregroundColor(ink).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Text(s.hide ? "•••" : short(c.v)).font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor((c.pct ?? 0) >= 1 && !s.hide ? red : ink).lineLimit(1).minimumScaleFactor(0.5)
                    Text(c.l != nil ? (s.hide ? "de ton plafond" : "sur \(short(c.l!))") : "pas de plafond").font(.system(size: 11)).foregroundColor(soft)
                    CBBar(pct: c.pct == nil ? 1 : p, color: c.pct == nil ? Color(hex: c.col).opacity(0.35) : barColor(c)).padding(.top, 2)
                }
                .widgetURL(URL(string: "cleanbudget://open"))
            }
        } else {
            CBHint(text: "Ajoute une catégorie dans l’app")
        }
    }
}

@available(iOSApplicationExtension 17.0, *)
struct CBCatPickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CBCatPick", intent: CBCategoryWidgetConfig.self, provider: CBCatPickProvider()) { en in
            CBContainer(en.e) { CBCatPickView(en: en) }
        }
        .configurationDisplayName("Catégorie au choix")
        .description("Suis la catégorie de ton choix : appui long sur le widget › Modifier le widget.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - 28 · Compte au choix (réglable)

@available(iOSApplicationExtension 17.0, *)
struct CBAccountProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CBPickEntry {
        CBPickEntry(date: Date(), e: cbEntry(preview: true), pick: nil, showGoal: true)
    }
    func snapshot(for configuration: CBAccountWidgetConfig, in context: Context) async -> CBPickEntry {
        CBPickEntry(date: Date(), e: cbEntry(preview: context.isPreview), pick: configuration.account?.id, showGoal: configuration.showGoal)
    }
    func timeline(for configuration: CBAccountWidgetConfig, in context: Context) async -> Timeline<CBPickEntry> {
        let now = Date()
        let en = CBPickEntry(date: now, e: cbEntry(now), pick: configuration.account?.id, showGoal: configuration.showGoal)
        return Timeline(entries: [en], policy: .after(now.addingTimeInterval(3600)))
    }
}

@available(iOSApplicationExtension 17.0, *)
struct CBAccountView: View {
    @Environment(\.widgetFamily) var family
    let en: CBPickEntry
    var body: some View {
        let s = en.e.s
        let list = s.accts ?? []
        let a = list.first(where: { $0.id == en.pick }) ?? list.first
        let name = a?.n ?? "Solde"
        let value = money(s, a.map { short($0.v) } ?? s.solde)
        let neg = (a?.raw ?? (s.soldeNeg ? -1 : 1)) < 0 && !s.hide
        switch family {
        case .accessoryInline:
            Text("\(name) : \(value)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.caption2).lineLimit(1)
                Text(value).font(.system(.title3, design: .rounded)).bold().minimumScaleFactor(0.6).lineLimit(1)
                if en.showGoal, let p = s.goalPct {
                    Text("Objectif \(pctText(p))").font(.caption2).opacity(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(name).font(.system(size: 13, weight: .bold)).foregroundColor(soft).lineLimit(1)
                    Spacer()
                    if let col = a?.col {
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: col)).frame(width: 10, height: 10)
                    }
                }
                Spacer(minLength: 0)
                Text(value).font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(neg ? red : ink).lineLimit(1).minimumScaleFactor(0.5)
                if a == nil {
                    Text("Active « Comptes » dans l’app pour choisir un compte").font(.system(size: 10)).foregroundColor(soft).lineLimit(2)
                }
                if en.showGoal, let p = s.goalPct {
                    CBBar(pct: p, gold: true).padding(.top, 2)
                    Text("Objectif d’épargne : \(pctText(p))").font(.system(size: 10)).foregroundColor(soft)
                }
            }
            .widgetURL(URL(string: "cleanbudget://open"))
        }
    }
}

@available(iOSApplicationExtension 17.0, *)
struct CBAccountWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "CBAccount", intent: CBAccountWidgetConfig.self, provider: CBAccountProvider()) { en in
            CBContainer(en.e) { CBAccountView(en: en) }
        }
        .configurationDisplayName("Compte au choix")
        .description("Le solde du compte de ton choix : appui long sur le widget › Modifier le widget.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - 29 · Activité en direct : budget du jour (écran verrouillé + Dynamic Island)

#if canImport(ActivityKit)
@available(iOSApplicationExtension 16.1, *)
struct CBLiveBar: View {
    let p: Double
    let over: Bool
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(over ? red : Color(hex: "#34c759"))
                    .frame(width: max(6, g.size.width * CGFloat(min(max(p, 0), 1))))
            }
        }
        .frame(height: 7)
    }
}

@available(iOSApplicationExtension 16.1, *)
struct CBLiveWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CBLiveAttributes.self) { context in
            let st = context.state
            HStack(spacing: 14) {
                Text(context.attributes.pet).font(.system(size: 38))
                VStack(alignment: .leading, spacing: 4) {
                    Text(st.over ? "Budget du jour dépassé" : "Reste aujourd’hui")
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(.white.opacity(0.7))
                    Text(st.hide ? "•••" : st.left)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(st.over ? Color(hex: "#ff6b6b") : .white)
                    CBLiveBar(p: st.pct, over: st.over)
                    Text(st.hide ? "Montants masqués" : "Dépensé \(st.spent) sur \(st.day) · il te reste \(st.solde)")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.65)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .activityBackgroundTint(Color(red: 0.08, green: 0.08, blue: 0.12))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "cleanbudget://add"))
        } dynamicIsland: { context in
            let st = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.pet).font(.system(size: 30)).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(st.over ? "Dépassé" : "Reste").font(.caption2).foregroundColor(.white.opacity(0.7))
                        Text(st.hide ? "•••" : st.left).font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(st.over ? Color(hex: "#ff6b6b") : Color(hex: "#34c759"))
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        CBLiveBar(p: st.pct, over: st.over)
                        HStack {
                            Text(st.hide ? "" : "Dépensé \(st.spent) sur \(st.day)").font(.caption2).foregroundColor(.white.opacity(0.7))
                            Spacer()
                            Link(destination: URL(string: "cleanbudget://add")!) {
                                Label("Dépense", systemImage: "plus.circle.fill").font(.caption.bold()).foregroundColor(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                Text(context.attributes.pet)
            } compactTrailing: {
                Text(st.hide ? "•••" : st.left)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(st.over ? Color(hex: "#ff6b6b") : Color(hex: "#34c759"))
            } minimal: {
                Text(context.attributes.pet)
            }
            .widgetURL(URL(string: "cleanbudget://add"))
        }
    }
}
#endif
