#!/usr/bin/env python3
"""Training der KI für das ganze Spiel (josh 2026-11-15).

Was hier passiert, in einfachen Worten
--------------------------------------
Die KI ist eine Tabelle von Zahlen ("Gewichte"). Für jeden Beruf, jede Handlung (z. B. "Haus bauen",
"Schiff bauen", "Überstunden für Bauern") und für die Wahl der Forschung gibt es eine Zeile. Das Spiel
rechnet daraus alle halben Spieltage aus, was die KI tut (scripts/autoload/ki_brain.gd und ki_acts.gd).

Gelernt wird durch Ausprobieren mit Belohnung (Reinforcement Learning, Verfahren "Augmented Random
Search", Mania, Guy, Recht 2018):
  1. Die Gewichte werden zufällig ein wenig verändert, einmal in eine Richtung (+) und einmal in die
     Gegenrichtung (-).
  2. Beide Fassungen spielen ein ganzes Spiel ohne Grafik, IMMER VOM ANFANG (neue Insel, 2 Siedler),
     mit denselben Würfeln.
  3. Das Spiel zählt Punkte (Wertung in ki_brain.gd: satte und zufriedene Siedler, Forschung, Zeitalter,
     Inseln, Zukunftsstadt, Abzug für Tote ...).
  4. Die Gewichte wandern in die Richtungen, die mehr Punkte gebracht haben.
Das ist eine Runde. Alle paar Runden gibt es eine Prüfung mit festen Würfeln; die besten Gewichte bleiben
in lauf/best.json.

Stufenlernen (josh 2026-11-15): jede Stufe hat ein Ziel (ein Zeitalter, zuletzt die Zukunftsstadt) und eine
feste Spiellänge. Ist das Ziel in den Prüfungen geschafft, hält das Training an und wartet auf das Okay; die
nächste Stufe lernt mit den bisherigen Gewichten weiter. Ein Spiel endet früher, wenn die Zukunftsstadt steht, alle tot
sind oder sich stillstand_tage lang nichts mehr tut.

Dateien in lauf/: zustand.json (alles zum Fortsetzen), status.json (für die Oberfläche), best.json
(beste Gewichte, so liest sie das Spiel), verlauf.jsonl (eine Zeile je Runde), pruefungen/ (ganze
Prüfspiele mit allen Entscheidungen der KI).

Aufruf:  python3 trainer.py --godot <Pfad zu Godot> [--spiel ../spiel] [--lauf ../lauf]
Nur Python-Standardbibliothek, keine Zusatzpakete.
"""
import argparse
import json
import math
import os
import random
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))

DEFAULTS = {
    "arbeiter": 0,            # Spiele gleichzeitig; 0 = Anzahl der Prozessorkerne minus 1
    "richtungen": 0,          # Zufallsrichtungen je Runde; 0 = so viele wie Arbeiter (mindestens 16)
    "rauschen": 0.3,          # wie stark die Gewichte zum Ausprobieren verändert werden
    "lernrate": 0.1,          # wie weit die Gewichte je Runde wandern
    # Stufenlernen (josh 2026-11-15): jede Stufe hat ein Ziel und eine feste Spiellänge in Spieltagen
    # (12 Tage = 1 Spieljahr). Ist das Ziel geschafft, hält das Training an und wartet auf das Okay.
    # "alter": mindestens dieses Zeitalter (0 = Steinzeit), "ziel": Zukunftsstadt gebaut.
    "stufen": [
        {"alter": 1, "tage": 80}, {"alter": 2, "tage": 180}, {"alter": 3, "tage": 300}, {"alter": 4, "tage": 450},
        {"alter": 5, "tage": 600}, {"alter": 6, "tage": 800}, {"alter": 7, "tage": 1000}, {"ziel": True, "tage": 1400}],
    "ziel_pruefungen": 2,     # das Ziel gilt, wenn es in so vielen Prüfungen nacheinander alle Prüfspiele schaffen
    "stillstand_tage": 40,    # Spiel endet, wenn so lange nichts Neues entsteht
    "pruefung_alle": 4,       # alle so viele Runden eine Prüfung
    "pruefung_wuerfel": 3,    # Prüfspiele je Prüfung
    "ereignisse": True,       # mit Ereignissen (harte Winter, Piraten ...)
    "runden": 100000,         # Ende des Trainings (praktisch: läuft, bis du stoppst)
    "saat": 7,
}


