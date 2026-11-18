import AppIntents
import Foundation
import WidgetKit

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

    static var parameterSummary: some ParameterSummary {
        Summary("Enregistrer \(\.$amount) chez \(\.$merchant)") {
            \.$card
            \.$category
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let a = CBApplePay.parse(amount) else {
            return .result(dialog: "Je n’ai pas compris le montant « \(amount) ». Vérifie que Montant vient bien de la Transaction.")
        }
        let shop = (merchant ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if CBApplePay.isDuplicate(a, shop) {
            return .result(dialog: "Ce paiement est déjà enregistré.")
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
            CBShared.save(cur)
            s = cur
            WidgetCenter.shared.reloadAllTimelines()
        }

        let catName = ap?.cats.first(where: { $0.id == catId }).map { "\($0.ic ?? "") \($0.n)".trimmingCharacters(in: .whitespaces) }
        var text = "💳 \(CBShared.money(a, s?.cur))"
        if !shop.isEmpty { text += " chez \(shop)" }
        text += catName.map { " · \($0)" } ?? " · catégorie à vérifier"
        if let s = s, !s.hide, s.soldeRaw != nil { text += "\nIl te reste \(s.solde)." }
        return .result(dialog: "\(text)")
    }
}
