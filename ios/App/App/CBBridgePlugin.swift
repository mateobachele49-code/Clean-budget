import Foundation
import Capacitor
import WidgetKit

/// Pont entre la page de l'app et les fonctions de l'iPhone propres à Clean Budget :
/// widget, opérations venues de Siri / Raccourcis, copie des sauvegardes sur iCloud Drive.
@objc(CBBridgePlugin)
public class CBBridgePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CBBridgePlugin"
    public let jsName = "CBBridge"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "setWidgetData", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setWidgetImage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "takePending", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "icloudStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "icloudSync", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "syncRead", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "syncWrite", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "syncWatch", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "liveSet", returnType: CAPPluginReturnPromise)
    ]

    private let container = "iCloud.com.mateobachele.cleanbudget"
    private var query: NSMetadataQuery?

    override public func load() {
        // Une dépense notée sur la montre : la page la récupère tout de suite si l'app est ouverte
        NotificationCenter.default.addObserver(forName: CBWatch.pendingNote, object: nil, queue: .main) { [weak self] _ in
            self?.notifyListeners("pending", data: [:])
        }
    }

    @objc func setWidgetData(_ call: CAPPluginCall) {
        guard let json = call.getString("json"), let data = json.data(using: .utf8) else {
            call.reject("json manquant")
            return
        }
        CBShared.defaults?.set(data, forKey: "summary")
        WidgetCenter.shared.reloadAllTimelines()
        CBWatch.shared.push(data)
        call.resolve()
    }

    /// Image de la mascotte (PNG en base64) pour les widgets : « pet-day.png » ou « pet-night.png ».
    @objc func setWidgetImage(_ call: CAPPluginCall) {
        guard let name = call.getString("name"), ["pet-day.png", "pet-night.png"].contains(name),
              let b64 = call.getString("b64"), let data = Data(base64Encoded: b64),
              let url = CBShared.fileURL(name) else {
            call.reject("image invalide")
            return
        }
        do {
            try data.write(to: url, options: .atomic)
            call.resolve()
        } catch {
            call.reject(error.localizedDescription)
        }
    }

    @objc func takePending(_ call: CAPPluginCall) {
        let d = CBShared.defaults
        let list = d?.array(forKey: "pending") as? [[String: Any]] ?? []
        let openAdd = d?.bool(forKey: "openAdd") ?? false
        d?.removeObject(forKey: "pending")
        d?.removeObject(forKey: "openAdd")
        call.resolve(["ops": list, "openAdd": openAdd])
    }

    private func icloudDocs() -> URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: container) else { return nil }
        return base.appendingPathComponent("Documents", isDirectory: true)
    }

    @objc func icloudStatus(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .utility).async {
            let ok = FileManager.default.ubiquityIdentityToken != nil && self.icloudDocs() != nil
            call.resolve(["available": ok])
        }
    }

    /// Écrit la sauvegarde du jour dans iCloud Drive › Clean Budget et supprime celles qui ne sont plus gardées.
    @objc func icloudSync(_ call: CAPPluginCall) {
        guard let name = call.getString("name"), let text = call.getString("data"),
              !name.contains("/"), name.hasPrefix("clean-budget-") else {
            call.reject("arguments invalides")
            return
        }
        let keep = Set((call.getArray("keep") as? [String]) ?? [])
        DispatchQueue.global(qos: .utility).async {
            guard let dir = self.icloudDocs() else {
                call.reject("iCloud indisponible")
                return
            }
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
                if !keep.isEmpty {
                    let files = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
                    for f in files where f.hasPrefix("clean-budget-") && f.hasSuffix(".json") && !keep.contains(f) && f != name {
                        try? fm.removeItem(at: dir.appendingPathComponent(f))
                    }
                }
                call.resolve()
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    // MARK: - Synchro iPhone ⇄ iPad

    /// Fichier de synchro : à la racine du conteneur iCloud (hors du dossier Documents),
    /// donc invisible dans l'app Fichiers. Une seule copie de l'état, partagée par tes appareils.
    private func syncURL() -> URL? {
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: container) else { return nil }
        return base.appendingPathComponent("Sync", isDirectory: true).appendingPathComponent("etat.json")
    }

    /// Lit l'état partagé. { none: true } s'il n'existe pas encore, { pending: true } s'il est en cours de téléchargement.
    @objc func syncRead(_ call: CAPPluginCall) {
        DispatchQueue.global(qos: .utility).async {
            guard let url = self.syncURL() else { call.reject("iCloud indisponible"); return }
            let fm = FileManager.default
            try? fm.startDownloadingUbiquitousItem(at: url)
            let rv = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
            if !fm.fileExists(atPath: url.path) {
                // Pas encore là en local : soit il n'existe pas, soit iCloud le télécharge
                if rv?.isUbiquitousItem == true { call.resolve(["pending": true]) } else { call.resolve(["none": true]) }
                return
            }
            if let st = rv?.ubiquitousItemDownloadingStatus, st != .current {
                call.resolve(["pending": true])
                return
            }
            var text: String?
            var err: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &err) { u in
                text = try? String(contentsOf: u, encoding: .utf8)
            }
            if let t = text { call.resolve(["data": t]) } else { call.reject(err?.localizedDescription ?? "lecture impossible") }
        }
    }

    @objc func syncWrite(_ call: CAPPluginCall) {
        guard let text = call.getString("data") else { call.reject("data manquant"); return }
        DispatchQueue.global(qos: .utility).async {
            guard let url = self.syncURL() else { call.reject("iCloud indisponible"); return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var ok = false
            var err: NSError?
            NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &err) { u in
                ok = (try? text.write(to: u, atomically: true, encoding: .utf8)) != nil
            }
            if ok { call.resolve() } else { call.reject(err?.localizedDescription ?? "écriture impossible") }
        }
    }

    /// Surveille le fichier : quand l'autre appareil l'a modifié, la page reçoit « icloudChanged ».
    @objc func syncWatch(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if self.query == nil {
                let q = NSMetadataQuery()
                q.searchScopes = [NSMetadataQueryUbiquitousDataScope]
                q.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, "etat.json")
                let nc = NotificationCenter.default
                for n in [Notification.Name.NSMetadataQueryDidUpdate, .NSMetadataQueryDidFinishGathering] {
                    nc.addObserver(forName: n, object: q, queue: .main) { [weak self] _ in
                        self?.notifyListeners("icloudChanged", data: [:])
                    }
                }
                q.start()
                self.query = q
            }
            call.resolve()
        }
    }

    /// Activité en direct : on = la démarrer ou la mettre à jour avec le résumé enregistré, sinon l'arrêter.
    @objc func liveSet(_ call: CAPPluginCall) {
        let on = call.getBool("on") ?? false
        #if canImport(ActivityKit)
        if #available(iOS 16.2, *) {
            Task {
                await CBLive.apply(on: on, summary: CBShared.summary())
                call.resolve(["ok": true])
            }
            return
        }
        #endif
        call.resolve(["ok": false])
    }
}
