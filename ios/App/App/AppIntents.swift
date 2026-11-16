import AppIntents
import Foundation

private func euros(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale(identifier: "fr_FR")
    f.currencyCode = "EUR"
    return f.string(from: NSNumber(value: v)) ?? String(format: "%.2f €", v)
}

/// « Dis Siri, ajoute une dépense dans Clean Budget » — aussi utilisable dans Raccourcis
/// (par exemple l'automatisation « Transaction » d'Apple Pay : montant + nom du commerçant).
@available(iOS 17.0, *)
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter une dépense"
    static var description = IntentDescription("Ajoute une dépense dans Clean Budget, sans ouvrir l'app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Montant", description: "Montant en euros", requestValueDialog: "Quel est le montant ?")
    var amount: Double

    @Parameter(title: "Libellé", description: "Magasin ou description (facultatif)")
    var note: String?

    @Parameter(title: "Catégorie", description: "Nom d'une de tes catégories (facultatif)")
    var category: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Ajouter \(\.$amount) € \(\.$note)") {
            \.$category
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let a = (abs(amount) * 100).rounded() / 100
        var op: [String: Any] = ["t": "e", "a": a, "at": Date().timeIntervalSince1970]
        if let n = note?.trimmingCharacters(in: .whitespaces), !n.isEmpty { op["n"] = n }
        if let c = category?.trimmingCharacters(in: .whitespaces), !c.isEmpty { op["c"] = c }
        CBShared.addPending(op)
        var text = "Dépense de \(euros(a))"
        if let n = op["n"] as? String { text += " (\(n))" }
        text += " ajoutée à Clean Budget."
        return .result(dialog: "\(text)")
    }
}

@available(iOS 17.0, *)
struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter un revenu"
    static var description = IntentDescription("Ajoute un revenu dans Clean Budget, sans ouvrir l'app.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Montant", description: "Montant en euros", requestValueDialog: "Quel est le montant ?")
    var amount: Double

    @Parameter(title: "Libellé", description: "Origine du revenu (facultatif)")
    var note: String?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let a = (abs(amount) * 100).rounded() / 100
        var op: [String: Any] = ["t": "r", "a": a, "at": Date().timeIntervalSince1970]
        if let n = note?.trimmingCharacters(in: .whitespaces), !n.isEmpty { op["n"] = n }
        CBShared.addPending(op)
        return .result(dialog: "\("Revenu de \(euros(a)) ajouté à Clean Budget.")")
    }
}

/// « Dis Siri, mon solde dans Clean Budget »
@available(iOS 17.0, *)
struct BalanceIntent: AppIntent {
    static var title: LocalizedStringResource = "Mon solde"
    static var description = IntentDescription("Te dit ce qu'il te reste à dépenser ce mois-ci.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let s = CBShared.summary() else {
            return .result(dialog: "Ouvre Clean Budget une fois pour que je connaisse ton solde.")
        }
        if s.hide {
            return .result(dialog: "Tes montants sont masqués dans Clean Budget.")
        }
        return .result(dialog: "\("Il te reste \(s.solde). Tu as dépensé \(s.dep) en \(s.month).")")
    }
}

@available(iOS 17.0, *)
struct CleanBudgetShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddExpenseIntent(), phrases: [
            "Ajoute une dépense dans \(.applicationName)",
            "Nouvelle dépense dans \(.applicationName)",
            "Note une dépense dans \(.applicationName)"
        ], shortTitle: "Ajouter une dépense", systemImageName: "minus.circle")
        AppShortcut(intent: AddIncomeIntent(), phrases: [
            "Ajoute un revenu dans \(.applicationName)",
            "Nouveau revenu dans \(.applicationName)"
        ], shortTitle: "Ajouter un revenu", systemImageName: "plus.circle")
        AppShortcut(intent: BalanceIntent(), phrases: [
            "Mon solde dans \(.applicationName)",
            "Combien il me reste dans \(.applicationName)"
        ], shortTitle: "Mon solde", systemImageName: "eurosign.circle")
    }
}
