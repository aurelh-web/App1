# KeyFocus – Setup, Grenzen und das eigentliche Experiment

> **Zuerst die wichtigste Zeile:** Dieser Code wurde **nicht kompiliert**. Er
> entstand in einer Linux-Umgebung ohne Xcode und ohne iPhone. Rechne mit
> kleineren Compile-Korrekturen. Alle API-Aussagen unten sind gegen Apples
> aktuelle Dokumentation geprüft, nicht aus dem Gedächtnis geschrieben – aber
> geprüft heißt gelesen, nicht ausgeführt.

---

## 1. Die zwei Befunde, die alles andere bestimmen

### 1.1 `NFCPaymentTagReaderSession` existiert – aber nur iOS 26+ und nur in der EU

Die Klasse ist real (ich hatte sie zunächst für erfunden gehalten und lag
falsch). Apples Dokumentation sagt:

> "The system supports use of NFCPaymentTagReaderSession only within the
> European Union (EU)… People using your app must have an account registered in
> the EU, and their device must be located within the EU. If the device isn't
> currently eligible to use NFCPaymentTagReaderSession, the
> `NFCPaymentTagReaderSession.readingAvailable` property is false."

Konkret:

| | |
|---|---|
| Verfügbar ab | iOS 26.0 / iPadOS 26.0 / Mac Catalyst 26.0 |
| Klasse | `NFCPaymentTagReaderSession : NFCTagReaderSession` |
| Initializer | `init(delegate:queue:)` – **kein** `pollingOption`-Parameter |
| Regional | **Nur EU.** Apple-ID EU-registriert **und** Gerät in der EU |
| Laufzeit-Gate | `NFCPaymentTagReaderSession.readingAvailable` |
| Neuer Fehler | `NFCReaderErrorIneligible` (iOS 26) bei fehlender Berechtigung |

Dass du in Deutschland testest, ist also keine Randnotiz, sondern die
Voraussetzung dafür, dass die App überhaupt etwas tut.

**Das ist auch der Grund, warum eine normale `NFCTagReaderSession` hier nicht
reicht:** Zahlkarten werden von ihr nicht erfasst. Die Payment-Variante ist der
einzige dokumentierte Weg.

### 1.2 Das Produktexperiment steht unter einem schlechten Stern

Deine zentrale Annahme lautet: *derselbe Karten-Identifier bei jedem Scan.*

**Apple garantiert das an keiner Stelle.** `NFCISO7816Tag.identifier` ist die
UID bzw. PUPI aus der ISO14443-Antikollision, und ISO/IEC 14443 erlaubt
ausdrücklich zufällig erzeugte IDs. Bei kontaktlosen Zahlkarten ist genau das
aus Datenschutzgründen üblich – eine feste UID würde bedeuten, dass jedes
Lesegerät der Welt deine Karte wiedererkennt, also auch jeder, der dich verfolgen
will. Die Kartenindustrie hat das bewusst abgestellt.

In der Fachliteratur zu kontaktlosen Zahlungen wird die UID entsprechend als
Nonce behandelt; bei Visa läuft sie unter der Bezeichnung
*L1SessionParameter*. Ein Nonce ist per Definition eine Zahl, die sich **jedes
Mal ändert**.

Das heißt nicht, dass du nicht messen sollst – genau dafür ist das Test Lab da,
und bei girocard oder älteren Karten kann das Ergebnis anders ausfallen. Es
heißt: erwarte ein negatives Ergebnis und plane den Fall mit ein, statt darauf
zu bauen, dass es klappt.

Die App hilft dir dabei doppelt: Sie misst die Stabilität über 10 Scans **und**
markiert sofort, wenn ein Identifier nach einer Zufalls-UID aussieht (4 Byte,
erstes Byte `0x08` oder `0xF8` – nach ISO/IEC 14443-3 die Kennzeichnung für
zufällig erzeugte UIDs). Bei ISO14443-B lässt sich das nicht am Muster ablesen;
dort entscheidet allein die Messreihe.

---

## 2. Bauen und starten

Das Projekt erzeugt **zwei Apps**:

| | CardProbe | KeyFocus |
|---|---|---|
| Zweck | nur die Messung | vollständige App mit Blocking |
| Capabilities | nur NFC | NFC **+ Family Controls** |
| Deployment-Target | iOS 17 | iOS 26 |
| Zahlkarten-Modus | ja (braucht iOS 26 + EU) | ja |
| „Andere Karte" | ja | ja |

