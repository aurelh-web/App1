#!/usr/bin/env python3
"""Erzeugt synthetische Messdaten mit bekannter Wahrheit, um calibrate.py zu prüfen.

Das ist KEIN Ersatz für echte Messungen – es simuliert nur plausiblen Traffic,
damit calibrate.py ohne iPhone lauffähig und testbar ist. Ob die Annahmen
stimmen, klärt erst eine echte Messung.

    python3 tools/make_sample_data.py > tools/sample-measurements.json
"""

from __future__ import annotations

import json
import random
import sys

# Die Wahrheit, die calibrate.py aus den Daten zurückgewinnen soll.
TRUE_BURSTS_PER_REEL = 1.8
TRUE_MIN_BURST_BYTES = 120_000
TRUE_IDLE_GAP = 0.4

SESSIONS = [
    ("2026-08-01-morgens", 34),
    ("2026-08-01-abends", 71),
    ("2026-08-03-bahn", 52),
    ("2026-08-04-mittags", 18),
    ("2026-08-05-abends", 96),
    ("2026-08-06-wartezimmer", 43),
]


def build_session(session_id: str, reel_count: int, start: float, rng: random.Random):
    packets: list[dict[str, float | int]] = []
    clock = start + 5.0

    def emit_burst(total_bytes: int, at: float) -> float:
        """Ein Video-Segment: viele MTU-große Pakete dicht hintereinander."""
        remaining = total_bytes
        t = at
        while remaining > 0:
            size = min(remaining, 1440)
            packets.append({"t": round(t, 3), "bytes": size})
            # Pakete innerhalb eines Bursts liegen klar unter dem Idle-Gap.
            t += rng.uniform(0.0005, 0.02)
            remaining -= size
        return t

    for _ in range(reel_count):
        # Ein Reel erzeugt mal einen, mal zwei Segment-Bursts – im Mittel 1.8.
        burst_count = 2 if rng.random() < (TRUE_BURSTS_PER_REEL - 1) else 1
        for _ in range(burst_count):
            payload = int(rng.uniform(150_000, 420_000))
            clock = emit_burst(payload, clock)
            clock += rng.uniform(0.6, 1.4)  # Pause > Idle-Gap trennt die Bursts

        # Betrachtungsdauer des Reels.
        clock += rng.uniform(3.0, 18.0)

        # Rauschen: Thumbnails und Telemetrie, zu klein für die Schwelle.
        if rng.random() < 0.4:
            packets.append({"t": round(clock, 3), "bytes": int(rng.uniform(800, 9_000))})
            clock += rng.uniform(0.5, 1.5)

    end = clock + 5.0

    # Hintergrund-Prefetch NACH Sitzungsende: volle Bursts, die aber kein
    # angeschautes Reel sind. Genau das muss der Zeitfenster-Filter wegwerfen.
    prefetch_clock = end + rng.uniform(30, 90)
    for _ in range(rng.randint(3, 9)):
        prefetch_clock = emit_burst(int(rng.uniform(180_000, 400_000)), prefetch_clock)
        prefetch_clock += rng.uniform(20, 120)

    return {
        "id": session_id,
        "manualReelCount": reel_count,
        "activeWindows": [[round(start, 3), round(end, 3)]],
        "packets": packets,
    }


def main() -> int:
    rng = random.Random(20260808)  # fester Seed -> reproduzierbare Datei
    clock = 1_754_600_000.0  # irgendein fixer Startzeitpunkt

    sessions = []
    for session_id, reel_count in SESSIONS:
        session = build_session(session_id, reel_count, clock, rng)
        sessions.append(session)
        clock = session["activeWindows"][0][1] + rng.uniform(3_600, 40_000)

    json.dump(
        {
            "_comment": (
                "Synthetische Testdaten aus tools/make_sample_data.py – keine echten "
                f"Messungen. Erzeugt mit burstsPerReel={TRUE_BURSTS_PER_REEL}, "
                f"minBurstBytes={TRUE_MIN_BURST_BYTES}, idleGap={TRUE_IDLE_GAP}."
            ),
            "sessions": sessions,
        },
        sys.stdout,
        indent=1,
    )
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