def load_config(path):
    cfg = dict(DEFAULTS)
    if os.path.exists(path):
        try:
            cfg.update(json.load(open(path, encoding="utf-8")))
        except Exception as e:
            print("einstellungen.json nicht lesbar:", e, file=sys.stderr)
    if int(cfg["arbeiter"]) <= 0:
        cfg["arbeiter"] = max(1, (os.cpu_count() or 2) - 1)
    if int(cfg["richtungen"]) <= 0:
        cfg["richtungen"] = max(16, int(cfg["arbeiter"]))
    return cfg


def write_json(path, data):
    """Erst in eine Nebendatei schreiben, dann umbenennen: die Oberfläche liest nie eine halbe Datei."""
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False)
    os.replace(tmp, path)


class Layout:
    """Welche Zeilen die Gewichte haben. Das Spiel sagt es selbst (--kinames), damit beides zusammenpasst."""

    def __init__(self, names):
        self.jobs = names["jobs"]
        self.acts = names["acts"]
        self.F = int(names["features"])
        self.X = int(names["act_x"])
        self.T = int(names["tech_f"])
        self.size = len(self.jobs) * self.F + len(self.acts) * (self.F + self.X) + self.T

    def to_game(self, vec):
        """Flache Zahlenliste -> Gewichtsdatei, wie sie ki_brain.gd liest."""
        F, X = self.F, self.X
        i = 0
        w = []
        for _ in self.jobs:
            w.append(vec[i:i + F])
            i += F
        a = {}
        for n in self.acts:
            a[n] = vec[i:i + F + X]
            i += F + X
        return {"w": w, "a": a, "t": vec[i:i + self.T], "full": True}

    def from_game(self, d):
        """Gewichtsdatei -> flache Liste (fehlende Zeilen und Eingänge sind 0)."""
        F, X = self.F, self.X
        vec = []
        rows = d.get("w", [])
        for j in range(len(self.jobs)):
            r = list(rows[j]) if j < len(rows) else []
            vec += (r + [0.0] * F)[:F]
        old = ["haus", "ausbau", "lager", "feld", "obstgarten", "strasse", "werft", "schiff", "erkunden", "besiedeln"]
        a = {old[i]: r for i, r in enumerate(d.get("b", [])[:len(old)])}
        a.update(d.get("a", {}))
        for n in self.acts:
            r = list(a.get(n, []))
            if len(r) <= F:  # alte Zeile ohne die Eingänge der Handlung
                r = (r + [0.0] * F)[:F] + [0.0] * X
            vec += (r + [0.0] * (F + X))[:F + X]
        vec += (list(d.get("t", [])) + [0.0] * self.T)[:self.T]
        return vec


