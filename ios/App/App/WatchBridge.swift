import Foundation
import WatchConnectivity
import WidgetKit

/// Lien avec l'app Apple Watch : envoie le résumé à la montre, reçoit les dépenses notées au poignet.
final class CBWatch: NSObject, WCSessionDelegate {
    static let shared = CBWatch()
    static let pendingNote = Notification.Name("cbWatchPending")

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Le résumé des widgets, tel quel : la montre n'en lit que quelques champs.
    func push(_ data: Data) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled, data.count < 60_000 else { return }
        try? s.updateApplicationContext(["s": data, "t": Date().timeIntervalSince1970])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let d = CBShared.defaults?.data(forKey: "summary") { push(d) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }

    /// La montre demande les chiffres à jour : on renvoie le résumé enregistré.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["get"] != nil {
            if let d = CBShared.defaults?.data(forKey: "summary"), d.count < 60_000 { replyHandler(["s": d]) } else { replyHandler([:]) }
            return
        }
        handle(message)
        replyHandler([:])
    }

    private func handle(_ m: [String: Any]) {
        guard let op = m["op"] as? [String: Any], let a = op["a"] as? Double, a > 0 else { return }
        CBShared.addPending(op)
        // Widgets et montre à jour sans attendre l'ouverture de l'app
        if var cur = CBShared.summary(), let raw = cur.soldeRaw {
            cur.soldeRaw = raw - a
            cur.solde = CBShared.money(raw - a, cur.cur)
            cur.soldeNeg = raw - a < 0
            if let d = cur.depRaw {
                cur.depRaw = d + a
                cur.dep = CBShared.money(d + a, cur.cur)
            }
            if let ls = cur.liveS { cur.liveS = ls + a }
            CBShared.save(cur)
            WidgetCenter.shared.reloadAllTimelines()
            if let d = CBShared.defaults?.data(forKey: "summary") { push(d) }
        }
        DispatchQueue.main.async { NotificationCenter.default.post(name: CBWatch.pendingNote, object: nil) }
    }
}
