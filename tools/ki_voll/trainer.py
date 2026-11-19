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
feste Spiellänge. josh wählt beim Start die Stufe und wie viele Durchgänge (Runden) laufen sollen
(josh 2026-11-16); danach hält das Training an. Die Gewichte bleiben über alle Starts und Stufen erhalten. Ein Spiel endet früher, wenn die Zukunftsstadt steht, alle tot
sind oder sich stillstand_tage lang nichts mehr tut.

Kleines neuronales Netz (josh 2026-11-16, Einstellung "netz": true): zu den Gewichten kommt ein Netz mit zwei
verdeckten Schichten (Eingänge -> netz_h1 -> netz_h2 -> eine Korrektur je Handlung und Beruf). Die Korrektur
wird zum Wert der Tabelle addiert. Am Anfang ist die letzte Schicht 0: die KI spielt genau wie die Tabelle.
Gelernt wird dann nur das Netz (gleiches Verfahren), die Tabelle bleibt stehen, solange sie nicht leer ist
("lerne_linear": true lässt beide lernen). Import: liegt in lauf/ eine Datei import.json (die Oberfläche legt
sie an, wenn josh einen Ordner nennt), übernimmt der nächste Start deren Gewichte und beginnt neu zu zählen.

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
    # (12 Tage = 1 Spieljahr). Welche Stufe trainiert wird, wählt josh beim Start (--stufe).
    # "alter": mindestens dieses Zeitalter (0 = Steinzeit), "ziel": Zukunftsstadt gebaut.
    "stufen": [
        {"alter": 1, "tage": 80}, {"alter": 2, "tage": 180}, {"alter": 3, "tage": 300}, {"alter": 4, "tage": 450},
        {"alter": 5, "tage": 600}, {"alter": 6, "tage": 800}, {"alter": 7, "tage": 1000}, {"ziel": True, "tage": 1400}],
    "ziel_in_folge": 10,      # die Stufe ist geschafft, wenn so viele Prüfspiele in Folge das Ziel erreichen (josh 2026-11-16)
    "tempo_punkte": 300,      # Punkte je Spieltag, den ein Spiel das Ziel der Stufe früher erreicht (schneller ist besser)
    "stillstand_tage": 40,    # Spiel endet, wenn so lange nichts Neues entsteht
    "pruefung_alle": 4,       # alle so viele Runden eine Prüfung
    "pruefung_wuerfel": 5,    # Prüfspiele je Prüfung (mindestens 5)
    "ereignisse": True,       # mit Ereignissen (harte Winter, Piraten ...)
    "runden": 100000,         # Ende des Trainings (praktisch: läuft, bis du stoppst)
    "saat": 7,
    "min_frei_gb": 2,         # weniger freier Platz auf dem Laufwerk des Trainings: das Training hält an
    # kleines neuronales Netz (josh 2026-11-16)
    "netz": False,            # true: zusätzlich zur Tabelle lernt ein kleines Netz
    "netz_h1": 24,            # Zellen der ersten verdeckten Schicht
    "netz_h2": 24,            # Zellen der zweiten verdeckten Schicht
    "netz_rauschen": 0.1,     # wie stark das Netz zum Ausprobieren verändert wird
    "netz_lernrate": 0.03,    # wie weit das Netz je Runde wandert
    "lerne_linear": False,    # false: mit Netz bleibt die Tabelle stehen (außer sie ist noch leer)
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
    cfg["pruefung_wuerfel"] = max(5, int(cfg["pruefung_wuerfel"]))
    if int(cfg["richtungen"]) <= 0:
        cfg["richtungen"] = max(16, int(cfg["arbeiter"]))
    return cfg


def local_env(base, extra=None):
    """Umgebung für Godot (josh 2026-11-17): alles, was Godot oder macOS sonst im Benutzerordner oder im
    Temp-Ordner des Systemlaufwerks ablegt (Spielstände, Protokolle, Einstellungen, Zwischenspeicher, Temp),
    landet unter base, also auf dem Laufwerk, auf dem das Training liegt."""
    e = dict(os.environ)
    for k, sub in (("XDG_DATA_HOME", "daten"), ("XDG_CONFIG_HOME", "einstellungen"), ("XDG_CACHE_HOME", "cache"), ("TMPDIR", "tmp")):
        p = os.path.join(base, sub)
        os.makedirs(p, exist_ok=True)
        e[k] = p
    e["TMP"] = e["TEMP"] = e["TMPDIR"]
    if extra:
        e.update(extra)
    return e


