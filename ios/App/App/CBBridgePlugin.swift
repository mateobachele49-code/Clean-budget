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
        CAPPluginMethod(name: "duoStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "duoRead", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "duoWrite", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "duoInvite", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "duoLeave", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "liveSet", returnType: CAPPluginReturnPromise)
    ]

    private let container = "iCloud.com.mateobachele.cleanbudget"
    private var query: NSMetadataQuery?

    override public func load() {
        // Une dépense notée sur la montre : la page la récupère tout de suite si l'app est ouverte
        NotificationCenter.default.addObserver(forName: CBWatch.pendingNote, object: nil, queue: .main) { [weak self] _ in
            self?.notifyListeners("pending", data: [:])
        }
        duoListen()
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

// MARK: - Budget partagé (Duo) avec CloudKit
//
// Le propriétaire crée une zone « Duo » dans sa base privée iCloud, avec un seul enregistrement « etat »
// (type « Etat », champ « f » = fichier JSON de tout le budget, champ « at » = date).
// Il partage toute la zone : la personne invitée la voit dans sa base partagée.
// Les deux téléphones (et l'iPad du propriétaire) lisent et écrivent ce même enregistrement ;
// la fusion des changements est faite par la page, comme la synchro iCloud Drive.

import CloudKit
import UIKit

final class CBDuo {
    static let shared = CBDuo()
    static let joinedNote = Notification.Name("CBDuoJoined")
    let container = CKContainer(identifier: "iCloud.com.mateobachele.cleanbudget")
    private let ud = UserDefaults.standard
    private var last: CKRecord?

    /// "owner", "member" ou "" (aucun budget partagé).
    var role: String {
        get { ud.string(forKey: "duoRole") ?? "" }
        set { ud.set(newValue, forKey: "duoRole") }
    }
    var zoneID: CKRecordZone.ID? {
        switch role {
        case "owner": return CKRecordZone.ID(zoneName: "Duo", ownerName: CKCurrentUserDefaultName)
        case "member":
            guard let z = ud.string(forKey: "duoZone"), let o = ud.string(forKey: "duoOwner") else { return nil }
            return CKRecordZone.ID(zoneName: z, ownerName: o)
        default: return nil
        }
    }
    var db: CKDatabase { role == "member" ? container.sharedCloudDatabase : container.privateCloudDatabase }
    var recordID: CKRecord.ID? { zoneID.map { CKRecord.ID(recordName: "etat", zoneID: $0) } }

    /// Sur l'iPad du propriétaire : la zone existe déjà dans son iCloud → il est propriétaire.
    func detect() async {
        if !role.isEmpty { return }
        let z = CKRecordZone.ID(zoneName: "Duo", ownerName: CKCurrentUserDefaultName)
        if (try? await container.privateCloudDatabase.recordZone(for: z)) != nil { role = "owner" }
    }

    func read() async throws -> String? {
        guard let id = recordID else { return nil }
        do {
            let r = try await db.record(for: id)
            last = r
            guard let a = r["f"] as? CKAsset, let u = a.fileURL else { return nil }
            return try String(contentsOf: u, encoding: .utf8)
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        } catch let e as CKError where e.code == .zoneNotFound || e.code == .userDeletedZone {
            // Partage arrêté ou zone supprimée
            role = ""
            throw e
        }
    }

    func write(_ text: String) async throws {
        guard let id = recordID else { throw CKError(.zoneNotFound) }
        let r = (last?.recordID == id ? last : nil) ?? CKRecord(recordType: "Etat", recordID: id)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cb-duo-\(UUID().uuidString).json")
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        r["f"] = CKAsset(fileURL: url)
        r["at"] = Date() as NSDate
        let (saved, _) = try await db.modifyRecords(saving: [r], deleting: [], savePolicy: .ifServerRecordUnchanged)
        if case .success(let s)? = saved[id] { last = s } else if case .failure(let e)? = saved[id] {
            if let ck = e as? CKError, ck.code == .serverRecordChanged { last = ck.serverRecord }
            throw e
        }
    }

    /// Crée la zone et l'enregistrement de départ, puis le partage de la zone.
    func create(_ text: String) async throws -> CKShare {
        let z = CKRecordZone(zoneName: "Duo")
        _ = try await container.privateCloudDatabase.modifyRecordZones(saving: [z], deleting: [])
        role = "owner"
        try await write(text)
        if let s = try? await existingShare() { return s }
        let share = CKShare(recordZoneID: z.zoneID)
        share[CKShare.SystemFieldKey.title] = "Clean Budget – budget partagé" as CKRecordValue
        share.publicPermission = .none
        let (saved, _) = try await container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
        if case .success(let s as CKShare)? = saved[share.recordID] { return s }
        return share
    }

    func existingShare() async throws -> CKShare? {
        guard let z = zoneID else { return nil }
        let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: z)
        return try await db.record(for: id) as? CKShare
    }

    func accept(_ meta: CKShare.Metadata) {
        let op = CKAcceptSharesOperation(shareMetadatas: [meta])
        op.perShareResultBlock = { [weak self] m, result in
            guard case .success = result, let self else { return }
            let z = m.share.recordID.zoneID
            self.ud.set(z.zoneName, forKey: "duoZone")
            self.ud.set(z.ownerName, forKey: "duoOwner")
            self.role = "member"
            self.last = nil
            var who = ""
            if let n = m.ownerIdentity.nameComponents { who = PersonNameComponentsFormatter.localizedString(from: n, style: .short) }
            DispatchQueue.main.async { NotificationCenter.default.post(name: CBDuo.joinedNote, object: nil, userInfo: ["owner": who]) }
        }
        container.add(op)
    }

    /// Propriétaire : supprime la zone (le partage s'arrête pour tout le monde).
    /// Invité : quitte le partage.
    func leave() async {
        if role == "owner", let z = zoneID {
            _ = try? await container.privateCloudDatabase.modifyRecordZones(saving: [], deleting: [z])
        } else if role == "member", let s = try? await existingShare() {
            _ = try? await container.sharedCloudDatabase.modifyRecords(saving: [], deleting: [s.recordID])
        }
        role = ""
        last = nil
        ud.removeObject(forKey: "duoZone")
        ud.removeObject(forKey: "duoOwner")
    }
}

