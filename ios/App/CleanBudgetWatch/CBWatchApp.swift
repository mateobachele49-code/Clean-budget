import SwiftUI
import WatchConnectivity
import WatchKit

// MARK: - Données reçues de l'iPhone (le même résumé que les widgets, seulement les champs utiles ici)

struct WCat: Codable, Hashable, Identifiable {
    var id: String
    var n: String
    var ic: String?
    var col: String?
}

struct WRecent: Codable, Hashable {
    var n: String
    var c: String
    var ic: String
    var a: String
    var w: String
    var col: String?
}

/// Couleur « #rrggbb » envoyée par l'app.
func wColor(_ hex: String?, _ fallback: Color = .orange) -> Color {
    guard var h = hex?.trimmingCharacters(in: .whitespaces), h.hasPrefix("#") else { return fallback }
    h.removeFirst()
    guard h.count == 6, let v = UInt32(h, radix: 16) else { return fallback }
    return Color(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
}

/// Accent orange-rose de l'app.
let wAccent = LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.33, blue: 0.47)], startPoint: .topLeading, endPoint: .bottomTrailing)

struct WAP: Codable { var cats: [WCat] }

/// Ce que tu as choisi d'afficher sur la montre (Réglages › Apple Pay et widgets › Montre).
struct WCfg: Codable {
    var big: String?
    var show: [String]?
    var order: [String]?
}

struct WSum: Codable {
    var solde: String
    var soldeNeg: Bool
    var dep: String
    var pet: String
    var hide: Bool
    var perDay: String?
    var soldeRaw: Double?
    var depRaw: Double?
    var cur: String?
    var liveB: Double?
    var liveS: Double?
    var recent: [WRecent]?
    var ap: WAP?
    var wcfg: WCfg?
    var bg1: String?
}

func wMoney(_ v: Double, _ cur: String?) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale(identifier: "fr_FR")
    f.currencyCode = cur ?? "EUR"
    f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f €", v)
}

// MARK: - Lien avec l'iPhone

final class WStore: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WStore()
    @Published var s: WSum?

    override init() {
        super.init()
        if let d = UserDefaults.standard.data(forKey: "sum") {
            s = try? JSONDecoder().decode(WSum.self, from: d)
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        apply(session.receivedApplicationContext)
        refresh()
    }

    /// Demande les chiffres à jour à l'iPhone quand il est joignable (ouverture de l'app sur la montre).
    func refresh() {
        let w = WCSession.default
        guard WCSession.isSupported(), w.activationState == .activated, w.isReachable else { return }
        w.sendMessage(["get": 1], replyHandler: { [weak self] r in self?.apply(r) }, errorHandler: nil)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    private func apply(_ ctx: [String: Any]) {
        guard let d = ctx["s"] as? Data, let v = try? JSONDecoder().decode(WSum.self, from: d) else { return }
        DispatchQueue.main.async {
            self.s = v
            UserDefaults.standard.set(d, forKey: "sum")
        }
    }

    /// Envoie la dépense à l'iPhone (livrée même s'il est verrouillé ou loin) et met l'écran à jour tout de suite.
    func add(_ a: Double, cat: WCat?) {
        var op: [String: Any] = ["t": "e", "a": a, "at": Date().timeIntervalSince1970, "src": "watch"]
        if let c = cat { op["cid"] = c.id }
        WCSession.default.transferUserInfo(["op": op])
        guard var v = s else { return }
        if let r = v.soldeRaw {
            v.soldeRaw = r - a
            v.solde = wMoney(r - a, v.cur)
            v.soldeNeg = r - a < 0
        }
        if let d = v.depRaw {
            v.depRaw = d + a
            v.dep = wMoney(d + a, v.cur)
        }
        v.liveS = (v.liveS ?? 0) + a
        let line = WRecent(n: cat?.n ?? "Dépense", c: cat?.n ?? "", ic: cat?.ic ?? "💸", a: wMoney(a, v.cur), w: "à l’instant")
        v.recent = [line] + (v.recent ?? [])
        s = v
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: "sum") }
    }
}

