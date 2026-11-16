import AppIntents
import Foundation

/// Bouton du widget « Saisie rapide » avec un montant fixe : ajoute la dépense sans ouvrir l'app.
/// Compilé dans l'app ET dans l'extension des widgets.
@available(iOS 17.0, *)
struct QuickAddIntent: AppIntent {
    static var title: LocalizedStringResource = "Saisie rapide"
    static var description = IntentDescription("Ajoute la dépense d'un bouton du widget Saisie rapide.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Bouton")
    var index: Int

    init() {}

    init(index: Int) {
        self.index = index
    }

    func perform() async throws -> some IntentResult {
        guard let s = CBShared.summary(), let q = s.quick, index >= 0, index < q.count,
              let a = q[index].a, a > 0 else {
            return .result()
        }
        let now = Date().timeIntervalSince1970
        CBShared.addPending(["t": "e", "a": a, "cid": q[index].c, "at": now])
        CBShared.defaults?.set(["i": index, "at": now], forKey: "quickDone")
        return .result()
    }
}

/// Ouvre l'app directement sur l'ajout d'une dépense (bouton du Centre de contrôle).
@available(iOS 17.0, *)
struct OpenAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Ouvrir l'ajout d'une dépense"
    static var description = IntentDescription("Ouvre Clean Budget sur la fiche d'ajout d'une dépense.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        CBShared.defaults?.set(true, forKey: "openAdd")
        return .result()
    }
}
