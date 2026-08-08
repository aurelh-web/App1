# ReelMeter

Konzept + Browser-Prototyp für ein iPhone-Widget (und Android-Pendant), das
anzeigt, wie viele Instagram Reels man geswiped hat und welche Strecke man
dabei gescrollt hat – umgerechnet in Meter/Kilometer, mit ein paar
motivierenden bzw. erschreckenden Vergleichen ("das sind 3× die Höhe des
Eiffelturms").

## Die Grundidee

Jeder Swipe im Reels-Feed bewegt den Bildschirminhalt um ungefähr eine volle
Bildschirmhöhe. Zählt man die Swipes und multipliziert mit der
Bildschirmhöhe des jeweiligen Geräts, bekommt man eine plausible "Strecke",
die man beim Reels-Scrollen zurückgelegt hat – als Home-Screen-Widget
sichtbar, ohne die App extra öffnen zu müssen.

## Wichtige Einschränkung zuerst

**Weder iOS noch Android erlauben einer Drittanbieter-App, Swipes gezielt
innerhalb von Instagram direkt und in Echtzeit mitzulesen.** Das ist kein
Implementierungsdetail, sondern eine bewusste Sandbox-/Privacy-Grenze beider
Betriebssysteme. Es gibt zwei ehrliche Wege, trotzdem an belastbare Zahlen zu
kommen – beide sind in [`native/README.md`](native/README.md) mit
Trade-offs dokumentiert:

- **iOS – Screen-Time-Schätzung** (Standard-Weg, App-Store-fähig): Apples
  `DeviceActivity`/`FamilyControls`-API liefert echte Nutzungszeit in
  Instagram. Reels-Anzahl und Strecke werden daraus hochgerechnet
  (Ø Sekunden pro Reel, Ø Bildschirmhöhe pro Swipe) – eine Schätzung, klar
  als solche gekennzeichnet.
- **iOS – ReplayKit-Bildanalyse** (optionaler "genauer Modus"): Nutzer startet
  bewusst eine Bildschirmaufnahme, on-device wird per Frame-Vergleich jeder
  harte Szenenwechsel als ein Swipe gezählt. Genauer, aber mit sichtbarem
  Aufnahme-Indikator (von Apple erzwungen) und höherem Akkuverbrauch.
- **Android – AccessibilityService** (echte Zählung möglich): Android erlaubt
  mit expliziter Nutzerfreigabe, echte UI-Scroll-Events aus jeder App zu
  lesen, auch aus Instagram. Genauer als die iOS-Schätzung, aber der Google
  Play Store kann die Zweckentfremdung der Bedienungshilfen-API ablehnen –
  realistischer Vertriebsweg ist Sideload statt Play Store.

Ein Jailbreak-Tweak könnte theoretisch unsichtbar und in Echtzeit zählen,
verletzt aber Apples Nutzungsbedingungen und wird hier bewusst nicht verfolgt.

## Was in diesem Repo ist

```
index.html, style.css, app.js   Browser-Prototyp (siehe unten)
native/README.md                Trade-off-Übersicht der nativen Datenpfade
native/ios/*.swift               WidgetKit + Screen-Time + ReplayKit Skizzen
native/android/*.kt              AccessibilityService + Glance-Widget Skizzen
```

## Browser-Prototyp starten

Reines HTML/CSS/JS, kein Build-Schritt nötig:

```bash
python3 -m http.server 8934
```

Dann `http://localhost:8934` im Browser öffnen.

**Was der Prototyp zeigt:** einen Demo-Feed zum Selbst-Durchswipen (Maus/
Trackpad-Scroll oder Touch) links, und rechts eine Live-Vorschau, wie das
echte iOS-Home-Screen-Widget in Klein- und Mittelgröße aussehen würde –
inklusive 7-Tage-Verlauf und Kilometer-Vergleichen. Jeder Swipe im Demo-Feed
zählt sofort im Widget mit. Alle Daten liegen nur lokal im `localStorage`
des Browsers.

**Was der Prototyp *nicht* macht:** Er liest keine echten Instagram-Daten –
das ist technisch auf Handys ohne die in `native/` skizzierte native
Integration nicht möglich (siehe oben). Er dient dazu, UX und
Zähl-/Umrechnungslogik zu demonstrieren und zu testen, bevor man in eine
echte native App investiert.

## Annahmen & Rechenweg

- 1 Swipe = 1 Bildschirmhöhe zurückgelegte Strecke (Reels sind Vollbild,
  jeder Swipe bringt genau ein neues Video ins Bild).
- Bildschirmhöhen sind grobe, geräteabhängige Schätzwerte (siehe
  `DEVICES` in `app.js` bzw. `DeviceScreen` in den Swift-Dateien) – für die
  Screen-Time-Schätzung zusätzlich eine angenommene Ø Reel-Länge von 20
  Sekunden (in einer echten App konfigurierbar).
- Diese Vereinfachungen sind bewusst grob gehalten und sollten in einer
  echten App durch Kalibrierung/Nutzerfeedback verfeinert werden.

## Nächste Schritte für eine echte App

Siehe [`native/README.md`](native/README.md) für die konkrete Xcode-/Android-
Studio-Projektstruktur, benötigte Capabilities und Store-Überlegungen.
