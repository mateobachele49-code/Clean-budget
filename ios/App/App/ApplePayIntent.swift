import AppIntents
import Foundation
import WidgetKit
import UserNotifications

// MARK: - Rangement automatique d'un paiement

enum CBApplePay {
    /// Montant lu dans n'importe quel format : « 12,50 € », « €12.50 », « 1 234,56 », « -8.90 »…
    static func parse(_ text: String) -> Double? {
        var t = text.filter { "0123456789,.".contains($0) }
        guard !t.isEmpty else { return nil }
        if let c = t.lastIndex(of: ","), let d = t.lastIndex(of: ".") {
            // les deux séparateurs : le dernier est celui des centimes
            if c > d { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { t = t.replacingOccurrences(of: ",", with: "") }
        } else if t.contains(",") {
            let parts = t.split(separator: ",")
            t = (parts.count == 2 && parts[1].count <= 2) ? t.replacingOccurrences(of: ",", with: ".") : t.replacingOccurrences(of: ",", with: "")
        } else if t.filter({ $0 == "." }).count > 1 {
            t = t.replacingOccurrences(of: ".", with: "")
        }
        guard let v = Double(t), v > 0 else { return nil }
        return (v * 100).rounded() / 100
    }

    /// Catégorie probable d'un commerçant : ce que tu as déjà choisi pour lui, tes règles, puis des mots-clés.
    static func guess(_ merchant: String, _ ap: CBShared.AP?) -> String? {
        let k = CBShared.key(merchant)
        guard k.count >= 2 else { return nil }
        if let learned = CBShared.defaults?.dictionary(forKey: "apLearn") as? [String: String], let c = learned[k],
           ap?.cats.contains(where: { $0.id == c }) ?? false {
            return c
        }
        for pair in ap?.kw ?? [] where pair.count == 2 {
            guard let re = try? NSRegularExpression(pattern: pair[0], options: [.caseInsensitive]) else { continue }
            if re.firstMatch(in: k, range: NSRange(k.startIndex..., in: k)) != nil { return pair[1] }
        }
        return nil
    }

    /// Notification de l'app (remplace la bulle de Raccourcis, peu lisible).
    static func notify(title: String, subtitle: String, body: String, id: String, loud: Bool = false) async {
        let c = UNMutableNotificationContent()
        c.title = title
        if !subtitle.isEmpty { c.subtitle = subtitle }
        c.body = body
        c.threadIdentifier = "cb-applepay"
        if loud { c.sound = .default }
        if #available(iOS 15.0, *) { c.interruptionLevel = .active; c.relevanceScore = loud ? 1 : 0.5 }
        let req = UNNotificationRequest(identifier: "\(id)-\(Int(Date().timeIntervalSince1970 * 1000))", content: c, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }

    static func learn(_ merchant: String, _ cat: String) {
        let k = CBShared.key(merchant)
        guard k.count >= 2 else { return }
        var d = CBShared.defaults?.dictionary(forKey: "apLearn") as? [String: String] ?? [:]
        d[k] = cat
        if d.count > 400 { d.removeValue(forKey: d.keys.first!) }
        CBShared.defaults?.set(d, forKey: "apLearn")
    }

    /// Évite d'ajouter deux fois le même paiement si l'automatisation se déclenche en double.
    static func isDuplicate(_ amount: Double, _ merchant: String) -> Bool {
        let now = Date().timeIntervalSince1970
        let sig = "\(amount)|\(CBShared.key(merchant))"
        let d = CBShared.defaults
        if let last = d?.dictionary(forKey: "apLast"), last["s"] as? String == sig,
           let at = last["at"] as? Double, now - at < 90 {
            return true
        }
        d?.set(["s": sig, "at": now], forKey: "apLast")
        return false
    }
}

// MARK: - Action « Enregistrer un paiement Apple Pay »

@available(iOS 17.0, *)
struct ApplePayIntent: AppIntent {
    static var title: LocalizedStringResource = "Enregistrer une transaction"
    static var description = IntentDescription("À mettre dans l’automatisation « Transaction » de Raccourcis : ajoute chaque paiement sans contact (téléphone ou montre) dans Clean Budget, rangé dans la bonne catégorie.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Montant", description: "Le Montant de la transaction")
    var amount: String

    @Parameter(title: "Commerçant", description: "Le Commerçant de la transaction")
    var merchant: String?

    @Parameter(title: "Carte", description: "La Carte de la transaction (pour choisir le compte)")
    var card: String?

    @Parameter(title: "Catégorie", description: "Laisse vide pour que Clean Budget la trouve tout seul")
    var category: CBCategory?

    @Parameter(title: "Commentaire", description: "Un petit mot ajouté à la dépense (facultatif)")
    var comment: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Enregistrer \(\.$amount) chez \(\.$merchant)") {
            \.$card
            \.$category
            \.$comment
        }
    }

