# Zeitbudget

Web-Prototyp für die Idee: Statt Apps wie Instagram, TikTok oder YouTube einfach
unbegrenzt zu nutzen, bekommt jede App ein tägliches Frei-Zeitkontingent. Ist es
aufgebraucht, kann man weitermachen – aber nur, indem man einen Betrag "spendet"
(simulierte Kartenzahlung), statt einfach zu bezahlen. Die Hemmschwelle der Zahlung
wirkt so als bewusste Bremse, und das Geld geht gedanklich an eine gute Sache statt
an den Anbieter der Ablenkungs-App.

## Starten

Reines HTML/CSS/JS, kein Build-Schritt nötig:

```bash
python3 -m http.server 8934
```

Dann `http://localhost:8934` im Browser öffnen. Alle Daten (Apps, Nutzung, Spenden)
werden nur lokal im `localStorage` des Browsers gespeichert.

## Funktionsumfang (Prototyp)

- Apps mit täglichem Frei-Minutenkontingent und Preis pro Extra-Minute anlegen/bearbeiten
- Sitzung starten: Timer zählt das Kontingent für die gewählte App live herunter
- Ist das Kontingent aufgebraucht, öffnet sich der Kauf-Dialog mit Minutenpaketen
- Die "Kartenzahlung" ist rein simuliert (keine echte Zahlungsabwicklung, kein
  Payment-Provider) – der Betrag wird nur lokal als Spendensumme verbucht
- Statistik: Gesamtspende, heutige Nutzung, Kaufverlauf
- Spendenorganisation und Tageskontingente sind in den Einstellungen frei konfigurierbar

## Einschränkungen

Dies ist ein **Browser-Prototyp**, kein echtes App-Blocking-Tool. Er kann nicht
messen oder verhindern, wie lange jemand tatsächlich Instagram auf dem Handy nutzt –
das würde native Integration erfordern:

- **iOS:** Screen Time / Family Controls API (Swift, Apple Developer Programm)
- **Android:** `UsageStatsManager` bzw. Accessibility Service

Für echte Zahlungen (statt der simulierten Kartenzahlung hier) wäre zusätzlich ein
Payment-Provider wie Stripe samt Anbindung an eine echte Spendenorganisation nötig.

Dieser Prototyp dient dazu, den Kernmechanismus – Frei-Kontingent, Bezahlschranke,
Spenden-Tracking – zu demonstrieren und zu testen, bevor man in eine native App
investiert.
