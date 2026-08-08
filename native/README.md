# Native Architektur – ReelMeter

Diese Dateien sind **Architektur-Skizzen**, keine vollständigen, kompilierbaren
Xcode-/Gradle-Projekte (dafür fehlen u.a. `.xcodeproj`/`build.gradle`,
Entitlements, Extension-Targets, Icons – das braucht Xcode bzw. Android Studio
und eine echte Developer-Account-Einrichtung, die sich nicht sinnvoll von Hand
in einem Git-Repo nachbauen lässt).

## Warum es nicht "einfach" geht

Der Touchscreen registriert zwar jeden Swipe – aber das Betriebssystem stellt
das Touch-Event **ausschließlich der App im Vordergrund** zu (iOS: IOKit/HID →
Mach-Port, Android: `InputReader`/`InputDispatcher` → Binder). Eine
Drittanbieter-App im Hintergrund bekommt diesen Kanal nie zu sehen. Das ist
keine fehlende Berechtigung, die man freischalten könnte, sondern eine
bewusste Sandbox-Grenze – sonst könnte jede App jede andere als Keylogger für
Wischgesten, PINs und Passworteingaben mitlesen.

Es gibt daher keinen direkten Weg, Swipes *in* Instagram zu zählen. Alle
realistischen Datenpfade messen etwas **anderes** und rechnen daraus die
Reels-Anzahl hoch.

## iOS: drei Datenpfade

| | **Netzwerk-Traffic** ⭐ | Screen-Time-Schätzung | ReplayKit-Bildanalyse |
|---|---|---|---|
| Datei | `ios/NetworkTrafficEstimator.swift` | `ios/ScreenTimeEstimator.swift` | `ios/ReplayKitSwipeDetector.swift` |
| Misst | Video-Ladevorgänge vom CDN | Nutzungsdauer in Instagram | Szenenwechsel im Bild |
| Genauigkeit | Mittel–hoch (pro geladenem Reel) | Grob (Zeit ÷ Ø Reel-Länge) | Hoch (echte Swipe-Erkennung) |
| Sichtbar für Nutzer | Dezentes VPN-Symbol in der Statusleiste | Nichts | Roter Aufnahme-Balken (von iOS erzwungen) |
| Läuft passiv im Hintergrund | Ja | Ja | **Nein** – muss pro Sitzung manuell gestartet werden |
| Akku/CPU | Mittel (Paketverarbeitung) | Sehr gering | Hoch (Live-Bildverarbeitung) |
| App-Store-fähig | Ja | Ja | Ja, aber für diesen Zweck ungewöhnlich |
| Jailbreak nötig | Nein | Nein | Nein |

**Empfehlung: Netzwerk-Traffic als Standard, kombiniert mit Screen Time.**
Die beiden ergänzen sich, statt zu konkurrieren – siehe nächster Abschnitt.
ReplayKit bleibt optionaler "Genau-Modus" für Nutzer, die den Aufnahme-Balken
in Kauf nehmen.

### Warum die Kombination aus beiden

Der Netzwerk-Pfad allein hat ein Kernproblem: **Instagram lädt Reels im Voraus
(Prefetch)** – typischerweise mehrere Videos auf Vorrat, auch solche, die man
nie zu Gesicht bekommt, teils sogar im Hintergrund. "Geladen" ist also nicht
gleich "angeschaut", und die reine Netzwerk-Zählung überschätzt systematisch.

Screen Time weiß umgekehrt nicht, *was* passiert ist – aber sehr genau, *wann*
Instagram tatsächlich im Vordergrund war.

Zusammengesetzt:

- **Screen Time liefert das Zeitfenster** ("zwischen 21:04 und 21:37 war
  Instagram aktiv")
- **Netzwerk-Traffic liefert die Menge** ("in diesem Fenster wurden 94
  Video-Segment-Bursts geladen")
- Bursts außerhalb aktiver Nutzungsfenster werden verworfen → der
  Hintergrund-Prefetch fällt heraus

Das ist in `CombinedEstimator.estimateReels(...)` in
`ios/NetworkTrafficEstimator.swift` skizziert.

### Ehrliche Grenzen des Netzwerk-Pfads

- **Es bleibt eine Schätzung.** Wir lesen keine dokumentierte API aus, sondern
  beobachtete Muster. `burstsPerReel` ist ein Kalibrierwert, kein Naturgesetz.
- **Der Traffic ist verschlüsselt** (TLS/QUIC). Sichtbar sind nur Metadaten:
  Ziel-IP, Zeitpunkt, Paketgröße – kein Videoinhalt. Das ist für den
  Datenschutz gut und für die Genauigkeit die Einschränkung.
- **Instagram-Updates können die Heuristik brechen.** Ändert sich das
  CDN-Verhalten oder die Segmentierung, muss nachkalibriert werden.
- **Nur ein VPN-Profil kann gleichzeitig aktiv sein.** Wer einen
  Firmen-VPN oder einen VPN-basierten Werbeblocker nutzt, kann ReelMeter
  nicht parallel laufen lassen. Das ist ein harter Nutzungskonflikt, keine
  Kleinigkeit.
- **DNS über HTTPS/TLS (DoH/DoT) umgeht die Hostnamen-Auflösung** im Tunnel.
  Dann greift das IP→Domain-Mapping nicht mehr zuverlässig; Fallback wären
  bekannte CDN-IP-Bereiche.
- **Der Tunnel übernimmt Verantwortung für den gesamten Netzwerkverkehr.**
  Ein `NEPacketTunnelProvider` ist kein passiver Mithörer: sobald er die
  Default-Route hat, braucht er einen funktionierenden Userspace-TCP/IP-Stack
  (lwIP, tun2socks o.ä.), sonst hat das Gerät kein Internet mehr. Das ist der
  aufwendigste Teil der gesamten Umsetzung – deutlich mehr Arbeit als die
  Zähl-Logik.

### Warum nicht die naheliegenderen NetworkExtension-APIs

`NEFilterDataProvider` (Content Filter) und `NEDNSProxyProvider` wären
technisch eleganter, erfordern auf iOS aber ein per MDM **supervidiertes**
Gerät. Für eine normale Endnutzer-App scheiden sie aus. Bleibt der
Packet-Tunnel über ein Personal-VPN-Profil, das der Nutzer selbst bestätigt –
derselbe Weg, den App-Store-Werbeblocker wie AdGuard oder Lockdown Privacy
gehen.

## Android: einfacher, aber mit Store-Risiko

`android/ReelAccessibilityService.kt` nutzt Androids `AccessibilityService`-API,
die – mit expliziter Nutzerfreigabe unter Einstellungen → Bedienungshilfen –
echte `AccessibilityEvent`s aus jeder App liefert, auch aus Instagram. Damit
lassen sich reale Scroll-/Swipe-Events zählen, nicht nur schätzen. Der
Netzwerk-Umweg ist auf Android deshalb gar nicht nötig (möglich wäre er über
`VpnService`, mit denselben Nachteilen wie oben).

**Trade-off:** Die Google-Play-Policy erlaubt die Bedienungshilfen-API nur für
echte Barrierefreiheits-Zwecke. Eine zweckfremde Nutzung fürs Reels-Tracking
kann bei der Review auffallen und zur Ablehnung führen. Realistische
Vertriebswege: Sideload (APK direkt verteilen), F-Droid, oder offen als
Experimental-/Open-Source-Tool – nicht der reguläre Play-Store-Weg.

## Datenfluss

```
[Instagram-Nutzung]
      │
      ├─────────────────────────┬──────────────────────────┐
      ▼                         ▼                          ▼
[Screen Time /           [Packet Tunnel            [AccessibilityService]
 DeviceActivity]          (Netzwerk-Bursts)]          (Android, echte Events)
   "WANN aktiv?"            "WIE VIELE?"
      │                         │                          │
      └────────► [CombinedEstimator] ◄────────┘            │
                          │                                │
                          ▼                                ▼
   [Gemeinsamer Speicher: App Group UserDefaults (iOS) / SharedPreferences (Android)]
                          │
                          ▼
   [Home-Screen-Widget: liest nur den gemeinsamen Speicher,
    kein eigener Instagram-Zugriff]
```

Die Haupt-App (nicht in dieser Skizze enthalten) verwaltet Einstellungen
(Gerät, Ø Reel-Länge, Kalibrierwerte, gewählter Datenpfad) und stößt die
Freigaben an (Family Controls / VPN-Profil / Bedienungshilfen).

## Nächste Schritte für eine echte App

1. Xcode-Projekt mit App-Target + WidgetKit-Extension + Network-Extension-Target
   + DeviceActivityMonitor-Extension anlegen, App-Group-Capability auf allen
   Targets aktivieren.
2. Entitlements beantragen/aktivieren: Family Controls und Network Extensions
   (Packet Tunnel Provider) müssen im Apple Developer Portal freigeschaltet
   sein – teils mit Antrag bei Apple, kein rein automatischer Prozess.
3. Den Userspace-TCP/IP-Stack für den Tunnel evaluieren (lwIP / tun2socks) –
   das ist der kritische Aufwandstreiber, hier zuerst einen Spike bauen.
4. `burstsPerReel`, `minBurstBytes` und `burstIdleGap` gegen echte Messungen
   kalibrieren: Reels manuell zählen, mit den Tunnel-Zahlen abgleichen.
5. Android-Projekt mit Glance-Widget + Accessibility-Service anlegen,
   Entscheidung Play Store vs. Sideload treffen.
