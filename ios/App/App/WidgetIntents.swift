import AppIntents
import WidgetKit
import Foundation

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

// MARK: - Catégories et comptes de l'app, proposés dans Raccourcis, par Siri et dans « Modifier le widget »

@available(iOS 17.0, *)
struct CBCategory: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Catégorie"
    static var defaultQuery = CBCategoryQuery()

    var id: String
    var name: String
    var icon: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(icon) \(name)")
    }

    static func all() -> [CBCategory] {
        (CBShared.summary()?.ap?.cats ?? []).map { CBCategory(id: $0.id, name: $0.n, icon: $0.ic ?? "") }
    }
}

@available(iOS 17.0, *)
struct CBCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CBCategory] {
        CBCategory.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CBCategory] {
        CBCategory.all()
    }
}

@available(iOS 17.0, *)
struct CBAccount: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Compte"
    static var defaultQuery = CBAccountQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static func all() -> [CBAccount] {
        (CBShared.summary()?.accts ?? []).map { CBAccount(id: $0.id, name: $0.n) }
    }
}

@available(iOS 17.0, *)
struct CBAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [CBAccount] {
        CBAccount.all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [CBAccount] {
        CBAccount.all()
    }
}

// MARK: - Réglages des widgets (appui long › Modifier le widget)

@available(iOS 17.0, *)
struct CBCategoryWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Catégorie suivie"
    static var description = IntentDescription("Choisis la catégorie affichée par le widget.")

    @Parameter(title: "Catégorie")
    var category: CBCategory?

    init() {}
}

@available(iOS 17.0, *)
struct CBAccountWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Compte affiché"
    static var description = IntentDescription("Choisis le compte affiché par le widget.")

    @Parameter(title: "Compte")
    var account: CBAccount?

    @Parameter(title: "Montrer l’objectif d’épargne", default: true)
    var showGoal: Bool

    init() {}
}