**Fang mit CardProbe an.** Um zu erfahren, ob eine Karte als Schlüssel taugt,
braucht es weder Screen Time noch Shields noch Keychain – jede dieser
Abhängigkeiten ist aber eine eigene Fehlerquelle beim Bauen und Signieren.
CardProbe hat nur die NFC-Capability und beantwortet dieselbe Frage.

### Weg A – XcodeGen (empfohlen)

```bash
brew install xcodegen
cd KeyFocus
xcodegen generate
open KeyFocus.xcodeproj
# Scheme "CardProbe" wählen, auf dem iPhone starten
```

### Was du zum Testen brauchst

| | |
|---|---|
| Mac mit Xcode 26 | zwingend |
| Physisches iPhone | NFC gibt es im Simulator nicht |
| Apple Developer Program (~99 €/Jahr) | NFC- und Family-Controls-Capability sind für kostenlose Personal Teams nicht verfügbar |
| iOS 26 + EU-Apple-ID | **nur** für den Zahlkarten-Modus. „Andere Karte" läuft ab iOS 17 |

### Weg B – von Hand in Xcode

1. Xcode → neues Projekt → **App**, Interface **SwiftUI**, Sprache **Swift**.
2. Produktname `KeyFocus`, Deployment Target **iOS 26.0**, Device **iPhone**.
3. Alle `.swift`-Dateien aus `KeyFocus/KeyFocus/` ins Target ziehen.
4. `Info.plist` und `KeyFocus.entitlements` aus diesem Ordner übernehmen bzw.
   die Schlüssel aus ihnen in die von Xcode erzeugten Dateien kopieren.
5. Build Settings: `SWIFT_VERSION = 6.0`, `SWIFT_STRICT_CONCURRENCY = complete`.

### In beiden Fällen

Unter **Signing & Capabilities** ein echtes Development Team wählen. Mit
Team "None" funktionieren weder NFC noch Family Controls.

**Bundle Identifier ändern.** Im Projekt steht `de.example.CardProbe` bzw.
`de.example.KeyFocus`. Diese Kennungen sind global eindeutig und
höchstwahrscheinlich schon vergeben – auf etwas Eigenes umstellen, z.B.
`de.deinname.CardProbe`, sonst scheitert schon die Registrierung der App-ID.

---

## 2b. Wenn der erste Build scheitert

Dieser Code wurde **nie kompiliert** (siehe ganz oben). Die folgenden Fehler
sind die wahrscheinlichsten und meist in einer Minute behoben.

### Beim Bauen

| Fehler | Ursache und Behebung |
|---|---|
| `No such module 'FamilyControls'` | Falsches Scheme. **CardProbe** braucht das nicht – im Scheme-Menü oben umschalten. Tritt es im KeyFocus-Target auf: Capability *Family Controls* fehlt. |
| `Failed to register bundle identifier` | `de.example.…` ist vergeben. Bundle-ID auf etwas Eigenes ändern. |
| `No profiles for '…' were found` / `Signing requires a development team` | Unter *Signing & Capabilities* Team auswählen, *Automatically manage signing* an. |
| `Cannot find 'NFCPaymentTagReaderSession' in scope` | Xcode älter als 26. Die Klasse gibt es erst im iOS-26-SDK. |
| Fehler in `NFCManager.swift` zur Nebenläufigkeit (`Sendable`, `actor-isolated`) | Der wahrscheinlichste Rest-Fehler. Fehlertext hierher schicken – die Datei ist bewusst so gebaut, dass nur Sendable-Werte den Actor wechseln, aber ungetestet. |
| Fehler zu `@Observable` / `@Environment` | Deployment Target zu niedrig oder Scheme-Mix. CardProbe braucht mindestens iOS 17. |

### Beim Starten auf dem iPhone

| Symptom | Ursache und Behebung |
|---|---|
| App startet, aber der NFC-Dialog erscheint nie | `NFCReaderUsageDescription` fehlt in der Info.plist des gebauten Targets. |
| `Missing required entitlement` beim Scannen | Capability *Near Field Communication Tag Reading* im Target nicht aktiviert. Entitlements-Datei allein genügt nicht – Xcode muss die App-ID im Portal entsprechend konfigurieren. |
| „Payment-Session verfügbar: nein" im Debug-Block | Erwartbar außerhalb der EU, ohne EU-Apple-ID oder unter iOS 26. **Kein Fehler.** Auf „Andere Karte" umschalten – dieser Modus ist nicht betroffen. |
| Karte wird gar nicht erkannt | Im Modus „Zahlkarte" werden nur Zahlkarten erfasst, im Modus „Andere Karte" alles außer Zahlkarten. Anderen Modus probieren. Karte an das **obere** Ende der Rückseite halten und ruhig halten. |
| Family Controls: Berechtigung schlägt fehl | Gerät muss mit einer Apple-ID angemeldet sein. Betrifft nur KeyFocus, nicht CardProbe. |

