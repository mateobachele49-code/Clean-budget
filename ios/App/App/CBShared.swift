import Foundation

/// Données partagées entre l'app, Siri / Raccourcis et le widget (App Group).
enum CBShared {
    static let group = "group.com.mateobachele.cleanbudget"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    /// Résumé calculé par l'app à chaque enregistrement, affiché par le widget et Siri.
    struct Summary: Codable {
        var solde: String        // « 342,50 € »
        var soldeNeg: Bool
        var dep: String          // dépenses du mois
        var sav: String          // épargne du mois
        var goalPct: Double?     // 0…1, nil si pas d'objectif
        var pet: String          // emoji de la mascotte
        var month: String        // « novembre »
        var hide: Bool           // montants masqués
        var bg1: String          // couleurs de fond (hex)
        var bg2: String
    }

    static let sample = Summary(solde: "342,50 €", soldeNeg: false, dep: "518,20 €", sav: "120,00 €",
                                goalPct: 0.6, pet: "🐷", month: "ce mois-ci", hide: false,
                                bg1: "#dbe9ff", bg2: "#c3d9ff")

    static func summary() -> Summary? {
        guard let d = defaults?.data(forKey: "summary") else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: d)
    }

    /// Opération ajoutée par Siri ou un Raccourci, récupérée par l'app à la prochaine ouverture.
    static func addPending(_ op: [String: Any]) {
        var list = defaults?.array(forKey: "pending") as? [[String: Any]] ?? []
        list.append(op)
        defaults?.set(list, forKey: "pending")
    }
}
