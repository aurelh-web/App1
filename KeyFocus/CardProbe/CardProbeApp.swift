import SwiftUI

/// CardProbe – die Messung, losgelöst von der eigentlichen App.
///
/// Warum es diese zweite App gibt: Um die zentrale Frage zu beantworten
/// ("bleibt der Identifier einer Karte über mehrere Scans gleich?"), braucht es
/// weder Screen Time noch Shields noch Keychain. Jede dieser Abhängigkeiten ist
/// aber eine eigene Fehlerquelle beim Bauen und Signieren – und eine
/// Family-Controls-Capability, die man erst einrichten muss.
///
/// CardProbe braucht nur die NFC-Capability. Weniger Teile, die schiefgehen
/// können, bevor die erste Karte auf dem iPhone liegt.
///
/// Deployment-Target ist iOS 17 statt 26, damit die Messung auf möglichst
/// vielen Geräten läuft. Der Modus "Andere Karte" funktioniert dort
/// vollständig; "Zahlkarte" braucht iOS 26 und EU-Berechtigung und meldet sich
/// andernfalls sauber ab.
@main
struct CardProbeApp: App {
    @State private var nfc = NFCManager()

    var body: some Scene {
        WindowGroup {
            ProbeView()
                .environment(nfc)
        }
    }
}
