# Kalibrier-Werkzeug

Bestimmt die drei Heuristik-Parameter aus `TrafficHeuristics` in
[`../native/ios/NetworkTrafficEstimator.swift`](../native/ios/NetworkTrafficEstimator.swift)
aus echten Messungen:

| Parameter | Bedeutung |
|---|---|
| `minBurstBytes` | Ab wann ein Datenschub als Video-Segment zählt (statt Thumbnail/Telemetrie) |
| `burstIdleGap` | Wie lange Ruhe herrschen muss, damit ein neuer Burst beginnt |
| `burstsPerReel` | Wie viele Segment-Bursts im Schnitt auf ein Reel entfallen |

Ohne Kalibrierung sind die Werte im Swift geraten. Sie sind der Unterschied
zwischen "ungefähr plausibel" und "verlässlich".

## Ausprobieren (ohne iPhone)

```bash
python3 tools/make_sample_data.py > tools/sample-measurements.json
python3 tools/calibrate.py tools/sample-measurements.json
```

`make_sample_data.py` erzeugt **synthetischen** Traffic mit bekannter Wahrheit
(`burstsPerReel = 1.8`), damit sich das Skript ohne Gerät ausführen und testen
lässt. Die Datei ist ~7 MB groß und deshalb nicht eingecheckt – sie wird bei
Bedarf neu erzeugt (fester Seed, also reproduzierbar).

**Das ersetzt keine echte Messung.** Die Simulation bestätigt nur, dass die
Auswertung rechnerisch funktioniert – nicht, dass die Annahmen über Instagrams
tatsächliches Ladeverhalten stimmen.

## Tests

```bash
cd tools && python3 -m unittest discover -s . -v
```

Prüft unter anderem, dass die Auswertung aus den synthetischen Daten den
eingebauten Wahrheitswert von 1.8 zurückgewinnt (Ergebnis: 1.774).

## Echte Messung durchführen

1. **Sitzung aufnehmen.** Reels schauen und dabei von Hand mitzählen – am
   einfachsten mit einem Zähler in der anderen Hand. Die Zahl ist die
   Referenz, gegen die alles andere gemessen wird, also sauber zählen.
2. **Traffic protokollieren.** Der Tunnel schreibt die Paket-Ereignisse
   (Zeitstempel + Bytes) mit, die Screen-Time-Seite die aktiven Zeitfenster.
3. **Als JSON exportieren** (Format unten) und `calibrate.py` darauf laufen
   lassen.
4. **Ergebnis ins Swift übernehmen** – das Skript gibt den fertigen Block zum
   Einfügen aus.

Sinnvoll sind **8–10 Sitzungen** über verschiedene Tage, Tageszeiten und Netze
(WLAN vs. Mobilfunk), unterschiedlich lang. Bei weniger als 5 Sitzungen warnt
das Skript, bei weniger als 3 kann es die Kreuzvalidierung nicht rechnen.

## Eingabeformat

```json
{
  "sessions": [
    {
      "id": "2026-08-01-abends",
      "manualReelCount": 71,
      "activeWindows": [["2026-08-01T21:04:00Z", "2026-08-01T21:37:00Z"]],
      "packets": [
        {"t": 1754600005.0, "bytes": 1440},
        {"t": 1754600005.01, "bytes": 1440}
      ]
    }
  ]
}
```

- Zeitangaben wahlweise als Unix-Sekunden oder ISO-8601.
- `activeWindows` stammen aus Screen Time und filtern den Hintergrund-Prefetch
  heraus. Fehlen sie, wird nicht gefiltert – und das Ergebnis überschätzt
  systematisch, weil vorgeladene Reels mitgezählt werden.
- Statt `packets` kann auch `bursts` (Liste von Zeitstempeln) angegeben werden,
  wenn die Gruppierung schon auf dem Gerät passiert ist. Dann lassen sich
  `minBurstBytes` und `burstIdleGap` allerdings nicht mehr variieren – die
  Grid-Suche braucht die rohen Paket-Ereignisse.

## Wie das Skript auswählt

Es probiert alle Kombinationen aus `minBurstBytes` × `burstIdleGap` durch,
fittet für jede das passende `burstsPerReel` und bewertet den Fehler.

Zwei Details, die das Ergebnis ehrlich halten:

- **Gepooltes Verhältnis statt Mittelwert der Einzelverhältnisse.** Lange
  Sitzungen wiegen stärker – eine 5-Reel-Sitzung ist viel rauschanfälliger als
  eine mit 80.
- **Leave-One-Out-Kreuzvalidierung** als Auswahlkriterium. Fittet man auf
  allen Daten und misst den Fehler auf denselben Daten, sieht jedes Ergebnis
  zu gut aus – die Grid-Suche würde die Parameter finden, die am besten zum
  Rauschen passen. Deshalb wird je Sitzung auf den *anderen* Sitzungen
  gefittet. Der ausgewiesene Leave-One-Out-Fehler ist die belastbare Zahl,
  der In-Sample-Fehler steht nur zum Vergleich daneben.

Verschiedene Parametersätze können dieselben Daten gleich gut beschreiben: ein
größerer `burstIdleGap` lässt die Segmente eines Reels verschmelzen, wodurch
`burstsPerReel` entsprechend sinkt. Das Skript zeigt deshalb auch die
nächstbesten Kandidaten an – bei praktisch gleichem Fehler bevorzugt es die
höhere Byte-Schwelle, weil sie unempfindlicher gegen Rausch-Traffic ist.
