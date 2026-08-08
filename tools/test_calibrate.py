#!/usr/bin/env python3
"""Tests für calibrate.py.

    python3 -m unittest discover -s tools -v
"""

from __future__ import annotations

import unittest

import calibrate
import make_sample_data


class GroupBurstsTest(unittest.TestCase):
    def test_pause_trennt_bursts(self):
        packets = [(0.0, 80_000), (0.1, 80_000), (5.0, 80_000), (5.1, 80_000)]
        bursts = calibrate.group_bursts(packets, min_burst_bytes=120_000, burst_idle_gap=0.4)
        self.assertEqual(bursts, [0.0, 5.0])

    def test_kleine_bursts_fallen_unter_schwelle_raus(self):
        packets = [(0.0, 5_000), (10.0, 300_000)]
        bursts = calibrate.group_bursts(packets, min_burst_bytes=120_000, burst_idle_gap=0.4)
        self.assertEqual(bursts, [10.0], "Thumbnail-Traffic darf nicht als Reel zählen")

    def test_groesserer_idle_gap_verschmilzt_bursts(self):
        packets = [(0.0, 200_000), (1.0, 200_000)]
        eng = calibrate.group_bursts(packets, min_burst_bytes=120_000, burst_idle_gap=0.4)
        weit = calibrate.group_bursts(packets, min_burst_bytes=120_000, burst_idle_gap=2.0)
        self.assertEqual(len(eng), 2)
        self.assertEqual(len(weit), 1)

    def test_leere_eingabe(self):
        self.assertEqual(calibrate.group_bursts([], 120_000, 0.4), [])


class ActiveWindowFilterTest(unittest.TestCase):
    def test_bursts_ausserhalb_werden_verworfen(self):
        timestamps = [5.0, 50.0, 105.0]
        windows = [(0.0, 10.0), (100.0, 110.0)]
        self.assertEqual(calibrate.filter_to_active_windows(timestamps, windows), [5.0, 105.0])

    def test_ohne_fenster_wird_nicht_gefiltert(self):
        timestamps = [1.0, 2.0]
        self.assertEqual(calibrate.filter_to_active_windows(timestamps, []), [1.0, 2.0])


class FitTest(unittest.TestCase):
    def test_gepooltes_verhaeltnis(self):
        # 18 Bursts auf 10 Reels -> 1.8
        self.assertAlmostEqual(calibrate.fit_bursts_per_reel([(9, 5), (9, 5)]), 1.8)

    def test_lange_sitzung_wiegt_staerker(self):
        # Kurze Sitzung mit abweichendem Verhaeltnis darf das Ergebnis nicht dominieren.
        ratio = calibrate.fit_bursts_per_reel([(180, 100), (6, 2)])
        self.assertLess(ratio, 2.0)
        self.assertGreater(ratio, 1.8)

    def test_ohne_daten_kein_fit(self):
        self.assertIsNone(calibrate.fit_bursts_per_reel([(0, 0)]))

    def test_leave_one_out_braucht_genug_sitzungen(self):
        self.assertIsNone(calibrate.leave_one_out_error([(18, 10), (18, 10)]))
        self.assertIsNotNone(calibrate.leave_one_out_error([(18, 10), (18, 10), (18, 10)]))


class SyntheticDataTest(unittest.TestCase):
    """Prüft die Kette End-to-End gegen Daten mit bekannter Wahrheit."""

    @classmethod
    def setUpClass(cls):
        import random

        rng = random.Random(20260808)
        clock = 1_754_600_000.0
        cls.sessions = []
        for session_id, reels in make_sample_data.SESSIONS:
            raw = make_sample_data.build_session(session_id, reels, clock, rng)
            cls.sessions.append(
                calibrate.Session(
                    id=raw["id"],
                    manual_reel_count=raw["manualReelCount"],
                    active_windows=[tuple(w) for w in raw["activeWindows"]],
                    packets=sorted((p["t"], p["bytes"]) for p in raw["packets"]),
                    bursts=None,
                )
            )

    def test_wahre_parameter_liefern_wahres_verhaeltnis(self):
        """Bei den Erzeugungs-Parametern muss burstsPerReel ~1.8 herauskommen."""
        counts = [
            (
                calibrate.relevant_burst_count(
                    s,
                    make_sample_data.TRUE_MIN_BURST_BYTES,
                    make_sample_data.TRUE_IDLE_GAP,
                ),
                s.manual_reel_count,
            )
            for s in self.sessions
        ]
        ratio = calibrate.fit_bursts_per_reel(counts)
        self.assertAlmostEqual(ratio, make_sample_data.TRUE_BURSTS_PER_REEL, delta=0.12)

    def test_prefetch_filter_macht_einen_unterschied(self):
        """Ohne Zeitfenster zaehlt der Hintergrund-Prefetch mit und verfaelscht nach oben."""
        gefiltert = sum(
            calibrate.relevant_burst_count(
                s, make_sample_data.TRUE_MIN_BURST_BYTES, make_sample_data.TRUE_IDLE_GAP
            )
            for s in self.sessions
        )
        ungefiltert = sum(
            len(
                calibrate.group_bursts(
                    s.packets,
                    make_sample_data.TRUE_MIN_BURST_BYTES,
                    make_sample_data.TRUE_IDLE_GAP,
                )
            )
            for s in self.sessions
        )
        self.assertGreater(
            ungefiltert, gefiltert, "Screen-Time-Fenster muessen Prefetch-Bursts entfernen"
        )

    def test_grid_findet_brauchbare_parameter(self):
        candidates = calibrate.evaluate_grid(self.sessions)
        self.assertTrue(candidates)
        best = candidates[0]
        self.assertIsNotNone(best.loo_error)
        self.assertLess(best.loo_error, 15.0, "Fehler sollte auf sauberen Daten klein sein")

    def test_report_laeuft_durch(self):
        import contextlib
        import io

        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            calibrate.print_report(self.sessions, calibrate.evaluate_grid(self.sessions))
        self.assertIn("burstsPerReel", buffer.getvalue())


if __name__ == "__main__":
    unittest.main()
