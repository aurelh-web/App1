import FamilyControls
import Foundation
import ManagedSettings
import Observation

extension ManagedSettingsStore.Name {
    static let keyFocus = Self("keyFocus")
}

/// Auswahl der zu blockierenden Apps und Anwenden der Shields.
///
/// Die Shields liegen im `ManagedSettingsStore`, also auf Systemebene. Sie
/// überleben deshalb das Beenden von KeyFocus und wirken auch, wenn die App
/// gar nicht läuft – genau das ist für den Test nötig.
@MainActor
@Observable
final class FocusManager {

    enum AuthorizationState: Equatable {
        case unknown
        case notDetermined
        case approved
        case denied(String)
    }

    private(set) var authorization: AuthorizationState = .unknown
    private(set) var isLocked: Bool
    var selection: FamilyActivitySelection {
        didSet { persistSelection() }
    }

    private let store = ManagedSettingsStore(named: .keyFocus)
    private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let selection = "de.keyfocus.selection"
        static let locked = "de.keyfocus.locked"
    }

    init() {
        isLocked = defaults.bool(forKey: DefaultsKey.locked)

        if let data = defaults.data(forKey: DefaultsKey.selection),
           let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = decoded
        } else {
            selection = FamilyActivitySelection()
        }

        // Zustand nach Neustart wiederherstellen: War gesperrt, muss gesperrt
        // bleiben. Die Shields liegen zwar systemseitig, aber neu anzuwenden
        // ist billig und schützt vor einem inkonsistenten Zwischenstand.
        if isLocked {
            applyShields()
        }
    }

    /// Wie viele einzelne Apps und Kategorien ausgewählt sind.
    var selectedCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var hasSelection: Bool { selectedCount > 0 }

    // MARK: - Berechtigung

    func refreshAuthorization() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .notDetermined: authorization = .notDetermined
        case .approved: authorization = .approved
        case .denied: authorization = .denied("Screen-Time-Zugriff wurde abgelehnt.")
        @unknown default: authorization = .unknown
        }
    }

    func requestAuthorization() async {
        do {
            // .individual = das Gerät verwaltet sich selbst (kein Familienmitglied).
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = .approved
        } catch {
            authorization = .denied(
                """
                Screen-Time-Berechtigung nicht erteilt: \(error.localizedDescription)
                Ohne sie kann KeyFocus keine Apps blockieren. \
                Prüfen unter Einstellungen › Bildschirmzeit.
                """
            )
        }
    }

    // MARK: - Sperren / Entsperren

    @discardableResult
    func lock() -> Bool {
        guard hasSelection else { return false }
        applyShields()
        isLocked = true
        defaults.set(true, forKey: DefaultsKey.locked)
        return true
    }

    /// Entfernt die Shields. Wird ausschließlich nach erfolgreicher
    /// Kartenprüfung aufgerufen – es gibt bewusst keinen Software-Ausweg.
    func unlock() {
        store.clearAllSettings()
        isLocked = false
        defaults.set(false, forKey: DefaultsKey.locked)
    }

    private func applyShields() {
        let apps = selection.applicationTokens
        let categories = selection.categoryTokens
        let domains = selection.webDomainTokens

        store.shield.applications = apps.isEmpty ? nil : apps
        // Generischer Typ wird aus dem Property abgeleitet – `.specific(...)`
        // ausgeschrieben als ShieldSettings.ActivityCategoryPolicy<Application>
        // würde die Inferenz unnötig festnageln.
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = domains.isEmpty ? nil : domains
    }

    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: DefaultsKey.selection)

        // Auswahl im gesperrten Zustand geändert: Shields sofort nachziehen,
        // sonst bliebe eine gerade entfernte App weiter gesperrt.
        if isLocked {
            applyShields()
        }
    }
}