class Trainer:
    def __init__(self, a):
        self.godot = a.godot
        self.spiel = os.path.abspath(a.spiel)
        self.lauf = os.path.abspath(a.lauf)
        os.makedirs(os.path.join(self.lauf, "pruefungen"), exist_ok=True)
        self.cfg = load_config(os.path.join(self.lauf, "einstellungen.json"))
        if not os.path.exists(os.path.join(self.lauf, "einstellungen.json")):
            write_json(os.path.join(self.lauf, "einstellungen.json"), {k: (0 if k in ("arbeiter", "richtungen") else v) for k, v in DEFAULTS.items()})
        self.tmp = tempfile.mkdtemp(prefix="insel_ki_")
        self.procs = {}
        self.lock = threading.Lock()
        self.stop = False
        self.running = {}   # Platz -> {art, saat, tage, start}
        self.phase = "Start"
        self.t_start = time.time()
        self.names = self.ask_names()
        self.lay = Layout(self.names)
        write_json(os.path.join(self.lauf, "namen.json"), self.names)
        self.rng = random.Random(int(self.cfg["saat"]))
        self.round = 0
        self.vec = [0.0] * self.lay.size
        self.history = []
        self.checks = []
        self.best = {"mittel": -1e18, "runde": 0}
        self.secs_total = 0.0
        self.games_total = 0
        self.seen = [0] * (self.lay.F + self.lay.X)  # in wie vielen Spielen war dieser Eingang einmal nicht 0
        self.seen_games = 0
        self.stage = 0       # Stufe (Index in cfg["stufen"])
        self.waiting = False  # Ziel der Stufe geschafft: wartet auf das Okay
        self.load_state(a.init)

    # ------------------------------------------------------------ Spiel starten
    def env(self, slot):
        e = dict(os.environ)
        e["XDG_DATA_HOME"] = os.path.join(self.tmp, "platz_%d" % slot)  # eigener Speicherplatz je Spiel
        e["KI_LANG"] = "de"
        return e

    def ask_names(self):
        out = os.path.join(self.tmp, "namen.json")
        cmd = [self.godot, "--headless", "--fixed-fps", "60", "--path", self.spiel, "--", "--autotest=999999", "--scale=10",
               "--kitrain=1", "--kifull=1", "--kidays=0", "--kinames=" + out, "--kiout=" + os.path.join(self.tmp, "n.json")]
        subprocess.run(cmd, env=self.env(99), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)
        if not os.path.exists(out):
            raise SystemExit("Das Spiel hat nicht geantwortet. Stimmt der Pfad zu Godot und zum Ordner spiel? "
                             "Beim ersten Start muss das Spiel einmal importiert werden (macht START.command).")
        return json.load(open(out, encoding="utf-8"))

    def episode(self, slot, vec, days, seed, kind):
        """Ein ganzes Spiel vom Anfang. Gibt (Punkte, Ergebnis) zurück, (None, None) bei Absturz."""
        d = os.path.join(self.tmp, "platz_%d" % slot)
        os.makedirs(d, exist_ok=True)
        wpath = os.path.join(d, "w.json")
        out = os.path.join(d, "r.json")
        prog = os.path.join(d, "p.json")
        for p in (out, prog):
            if os.path.exists(p):
                os.remove(p)
        with open(wpath, "w") as f:
            json.dump(self.lay.to_game(vec), f)
        cmd = [self.godot, "--headless", "--fixed-fps", "60", "--path", self.spiel, "--", "--autotest=999999", "--scale=10",
               "--kitrain=1", "--kifull=1", "--kiw=" + wpath, "--kidays=%d" % days, "--kiseed=%d" % seed,
               "--kistall=%d" % int(self.cfg["stillstand_tage"]), "--kiprog=" + prog, "--kiout=" + out]
        if not self.cfg["ereignisse"]:
            cmd.append("--noevents=1")
        timeout = min(6 * 3600, 120 + days * 25)
        with self.lock:
            self.running[slot] = {"art": kind, "saat": seed, "tage": days, "start": time.time(), "prog": prog}
        try:
            p = subprocess.Popen(cmd, env=self.env(slot), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            with self.lock:
                self.procs[slot] = p
            p.wait(timeout=timeout)
            with open(out, encoding="utf-8") as f:
                res = json.load(f)
            return float(res["score"]), res
        except Exception as e:
            if not self.stop:
                print("  Spiel fehlgeschlagen (Platz %d): %s" % (slot, e), file=sys.stderr, flush=True)
            try:
                p.kill()
            except Exception:
                pass
            return None, None
        finally:
            with self.lock:
                self.procs.pop(slot, None)
                self.running.pop(slot, None)
                self.games_total += 1

    def play(self, jobs, kind):
        """Viele Spiele gleichzeitig: jobs = [(Gewichte, Tage, Würfel)]."""
        slots = list(range(int(self.cfg["arbeiter"])))
        sl = threading.Lock()

        def one(j):
            if self.stop:
                return None, None
            with sl:
                slot = slots.pop()
            try:
                return self.episode(slot, j[0], j[1], j[2], kind)
            finally:
                with sl:
                    slots.append(slot)
        with ThreadPoolExecutor(max_workers=int(self.cfg["arbeiter"])) as ex:
            return list(ex.map(one, jobs))

    # ------------------------------------------------------------ Zustand
    def load_state(self, init):
        p = os.path.join(self.lauf, "zustand.json")
        if os.path.exists(p):
            s = json.load(open(p, encoding="utf-8"))
            if len(s.get("vec", [])) == self.lay.size:
                self.round = int(s["runde"])
                self.vec = s["vec"]
                self.history = s.get("verlauf", [])
                self.checks = s.get("pruefungen", [])
                self.best = s.get("best", self.best)
                self.secs_total = float(s.get("sek", 0.0))
                self.games_total = int(s.get("spiele", 0))
                self.stage = min(int(s.get("stufe", 0)), len(self.cfg["stufen"]) - 1)
                self.waiting = bool(s.get("wartet", False))
                if len(s.get("gesehen", [])) == len(self.seen):
                    self.seen = s["gesehen"]
                    self.seen_games = int(s.get("gesehen_spiele", 0))
                st = s.get("zufall")
                if st:
                    self.rng.setstate((st[0], tuple(st[1]), st[2]))
                print("Fortsetzen ab Runde %d" % self.round, flush=True)
                return
            print("zustand.json passt nicht mehr zum Spiel (andere Handlungen): Neustart, alte Datei als zustand_alt.json", flush=True)
            shutil.move(p, os.path.join(self.lauf, "zustand_alt.json"))
        if init and os.path.exists(init):
            self.vec = self.lay.from_game(json.load(open(init, encoding="utf-8")))
            print("Startgewichte aus", init, flush=True)

    def save_state(self):
        st = self.rng.getstate()
        write_json(os.path.join(self.lauf, "zustand.json"), {
            "runde": self.round, "vec": self.vec, "verlauf": self.history, "pruefungen": self.checks, "best": self.best,
            "sek": self.secs_total + (time.time() - self.t_start), "spiele": self.games_total,
            "gesehen": self.seen, "gesehen_spiele": self.seen_games, "stufe": self.stage, "wartet": self.waiting,
            "zufall": [st[0], list(st[1]), st[2]]})

    def days_for(self, rnd):
        return int(self.cfg["stufen"][self.stage]["tage"])

    def stage_ok(self, game):
        """Schafft dieses Prüfspiel das Ziel der Stufe?"""
        st = self.cfg["stufen"][self.stage]
        if st.get("ziel"):
            return bool(game.get("ziel"))
        return int(game.get("alter", 0)) >= int(st.get("alter", 0))

    def stage_reached(self):
        n = int(self.cfg["ziel_pruefungen"])
        mine = [c for c in self.checks if c.get("stufe", -1) == self.stage]
        if len(mine) < n:
            return False
        return all(self.stage_ok(g) for c in mine[-n:] for g in c["spiele"])

    def status(self):
        with self.lock:
            run = []
            for slot, r in sorted(self.running.items()):
                e = {"platz": slot, "art": r["art"], "saat": r["saat"], "tage": r["tage"], "sek": round(time.time() - r["start"])}
                try:
                    e.update(json.load(open(r["prog"], encoding="utf-8")))
                except Exception:
                    pass
                run.append(e)
        return {"zeit": time.time(), "phase": self.phase, "runde": self.round, "tage": self.days_for(max(1, self.round + 1)),
                "arbeiter": int(self.cfg["arbeiter"]), "richtungen": int(self.cfg["richtungen"]), "laufend": run,
                "verlauf": self.history[-400:], "pruefungen": self.checks, "best": self.best, "gewichte": self.lay.size,
                "handlungen": len(self.lay.acts), "sek": self.secs_total + (time.time() - self.t_start),
                "spiele": self.games_total, "einstellungen": self.cfg, "gestoppt": self.stop,
                "gesehen": self.seen, "gesehen_spiele": self.seen_games,
                "stufe": self.stage, "wartet": self.waiting, "stufen": self.cfg["stufen"], "ziel_pruefungen": int(self.cfg["ziel_pruefungen"])}

    def status_loop(self):
        p = os.path.join(self.lauf, "status.json")
        while True:
            try:
                write_json(p, self.status())
            except Exception as e:
                print("status:", e, file=sys.stderr)
            if self.stop and not self.running:
                break
            time.sleep(2.0)

    # ------------------------------------------------------------ Lernen
    def note_seen(self, res):
        """Zählt, welche Eingänge in diesem Spiel je vorkamen (nicht 0 waren)."""
        s = (res.get("seen") or [])
        x = (res.get("seen_x") or [])
        if len(s) != self.lay.F:
            return
        for k in range(self.lay.F):
            if s[k] > 0:
                self.seen[k] += 1
        for k in range(min(len(x), self.lay.X)):
            if x[k] > 0:
                self.seen[self.lay.F + k] += 1
        self.seen_games += 1
        # die Spiele selbst brauchen die langen Listen nicht mehr
        res.pop("seen", None)
        res.pop("seen_x", None)

    @staticmethod
    def summary(res):
        return {"punkte": round(res["score"]), "tag": round(float(res.get("day", 0))), "siedler": res.get("pop", 0),
                "zeitalter": res.get("age_name", ""), "alter": res.get("age", 0), "forschungen": len(res.get("techs", [])),
                "inseln": res.get("islands", 1), "droiden": res.get("droids", 0), "ziel": bool(res.get("goal", False)),
                "stillstand": bool(res.get("stalled", False)), "ende": bool(res.get("over", False))}

    def check(self, tag):
        """Prüfung: die jetzigen Gewichte spielen mit festen Würfeln. Das erste Prüfspiel wird ganz gespeichert."""
        self.phase = "Prüfung nach Runde %d" % self.round
        days = self.days_for(max(1, self.round))
        seeds = [900000 + i for i in range(int(self.cfg["pruefung_wuerfel"]))]
        rs = self.play([(self.vec, days, s) for s in seeds], "Prüfung")
        ok = [r for r in rs if r[0] is not None]
        if not ok:
            return
        for r in ok:
            self.note_seen(r[1])
        mean = sum(r[0] for r in ok) / len(ok)
        per_day = sum(r[0] / max(1.0, float(r[1].get("day", days))) for r in ok) / len(ok)
        rec = {"runde": self.round, "tage": days, "mittel": mean, "je_tag": per_day, "spiele": [self.summary(r[1]) for r in ok], "zeit": time.time(), "stufe": self.stage}
        self.checks.append(rec)
        full = dict(ok[0][1])
        full["runde"] = self.round
        full["tage"] = days
        write_json(os.path.join(self.lauf, "pruefungen", "runde_%05d.json" % self.round), full)
        # Bestes: verglichen wird nur bei gleicher Spiellänge (längere Spiele sind schwerer und bringen je Tag
        # weniger Punkte). Wird das Spiel länger, zählt die erste Prüfung der neuen Länge als neues Bestes.
        if tag == "start" or days > int(self.best.get("tage", 0)) or per_day > float(self.best.get("je_tag", -1e18)):
            self.best = {"mittel": mean, "je_tag": per_day, "runde": self.round, "tage": days}
            g = self.lay.to_game(self.vec)
            g.update({"runde": self.round, "tage": days, "punkte": mean, "method": "ARS, ganzes Spiel vom Anfang (tools/ki_voll)"})
            write_json(os.path.join(self.lauf, "best.json"), g)
        write_json(os.path.join(self.lauf, "aktuell.json"), self.lay.to_game(self.vec))
        print("PRUEFUNG Runde %d (%d Tage): %.0f Punkte, %s" % (self.round, days, mean, rec["spiele"]), flush=True)

    def one_round(self):
        rnd = self.round + 1
        days = self.days_for(rnd)
        n = int(self.cfg["richtungen"])
        sigma = float(self.cfg["rauschen"])
        self.phase = "Runde %d: %d Spiele über %d Tage" % (rnd, 2 * n, days)
        t0 = time.time()
        dirs = [[self.rng.gauss(0.0, 1.0) for _ in range(self.lay.size)] for _ in range(n)]
        jobs = []
        for k, d in enumerate(dirs):
            seed = rnd * 1000 + k
            jobs.append(([v + sigma * x for v, x in zip(self.vec, d)], days, seed))
            jobs.append(([v - sigma * x for v, x in zip(self.vec, d)], days, seed))
        rs = self.play(jobs, "Runde %d" % rnd)
        if self.stop:
            return False
        pairs = []
        sums = []
        for k in range(n):
            rp, rm = rs[2 * k], rs[2 * k + 1]
            if rp[0] is None or rm[0] is None:
                continue
            pairs.append((max(rp[0], rm[0]), rp[0], rm[0], dirs[k]))
            self.note_seen(rp[1])
            self.note_seen(rm[1])
            sums += [self.summary(rp[1]), self.summary(rm[1])]
        if not pairs:
            print("Runde %d: kein Spiel kam zurück" % rnd, flush=True)
            time.sleep(5)
            return True
        pairs.sort(key=lambda p: -p[0])
        top = pairs[:max(1, n // 2)]
        allr = [p[1] for p in top] + [p[2] for p in top]
        mu = sum(allr) / len(allr)
        sd = math.sqrt(sum((x - mu) ** 2 for x in allr) / len(allr)) or 1.0
        step = [0.0] * self.lay.size
        for _, rp, rm, d in top:
            c = rp - rm
            for i in range(self.lay.size):
                step[i] += c * d[i]
        f = float(self.cfg["lernrate"]) / (len(top) * sd)
        self.vec = [v + f * s for v, s in zip(self.vec, step)]
        self.round = rnd
        scores = [p[1] for p in pairs] + [p[2] for p in pairs]
        rec = {"runde": rnd, "tage": days, "mittel": sum(scores) / len(scores), "bestes": max(scores), "schlechtestes": min(scores),
               "sek": round(time.time() - t0), "spiele": len(scores),
               "forschungen": sum(s["forschungen"] for s in sums) / len(sums), "forschungen_max": max(s["forschungen"] for s in sums),
               "siedler": sum(s["siedler"] for s in sums) / len(sums), "siedler_max": max(s["siedler"] for s in sums),
               "alter_max": max(s["alter"] for s in sums), "tag": sum(s["tag"] for s in sums) / len(sums),
               "inseln_max": max(s["inseln"] for s in sums), "ziel": sum(1 for s in sums if s["ziel"]), "zeit": time.time()}
        self.history.append(rec)
        with open(os.path.join(self.lauf, "verlauf.jsonl"), "a", encoding="utf-8") as fh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print("Runde %d (%d Tage): Mittel %.0f, bestes %.0f, Forschungen bis %d, Siedler bis %d, %d s" % (
            rnd, days, rec["mittel"], rec["bestes"], rec["forschungen_max"], rec["siedler_max"], rec["sek"]), flush=True)
        return True

    def run(self):
        threading.Thread(target=self.status_loop, daemon=True).start()
        if not self.waiting and not any(c.get("stufe", -1) == self.stage for c in self.checks):
            self.check("start")  # erste Prüfung der Stufe: zählt als neues Bestes (andere Spiellänge, andere Wertung)
            self.save_state()
        while not self.stop and not self.waiting and self.round < int(self.cfg["runden"]):
            if not self.one_round():
                break
            if self.round % int(self.cfg["pruefung_alle"]) == 0 and not self.stop:
                self.check("runde")
                if self.stage_reached():
                    self.waiting = True
                    print("STUFE %d geschafft nach Runde %d: wartet auf das Okay" % (self.stage + 1, self.round), flush=True)
            if not self.stop:
                self.save_state()
        self.phase = "Stufe %d geschafft, wartet auf dein Okay" % (self.stage + 1) if self.waiting else "Angehalten"
        write_json(os.path.join(self.lauf, "status.json"), self.status())
        shutil.rmtree(self.tmp, ignore_errors=True)

    def halt(self, *_):
        """Stopp: laufende Spiele beenden; die angefangene Runde wird beim nächsten Start wiederholt."""
        self.stop = True
        with self.lock:
            for p in self.procs.values():
                try:
                    p.kill()
                except Exception:
                    pass


def main():
    ap = argparse.ArgumentParser(description="Training der Insel-KI für das ganze Spiel")
    ap.add_argument("--godot", required=True, help="Pfad zum Programm Godot 4.7.2")
    ap.add_argument("--spiel", default=os.path.join(HERE, "..", "spiel"), help="Ordner mit dem Spiel (project.godot)")
    ap.add_argument("--lauf", default=os.path.join(HERE, "..", "lauf"), help="Ordner für Zustand und Ergebnisse")
    ap.add_argument("--init", default="", help="Startgewichte (Datei wie best.json); ohne: alles 0")
    a = ap.parse_args()
    t = Trainer(a)
    signal.signal(signal.SIGTERM, t.halt)
    signal.signal(signal.SIGINT, t.halt)
    t.run()


if __name__ == "__main__":
    main()
