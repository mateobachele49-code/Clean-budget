import SwiftUI
import WatchConnectivity
import WatchKit

// MARK: - Données reçues de l'iPhone (le même résumé que les widgets, seulement les champs utiles ici)

struct WCat: Codable, Hashable, Identifiable {
    var id: String
    var n: String
    var ic: String?
}

struct WRecent: Codable, Hashable {
    var n: String
    var c: String
    var ic: String
    var a: String
    var w: String
}

struct WAP: Codable { var cats: [WCat] }

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

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 8) {
                    if let s = store.s {
                        Text(s.pet).font(.system(size: 30))
                        // Le solde en grand, comme dans l'app
                        Text("Solde").font(.footnote).foregroundStyle(.secondary)
                        Text(s.hide ? "•••" : s.solde)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(s.soldeNeg && !s.hide ? Color.red : Color.primary)
                            .contentTransition(.numericText())
                            .minimumScaleFactor(0.5).lineLimit(1)
                        if let b = s.liveB, !s.hide {
                            let left = b - (s.liveS ?? 0)
                            HStack {
                                Text(left < 0 ? "Budget du jour" : "Reste aujourd’hui").foregroundStyle(.secondary)
                                Spacer()
                                Text(left < 0 ? "dépassé de " + wMoney(-left, s.cur) : wMoney(left, s.cur))
                                    .bold().foregroundStyle(left < 0 ? Color.orange : Color.green)
                                    .lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .font(.footnote)
                        }
                        if let pd = s.perDay, !s.hide {
                            HStack {
                                Text("Par jour").foregroundStyle(.secondary)
                                Spacer()
                                Text(pd).bold()
                            }
                            .font(.footnote)
                        }
                    } else {
                        Text("🐷").font(.system(size: 40))
                        Text("Ouvre Clean Budget sur ton iPhone pour afficher tes chiffres.")
                            .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }

                    NavigationLink(value: WRoute.amount) {
                        Label("Dépense", systemImage: "plus.circle.fill").font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .padding(.top, 4)

                    if let d = done {
                        Text(d).font(.footnote).foregroundStyle(.green).multilineTextAlignment(.center)
                    }

                    if let r = store.s?.recent, !r.isEmpty, !(store.s?.hide ?? false) {
                        Text("Dernières dépenses").font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                        ForEach(Array(r.prefix(4).enumerated()), id: \.offset) { _, x in
                            HStack(spacing: 6) {
                                Text(x.ic)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(x.n).font(.footnote).lineLimit(1)
                                    Text(x.w).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 2)
                                Text("−" + x.a).font(.footnote.bold()).lineLimit(1).minimumScaleFactor(0.7)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Clean Budget")
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
}

// MARK: - Saisie du montant

struct WAmount: View {
    var next: (Double) -> Void
    @State private var txt = ""
    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "⌫"]

    private var value: Double { Double(txt.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        VStack(spacing: 4) {
            Text(txt.isEmpty ? "0 €" : txt + " €")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5).lineLimit(1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(keys, id: \.self) { k in
                    Button { tap(k) } label: {
                        Text(k).font(.system(size: 18, weight: .semibold, design: .rounded)).frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.14)))
                }
            }
            Button("Suivant") { next(value) }
                .buttonStyle(.borderedProminent).tint(.orange)
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
            Section(wMoney(amount, cur)) {
                ForEach(cats) { c in
                    Button { pick(c) } label: {
                        HStack {
                            Text(c.ic ?? "•")
                            Text(c.n).lineLimit(1)
                        }
                    }
                }
                Button { pick(nil) } label: {
                    HStack {
                        Text("❓")
                        Text("Je choisirai plus tard").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Catégorie")
    }
}
