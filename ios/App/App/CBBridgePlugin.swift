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
        CAPPluginMethod(name: "icloudSync", returnType: CAPPluginReturnPromise)
    ]

    private let container = "iCloud.com.mateobachele.cleanbudget"

    @objc func setWidgetData(_ call: CAPPluginCall) {
        guard let json = call.getString("json"), let data = json.data(using: .utf8) else {
            call.reject("json manquant")
            return
        }
        CBShared.defaults?.set(data, forKey: "summary")
        WidgetCenter.shared.reloadAllTimelines()
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
}
