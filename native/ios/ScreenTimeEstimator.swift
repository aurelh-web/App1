// ScreenTimeEstimator.swift
//
// App-Store-konformer Datenpfad (kein Jailbreak, keine privaten APIs).
//
// iOS erlaubt keiner Drittanbieter-App, Touch-/Swipe-Events INNERHALB von Instagram
// zu lesen. Was es erlaubt: über die Family-Controls-/DeviceActivity-APIs die
// tatsächliche Nutzungsdauer einer vom Nutzer ausgewählten App zu erfahren.
// Aus dieser Dauer schätzen wir Reels-Anzahl und Strecke.
//
// Benötigte Capabilities im Xcode-Projekt:
//   - "Family Controls" Entitlement (com.apple.developer.family-controls)
//   - Ein DeviceActivityMonitor-Extension-Target, das täglich/stündlich Events
//     bekommt
//   - Nutzerfreigabe via AuthorizationCenter.shared.requestAuthorization(for: .individual)
//
// Diese Datei ist eine Architektur-Skizze, kein vollständiges, kompilierbares
// Xcode-Target (dafür fehlen u.a. das Extension-Target und Entitlements-Dateien).

import DeviceActivity
import FamilyControls
import Foundation

/// Durchschnittliche Reel-Länge in Sekunden. Instagram selbst nennt hier keine
/// öffentliche Zahl – 20s ist ein in Studien häufig zitierter Richtwert für
/// Short-Form-Video, sollte aber in den App-Einstellungen anpassbar sein.
let averageReelSeconds: Double = 20

/// Physische Bildschirmhöhe in Metern, pro Gerät. Ein Swipe entspricht (ungefähr)
/// einer vollen Bildschirmhöhe, weil Reels als Vollbild-Feed funktionieren.
enum DeviceScreen {
    static func heightMeters(model: String) -> Double {
        switch model {
        case "iPhone SE": return 0.122
        case "iPhone 15", "iPhone 14": return 0.147
        case "iPhone 15 Pro Max", "iPhone 16 Pro Max": return 0.160
        default: return 0.147
        }
    }
}

struct ReelEstimate {
    let reels: Int
    let distanceMeters: Double
}

/// Wandelt eine vom DeviceActivityMonitor gemeldete Nutzungsdauer in eine
/// geschätzte Reels-Anzahl + Strecke um. Wird sowohl in der Haupt-App als auch
/// in der DeviceActivityMonitor-Extension aufgerufen, sobald ein neues
/// Zeitintervall gemeldet wird.
func estimate(secondsInInstagram: Double, deviceModel: String) -> ReelEstimate {
    let reels = Int((secondsInInstagram / averageReelSeconds).rounded())
    let distance = Double(reels) * DeviceScreen.heightMeters(model: deviceModel)
    return ReelEstimate(reels: reels, distanceMeters: distance)
}

/// DeviceActivityMonitor-Extension-Grundgerüst. Läuft in einem eigenen Prozess,
/// den iOS periodisch aufweckt (nicht in Echtzeit – typischerweise mehrmals
/// täglich), NICHT in der Haupt-App.
final class ReelMeterActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        // Optional: Tages-Reset im App Group Storage anstoßen.
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        // Wird z.B. alle 5 Minuten Instagram-Nutzung ausgelöst (Threshold in
        // der DeviceActivitySchedule/Event-Konfiguration definiert).
        // Hier: Sekunden seit letztem Threshold zur bisherigen Summe addieren,
        // estimate(...) aufrufen und das Ergebnis in den App-Group-
        // UserDefaults ablegen, damit Haupt-App & Widget es lesen können.
        SharedStore.appendUsageSeconds(300, forApp: "com.instagram")
    }
}

/// Gemeinsamer Speicher zwischen Haupt-App, DeviceActivity-Extension und
/// WidgetKit-Extension. Alle drei Targets teilen sich eine App-Group-ID.
enum SharedStore {
    static let suiteName = "group.com.example.reelmeter"

    static func appendUsageSeconds(_ seconds: Double, forApp bundleId: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let key = "usageSeconds.\(bundleId).\(todayKey())"
        let current = defaults.double(forKey: key)
        defaults.set(current + seconds, forKey: key)
    }

    private static func todayKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
