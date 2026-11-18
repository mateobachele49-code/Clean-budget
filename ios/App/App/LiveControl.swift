import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Démarrage et mises à jour de l'activité en direct (app seulement).
@available(iOS 16.2, *)
enum CBLive {
    static func state(from s: CBShared.Summary, extraSpent: Double = 0) -> CBLiveAttributes.ContentState? {
        guard let b = s.liveB, let sp0 = s.liveS else { return nil }
        let sp = sp0 + extraSpent
        let left = b - sp
        return CBLiveAttributes.ContentState(
            left: CBShared.money(max(left, 0), s.cur).replacingOccurrences(of: ",00", with: ""),
            day: CBShared.money(b, s.cur).replacingOccurrences(of: ",00", with: ""),
            spent: CBShared.money(sp, s.cur).replacingOccurrences(of: ",00", with: ""),
            solde: s.solde,
            pct: b > 0 ? min(sp / b, 1) : (sp > 0 ? 1 : 0),
            over: left < 0,
            hide: s.hide)
    }

    static func endOfDay() -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date().addingTimeInterval(86400)
    }

    /// Démarre, met à jour ou arrête l'activité.
    static func apply(on: Bool, summary: CBShared.Summary?) async {
        let running = Activity<CBLiveAttributes>.activities
        guard on, let s = summary, let st = state(from: s) else {
            for a in running { await a.end(nil, dismissalPolicy: .immediate) }
            return
        }
        let content = ActivityContent(state: st, staleDate: endOfDay())
        if let a = running.first {
            await a.update(content)
            for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: CBLiveAttributes(pet: s.pet), content: content, pushType: nil)
        }
    }

    /// Après un paiement Apple Pay, sans ouvrir l'app.
    static func addSpent(_ amount: Double) async {
        guard let a = Activity<CBLiveAttributes>.activities.first, let s = CBShared.summary(),
              let st = state(from: s) else { return }
        await a.update(ActivityContent(state: st, staleDate: endOfDay()))
        _ = amount
    }
}
#endif
