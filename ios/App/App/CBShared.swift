import Foundation

/// Données partagées entre l'app, Siri / Raccourcis et les widgets (App Group).
enum CBShared {
    static let group = "group.com.mateobachele.cleanbudget"
    static var defaults: UserDefaults? { UserDefaults(suiteName: group) }

    struct Cat: Codable, Hashable {
        var n: String            // nom
        var ic: String?          // emoji
        var v: String            // dépensé ce mois
        var l: String?           // plafond (vide si aucun)
        var pct: Double?         // dépensé / plafond (peut dépasser 1)
        var col: String          // couleur (hex)
    }

    struct Bill: Codable, Hashable {
        var n: String            // « Loyer »
        var a: String            // « 650,00 € »
        var w: String            // « Demain », « le 3 déc »
    }

    struct Quick: Codable, Hashable {
        var n: String            // nom de la catégorie
        var c: String            // identifiant de la catégorie
        var a: Double?           // montant fixe (nil = demander)
        var al: String           // montant affiché
        var ic: String           // symbole SF
        var col: String          // couleur (hex)
    }

    struct APCat: Codable, Hashable {
        var id: String
        var n: String
        var ic: String?
    }

    /// Ce qu'il faut pour ranger un paiement Apple Pay sans ouvrir l'app.
    struct AP: Codable {
        var cats: [APCat]
        var kw: [[String]]       // [expression régulière, identifiant de catégorie], dans l'ordre de priorité
        var ask: Int?            // 0 : jamais demander, 1 : si inconnue, 2 : toujours
        var other: String?       // catégorie « Autre »
    }

    /// Résumé calculé par l'app à chaque enregistrement, affiché par les widgets et Siri.
    /// Les champs ajoutés après la première version sont optionnels : un ancien résumé reste lisible.
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
        var goalLabel: String?
        var perDay: String?      // reste par jour
        var perNote: String?
        var budgetPct: Double?   // dépenses / revenus du mois
        var cats: [Cat]?
        var watch: Cat?
        var curve: [Double]?     // solde jour par jour
        var curveDays: Int?
        var week: [Double]?      // 7 valeurs 0…1, lundi → dimanche
        var weekToday: Int?
        var weekTotal: String?
        var cal: [Int]?          // niveau 0…4 par jour, -1 = à venir
        var calFirst: Int?       // décalage du 1er (0 = lundi)
        var calToday: Int?
        var calMonth: String?
        var upcoming: [Bill]?
        var quick: [Quick]?
        var soldeRaw: Double?
        var depRaw: Double?
        var cur: String?
        var ap: AP?
    }

    static let sample = Summary(
        solde: "342,50 €", soldeNeg: false, dep: "518,20 €", sav: "120,00 €",
        goalPct: 0.6, pet: "🐷", month: "novembre", hide: false, bg1: "#dbe9ff", bg2: "#c3d9ff",
        goalLabel: "120 € sur 200 €", perDay: "24,00 €", perNote: "jusqu’à la fin du mois", budgetPct: 0.62,
        cats: [Cat(n: "Courses", ic: "🛒", v: "212 €", l: "250 €", pct: 0.85, col: "#ef4444"),
               Cat(n: "Restaurants", ic: "🍽️", v: "86 €", l: "120 €", pct: 0.72, col: "#f59e0b"),
               Cat(n: "Transport", ic: "🚗", v: "64 €", l: "150 €", pct: 0.43, col: "#06b6d4"),
               Cat(n: "Loisirs", ic: "🎮", v: "40 €", l: nil, pct: nil, col: "#8b5cf6")],
        watch: Cat(n: "Courses", ic: "🛒", v: "212 €", l: "250 €", pct: 0.85, col: "#ef4444"),
        curve: [900, 860, 820, 1500, 1420, 1380, 1300, 1240, 1180, 1100, 1020, 960, 900, 860], curveDays: 30,
        week: [0.4, 0.7, 0.2, 1, 0.5, 0, 0], weekToday: 4, weekTotal: "86,40 €",
        cal: [0, 1, 2, 0, 3, 1, 0, 2, 4, 1, 0, 2, 1, 3, 2, 0, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1],
        calFirst: 6, calToday: 16, calMonth: "novembre",
        upcoming: [Bill(n: "Netflix", a: "13,49 €", w: "Demain"), Bill(n: "Loyer", a: "650,00 €", w: "le 1 déc")],
        quick: [Quick(n: "Courses", c: "", a: nil, al: "montant ?", ic: "cart.fill", col: "#ef4444"),
                Quick(n: "Café", c: "", a: 2.5, al: "2,50 €", ic: "cup.and.saucer.fill", col: "#a16207"),
                Quick(n: "Essence", c: "", a: nil, al: "montant ?", ic: "fuelpump.fill", col: "#06b6d4"),
                Quick(n: "Resto", c: "", a: nil, al: "montant ?", ic: "fork.knife", col: "#f59e0b")])

    static func save(_ s: Summary) {
        if let d = try? JSONEncoder().encode(s) { defaults?.set(d, forKey: "summary") }
    }

    static func money(_ v: Double, _ cur: String?) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "fr_FR")
        f.currencyCode = cur ?? "EUR"
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f €", v)
    }

    /// Texte simplifié pour comparer des noms de commerçants : minuscules, sans accents.
    static func key(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func summary() -> Summary? {
        guard let d = defaults?.data(forKey: "summary") else { return nil }
        return try? JSONDecoder().decode(Summary.self, from: d)
    }

    /// Opération ajoutée par Siri, un Raccourci ou un widget, récupérée par l'app à la prochaine ouverture.
    static func addPending(_ op: [String: Any]) {
        var list = defaults?.array(forKey: "pending") as? [[String: Any]] ?? []
        list.append(op)
        defaults?.set(list, forKey: "pending")
    }

    /// Dossier partagé où l'app dépose les images de la mascotte.
    static func fileURL(_ name: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent(name)
    }
}
