#!/usr/bin/env python3
"""Kalibriert die Burst-Heuristik aus TrafficHeuristics (Swift) gegen echte Messungen.

Ablauf: Man schaut eine Sitzung lang Reels und zählt sie von Hand mit. Parallel
protokolliert der Tunnel den Traffic. Dieses Skript vergleicht beides und
bestimmt die Parameter, mit denen die Schätzung am besten trifft:

    minBurstBytes, burstIdleGap  -> wie Pakete zu Bursts gruppiert werden
    burstsPerReel                -> wie viele Bursts auf ein Reel entfallen

Aufruf:
    python3 tools/calibrate.py tools/sample-measurements.json

Siehe tools/README.md für das Eingabeformat und wie man die Messdaten erhebt.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime
from typing import Iterable, Sequence

# Startwerte aus native/ios/NetworkTrafficEstimator.swift. Die Grid-Suche
# variiert um diese Werte herum.
DEFAULT_MIN_BURST_BYTES = 120_000
DEFAULT_BURST_IDLE_GAP = 0.4

MIN_BURST_BYTES_GRID = [40_000, 60_000, 80_000, 120_000, 160_000, 240_000, 320_000]
BURST_IDLE_GAP_GRID = [0.2, 0.3, 0.4, 0.6, 0.8, 1.2]


# --------------------------------------------------------------------------
# Datenmodell
# --------------------------------------------------------------------------


@dataclass
class Session:
    """Eine Messsitzung: von Hand gezählte Reels + der protokollierte Traffic."""

    id: str
    manual_reel_count: int
    active_windows: list[tuple[float, float]]
    packets: list[tuple[float, int]]  # (timestamp, bytes)
    bursts: list[float] | None  # vorgruppierte Burst-Zeitstempel, falls keine Pakete


def _parse_time(value: object) -> float:
    """Akzeptiert Unix-Sekunden oder ISO-8601-Strings."""
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    raise ValueError(f"Zeitangabe nicht lesbar: {value!r}")


def load_sessions(path: str) -> list[Session]:
    with open(path, encoding="utf-8") as handle:
        raw = json.load(handle)

    sessions = []
    for entry in raw["sessions"]:
        windows = [
            (_parse_time(start), _parse_time(end))
            for start, end in entry.get("activeWindows", [])
        ]
        packets = [
            (_parse_time(p["t"]), int(p["bytes"])) for p in entry.get("packets", [])
        ]
        bursts = entry.get("bursts")
        sessions.append(
            Session(
                id=entry["id"],
                manual_reel_count=int(entry["manualReelCount"]),
                active_windows=windows,
                packets=sorted(packets),
                bursts=sorted(_parse_time(b) for b in bursts) if bursts else None,
            )
        )
    return sessions


# --------------------------------------------------------------------------
# Burst-Gruppierung – spiegelt ReelTrafficAnalyzer.inspect() aus dem Swift
# --------------------------------------------------------------------------


def group_bursts(
    packets: Sequence[tuple[float, int]],
    min_burst_bytes: int,
    burst_idle_gap: float,
) -> list[float]:
    """Gruppiert Pakete zu Bursts und gibt deren Startzeitpunkte zurück.

    Ein Burst endet, wenn länger als burst_idle_gap nichts mehr kam. Er zählt
    nur, wenn dabei mindestens min_burst_bytes zusammengekommen sind – das
    filtert Thumbnails, Icons und Telemetrie heraus.
    """
    starts: list[float] = []
    current_bytes = 0
    current_start: float | None = None
    last_t: float | None = None

    for timestamp, size in packets:
        if last_t is not None and timestamp - last_t > burst_idle_gap:
            if current_bytes >= min_burst_bytes and current_start is not None:
                starts.append(current_start)
            current_bytes = 0
            current_start = None

        if current_start is None:
            current_start = timestamp
        current_bytes += size
        last_t = timestamp

    if current_bytes >= min_burst_bytes and current_start is not None:
        starts.append(current_start)

    return starts


def filter_to_active_windows(
    timestamps: Iterable[float], windows: Sequence[tuple[float, float]]
) -> list[float]:
    """Verwirft Bursts außerhalb echter Nutzung – der Prefetch-Filter.

    Ohne Zeitfenster (keine Screen-Time-Daten) wird nichts gefiltert.
    """
    if not windows:
        return list(timestamps)
    return [t for t in timestamps if any(start <= t <= end for start, end in windows)]


def relevant_burst_count(
    session: Session, min_burst_bytes: int, burst_idle_gap: float
) -> int:
    """Bursts einer Sitzung, die als echtes Reel-Laden zählen."""
    if session.packets:
        raw = group_bursts(session.packets, min_burst_bytes, burst_idle_gap)
    elif session.bursts is not None:
        raw = session.bursts  # bereits gruppiert, Parameter greifen nicht mehr
    else:
        raw = []
    return len(filter_to_active_windows(raw, session.active_windows))


# --------------------------------------------------------------------------
# Fit & Bewertung
# --------------------------------------------------------------------------


def fit_bursts_per_reel(counts: Sequence[tuple[int, int]]) -> float | None:
    """Schätzt burstsPerReel aus (Burst-Anzahl, gezählte Reels)-Paaren.

    Gepooltes Verhältnis der Summen statt Mittelwert der Einzelverhältnisse:
    lange Sitzungen wiegen dadurch stärker als kurze, was hier gewollt ist –
    eine 5-Reel-Sitzung ist deutlich rauschanfälliger als eine mit 80.
    """
    total_bursts = sum(bursts for bursts, _ in counts)
    total_reels = sum(reels for _, reels in counts)
    if total_reels == 0 or total_bursts == 0:
        return None
    return total_bursts / total_reels


def mean_absolute_percentage_error(
    counts: Sequence[tuple[int, int]], bursts_per_reel: float
) -> float | None:
    """Mittlerer prozentualer Fehler der geschätzten gegenüber echter Reel-Zahl."""
    errors = []
    for bursts, actual in counts:
        if actual == 0:
            continue
        predicted = bursts / bursts_per_reel
        errors.append(abs(predicted - actual) / actual)
    if not errors:
        return None
    return 100 * sum(errors) / len(errors)


def leave_one_out_error(counts: Sequence[tuple[int, int]]) -> float | None:
    """Ehrlichere Fehlerschätzung: je Sitzung auf den ANDEREN Sitzungen fitten.

    Fittet man burstsPerReel auf allen Daten und misst den Fehler auf denselben
    Daten, sieht jedes Ergebnis zu gut aus – erst recht bei der Grid-Suche, die
    sonst die Parameter findet, die am besten zum Rauschen passen.
    """
    if len(counts) < 3:
        return None

    errors = []
    for index, (bursts, actual) in enumerate(counts):
        if actual == 0:
            continue
        others = [c for i, c in enumerate(counts) if i != index]
        ratio = fit_bursts_per_reel(others)
        if ratio is None:
            continue
        predicted = bursts / ratio
        errors.append(abs(predicted - actual) / actual)

    if not errors:
        return None
    return 100 * sum(errors) / len(errors)


@dataclass
class Candidate:
    min_burst_bytes: int
    burst_idle_gap: float
    bursts_per_reel: float
    in_sample_error: float
    loo_error: float | None

    @property
    def ranking_error(self) -> float:
        """Nach Leave-One-Out sortieren, wenn verfügbar – sonst In-Sample."""
        return self.loo_error if self.loo_error is not None else self.in_sample_error


def evaluate_grid(sessions: Sequence[Session]) -> list[Candidate]:
    candidates = []
    for min_bytes in MIN_BURST_BYTES_GRID:
        for gap in BURST_IDLE_GAP_GRID:
            counts = [
                (relevant_burst_count(s, min_bytes, gap), s.manual_reel_count)
                for s in sessions
            ]
            ratio = fit_bursts_per_reel(counts)
            if ratio is None:
                continue
            in_sample = mean_absolute_percentage_error(counts, ratio)
            if in_sample is None:
                continue
            candidates.append(
                Candidate(
                    min_burst_bytes=min_bytes,
                    burst_idle_gap=gap,
                    bursts_per_reel=ratio,
                    in_sample_error=in_sample,
                    loo_error=leave_one_out_error(counts),
                )
            )

    # Bei praktisch gleichem Fehler die höhere Byte-Schwelle bevorzugen: sie
    # ist unempfindlicher gegen kleines Rausch-Traffic. Ohne diesen Tie-Break
    # entschiede die Reihenfolge im Grid, also der Zufall.
    candidates.sort(key=lambda c: (round(c.ranking_error, 1), -c.min_burst_bytes))
    return candidates


# --------------------------------------------------------------------------
# Ausgabe
# --------------------------------------------------------------------------


def print_report(sessions: Sequence[Session], candidates: Sequence[Candidate]) -> None:
    total_reels = sum(s.manual_reel_count for s in sessions)
    has_packets = any(s.packets for s in sessions)

    print(f"Sitzungen: {len(sessions)}   von Hand gezählte Reels gesamt: {total_reels}")
    print()

    if not candidates:
        print("Keine auswertbaren Daten – wurden Bursts/Pakete protokolliert?")
        return

    if not has_packets:
        print(
            "Hinweis: Es liegen nur vorgruppierte Bursts vor. minBurstBytes und\n"
            "burstIdleGap lassen sich damit nicht mehr variieren – dafür braucht\n"
            "es die rohen Paket-Ereignisse. Es wird nur burstsPerReel gefittet."
        )
        print()

    best = candidates[0]
    uses_loo = best.loo_error is not None

    print("Beste Parameter:")
    print(f"  minBurstBytes  = {best.min_burst_bytes:_}")
    print(f"  burstIdleGap   = {best.burst_idle_gap}")
    print(f"  burstsPerReel  = {best.bursts_per_reel:.2f}")
    print()
    print(f"  Fehler in-sample:      {best.in_sample_error:.1f} %")
    if uses_loo:
        print(f"  Fehler leave-one-out:  {best.loo_error:.1f} %   <- die belastbare Zahl")
    else:
        print(
            "  Fehler leave-one-out:  n/a (mindestens 3 Sitzungen nötig)\n"
            "  Achtung: ohne Kreuzvalidierung ist der Wert oben geschönt –\n"
            "  die Parameter sind auf genau diese Daten hin optimiert."
        )
    print()

    if has_packets and len(candidates) > 1:
        print("Nächstbeste Kandidaten:")
        for candidate in candidates[1:5]:
            loo = (
                f"{candidate.loo_error:.1f} %"
                if candidate.loo_error is not None
                else "n/a"
            )
            print(
                f"  minBytes={candidate.min_burst_bytes:>7}  gap={candidate.burst_idle_gap:>4}  "
                f"ratio={candidate.bursts_per_reel:>5.2f}  loo={loo}"
            )
        print()

    print("Je Sitzung mit den besten Parametern:")
    print(f"  {'Sitzung':<24} {'gezählt':>8} {'geschätzt':>10} {'Abweichung':>11}")
    for session in sessions:
        bursts = relevant_burst_count(
            session, best.min_burst_bytes, best.burst_idle_gap
        )
        predicted = bursts / best.bursts_per_reel
        actual = session.manual_reel_count
        deviation = (
            f"{100 * (predicted - actual) / actual:+.1f} %" if actual else "n/a"
        )
        print(f"  {session.id:<24} {actual:>8} {predicted:>10.1f} {deviation:>11}")
    print()

    print("Übernehmen in native/ios/NetworkTrafficEstimator.swift:")
    print(f"    static let minBurstBytes = {best.min_burst_bytes:_}")
    print(f"    static let burstIdleGap: TimeInterval = {best.burst_idle_gap}")
    print(f"    static let burstsPerReel: Double = {best.bursts_per_reel:.2f}")

    if len(sessions) < 5:
        print()
        print(
            f"Datenbasis dünn ({len(sessions)} Sitzungen). Für tragfähige Werte eher\n"
            "8-10 Sitzungen über verschiedene Tage, Netze (WLAN/Mobilfunk) und\n"
            "Tageszeiten aufnehmen."
        )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("measurements", help="JSON mit den Messsitzungen")
    args = parser.parse_args(argv)

    try:
        sessions = load_sessions(args.measurements)
    except (OSError, ValueError, KeyError) as error:
        print(f"Messdaten konnten nicht gelesen werden: {error}", file=sys.stderr)
        return 1

    if not sessions:
        print("Keine Sitzungen in der Datei.", file=sys.stderr)
        return 1

    try:
        print_report(sessions, evaluate_grid(sessions))
    except BrokenPipeError:
        # Passiert bei "| head". stdout auf devnull umbiegen, sonst meldet der
        # Interpreter beim Aufräumen ein zweites Mal denselben Fehler.
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