### Build-Log für die Fehlersuche mitschicken

In Xcode den Report Navigator öffnen (⌘9), letzten Build auswählen,
Rechtsklick → *Copy Transcript for All Combined Issues*. Das enthält Datei,
Zeile und den vollständigen Fehlertext.

---

## 3. Erforderliche Xcode-Capabilities

| Capability | Erzeugt | Wofür |
|---|---|---|
| **Near Field Communication Tag Reading** | `com.apple.developer.nfc.readersession.formats` = `["TAG"]` | Jede Core-NFC-Tag-Session |
| **Family Controls** | `com.apple.developer.family-controls` = `true` | App-Auswahl und Shields |

Beide sind in `KeyFocus.entitlements` bereits hinterlegt. In Xcode müssen sie
trotzdem als Capability hinzugefügt werden, damit die App-ID im Developer
Portal passend konfiguriert wird.

Zusätzlich in `Info.plist` (nicht in den Entitlements):

- `NFCReaderUsageDescription` – Pflicht, darf nicht leer sein.
- `com.apple.developer.nfc.readersession.iso7816.select-identifiers` – die
  AID-Liste, mit der die Session selbstständig SELECT ausführt.

---

## 4. Was du bei Apple beantragen bzw. manuell einrichten musst

Ehrlich getrennt nach dem, was ich belegen konnte, und dem, was du prüfen musst.

### Belegt

1. **EU-Berechtigung ist Laufzeitbedingung, kein Formular.** Apple prüft
   Account-Region und Gerätestandort. Ist eins davon nicht EU, ist
   `readingAvailable == false` und du bekommst `NFCReaderErrorIneligible`. Die
   App zeigt das im DEBUG-Block und als Klartextmeldung an.
2. **Family Controls für Entwicklung** funktioniert mit der Capability auf dem
   eigenen Gerät.
3. **Family Controls für TestFlight/App Store** erfordert eine gesonderte
   Freigabe durch Apple (Distribution-Entitlement, Antragsformular). Für einen
   MVP auf dem eigenen Gerät brauchst du das nicht.

### Von dir zu verifizieren (ich konnte es nicht abschließend belegen)

4. **Ob `NFCPaymentTagReaderSession` ein zusätzliches, gesondert zu
   beantragendes Entitlement braucht.** Apples Doku zur Klasse nennt nur die
   zwei oben genannten Schlüssel. Für ältere NFC-Payment-Zugänge galt jedoch
   "nur über besondere Entitlements und Vereinbarungen mit Apple". Ob das für
   diese neue, DMA-getriebene Lese-API weiterhin gilt, geht aus der öffentlichen
   Dokumentation nicht hervor.
   **Test:** App bauen und starten. Zeigt der DEBUG-Block
   `Payment-Session verfügbar: nein`, obwohl du in der EU mit EU-Apple-ID auf
   iOS 26 bist, ist ein Entitlement die wahrscheinlichste Ursache → Apple
   Developer Support kontaktieren.
5. **Ob Apple alle in `Info.plist` gelisteten Zahlungs-AIDs akzeptiert.**
   Historisch hat Apple EMV-Zahlungs-AIDs in `select-identifiers` blockiert.
   Mit der neuen Payment-Session muss sich das geändert haben, sonst wäre sie
   funktionslos – belegen konnte ich es nicht.
   **Test:** Das Test Lab zeigt je Scan den tatsächlich selektierten AID. Bleibt
   der leer, hat kein SELECT stattgefunden.

Die AIDs in `Info.plist` sind öffentlich standardisierte EMV-Kennungen (Visa,
Mastercard, Maestro, V PAY, girocard, Amex, JCB, UnionPay). Ich habe keine
davon erfunden – aber prüfe, ob deine konkreten Karten getroffen werden.

---

## 5. Test mit echter Karte