    func perform() async throws -> some IntentResult {
        guard let a = CBApplePay.parse(amount) else {
            await CBApplePay.notify(title: "Montant non reconnu", subtitle: "« \(amount) »", body: "Vérifie dans Raccourcis que Montant vient bien de la Transaction.", id: "cb-ap-err")
            return .result()
        }
        let shop = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if CBApplePay.isDuplicate(a, shop) {
            return .result()
        }
        var s = CBShared.summary()
        let ap = s?.ap
        let ask = ap?.ask ?? 1

        // 1. catégorie choisie dans le raccourci, 2. devinée, 3. demandée si besoin
        var catId = category?.id
        let guessed = catId == nil ? CBApplePay.guess(shop, ap) : nil
        if catId == nil, ask == 2 || (ask == 1 && guessed == nil), !(ap?.cats.isEmpty ?? true) {
            let question = shop.isEmpty ? "Dans quelle catégorie ranger \(CBShared.money(a, s?.cur)) ?"
                                        : "Dans quelle catégorie ranger \(shop) ?"
            let prompt = IntentDialog(stringLiteral: question)
            if let picked = try? await $category.requestValue(prompt) {
                catId = picked.id
                if !shop.isEmpty { CBApplePay.learn(shop, picked.id) }
            }
        }
        if catId == nil { catId = guessed }

        var op: [String: Any] = ["t": "e", "a": a, "at": Date().timeIntervalSince1970, "src": "ap"]
        if !shop.isEmpty { op["n"] = shop }
        if let c = comment?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty { op["cm"] = c }
        if let c = catId { op["cid"] = c }
        if let c = card?.trimmingCharacters(in: .whitespaces), !c.isEmpty { op["card"] = c }
        CBShared.addPending(op)

        // Widgets à jour tout de suite, sans attendre l'ouverture de l'app
        if var cur = s, let raw = cur.soldeRaw {
            let nv = raw - a
            cur.soldeRaw = nv
            cur.solde = CBShared.money(nv, cur.cur)
            cur.soldeNeg = nv < 0
            if let d = cur.depRaw {
                cur.depRaw = d + a
                cur.dep = CBShared.money(d + a, cur.cur)
            }
            if let ls = cur.liveS { cur.liveS = ls + a }
            CBShared.save(cur)
            s = cur
            WidgetCenter.shared.reloadAllTimelines()
        }

        // Alerte de plafond : la catégorie vient de passer le seuil (80 % par défaut) ou son plafond
        var alert: String? = nil
        var limLine: String? = nil
        if var cur = s, let id = catId, var all = cur.catsAll, let i = all.firstIndex(where: { $0.id == id }) {
            let before = all[i].vr ?? 0
            let after = before + a
            all[i].vr = after
            if let lim = all[i].lr, lim > 0 {
                let w = cur.warn ?? 0.8
                all[i].pct = min(after / lim, 1.5)
                all[i].v = CBShared.money(after, cur.cur)
                limLine = after > lim ? "Plafond dépassé de \(CBShared.money(after - lim, cur.cur))" : "\(Int((after / lim * 100).rounded())) % du plafond · reste \(CBShared.money(lim - after, cur.cur))"
                let name = "\(all[i].ic ?? "") \(all[i].n)".trimmingCharacters(in: .whitespaces)
                if before <= lim && after > lim {
                    alert = "🚨 \(name) : plafond dépassé (\(CBShared.money(after, cur.cur)) sur \(CBShared.money(lim, cur.cur)))"
                } else if before / lim < w && after / lim >= w && after <= lim {
                    alert = "⚠️ \(name) : \(Int((after / lim * 100).rounded())) % du plafond (\(CBShared.money(after, cur.cur)) sur \(CBShared.money(lim, cur.cur)))"
                }
            }
            cur.catsAll = all
            CBShared.save(cur)
            s = cur
            WidgetCenter.shared.reloadAllTimelines()
        }
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) { await CBLive.addSpent(a) }
        #endif
        // Une seule notification, claire : montant et commerçant, catégorie, puis ce qu'il reste
        let cat = ap?.cats.first(where: { $0.id == catId })
        let hide = s?.hide ?? false
        if hide {
            await CBApplePay.notify(title: "Dépense enregistrée", subtitle: cat.map { "\($0.ic ?? "") \($0.n)".trimmingCharacters(in: .whitespaces) } ?? "", body: "Montants masqués", id: "cb-ap")
        } else {
            let title = shop.isEmpty ? "−\(CBShared.money(a, s?.cur))" : "−\(CBShared.money(a, s?.cur)) · \(shop)"
            let sub = cat.map { "\($0.ic ?? "") \($0.n)".trimmingCharacters(in: .whitespaces) } ?? "❓ Catégorie à vérifier dans l’app"
            var lines: [String] = []
            if let m = alert { lines.append(m) } else if let l = limLine { lines.append(l) }
            if let s = s, s.soldeRaw != nil { lines.append("Il te reste \(s.solde)") }
            await CBApplePay.notify(title: title, subtitle: sub, body: lines.joined(separator: "\n"), id: "cb-ap", loud: alert != nil)
        }
        return .result()
    }
}