// MARK: - App

@main
struct CleanBudgetWatchApp: App {
    @StateObject private var store = WStore.shared
    var body: some Scene {
        WindowGroup {
            WHome().environmentObject(store)
        }
    }
}

enum WRoute: Hashable {
    case amount
    case cat(Double)
}

struct WHome: View {
    @EnvironmentObject var store: WStore
    @State private var path: [WRoute] = []
    @State private var done: String?

    static let defOrder = ["pet", "big", "solde", "today", "perday", "dep", "btn", "recent"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 8) {
                    if let s = store.s {
                        let big = (s.wcfg?.big ?? "solde").lowercased()
                        let show = Set(s.wcfg?.show ?? ["solde", "today", "perday", "dep", "recent", "pet"])
                        let given = (s.wcfg?.order ?? []).filter { WHome.defOrder.contains($0) }
                        let order = given + WHome.defOrder.filter { !given.contains($0) }
                        ForEach(order, id: \.self) { k in
                            block(k, s, big: big, show: show)
                        }
                    } else {
                        Text("🐷").font(.system(size: 40))
                        Text("Ouvre Clean Budget sur ton iPhone pour afficher tes chiffres.")
                            .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        addButton
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Clean Budget")
            .containerBackground(LinearGradient(colors: [wColor(store.s?.bg1, .orange).opacity(0.45), Color.black], startPoint: .top, endPoint: .center), for: .navigation)
            .onAppear { store.refresh() }
            .navigationDestination(for: WRoute.self) { r in
                switch r {
                case .amount:
                    WAmount { a in path.append(.cat(a)) }
                case .cat(let a):
                    WCats(amount: a, cats: store.s?.ap?.cats ?? [], cur: store.s?.cur) { c in
                        store.add(a, cat: c)
                        WKInterfaceDevice.current().play(.success)
                        done = "✓ " + wMoney(a, store.s?.cur) + (c.map { " · \($0.ic ?? "") \($0.n)" } ?? "")
                        path = []
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { done = nil }
                    }
                }
            }
        }
    }

    private var addButton: some View {
        VStack(spacing: 6) {
            NavigationLink(value: WRoute.amount) {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 15, weight: .heavy))
                    Text("Dépense").font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Capsule().fill(wAccent))
                .shadow(color: Color(red: 1, green: 0.4, blue: 0.3).opacity(0.45), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            if let d = done {
                Label(d, systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.green)
                    .multilineTextAlignment(.center)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
        .animation(.spring(duration: 0.35), value: done)
    }

    /// Un élément de l'écran, dans l'ordre choisi dans l'app.
    @ViewBuilder
    private func block(_ k: String, _ s: WSum, big: String, show: Set<String>) -> some View {
        switch k {
        case "pet":
            if show.contains("pet") {
                Text(s.pet).font(.system(size: 34))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
        case "big":
            if let v = wValue(big, s) {
                VStack(spacing: 2) {
                    Text(v.label.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                    Text(s.hide ? "•••" : v.text)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(s.hide ? Color.primary : v.color)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.45).lineLimit(1)
                    if !s.hide, let b = s.liveB, b > 0 {
                        let p = min(max((s.liveS ?? 0) / b, 0), 1)
                        let c: Color = p >= 1 ? .red : p >= 0.8 ? .orange : .green
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.15))
                                Capsule().fill(c).frame(width: max(6, g.size.width * p))
                            }
                        }
                        .frame(height: 5)
                        .padding(.horizontal, 14)
                        .padding(.top, 3)
                    }
                }
                .padding(.vertical, 4)
            }
        case "btn":
            addButton
        case "recent":
            if let r = s.recent, !r.isEmpty, !s.hide, show.contains("recent") {
                VStack(spacing: 6) {
                    Text("DERNIÈRES DÉPENSES").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
                    ForEach(Array(r.prefix(4).enumerated()), id: \.offset) { _, x in
                        HStack(spacing: 8) {
                            Text(x.ic).font(.system(size: 15))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(wColor(x.col, .gray).opacity(0.3)))
                            VStack(alignment: .leading, spacing: 0) {
                                Text(x.n).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(x.w).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 2)
                            Text("−" + x.a).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08)))
                    }
                }
                .padding(.top, 6)
            }
        default:
            if k != big, show.contains(k), !s.hide, let v = wValue(k, s) {
                HStack(spacing: 6) {
                    Image(systemName: wIcon(k)).font(.system(size: 12, weight: .semibold)).foregroundStyle(v.color == .primary ? Color.secondary : v.color)
                        .frame(width: 18)
                    Text(v.label).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(v.text).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(v.color).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
            }
        }
    }
}