def move_old_temp(lauf):
    """Holt Arbeitsordner früherer Trainings (insel_ki_*) aus dem Temp-Ordner des Systemlaufwerks in
    lauf/alte_temp_dateien. Gibt die Zahl der verschobenen Ordner zurück."""
    found = 0
    places = {os.environ.get("INSEL_ALT_TMP", ""), tempfile.gettempdir(), "/tmp", "/private/tmp"}
    dest = os.path.join(lauf, "alte_temp_dateien")
    for place in places:
        if not place or not os.path.isdir(place) or os.path.realpath(place).startswith(os.path.realpath(lauf)):
            continue
        try:
            names = os.listdir(place)
        except OSError:
            continue
        for n in names:
            src = os.path.join(place, n)
            if not n.startswith("insel_ki_") or not os.path.isdir(src):
                continue
            try:
                os.makedirs(dest, exist_ok=True)
                shutil.move(src, os.path.join(dest, n))
                found += 1
                print("Alte Trainingsdateien vom Systemlaufwerk verschoben: %s -> %s" % (src, dest), flush=True)
            except Exception as e:
                print("Konnte %s nicht verschieben: %s" % (src, e), flush=True)
    return found


def write_json(path, data):
    """Erst in eine Nebendatei schreiben, dann umbenennen: die Oberfläche liest nie eine halbe Datei."""
    tmp = "%s.%d.tmp" % (path, threading.get_ident())  # eigene Nebendatei je Faden: zwei Schreiber stören sich nicht
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
        self.outs = list(self.acts) + ["job:" + j for j in self.jobs]  # Ausgänge des Netzes

    # ---- kleines neuronales Netz: flache Liste = w1, b1, w2, b2, w3, b3
    def net_size(self, h1, h2):
        return h1 * self.F + h1 + h2 * h1 + h2 + len(self.outs) * h2 + len(self.outs)

    def net_new(self, h1, h2, rng):
        """Erste und zweite Schicht zufällig klein, letzte Schicht 0: das Netz ändert am Anfang nichts."""
        s1, s2 = 1.0 / math.sqrt(self.F), 1.0 / math.sqrt(h1)
        n = len(self.outs)
        return ([rng.gauss(0.0, s1) for _ in range(h1 * self.F)] + [0.0] * h1 +
                [rng.gauss(0.0, s2) for _ in range(h2 * h1)] + [0.0] * h2 + [0.0] * (n * h2 + n))

    def net_to_game(self, net, h1, h2):
        n = len(self.outs)
        cut = [h1 * self.F, h1, h2 * h1, h2, n * h2, n]
        parts = []
        i = 0
        for c in cut:
            parts.append(net[i:i + c])
            i += c
        return {"h1": h1, "h2": h2, "aus": self.outs, "w1": parts[0], "b1": parts[1], "w2": parts[2], "b2": parts[3],
                "w3": parts[4], "b3": parts[5]}

    def net_from_game(self, d, h1, h2, f_old=None):
        """Netz aus einer Gewichtsdatei, wenn es passt (gleiche Größe, gleiche Ausgänge). Sonst None.
        Hat die Datei weniger Eingänge (f_old, ältere Fassung), bekommen die neuen Eingänge das Gewicht 0."""
        if not isinstance(d, dict) or int(d.get("h1", 0)) != h1 or int(d.get("h2", 0)) != h2 or list(d.get("aus", [])) != self.outs:
            return None
        w1 = list(d.get("w1", []))
        fo = int(f_old or 0)
        if fo and fo < self.F and len(w1) == h1 * fo:
            w1 = [r for j in range(h1) for r in (self.fix_old(w1[j * fo:(j + 1) * fo], fo) + [0.0] * (self.F - fo))]
        net = w1
        for k in ("b1", "w2", "b2", "w3", "b3"):
            net += list(d.get(k, []))
        return net if len(net) == self.net_size(h1, h2) else None

    F_OLD = 96  # Eingänge bis 2026-11-18; Eingang 70 war damals immer 0 (Prüfung: Inseln, falscher Name)

    @staticmethod
    def file_f(d):
        """Zahl der Eingänge einer Gewichtsdatei: "f", sonst die Länge der ersten Berufszeile."""
        rows = d.get("w", []) if isinstance(d, dict) else []
        return int(d.get("f") or (len(rows[0]) if rows else 0)) if isinstance(d, dict) else 0

    def fix_old(self, row, fo):
        row = list(row)
        if fo == self.F_OLD and len(row) > 70:
            row[70] = 0.0
        return row

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
        return {"w": w, "a": a, "t": vec[i:i + self.T], "full": True, "f": F}

    def from_game(self, d):
        """Gewichtsdatei -> flache Liste (fehlende Zeilen und Eingänge sind 0)."""
        F, X = self.F, self.X
        fo = self.file_f(d) or F
        vec = []
        rows = d.get("w", [])
        for j in range(len(self.jobs)):
            r = self.fix_old(rows[j], fo) if j < len(rows) else []
            vec += (r + [0.0] * F)[:F]
        old = ["haus", "ausbau", "lager", "feld", "obstgarten", "strasse", "werft", "schiff", "erkunden", "besiedeln"]
        a = {old[i]: r for i, r in enumerate(d.get("b", [])[:len(old)])}
        a.update(d.get("a", {}))
        for n in self.acts:
            r = self.fix_old(a.get(n, []), fo)
            if fo < F and len(r) == fo + X:  # ältere Datei: Eingänge der Insel, dann die der Handlung
                r = r[:fo] + [0.0] * (F - fo) + r[fo:]
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
        # Arbeitsordner auf dem Laufwerk des Trainings, nicht im Temp-Ordner des Systems (josh 2026-11-17)
        move_old_temp(self.lauf)
        self.tmp = os.path.join(self.lauf, "arbeit")
        shutil.rmtree(self.tmp, ignore_errors=True)
        os.makedirs(self.tmp, exist_ok=True)
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
        self.waiting = False  # alt (Stufe geschafft); wird nicht mehr benutzt
        self.goal = 0         # so viele Durchgänge laufen in diesem Start (josh 2026-11-16)
        self.start_round = 0
        self.net_on = bool(self.cfg["netz"])
        self.h1 = max(1, int(self.cfg["netz_h1"]))
        self.h2 = max(1, int(self.cfg["netz_h2"]))
        self.net = []         # Zahlen des Netzes (leer = kein Netz)
        self.imp = None       # woher die Gewichte übernommen wurden
        self.lin_free = False  # die Tabelle war beim ersten Start leer: sie lernt neben dem Netz mit
        self.load_state(a.init)
        self.take_import()
        if self.net_on and len(self.net) != self.lay.net_size(self.h1, self.h2):
            self.net = self.lay.net_new(self.h1, self.h2, self.rng)
        # die Tabelle lernt mit, wenn kein Netz da ist, wenn es so eingestellt ist oder wenn sie noch leer ist
        # (nichts importiert und noch keine Runde gelernt)
        self.learn_lin = (not self.net_on) or bool(self.cfg["lerne_linear"]) or not any(self.vec) or bool(self.lin_free)
        if a.stufe >= 1:
            self.stage = min(a.stufe - 1, len(self.cfg["stufen"]) - 1)
        self.waiting = False
        self.start_round = self.round
        self.goal = max(1, int(a.durchgaenge))

    # ------------------------------------------------------------ Spiel starten
    def env(self, slot):
        return local_env(os.path.join(self.tmp, "platz_%d" % slot), {"KI_LANG": "de"})  # eigener Speicherplatz je Spiel

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
        try:
            for p in (out, prog):
                if os.path.exists(p):
                    os.remove(p)
            with open(wpath, "w") as f:
                json.dump(self.game(vec), f)
        except OSError as e:
            print("  Spiel nicht gestartet (Platz %d): %s" % (slot, e), file=sys.stderr, flush=True)
            return None, None
        cmd = [self.godot, "--headless", "--fixed-fps", "60", "--path", self.spiel, "--", "--autotest=999999", "--scale=10",
               "--kitrain=1", "--kifull=1", "--kiw=" + wpath, "--kidays=%d" % days, "--kiseed=%d" % seed,
               "--kistall=%d" % int(self.cfg["stillstand_tage"]), "--kiprog=" + prog, "--kiout=" + out]
        st = self.cfg["stufen"][self.stage]
        if not st.get("ziel"):
            cmd.append("--kigoalage=%d" % int(st.get("alter", 0)))  # das Spiel endet, sobald das Ziel der Stufe erreicht ist
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
            # schneller ist besser: jeder Spieltag, den das Ziel früher erreicht ist, bringt Punkte
            res["score_spiel"] = float(res["score"])
            if self.stage_ok({"alter": res.get("age", 0), "ziel": res.get("goal", False)}):
                left = max(0.0, float(days) - float(res.get("day", days)))
                res["score"] = float(res["score"]) + float(self.cfg["tempo_punkte"]) * left
                res["ziel_tag"] = round(float(res.get("day", days)), 1)
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

    def game(self, pair):
        """(Tabelle, Netz) -> Gewichtsdatei für das Spiel."""
        g = self.lay.to_game(pair[0])
        if self.net_on and pair[1]:
            g["netz"] = self.lay.net_to_game(pair[1], self.h1, self.h2)
        return g

    def take_import(self):
        """Liegt lauf/import.json da (von der Oberfläche), werden deren Gewichte übernommen. Das Zählen beginnt neu;
        der alte Stand bleibt als zustand_vor_import_<Zeit>.json liegen."""
        p = os.path.join(self.lauf, "import.json")
        if not os.path.exists(p):
            return
        try:
            d = json.load(open(p, encoding="utf-8"))
            g = d.get("gewichte", d)
            vec = self.lay.from_game(g)
        except Exception as e:
            print("Import nicht lesbar:", e, flush=True)
            os.replace(p, os.path.join(self.lauf, "import_fehler.json"))
            return
        stamp = time.strftime("%Y%m%d_%H%M%S")
        old = os.path.join(self.lauf, "zustand.json")
        if os.path.exists(old):
            shutil.move(old, os.path.join(self.lauf, "zustand_vor_import_%s.json" % stamp))
        pr = os.path.join(self.lauf, "pruefungen")
        if os.path.isdir(pr) and os.listdir(pr):
            shutil.move(pr, os.path.join(self.lauf, "pruefungen_vor_import_%s" % stamp))
            os.makedirs(pr, exist_ok=True)
        self.vec = vec
        net = self.lay.net_from_game(g.get("netz"), self.h1, self.h2, self.lay.file_f(g)) if self.net_on else None
        self.net = net or []
        self.round = 0
        self.lin_free = False
        self.history = []
        self.checks = []
        self.best = {"mittel": -1e18, "runde": 0}
        self.seen = [0] * (self.lay.F + self.lay.X)
        self.seen_games = 0
        self.imp = {"ordner": d.get("ordner", ""), "datei": d.get("datei", ""), "runde": g.get("runde"), "punkte": g.get("punkte"),
                    "zeit": time.time(), "netz": bool(net), "zahlen": sum(1 for x in vec if x)}
        os.replace(p, os.path.join(self.lauf, "import_erledigt.json"))
        print("IMPORT: Gewichte aus %s übernommen (%d Zahlen ungleich 0%s)" % (
            d.get("datei", p), self.imp["zahlen"], ", mit Netz" if net else ""), flush=True)

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
            self.upgrade_state(s)
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
                self.net = s.get("netz", []) or []
                self.imp = s.get("import")
                self.lin_free = bool(s.get("tabelle_frei", False))
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

    def upgrade_state(self, s):
        """zustand.json einer älteren Fassung mit weniger Eingängen (96 bis 2026-11-18): Tabelle, Netz und
        Zähler an der richtigen Stelle mit Nullen erweitern. Das Spiel rechnet danach genau wie vorher."""
        fo = int(s.get("f") or self.lay.F_OLD)
        if fo >= self.lay.F or len(s.get("vec", [])) == self.lay.size:
            return
        old = Layout({"jobs": self.lay.jobs, "acts": self.lay.acts, "features": fo, "act_x": self.lay.X, "tech_f": self.lay.T})
        if len(s.get("vec", [])) != old.size:
            return
        g = old.to_game(s["vec"])
        s["vec"] = self.lay.from_game(g)
        net = s.get("netz") or []
        if net:
            if self.h1 and old.net_size(self.h1, self.h2) == len(net):
                s["netz"] = self.lay.net_from_game(old.net_to_game(net, self.h1, self.h2), self.h1, self.h2, fo) or []
            else:
                s["netz"] = []
                print("Netz in zustand.json passt nicht zu netz_h1/netz_h2: das Netz fängt neu an", flush=True)
        seen = s.get("gesehen", [])
        if len(seen) == fo + self.lay.X:
            s["gesehen"] = seen[:fo] + [0] * (self.lay.F - fo) + seen[fo:]
        print("zustand.json von %d auf %d Eingänge erweitert (neue Gewichte 0)" % (fo, self.lay.F), flush=True)

    def save_state(self):
        st = self.rng.getstate()
        write_json(os.path.join(self.lauf, "zustand.json"), {
            "runde": self.round, "vec": self.vec, "verlauf": self.history, "pruefungen": self.checks, "best": self.best,
            "sek": self.secs_total + (time.time() - self.t_start), "spiele": self.games_total,
            "gesehen": self.seen, "gesehen_spiele": self.seen_games, "stufe": self.stage, "wartet": self.waiting,
            "netz": self.net, "import": self.imp, "tabelle_frei": self.learn_lin and self.net_on,
            "zufall": [st[0], list(st[1]), st[2]], "f": self.lay.F})

    def days_for(self, rnd):
        return int(self.cfg["stufen"][self.stage]["tage"])

    def stage_ok(self, game):
        """Schafft dieses Prüfspiel das Ziel der Stufe?"""
        st = self.cfg["stufen"][self.stage]
        if st.get("ziel"):
            return bool(game.get("ziel"))
        return int(game.get("alter", 0)) >= int(st.get("alter", 0))

    def stage_reached(self):
        n = int(self.cfg["ziel_in_folge"])
        games = [g for c in self.checks if c.get("stufe", -1) == self.stage for g in c["spiele"]]
        return len(games) >= n and all(self.stage_ok(g) for g in games[-n:])

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
                "stufe": self.stage, "wartet": False, "stufen": self.cfg["stufen"],
                "netz": {"an": self.net_on, "h1": self.h1, "h2": self.h2, "zahlen": len(self.net) if self.net_on else 0,
                         "tabelle_lernt": self.learn_lin, "ausschlag": self.net_reach()},
                "import": self.imp,
                "durchgaenge": self.goal, "durchgang": self.round - self.start_round, "erreicht": self.stage_reached(), "ziel_in_folge": int(self.cfg["ziel_in_folge"])}

    def net_reach(self):
        """Wie viel das Netz schon gelernt hat: mittlere Größe der Zahlen der letzten Schicht (am Anfang 0)."""
        if not (self.net_on and self.net):
            return 0.0
        n = len(self.lay.outs)
        last = self.net[-(n * self.h2 + n):]
        return round(math.sqrt(sum(x * x for x in last) / len(last)), 4)

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
                "stillstand": bool(res.get("stalled", False)), "ende": bool(res.get("over", False)), "ziel_tag": res.get("ziel_tag")}

    def check(self, tag):
        """Prüfung: die jetzigen Gewichte spielen mit festen Würfeln. Das erste Prüfspiel wird ganz gespeichert."""
        self.phase = "Prüfung nach Runde %d" % self.round
        days = self.days_for(max(1, self.round))
        # zwei Sätze fester Würfel im Wechsel: "10 in Folge" sind so 10 verschiedene Spiele
        nw = int(self.cfg["pruefung_wuerfel"])
        base = 900000 + nw * ((self.round // max(1, int(self.cfg["pruefung_alle"]))) % 2)
        seeds = [base + i for i in range(nw)]
        rs = self.play([((self.vec, self.net), days, s) for s in seeds], "Prüfung")
        ok = [r for r in rs if r[0] is not None]
        if not ok:
            return
        for r in ok:
            self.note_seen(r[1])
        mean = sum(r[0] for r in ok) / len(ok)
        per_day = mean / max(1.0, float(days))  # mit Tempo-Punkten, auf die Länge der Stufe bezogen
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
            g = self.game((self.vec, self.net))
            g.update({"runde": self.round, "tage": days, "punkte": mean, "method": "ARS, ganzes Spiel vom Anfang (tools/ki_voll)" + (", mit kleinem neuronalen Netz" if self.net_on else "")})
            write_json(os.path.join(self.lauf, "best.json"), g)
        write_json(os.path.join(self.lauf, "aktuell.json"), self.game((self.vec, self.net)))
        print("PRUEFUNG Runde %d (%d Tage): %.0f Punkte, %s" % (self.round, days, mean, rec["spiele"]), flush=True)

    def one_round(self):
        rnd = self.round + 1
        days = self.days_for(rnd)
        n = int(self.cfg["richtungen"])
        sigma = float(self.cfg["rauschen"])
        self.phase = "Runde %d: %d Spiele über %d Tage" % (rnd, 2 * n, days)
        t0 = time.time()
        # eine Richtung = (Teil für die Tabelle, Teil für das Netz); ein Teil, der nicht lernt, bleibt leer
        nsig = float(self.cfg["netz_rauschen"])
        net = self.net if self.net_on else []
        dirs = [([self.rng.gauss(0.0, 1.0) for _ in range(self.lay.size)] if self.learn_lin else [],
                 [self.rng.gauss(0.0, 1.0) for _ in range(len(net))]) for _ in range(n)]

        def moved(base, d, s):
            return [v + s * x for v, x in zip(base, d)] if d else base
        jobs = []
        for k, d in enumerate(dirs):
            seed = rnd * 1000 + k
            jobs.append(((moved(self.vec, d[0], sigma), moved(net, d[1], nsig)), days, seed))
            jobs.append(((moved(self.vec, d[0], -sigma), moved(net, d[1], -nsig)), days, seed))
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
        for part, rate in ((0, float(self.cfg["lernrate"])), (1, float(self.cfg["netz_lernrate"]))):
            size = len(top[0][3][part])
            if not size:
                continue
            step = [0.0] * size
            for _, rp, rm, d in top:
                c = rp - rm
                dd = d[part]
                for i in range(size):
                    step[i] += c * dd[i]
            f = rate / (len(top) * sd)
            if part == 0:
                self.vec = [v + f * s for v, s in zip(self.vec, step)]
            else:
                self.net = [v + f * s for v, s in zip(self.net, step)]
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
        if not any(c.get("stufe", -1) == self.stage for c in self.checks):
            self.check("start")  # erste Prüfung der Stufe: zählt als neues Bestes (andere Spiellänge, andere Wertung)
            self.save_state()
        end = self.start_round + self.goal
        while not self.stop and self.round < end:
            if self.disk_full():
                break
            try:
                if not self.one_round():
                    break
            except OSError as e:
                self.phase = "Angehalten: Schreibfehler (%s). Bitte freien Platz prüfen, dann wieder Start." % e
                print(self.phase, flush=True)
                self.stop = True
                break
            last = self.round >= end
            if (self.round % int(self.cfg["pruefung_alle"]) == 0 or last) and not self.stop:
                self.check("runde")
                if self.stage_reached():
                    print("STUFE %d: Ziel %d mal in Folge erreicht (Runde %d)" % (self.stage + 1, int(self.cfg["ziel_in_folge"]), self.round), flush=True)
            if not self.stop:
                self.save_state()
        done = self.round - self.start_round
        if self.phase.startswith("Angehalten:"):
            write_json(os.path.join(self.lauf, "status.json"), self.status())
            shutil.rmtree(self.tmp, ignore_errors=True)
            return
        self.phase = ("Fertig: %d von %d Durchgängen" % (done, self.goal)) if done >= self.goal else ("Angehalten nach %d von %d Durchgängen" % (done, self.goal))
        write_json(os.path.join(self.lauf, "status.json"), self.status())
        shutil.rmtree(self.tmp, ignore_errors=True)

    def disk_full(self):
        """Zu wenig Platz auf dem Laufwerk des Trainings: sauber anhalten (der Stand bis zur letzten Runde bleibt)."""
        try:
            free = shutil.disk_usage(self.lauf).free / 1e9
        except OSError:
            return False
        if free >= float(self.cfg.get("min_frei_gb", 2)):
            return False
        self.phase = "Angehalten: auf dem Laufwerk des Trainings sind nur noch %.1f GB frei (nötig %.0f GB)" % (free, float(self.cfg.get("min_frei_gb", 2)))
        print(self.phase, flush=True)
        return True

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
    ap.add_argument("--durchgaenge", type=int, default=10, help="so viele Durchgänge (Runden) laufen, dann hält das Training an")
    ap.add_argument("--stufe", type=int, default=0, help="Stufe 1 bis 8 (0 = wie zuletzt)")
    a = ap.parse_args()
    t = Trainer(a)
    signal.signal(signal.SIGTERM, t.halt)
    signal.signal(signal.SIGINT, t.halt)
    t.run()


if __name__ == "__main__":
    main()