extension CBBridgePlugin: UICloudSharingControllerDelegate {
    public func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}
    public func itemTitle(for csc: UICloudSharingController) -> String? { "Clean Budget – budget partagé" }
    public func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        Task { await CBDuo.shared.leave(); self.notifyListeners("duoChanged", data: [:]) }
    }

    func duoListen() {
        NotificationCenter.default.addObserver(forName: CBDuo.joinedNote, object: nil, queue: .main) { [weak self] n in
            self?.notifyListeners("duoJoined", data: ["owner": (n.userInfo?["owner"] as? String) ?? ""])
        }
    }

    private func ckReject(_ call: CAPPluginCall, _ e: Error) {
        if let ck = e as? CKError {
            switch ck.code {
            case .serverRecordChanged: call.reject("conflict"); return
            case .notAuthenticated: call.reject("icloud"); return
            case .networkUnavailable, .networkFailure: call.reject("network"); return
            case .zoneNotFound, .userDeletedZone: call.reject("gone"); return
            default: break
            }
        }
        call.reject(e.localizedDescription)
    }

    @objc func duoStatus(_ call: CAPPluginCall) {
        Task {
            let d = CBDuo.shared
            let st = (try? await d.container.accountStatus()) ?? .couldNotDetermine
            if st == .available { await d.detect() }
            var n = 0
            if !d.role.isEmpty, let s = try? await d.existingShare() { n = s.participants.filter { $0.acceptanceStatus == .accepted }.count }
            call.resolve(["role": d.role, "account": st == .available, "people": n])
        }
    }

    @objc func duoRead(_ call: CAPPluginCall) {
        Task {
            do {
                if let t = try await CBDuo.shared.read() { call.resolve(["data": t]) } else { call.resolve(["none": true]) }
            } catch { self.ckReject(call, error) }
        }
    }

    @objc func duoWrite(_ call: CAPPluginCall) {
        guard let t = call.getString("data") else { call.reject("data manquant"); return }
        Task {
            do { try await CBDuo.shared.write(t); call.resolve() } catch { self.ckReject(call, error) }
        }
    }

    /// Crée le budget partagé si besoin, puis ouvre la fenêtre d'invitation d'Apple (Messages, Mail…).
    @objc func duoInvite(_ call: CAPPluginCall) {
        let text = call.getString("data") ?? ""
        Task {
            do {
                let d = CBDuo.shared
                let share: CKShare
                if d.role == "owner", let s = try await d.existingShare() { share = s } else { share = try await d.create(text) }
                await MainActor.run {
                    let c = UICloudSharingController(share: share, container: d.container)
                    c.delegate = self
                    c.availablePermissions = [.allowReadWrite, .allowPrivate]
                    if let vc = self.bridge?.viewController {
                        c.popoverPresentationController?.sourceView = vc.view
                        c.popoverPresentationController?.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1)
                        vc.present(c, animated: true)
                    }
                    call.resolve(["role": d.role])
                }
            } catch { self.ckReject(call, error) }
        }
    }

    @objc func duoLeave(_ call: CAPPluginCall) {
        Task { await CBDuo.shared.leave(); call.resolve() }
    }
}
