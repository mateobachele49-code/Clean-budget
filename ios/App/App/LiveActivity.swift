import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Activité en direct « budget du jour » : écran verrouillé et Dynamic Island.
/// Compilé dans l'app ET dans l'extension des widgets.
@available(iOS 16.1, *)
struct CBLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var left: String      // ce qu'il reste à dépenser aujourd'hui
        var day: String       // budget du jour
        var spent: String     // dépensé aujourd'hui
        var solde: String     // ce qu'il reste sur la période
        var pct: Double       // part du budget du jour déjà dépensée (0…1)
        var over: Bool        // budget du jour dépassé
        var hide: Bool        // montants masqués
    }

    var pet: String
}

#endif
