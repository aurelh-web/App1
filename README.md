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
innerhalb von Instagram direkt und in Echtzeit mitzulesen.** Der Touchscreen
registriert den Swipe zwar, aber das Betriebssystem stellt das Event
ausschließlich der App im Vordergrund zu – eine App im Hintergrund sieht davon
nichts. Das ist keine fehlende Berechtigung, sondern eine bewusste
Sandbox-Grenze: sonst könnte jede App jede andere als Keylogger für
Wischgesten und Passworteingaben mitlesen.

Es gibt aber mehrere ehrliche Umwege, die etwas *anderes* messen und daraus die
Reels-Anzahl hochrechnen – alle mit Trade-offs in
[`native/README.md`](native/README.md) dokumentiert:

- **iOS – Netzwerk-Traffic + Screen Time** (empfohlener Standard,
  App-Store-fähig): Jedes Reel muss als Video vom Instagram-CDN geladen
  werden. Über Apples `NetworkExtension` läuft ein rein lokales VPN – kein
  Traffic verlässt das Gerät –, das diese Ladevorgänge zählt (dieselbe API,
  die App-Store-Werbeblocker nutzen). Weil Instagram Videos *vorlädt*, wird
  das Ergebnis mit Screen Time verrechnet: Screen Time sagt, *wann* Instagram
  wirklich aktiv war, der Traffic sagt, *wie viele* Reels in diesem Fenster
  liefen. Sichtbar ist nur das dezente VPN-Symbol in der Statusleiste.
- **iOS – Screen-Time-Schätzung allein** (sparsamster Weg): Apples
  `DeviceActivity`/`FamilyControls`-API liefert die Nutzungszeit in
  Instagram, daraus wird über die Ø Reel-Länge hochgerechnet. Grob, aber
  praktisch aufwandslos.
- **iOS – ReplayKit-Bildanalyse** (optionaler "Genau-Modus"): Nutzer startet
  bewusst eine Bildschirmaufnahme, on-device wird per Frame-Vergleich jeder
  harte Szenenwechsel als ein Swipe gezählt. Am genauesten, aber mit
  sichtbarem Aufnahme-Indikator (von Apple erzwungen) und höherem
  Akkuverbrauch.
- **Android – AccessibilityService** (echte Zählung möglich): Android erlaubt
  mit expliziter Nutzerfreigabe, echte UI-Scroll-Events aus jeder App zu
  lesen, auch aus Instagram. Genauer als jede iOS-Variante, aber der Google
  Play Store kann die Zweckentfremdung der Bedienungshilfen-API ablehnen –
  realistischer Vertriebsweg ist Sideload statt Play Store.

Ein Jailbreak-Tweak könnte theoretisch unsichtbar und in Echtzeit zählen,
verletzt aber Apples Nutzungsbedingungen und wird hier bewusst nicht verfolgt.

## Was in diesem Repo ist

```
index.html, style.css, app.js   Browser-Prototyp (siehe unten)
native/README.md                Trade-off-Übersicht der nativen Datenpfade
native/ios/*.swift              WidgetKit + Netzwerk-Traffic + Screen-Time
                                + ReplayKit Skizzen
native/android/*.kt             AccessibilityService + Glance-Widget Skizzen
tools/calibrate.py              Eicht die Heuristik gegen echte Messungen
tools/README.md                 Messvorgehen und Eingabeformat
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
- Für den Netzwerk-Pfad kommt ein Kalibrierwert dazu: wie viele
  Video-Segment-Bursts im Schnitt auf ein Reel entfallen
  (`TrafficHeuristics.burstsPerReel`). Der muss gegen echte Messungen
  geeicht werden – Reels manuell zählen und mit den Tunnel-Zahlen abgleichen.
- Diese Vereinfachungen sind bewusst grob gehalten und sollten in einer
  echten App durch Kalibrierung/Nutzerfeedback verfeinert werden.

## Kalibrierung

Die Schätzwerte oben sind geraten, solange sie nicht gegen echte Messungen
geeicht wurden. Dafür liegt in [`tools/`](tools/) ein Auswertungsskript bereit.
Ohne iPhone ausprobieren:

```bash
python3 tools/make_sample_data.py > tools/sample-measurements.json
python3 tools/calibrate.py tools/sample-measurements.json
```

Das rechnet auf synthetischen Daten mit bekannter Wahrheit und zeigt, wie der
Report aussieht. Für die echte Eichung: Reels beim Schauen von Hand mitzählen,
Tunnel-Log dazulegen, Skript laufen lassen – es gibt den fertigen Swift-Block
zum Einfügen aus. Details in [`tools/README.md`](tools/README.md).

## Nächste Schritte für eine echte App

Siehe [`native/README.md`](native/README.md) für die konkrete Xcode-/Android-
Studio-Projektstruktur, benötigte Capabilities und Store-Überlegungen.
