# Native Architektur – ReelMeter

Diese Dateien sind **Architektur-Skizzen**, keine vollständigen, kompilierbaren
Xcode-/Gradle-Projekte (dafür fehlen u.a. `.xcodeproj`/`build.gradle`,
Entitlements, Extension-Targets, Icons – das braucht Xcode bzw. Android Studio
und eine echte Developer-Account-Einrichtung, die sich nicht sinnvoll von Hand
in einem Git-Repo nachbauen lässt).

## Warum es nicht "einfach" geht

Weder iOS noch Android erlauben einer Drittanbieter-App, Touch- oder
Swipe-Events **innerhalb** einer anderen App wie Instagram direkt zu lesen.
Es gibt kein öffentliches API "gib mir Instagrams Swipes". Für ein Konzept,
das *ehrlich* ist statt nur Marketing-Versprechen zu machen, muss man also
sagen, was technisch tatsächlich geht – und was nicht.

## iOS: zwei Pfade, unterschiedlich genau

| | Screen-Time-Schätzung | ReplayKit-Bildanalyse |
|---|---|---|
| Datei | `ios/ScreenTimeEstimator.swift` | `ios/ReplayKitSwipeDetector.swift` |
| Genauigkeit | Geschätzt (Zeit ÷ Ø Reel-Länge) | Echte Swipe-Zählung |
| App-Store-fähig | Ja | Ja, aber ungewöhnlich für diesen Zweck |
| Nutzeraufwand | Einmalige Freigabe (Family Controls) | Aufnahme **pro Sitzung** manuell starten |
| Sichtbarkeit für Nutzer | Unsichtbar im Hintergrund | Roter Aufnahme-Indikator, von iOS erzwungen |
| Akku/Performance | Gering | Spürbar (Bildverarbeitung live) |
| Jailbreak nötig? | Nein | Nein |

Empfehlung: **Screen-Time-Schätzung als Standard**, ReplayKit optional als
"Genauer Modus" für Nutzer, die es aktiv anschalten wollen. Ein
Jailbreak-Tweak (SpringBoard-Hook o.ä.) könnte theoretisch echte,
unsichtbare Live-Zählung liefern, ist aber nicht App-Store-fähig, verletzt
Apples Nutzungsbedingungen und wird hier bewusst nicht skizziert.

## Android: ein Pfad, aber mit Store-Risiko

`android/ReelAccessibilityService.kt` nutzt Androids `AccessibilityService`-API,
die – mit expliziter Nutzerfreigabe unter Einstellungen → Bedienungshilfen –
echte `AccessibilityEvent`s aus jeder App liefert, auch aus Instagram. Damit
lassen sich reale Scroll-/Swipe-Events zählen, nicht nur Zeit.

**Trade-off:** Google Play Store Policy erlaubt die Bedienungshilfen-API nur
für echte Barrierefreiheits-Zwecke. Eine zweckfremde Nutzung fürs
Reels-Tracking kann bei der Review auffallen und zur Ablehnung führen.
Realistische Vertriebswege: Sideload (APK direkt verteilen), F-Droid, oder
offen als Experimental-/Open-Source-Tool – nicht der reguläre Play-Store-Weg.

## Datenfluss (beide Plattformen)

```
[Instagram-Nutzung]
      │
      ▼
[Datenquelle: Screen Time / ReplayKit / AccessibilityService]
      │  (läuft in Extension/Service, NICHT in Haupt-App)
      ▼
[Gemeinsamer Speicher: App Group UserDefaults (iOS) / SharedPreferences (Android)]
      │
      ▼
[Home-Screen-Widget: liest nur den gemeinsamen Speicher, kein eigener Instagram-Zugriff]
```

Die Haupt-App (nicht in dieser Skizze enthalten) wäre dafür da, Einstellungen
zu verwalten (Gerät, Ø Reel-Länge, gewählter Genauigkeits-Modus) und die
Freigaben (Family Controls / Bedienungshilfen / Broadcast-Aufnahme)
anzustoßen.

## Nächste Schritte für eine echte App

1. Xcode-Projekt mit App-Target + WidgetKit-Extension-Target + (optional)
   DeviceActivityMonitor-Extension-Target anlegen, App-Group-Capability auf
   allen Targets aktivieren.
2. Family-Controls-Entitlement beim Apple Developer Program beantragen
   (muss von Apple freigeschaltet werden, kein automatischer Prozess).
3. Android Studio-Projekt mit Glance-Widget-Modul + Accessibility-Service
   anlegen, Entscheidung Play Store vs. Sideload treffen.
4. Ø-Reel-Länge und Bildschirmhöhen-Tabelle mit echten Messwerten validieren
   statt der hier verwendeten Schätzwerte.