Vorbedingungen: physisches iPhone, iOS 26+, EU-Apple-ID, Gerät in der EU,
mindestens zwei verschiedene kontaktlose Karten.

**Grunddurchlauf**

1. App installieren, starten.
2. Screen-Time-Berechtigung erteilen (Dialog beim ersten Start).
3. „Apps auswählen" → Instagram markieren → „Fertig".
4. „Karte registrieren" → Karte an das **obere Ende** des iPhones halten,
   bis „Karte registriert ✓" erscheint.
5. „APPS SPERREN".
6. KeyFocus verlassen, Instagram öffnen → muss geshieldet sein.
7. Zurück zu KeyFocus → „MIT KARTE ENTSPERREN".
8. **Zuerst die falsche Karte** auflegen → „Falsche Karte", Instagram bleibt
   gesperrt.
9. Registrierte Karte auflegen → „Entsperrt ✓", Instagram sofort wieder nutzbar.
10. App komplett beenden und neu starten → Registrierung muss erhalten sein.

**Das eigentliche Experiment**

11. „Test Lab" (oben rechts, nur im entsperrten Zustand erreichbar).
12. Karten-Label auf „Karte A" setzen.
13. „Stabilitätstest starten" → dieselbe Karte 10× nacheinander auflegen.
14. Ergebnis ablesen: `IDENTIFIER STABIL 10 / 10` oder
    `IDENTIFIER INSTABIL 3 / 10`.
15. Label auf „Karte B" ändern, zweite Karte mehrfach scannen. Unter „JE KARTE"
    muss stehen: je Karte 1 verschiedener Identifier, und beide Karten dürfen
    sich keinen teilen.

Ergebnis notieren – **das ist das Resultat, um das es hier eigentlich geht.**

**Falls die Bankkarte durchfällt**, im Test Lab auf „Andere Karte" umschalten
und die übrigen NFC-Karten aus dem Portemonnaie durchmessen (Firmenausweis,
Fitnessstudio, Bibliothek, Kundenkarte). Diese Session unterliegt weder der
EU-Beschränkung noch iOS 26, und solche Karten haben meist eine feste UID.
Der Scan-Verlauf zeigt je Eintrag den Tag-Typ, damit sich einordnen lässt,
womit man es zu tun hat.

---

## 6. Was einer App-Store-App im Weg steht

1. **EU-Beschränkung.** Außerhalb der EU tut die App nichts. Kein weltweites
   Produkt, sondern bestenfalls ein EU-Produkt.
2. **iOS 26+.** Schneidet jedes ältere Gerät ab.
3. **Family-Controls-Distribution-Entitlement.** Gesonderte Apple-Freigabe für
   TestFlight und App Store nötig.
4. **Möglicher Payment-Entitlement-Prozess.** Siehe Punkt 4 oben – ungeklärt.
5. **Review-Risiko beim Zweck.** Die App nutzt eine Zahlungs-API für etwas, das
   keine Zahlung ist. Auch wenn technisch keine Zahlungsdaten anfallen: das ist
   ein Zweck, für den die API nicht gedacht ist, und ein plausibler
   Ablehnungsgrund.
6. **Fachlicher Blocker.** Wenn sich die Identifier als instabil erweisen, ist
   das Produkt nicht "verbesserungsbedürftig", sondern in dieser Form nicht
   baubar. Siehe unten.
7. **Verlorene Karte = ausgesperrt.** Es gibt bewusst keinen Software-Ausweg.
   Für ein echtes Produkt bräuchte es einen Wiederherstellungsweg – der genau
   die Hemmschwelle aufweicht, um die es geht. Echter Zielkonflikt, kein Detail.

---

## 7. Kann eine normale Bankkarte als dauerhafter Schlüssel dienen?

**Nach Apples API-Garantien: nein – Apple sagt dazu schlicht nichts zu.**

`NFCISO7816Tag.identifier` ist dokumentiert als der Identifier des erkannten
Tags. Nirgends in der Core-NFC-Dokumentation steht zu, dass dieser Wert für
dieselbe physische Karte über mehrere Scans hinweg konstant bleibt. Es gibt
keine Stabilitätsgarantie, auf die man ein Produkt gründen könnte. Wer es
trotzdem tut, baut auf ein Implementierungsdetail der jeweiligen Karte – nicht
auf eine Zusage der Plattform.

**Nach der Funktionsweise kontaktloser Zahlkarten: sehr wahrscheinlich nein.**