/// Symbole de chaque ligne.
func wIcon(_ k: String) -> String {
    switch k {
    case "solde": return "banknote"
    case "today": return "sun.max"
    case "perday": return "calendar"
    case "dep": return "cart"
    default: return "circle"
    }
}

/// Libellé, texte et couleur de chaque chiffre que la montre sait afficher.
func wValue(_ k: String, _ s: WSum) -> (label: String, text: String, color: Color)? {
    switch k {
    case "solde":
        return ("Solde", s.solde, s.soldeNeg ? Color.red : Color.primary)
    case "today":
        guard let b = s.liveB else { return nil }
        let left = b - (s.liveS ?? 0)
        if left < 0 { return ("Budget du jour", "dépassé de " + wMoney(-left, s.cur), Color.orange) }
        return ("Reste aujourd’hui", wMoney(left, s.cur), Color.green)
    case "perday":
        guard let pd = s.perDay else { return nil }
        return ("Par jour", pd, Color.primary)
    case "dep":
        return ("Dépensé ce mois", s.dep, Color.primary)
    default:
        return nil
    }
}

// MARK: - Saisie du montant

struct WAmount: View {
    var next: (Double) -> Void
    @State private var txt = ""
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"]

    private var value: Double { Double(txt.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        VStack(spacing: 5) {
            Text(txt.isEmpty ? "0 €" : txt + " €")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(txt.isEmpty ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(wAccent))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: txt)
                .minimumScaleFactor(0.5).lineLimit(1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
                ForEach(keys, id: \.self) { k in
                    Button { tap(k) } label: {
                        Group {
                            if k == "⌫" { Image(systemName: "delete.left").font(.system(size: 15, weight: .semibold)) }
                            else { Text(k).font(.system(size: 19, weight: .semibold, design: .rounded)) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 27)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(k == "⌫" ? 0.08 : 0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { next(value) } label: {
                Text("Suivant").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Capsule().fill(value > 0 ? AnyShapeStyle(wAccent) : AnyShapeStyle(Color.white.opacity(0.12))))
            }
            .buttonStyle(.plain)
            .disabled(value <= 0)
        }
        .navigationTitle("Montant")
    }

    private func tap(_ k: String) {
        WKInterfaceDevice.current().play(.click)
        switch k {
        case "⌫": if !txt.isEmpty { txt.removeLast() }
        case ",": if !txt.contains(",") { txt += txt.isEmpty ? "0," : "," }
        default:
            if let i = txt.firstIndex(of: ","), txt.distance(from: i, to: txt.endIndex) > 2 { return }
            if txt == "0" { txt = k } else if txt.count < 7 { txt += k }
        }
    }
}

// MARK: - Choix de la catégorie

struct WCats: View {
    let amount: Double
    let cats: [WCat]
    let cur: String?
    var pick: (WCat?) -> Void

    var body: some View {
        List {
            Section {
                ForEach(cats) { c in
                    Button { pick(c) } label: {
                        HStack(spacing: 10) {
                            Text(c.ic ?? "•").font(.system(size: 17))
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(wColor(c.col, .gray).opacity(0.35)))
                            Text(c.n).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        }
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(wColor(c.col, .gray).opacity(0.14)))
                }
                Button { pick(nil) } label: {
                    HStack {
                        Text("❓")
                        Text("Je choisirai plus tard").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(wMoney(amount, cur))
    }
}
