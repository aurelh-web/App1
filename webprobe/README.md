# CardProbe Web

Misst dieselbe Frage wie die native App – ob eine Karte bei jedem Tap dieselbe
UID sendet – aber im Browser, ohne Mac, ohne Xcode und ohne Apple-Account.

## Wofür das gut ist

Ob eine Karte ihre UID würfelt, ist eine Eigenschaft **des Chips in der Karte**,
nicht des Lesegeräts. Sendet eine Karte bei jedem Tap eine neue UID, tut sie das
gegenüber jedem Leser – Android wie iPhone. Deshalb beantwortet diese Seite die
Kernfrage genauso gültig wie die native App.

## Voraussetzungen

**Android mit Chrome (ab 89).** Sonst funktioniert es nicht:

| | |
|---|---|
| Android + Chrome | ✅ funktioniert |
| **iPhone, jeder Browser** | ❌ **unmöglich** |
| Desktop | ❌ kein NFC |

Auf dem iPhone unterstützt Safari die Web-NFC-API nicht, und auf iOS läuft jeder
Browser zwangsweise auf WebKit – auch Chrome und Firefox. Aus einer Webseite
heraus gibt es dort keinen NFC-Zugriff. Kein Localhost-Trick ändert das.

## Starten

Web NFC verlangt einen sicheren Kontext, also `https://` oder `localhost`.

```bash
python3 -m http.server 8080
```

Dann am Android-Handy öffnen. Im selben WLAN reicht die IP des Rechners nicht –
das wäre `http://` auf einer fremden Herkunft und damit kein sicherer Kontext.
Zwei Wege, die funktionieren:

- **Port-Weiterleitung über USB** (empfohlen): Handy per Kabel anschließen,
  in Chrome am Desktop `chrome://inspect` öffnen, unter „Port forwarding"
  `8080 → localhost:8080` eintragen. Dann am Handy `http://localhost:8080`
  aufrufen – das gilt als sicherer Kontext.
- **Irgendwo per HTTPS hosten** und die Seite dort aufrufen.

## Was diese Seite liest – und was nicht

Die Web-NFC-API gibt nur die **Seriennummer** des Tags heraus
(`NDEFReadingEvent.serialNumber`), also die UID aus der ISO14443-Antikollision.
Keine Karteninhalte, keine Zahlungsdaten. Die Seriennummer wird zusätzlich lokal
SHA-256-gehasht, bevor sie angezeigt wird; nichts verlässt das Gerät, es gibt
keinen Netzwerkaufruf.

## Grenzen – wichtig

**Zahlkarten liest diese Seite sehr wahrscheinlich nicht.** Web NFC ist auf
NDEF-Tags ausgelegt; EMV-Zahlkarten sind keine. Für die Bankkarte brauchst du am
Ende die native App mit `NFCPaymentTagReaderSession`.

Wofür es dagegen gut funktionieren sollte: die Karten der Priorität 2 –
Firmenausweis, Fitnessstudio, Bibliothek, Kundenkarte. Also genau die, die nach
aktuellem Stand die besseren Chancen auf eine feste UID haben.

Falls eine Karte gar nicht erkannt wird, liegt das an dieser NDEF-Beschränkung
und sagt nichts über ihre UID-Stabilität aus.

## Noch schneller ohne alles

Eine NFC-Reader-App aus dem Play Store (z. B. „NFC Tools") zeigt die UID
ebenfalls an. Karte zehnmal auflegen, schauen ob sich die UID ändert – fertig.
Diese Seite nimmt dir nur das Vergleichen und Zählen ab.