ISO/IEC 14443 erlaubt zufällige UIDs ausdrücklich, und die Kartenindustrie nutzt
das als Standard-Datenschutzmaßnahme gegen Tracking. Bei Visa wird die UID als
Session-Parameter geführt, also als Wert, der sich je Tap ändert. Eine feste,
weltweit auslesbare Kartenkennung wäre ein Tracking-Vektor – ihre Abschaffung
war Absicht, kein Versäumnis.

**Was nur empirisch zu klären ist:**

Nicht jede Karte verhält sich gleich. Ältere Karten, manche girocard-Umsetzungen
und Nicht-EMV-Karten können statische UIDs haben. Und ob eine bestimmte Karte
würfelt, steht auf keinem Datenblatt. Deshalb existiert das Test Lab, und
deshalb ist es der wichtigste Teil dieses MVP: Es beantwortet in fünf Minuten,
was keine Dokumentation beantworten kann.

**Erwartete Ergebnisse und was sie bedeuten:**

| Ergebnis | Bedeutung |
|---|---|
| `10 / 10` bei allen Testkarten | Annahme hält für diese Karten. Trotzdem keine Garantie für andere Karten oder künftige Neuausgaben – kein Produktversprechen darauf bauen. |
| `10 / 10` bei einer, instabil bei anderen | Kartenabhängig. Als Produkt nur mit Kompatibilitätsprüfung bei der Registrierung denkbar ("diese Karte eignet sich nicht"). |
| überwiegend instabil | Die Produktidee funktioniert mit Bankkarten nicht. |

**Wenn das Ergebnis negativ ausfällt**, ist die Idee nicht tot – nur der
Träger. Der Rest der App (Screen-Time-Shields, Besitzfaktor zum Entsperren)
bleibt unverändert gültig.

Und der Ausweg muss kein Sticker sein: In fast jedem Portemonnaie liegen
bereits andere NFC-Karten – Firmenausweis, Fitnessstudio, Bibliothek,
Kundenkarte, Hotelkarte. Das sind meist MIFARE-Karten, und die haben in aller
Regel eine **feste UID**, weil ihr ganzer Zweck das Wiedererkennen ist. Genau
umgekehrt zur Zahlkarte, die Wiedererkennung bewusst verhindert.

Deshalb kann die App beides. Über den Umschalter **Zahlkarte / Andere Karte**
(im Setup und im Test Lab):

| | Zahlkarte | Andere Karte |
|---|---|---|
| Session | `NFCPaymentTagReaderSession` | `NFCTagReaderSession` |
| Erfasst | nur Zahlkarten | MIFARE, ISO15693, FeliCa, sonstige ISO7816 |
| iOS 26+ nötig | ja | nein |
| EU-Beschränkung | ja | **nein** |
| UID meist stabil | eher nicht | in der Regel ja |

Der bei der Registrierung gewählte Modus wird gespeichert und beim Entsperren
automatisch wiederverwendet – eine Zahlkarte wird von der generischen Session
nicht erkannt und umgekehrt.

Praktisch heißt das: **erst die Bankkarte messen.** Fällt sie durch, im Test
Lab auf „Andere Karte" umschalten und durchprobieren, was ohnehin im
Portemonnaie liegt. Der Charme, nichts Zusätzliches mitschleppen zu müssen,
bleibt so erhalten – nur eben mit einer anderen Karte aus demselben
Portemonnaie.

---

## 8. Datenschutz – was die App tut und was nicht

Gespeichert wird ausschließlich:

```
SHA256(NFCISO7816Tag.identifier)  →  Keychain, gerätegebunden, kein iCloud-Sync
```

Nicht gelesen, nicht gespeichert, nicht angezeigt, nicht übertragen: PAN,
Ablaufdatum, Karteninhaber, CVV, Transaktionsdaten, sowie der rohe Identifier.

Konstruktiv abgesichert, nicht nur zugesagt: `NFCManager` ruft **niemals**
`session.connect(to:)` auf und sendet **kein einziges APDU-Kommando**. Es findet
also gar keine Kommunikation mit der Karte statt, in der Zahlungsdaten anfallen
könnten – gelesen wird nur, was beim Erkennen ohnehin bereitliegt
(`identifier`, `initialSelectedAID`).

Kein Backend, kein Login, keine Analytics, keine Netzwerkschicht. Die App
enthält keinen einzigen Netzwerkaufruf.
