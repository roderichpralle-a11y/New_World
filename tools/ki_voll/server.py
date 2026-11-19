#!/usr/bin/env python3
"""Oberfläche für das KI-Training (josh 2026-11-15).

Ein kleiner Web-Server, normal nur auf diesem Rechner (127.0.0.1); im Docker mit --host 0.0.0.0 (josh 2026-11-18). Er zeigt im Browser drei Dinge:
  1. den Programmcode (Trainingsprogramm und die KI im Spiel),
  2. den Status des Trainings insgesamt und was gerade läuft,
  3. was die KI gelernt hat (Prüfspiele mit allen Entscheidungen, Vergleich über die Runden, Gewichte in Worten).
Er startet und stoppt außerdem das Trainingsprogramm trainer.py.

Aufruf:  python3 server.py --godot <Pfad zu Godot> [--start] [--open]
Nur Python-Standardbibliothek.
"""
import argparse
import base64
import hmac
import json
import os
import shutil
import signal
import subprocess
import tempfile
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from trainer import local_env, DEFAULTS as T_DEFAULTS  # noqa: E402  (alles Schreiben auf dem Laufwerk des Trainings, josh 2026-11-17)

# Einstellungen, die josh auf der Seite ändern kann (josh 2026-11-18): (Schlüssel, Name, Art, kleinster, größter Wert, Erklärung)
SETTINGS = [
    ("arbeiter", "Spiele gleichzeitig", "int", 0, 64, "0 = Zahl der Prozessorkerne minus 1."),
    ("richtungen", "Richtungen je Runde", "int", 0, 256, "So viele veränderte Fassungen probiert eine Runde aus, jede in 2 Spielen. 0 = so viele wie Spiele gleichzeitig, mindestens 16."),
    ("rauschen", "Rauschen Tabelle", "float", 0.0, 5.0, "Wie stark die Gewichte der Tabelle zum Ausprobieren verändert werden."),
    ("lernrate", "Lernrate Tabelle", "float", 0.0, 5.0, "Wie weit die Gewichte der Tabelle je Runde wandern."),
    ("netz", "Neuronales Netz", "bool", 0, 1, "An: zusätzlich zur Tabelle lernt ein kleines Netz."),
    ("netz_h1", "Netz: Zellen Schicht 1", "int", 1, 256, "Achtung: eine andere Zahl fängt das Netz neu bei null an."),
    ("netz_h2", "Netz: Zellen Schicht 2", "int", 1, 256, "Achtung: eine andere Zahl fängt das Netz neu bei null an."),
    ("netz_rauschen", "Rauschen Netz", "float", 0.0, 5.0, "Wie stark das Netz zum Ausprobieren verändert wird."),
    ("netz_lernrate", "Lernrate Netz", "float", 0.0, 5.0, "Wie weit das Netz je Runde wandert."),
    ("lerne_linear", "Tabelle lernt mit", "bool", 0, 1, "An: mit Netz lernt auch die Tabelle weiter. Aus: die Tabelle bleibt stehen."),
    ("ziel_in_folge", "Ziel in Folge", "int", 1, 1000, "Die Stufe gilt als geschafft, wenn so viele Prüfspiele in Folge das Ziel erreichen."),
    ("tempo_punkte", "Punkte je gesparter Tag", "float", 0.0, 100000.0, "Punkte für jeden Spieltag, den ein Spiel das Ziel früher erreicht."),
    ("stillstand_tage", "Stillstand nach Tagen", "int", 1, 10000, "Ein Spiel endet, wenn so lange nichts Neues entsteht."),
    ("pruefung_alle", "Prüfung alle … Runden", "int", 1, 1000, "Wie oft die festen Prüfspiele laufen."),
    ("pruefung_wuerfel", "Prüfspiele je Prüfung", "int", 5, 100, "Mindestens 5."),
    ("ereignisse", "Ereignisse", "bool", 0, 1, "An: harte Winter, Piraten und andere Ereignisse kommen vor."),
    ("runden", "Runden bis zum Ende", "int", 1, 100000000, "Danach hört das Training von selbst auf. Praktisch: läuft, bis du anhältst."),
    ("saat", "Zufallszahl", "int", 0, 2000000000, "Startwert für den Zufall des Trainings."),
    ("min_frei_gb", "Mindestens frei (GB)", "float", 0.0, 10000.0, "Ist auf dem Laufwerk weniger frei, hält das Training an."),
]

ROOT = os.path.dirname(HERE)

# Die 108 Eingänge der KI (96..107 seit 2026-11-19) (Reihenfolge wie in ki_brain.gd features() und ki_acts.gd more_features())
FEATURES = [
    "Grundneigung (immer)", "Frühling", "Sommer", "Herbst", "Winter", "wie weit die Jahreszeit ist", "Nahrung reicht für viele Tage",
    "viele Beeren im Lager", "viel Fisch im Lager", "viel Weizen im Lager", "viele Äpfel im Lager", "viel Mehl im Lager",
    "viel Brot, Räucherfisch, Eier, Milch, Fleisch", "viel Holz im Lager", "viel Kohle im Lager", "viele Bretter im Lager",
    "viel Stein im Lager", "viel Lehm im Lager", "viel Erz im Lager", "viele Ziegel im Lager", "viele Tontafeln im Lager",
    "Siedler sind satt", "viele Siedler hungrig", "gute Laune", "viele Siedler unzufrieden", "viele Erwachsene", "viele Kinder",
    "Brennstoff reicht für viele Tage", "Lager ist voll", "viele Bäume auf der Insel", "viele Sträucher und Palmen",
    "viele Holzfäller", "viele Steinmetze", "viele Sammler", "viele Fischer", "viele Bauern", "viele Köche", "viele Handwerker",
    "viele Jäger", "eine Forschung läuft", "Forschung ist weit fortgeschritten", "der Forschung fehlt Eisen",
    "der Forschung fehlt Werkzeug", "der Forschung fehlt Kohle", "der Forschung fehlen Bretter", "der Forschung fehlen Ziegel",
    "der Forschung fehlen andere Waren", "viel Eisen im Lager", "viel Werkzeug im Lager", "viele Forscher",
    "freie Betten (Anteil)", "viele Häuser", "viele Baustellen", "viele Felder", "viele Felder je Bauer", "viel Lagerraum",
    "viele Straßen", "eine Werft steht", "viele Schiffe", "freie Schiffe im Hafen", "entdeckte Inseln ohne Siedler",
    "viele besiedelte Inseln", "Häuser können ausgebaut werden", "lange nichts gebaut", "Brennstoff deckt den Winter",
    "Brennstoff über der Winterreserve", "spätes Zeitalter", "hohe Forschungsstufe", "Prüfung: viele Bedingungen offen",
    "Prüfung: es fehlen Siedler", "Prüfung: es fehlen Inseln", "Prüfung: es fehlen Häuser", "viele Droiden", "viel Strom",
    "Funkstation auf dieser Insel", "hohe Stufe der Verwaltung", "es ist die Heimatinsel", "viele wilde Tiere", "Jagdhütten stehen",
    "freie Seeleute", "Schiffe fahren Routen", "viel Elektronik", "viel Gold", "viel Glas und Papier", "viel Stahl und Maschinen",
    "viele Werkstätten", "viele Werkstätten stehen still", "viele Siedler ohne Beruf", "hoher Lebensstil", "viele Anordnungen laufen",
    "viele freie Betten", "hoher Anteil Kinder", "Nebeninsel hat genug Nahrung", "viele Forschungen wählbar", "spät im Spiel",
    "viele Waren an der Höchstmenge",
    # neu 2026-11-19 (josh)
    "zuletzt ist jemand gestorben", "die Nahrung nimmt ab", "Baustellen warten auf Material",
    "Prüfung: es fehlen Tage ohne Hungertod", "Prüfung: es fehlt Vielfalt der Nahrung", "Prüfung: ein Gebäude fehlt",
    "Werkstätten fehlt ein Rohstoff", "Werkstätten fehlt ein Arbeiter", "lange keine Forschung fertig",
    "Piraten angekündigt oder da", "harter Winter", "es fehlt Brot (Forschung oder Prüfung)",
]
ACT_X = ["davon stehen schon viele", "davon steht noch keins", "liefert, was für eine Forschung oder die Prüfung fehlt (auch Vorstufen)", "die vorhandenen sind voll besetzt"]
TECH_F = ["Grundneigung", "hohe Stufe", "teuer (viele Forschungspunkte)", "Kosten liegen im Lager", "es fehlen Waren für die Kosten",
          "liegt auf dem Weg zur Zukunftsstadt", "schaltet Gebäude frei", "schaltet Häuser oder Lager frei", "bringt Vorteile (Effekte)",
          "zählt für die nächste Prüfung", "gehört zur Seefahrt", "viele Forschungen bauen darauf auf"]
ACT_LABELS = {
    "haus": "Haus bauen", "ausbau": "Haus ausbauen", "lager": "Lager bauen", "feld": "Getreidefelder anlegen",
    "obstgarten": "Obstgarten anlegen", "strasse": "Straße bauen", "werft": "Werft bauen", "schiff": "Schiff bauen",
    "erkunden": "Insel erkunden", "besiedeln": "Insel besiedeln", "ausbau_lager": "Lager ausbauen",
    "ausbau_wissen": "Schreibstube ausbauen", "ausbau_amt": "Verwaltung ausbauen", "ausbau_werft": "Werft ausbauen",
    "schmuck": "Schmuck bauen", "setzling": "Bäume nachpflanzen", "gehege": "Gehege mit Jagdhütte anlegen",
    "verwalter": "Verwalter einsetzen", "abriss_werkstatt": "stillstehende Werkstatt abreißen", "abriss_haus": "leeres Haus abreißen",
    "abriss_feld": "überzähliges Feld aufgeben", "versetzen": "Gebäude versetzen", "pause": "Werkstatt anhalten",
    "weiter": "Werkstatt wieder starten", "seemann": "Seemann zuteilen", "fracht_hin": "Schiff mit Waren zu einer Nebeninsel schicken",
    "fracht_her": "Rohstoffe von einer Nebeninsel holen", "route": "Route einrichten", "route_weg": "Route aufheben",
    "limit": "Höchstmenge setzen", "limit_frei": "Höchstmenge aufheben", "reserve": "Reserve erhöhen (nicht verarbeiten)",
    "reserve_weg": "Reserve senken", "nicht_essen": "„Nicht essen“ erhöhen", "nicht_essen_weg": "„Nicht essen“ senken",
}
GROUPS = {
    "berufe": "Berufe", "wohnen": "Wohnraum", "natur": "Natur und Felder", "wege": "Straßen", "forschung": "Forschung", "lager": "Lager",
    "werkstatt": "Gebäude und Werkstätten", "umbau": "Versetzen und Abriss", "arbeitszeit": "Arbeitszeit", "jagd": "Tiere und Jagd",
    "see": "Seefahrt", "routen": "Routen und Fracht", "funk": "Funk", "droiden": "Droiden", "zukunft": "Zukunftsstadt",
}
# Dateien für den Reiter Programmcode: (Pfad ab dem Paket, Titel, Beschreibung)
CODE = [
    ("training/trainer.py", "Trainingsprogramm", "Lässt die KI lernen: verändert die Gewichte, lässt Spiele vom Anfang laufen, zählt die Punkte und schiebt die Gewichte in die bessere Richtung."),
    ("training/server.py", "Oberfläche (Server)", "Dieses Programm: zeigt Code, Status und Gelerntes im Browser und startet oder stoppt das Training."),
    ("training/web/index.html", "Oberfläche (Seite)", "Die Seite, die du gerade siehst."),
    ("spiel/scripts/autoload/ki_brain.gd", "KI im Spiel: Kopf", "Eingänge der KI (was sie von der Insel sieht), Berufe vergeben, Wertung in Punkten."),
    ("spiel/scripts/autoload/ki_acts.gd", "KI im Spiel: Handlungen", "Alle Handlungen (Bauen, Abriss, Lager, Arbeitszeit, Seefahrt ...), die Wahl der Forschung und die Freischalt-Liste."),
    ("spiel/scripts/test/harness.gd", "Spiel ohne Grafik starten", "Testhilfen des Spiels. Die Teile mit „ki“ starten ein Trainingsspiel und schreiben das Ergebnis."),
    ("START.command", "Startdatei für den Mac", "Lädt Godot, bereitet das Spiel vor und startet diese Oberfläche."),
    ("LIESMICH.md", "Anleitung", "Was das Paket enthält und wie du es startest."),
    ("lauf/einstellungen.json", "Einstellungen", "Zahl der gleichzeitigen Spiele, Spiellänge, Lernrate. Änderungen gelten ab dem nächsten Start des Trainings."),
]


def paths(a):
    """Im Paket liegen training/, spiel/, lauf/ nebeneinander; im Repo liegt alles in tools/ki_voll."""
    if os.path.isdir(os.path.join(ROOT, "spiel")):
        return {"root": ROOT, "spiel": os.path.join(ROOT, "spiel"), "lauf": os.path.join(ROOT, "lauf"), "paket": True}
    repo = os.path.dirname(os.path.dirname(HERE))
    return {"root": repo, "spiel": repo, "lauf": a.lauf or os.path.join(HERE, "lauf"), "paket": False}


class App:
    def __init__(self, a):
        self.a = a
        self.p = paths(a)
        os.makedirs(self.p["lauf"], exist_ok=True)
        self.proc = None
        self.lock = threading.Lock()

    # ------------------------------------------------------------ Training starten und stoppen
    def running(self):
        return self.proc is not None and self.proc.poll() is None

    def start(self, durchgaenge=10, stufe=0):
        with self.lock:
            if self.running():
                return "läuft schon"
            log = open(os.path.join(self.p["lauf"], "trainer.log"), "a", encoding="utf-8")
            log.write("\n--- Start %s ---\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
            log.flush()
            cmd = [sys.executable, "-u", os.path.join(HERE, "trainer.py"), "--godot", self.a.godot, "--spiel", self.p["spiel"], "--lauf", self.p["lauf"]]
            if self.a.init:
                cmd += ["--init", self.a.init]
            cmd += ["--durchgaenge", str(max(1, int(durchgaenge))), "--stufe", str(max(0, int(stufe)))]
            log.write("Durchgänge %d, Stufe %s\n" % (int(durchgaenge), stufe or "wie zuletzt"))
            log.flush()
            self.proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=local_env(os.path.join(self.p["lauf"], "arbeit_programm"),
                                         {"INSEL_ALT_TMP": os.environ.get("INSEL_ALT_TMP") or tempfile.gettempdir()}))
            return "gestartet"

    def stop(self):
        with self.lock:
            if not self.running():
                return "läuft nicht"
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(timeout=30)
            except Exception:
                self.proc.kill()
            return "gestoppt"

    # ------------------------------------------------------------ Gelerntes übernehmen (josh 2026-11-16)
    @staticmethod
    def clean_path(text):
        """Macht aus dem, was josh eintippt oder aus dem Finder zieht, einen Pfad."""
        t = (text or "").strip().strip("'\"")
        if t.startswith("file://"):
            from urllib.parse import unquote
            t = unquote(t[7:])
        t = t.replace("\\ ", " ")  # das Terminal schreibt Leerzeichen als "\ "
        return os.path.abspath(os.path.expanduser(t)) if t else ""

    @staticmethod
    def weights_ok(path):
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
            return d if isinstance(d, dict) and (isinstance(d.get("a"), dict) or isinstance(d.get("w"), list)) else None
        except Exception:
            return None

    def find_weights(self, folder):
        """Sucht im Ordner die besten Gewichte: best.json, sonst aktuell.json; auch im Unterordner lauf und bis zu
        drei Ordner tief. Eine Datei darf auch direkt genannt werden."""
        if os.path.isfile(folder):
            return folder if self.weights_ok(folder) else None
        if not os.path.isdir(folder):
            return None
        for name in ("best.json", "aktuell.json"):
            for sub in ("", "lauf"):
                p = os.path.join(folder, sub, name)
                if os.path.isfile(p) and self.weights_ok(p):
                    return p
        base = folder.rstrip(os.sep).count(os.sep)
        for dp, dns, fns in os.walk(folder):
            if dp.count(os.sep) - base >= 3:
                dns[:] = []
            dns[:] = [x for x in dns if x not in ("spiel", "godot", "pruefungen", ".git") and not x.startswith("pruefungen_")]
            if "best.json" in fns and self.weights_ok(os.path.join(dp, "best.json")):
                return os.path.join(dp, "best.json")
        return None

    def do_import(self, text):
        if self.running():
            return {"fehler": "Das Training läuft. Bitte erst Stopp drücken, dann übernehmen."}
        folder = self.clean_path(text)
        if not folder:
            return {"fehler": "Bitte einen Ordner angeben."}
        if not os.path.exists(folder):
            return {"fehler": "Diesen Ordner gibt es nicht: " + folder}
        p = self.find_weights(folder)
        if not p:
            return {"fehler": "In diesem Ordner liegt keine Datei best.json mit Gewichten: " + folder}
        g = self.weights_ok(p)
        tmp = os.path.join(self.p["lauf"], "import.json.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"ordner": folder, "datei": p, "gewichte": g}, f, ensure_ascii=False)
        os.replace(tmp, os.path.join(self.p["lauf"], "import.json"))
        return {"ok": True, "datei": p, "runde": g.get("runde"), "punkte": g.get("punkte"), "netz": isinstance(g.get("netz"), dict)}

    def drop_import(self):
        try:
            os.remove(os.path.join(self.p["lauf"], "import.json"))
        except OSError:
            pass
        return {"ok": True}

    def choose_folder(self):
        """Öffnet auf dem Mac das Fenster zum Wählen eines Ordners."""
        if sys.platform != "darwin":
            return {"fehler": "Das Auswahlfenster gibt es nur auf dem Mac. Bitte den Ordner eintippen" + (" (im Docker: der Pfad im Container, zum Beispiel /insel/import/…)." if os.environ.get("INSEL_DOCKER") else ".")}
        try:
            r = subprocess.run(["osascript", "-e", 'POSIX path of (choose folder with prompt "Ordner mit dem bisherigen Training wählen")'],
                               capture_output=True, text=True, timeout=600)
            path = r.stdout.strip()
            return {"ordner": path} if path else {"abbruch": True}
        except Exception as e:
            return {"fehler": "Das Auswahlfenster ließ sich nicht öffnen (%s). Bitte den Ordner eintippen." % e}

    # ------------------------------------------------------------ Einstellungen ändern (josh 2026-11-18)
    def settings(self):
        p = os.path.join(self.p["lauf"], "einstellungen.json")
        cfg = dict(T_DEFAULTS)
        cfg.update(self.read("einstellungen.json", {}) or {})
        fields = [{"key": k, "name": n, "art": a, "min": lo, "max": hi, "text": t} for k, n, a, lo, hi, t in SETTINGS]
        st = cfg.get("stufen") or T_DEFAULTS["stufen"]
        return {"felder": fields, "werte": {k: cfg.get(k) for k, *_ in SETTINGS}, "stufen": st, "laeuft": self.running(),
                "standard": {k: T_DEFAULTS.get(k) for k, *_ in SETTINGS}, "standard_stufen": T_DEFAULTS["stufen"],
                "datei": p, "ages": (self.read("namen.json", {}) or {}).get("ages", [])}

    def save_settings(self, body):
        """Prüft jeden Wert und schreibt lauf/einstellungen.json. Unbekannte Schlüssel in der Datei bleiben."""
        try:
            new = json.loads(body or "{}")
        except Exception:
            return {"fehler": "Die Werte kamen nicht lesbar an."}
        vals = new.get("werte", {})
        errs = []
        cfg = dict(T_DEFAULTS)
        cfg.update(self.read("einstellungen.json", {}) or {})
        for k, n, a, lo, hi, _t in SETTINGS:
            if k not in vals:
                continue
            v = vals[k]
            try:
                if a == "bool":
                    v = bool(v) if isinstance(v, bool) else str(v).lower() in ("1", "true", "ja", "an")
                elif a == "int":
                    v = int(str(v).replace(",", ".").split(".")[0])
                else:
                    v = float(str(v).replace(",", "."))
            except ValueError:
                errs.append("%s: „%s“ ist keine Zahl." % (n, vals[k]))
                continue
            if a != "bool" and not (lo <= v <= hi):
                errs.append("%s: erlaubt ist %s bis %s." % (n, lo, hi))
                continue
            cfg[k] = v
        stufen = new.get("stufen")
        if isinstance(stufen, list) and stufen:
            out = []
            for i, s in enumerate(stufen):
                try:
                    tage = int(str(s.get("tage")).split(".")[0])
                except (ValueError, AttributeError):
                    errs.append("Stufe %d: Spieltage ist keine Zahl." % (i + 1))
                    continue
                if not 1 <= tage <= 100000:
                    errs.append("Stufe %d: Spieltage erlaubt 1 bis 100000." % (i + 1))
                    continue
                old = (cfg.get("stufen") or T_DEFAULTS["stufen"])
                e = dict(old[i]) if i < len(old) else {}
                e["tage"] = tage
                if not e.get("ziel") and s.get("alter") is not None:
                    try:
                        al = int(str(s.get("alter")).split(".")[0])
                    except ValueError:
                        errs.append("Stufe %d: Zeitalter ist keine Zahl." % (i + 1))
                        continue
                    if not 1 <= al <= 7:
                        errs.append("Stufe %d: Zeitalter erlaubt 1 bis 7." % (i + 1))
                        continue
                    e["alter"] = al
                out.append(e)
            if len(out) == len(stufen):
                cfg["stufen"] = out
        if errs:
            return {"fehler": " ".join(errs)}
        tmp = os.path.join(self.p["lauf"], "einstellungen.json.tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=1, ensure_ascii=False)
        os.replace(tmp, os.path.join(self.p["lauf"], "einstellungen.json"))
        return {"ok": True, "laeuft": self.running()}

    # ------------------------------------------------------------ Spiel ansehen
    def watch(self, which, seed, tempo):
        """Ein Spiel mit Fenster starten: die KI spielt vom Anfang, du siehst zu (Fenster schließen beendet es).
        Gleiche Gewichte und gleiche Würfel wie im Training; ganz genau gleich wird es nicht, weil das Spiel nicht
        in jedem Punkt vorherbestimmt ist."""
        if os.environ.get("INSEL_DOCKER") or (sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and not os.environ.get("WAYLAND_DISPLAY")):
            return "Zusehen braucht einen Bildschirm am Rechner des Trainings. Im Docker geht das nicht; starte es auf dem Mac mit dem gleichen Stand (best.json)."
        g = os.path.join(self.p["lauf"], "best.json" if which == "best" else "aktuell.json")
        if not os.path.exists(g):
            return "Es gibt noch keine Gewichte. Warte auf die erste Prüfung."
        d = os.path.join(self.p["lauf"], "zusehen")
        os.makedirs(d, exist_ok=True)
        w = os.path.join(d, "w.json")
        shutil.copyfile(g, w)
        env = local_env(d, {"KI_LANG": "de"})  # eigener Speicherplatz auf dem Laufwerk: deine Spielstände bleiben unberührt
        cmd = [self.a.godot, "--path", self.p["spiel"], "--", "--autotest=999999", "--scale=%s" % tempo, "--kitrain=1", "--kifull=1",
               "--kiw=" + w, "--kidays=999999", "--kiseed=%d" % seed, "--kiwatch=1", "--kiout=" + os.path.join(d, "r.json")]
        subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return "gestartet"

    # ------------------------------------------------------------ Daten für die Seite
    def read(self, name, default=None):
        try:
            with open(os.path.join(self.p["lauf"], name), encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return default

    def status(self):
        s = self.read("status.json", {}) or {}
        s["laeuft"] = self.running()
        cfg = self.read("einstellungen.json", {}) or {}
        s["netz_an"] = bool(cfg.get("netz", False))
        s["netz_plan"] = [int(cfg.get("netz_h1", 24)), int(cfg.get("netz_h2", 24))]
        w = self.read("import.json")
        s["import_wartet"] = {"ordner": w.get("ordner"), "datei": w.get("datei"), "runde": (w.get("gewichte") or {}).get("runde"),
                              "punkte": (w.get("gewichte") or {}).get("punkte")} if isinstance(w, dict) else None
        s["namen"] = {k: v for k, v in (self.read("namen.json", {}) or {}).items() if k in ("techs_total", "ages", "unlock")}
        try:
            with open(os.path.join(self.p["lauf"], "trainer.log"), encoding="utf-8", errors="replace") as f:
                s["log"] = f.read()[-3000:]
        except Exception:
            s["log"] = ""
        return s

    def code_path(self, rel):
        """Pfad im Paket -> Datei auf der Platte (im Repo liegen die Dateien woanders)."""
        if self.p["paket"]:
            return os.path.join(self.p["root"], rel)
        if rel.startswith("spiel/"):
            return os.path.join(self.p["spiel"], rel[6:])
        if rel.startswith("training/"):
            return os.path.join(HERE, rel[9:])
        if rel.startswith("lauf/"):
            return os.path.join(self.p["lauf"], rel[5:])
        return os.path.join(HERE, rel)

    def files(self):
        out = [{"p": p, "titel": t, "text": d, "haupt": True} for p, t, d in CODE if os.path.exists(self.code_path(p))]
        seen = {e["p"] for e in out}
        for sub in ("scripts", "data"):
            base = os.path.join(self.p["spiel"], sub)
            for dp, _, fns in sorted(os.walk(base)):
                for fn in sorted(fns):
                    if not fn.endswith((".gd", ".json")):
                        continue
                    rel = "spiel/" + os.path.relpath(os.path.join(dp, fn), self.p["spiel"]).replace(os.sep, "/")
                    if rel not in seen:
                        out.append({"p": rel, "titel": rel[6:], "text": "", "haupt": False})
        return out

    def file(self, rel):
        rel = rel.replace("\\", "/")
        if ".." in rel.split("/") or rel.startswith("/"):
            return None
        if rel not in {e["p"] for e in self.files()}:
            return None
        try:
            with open(self.code_path(rel), encoding="utf-8", errors="replace") as f:
                return f.read()
        except Exception:
            return None

    def checks(self):
        d = os.path.join(self.p["lauf"], "pruefungen")
        return sorted(int(f[6:11]) for f in os.listdir(d) if f.startswith("runde_")) if os.path.isdir(d) else []

    def check(self, rnd):
        ids = self.checks()
        if not ids:
            return None
        if rnd not in ids:
            rnd = ids[-1]
        c = self.read(os.path.join("pruefungen", "runde_%05d.json" % rnd))
        if c is None:
            return None
        names = self.read("namen.json", {}) or {}
        c["handlungen"] = [{"name": act_label(k, names), "anzahl": v, "gruppe": GROUPS.get(group_of(k, names), "")}
                           for k, v in sorted(c.get("built", {}).items(), key=lambda kv: -kv[1])]
        tn = self.tech_names()
        c["forschung"] = [tn.get(t, t) for t in c.get("techs", [])]
        c["alle_runden"] = ids
        return c

    def tech_names(self):
        try:
            with open(os.path.join(self.p["spiel"], "data", "techs.json"), encoding="utf-8") as f:
                t = json.load(f)
            return {k: v.get("name", k) for k, v in t.items() if not k.startswith("_")}
        except Exception:
            return {}

    def learned(self, which):
        """Die Gewichte in Worten: je Entscheidung die stärksten Einflüsse."""
        g = self.read("best.json" if which == "best" else "aktuell.json")
        names = self.read("namen.json", {}) or {}
        if not g or not names:
            return {"zeilen": [], "runde": None}
        F = int(names["features"])
        rows = []

        st = self.read("zustand.json", {}) or {}
        seen = st.get("gesehen", [])
        games = max(1, int(st.get("gesehen_spiele", 0)))

        def frac(i):
            """Anteil der Spiele, in denen dieser Eingang je vorkam. Unbekannt (altes Training): 1."""
            return seen[i] / games if i < len(seen) and st.get("gesehen_spiele") else 1.0

        def tops(row, labels, n=5, offset=0):
            # nur Eingänge, die in mindestens 2 % der Spiele vorkamen: nur dort kann etwas gelernt worden sein
            known = [i for i in range(len(row)) if frac(offset + i if offset >= 0 else i) >= 0.02]
            idx = sorted(known, key=lambda i: -abs(row[i]))[:n]
            return [{"was": labels[i] if i < len(labels) else "Eingang %d" % i, "w": round(row[i], 3), "oft": round(frac(i), 2)} for i in idx if abs(row[i]) > 1e-9]

        def unseen(row, labels, n=3):
            idx = sorted([i for i in range(len(row)) if frac(i) < 0.02], key=lambda i: -abs(row[i]))[:n]
            return [{"was": labels[i] if i < len(labels) else "Eingang %d" % i, "w": round(row[i], 3)} for i in idx if abs(row[i]) > 1e-9]
        nz = g.get("netz") if isinstance(g.get("netz"), dict) else None
        nstr = {}
        if nz:  # wie stark das Netz bei dieser Entscheidung mitredet: Größe ihrer Zeile in der letzten Schicht
            h2 = int(nz.get("h2", 0))
            for i, nm in enumerate(nz.get("aus", [])):
                nstr[nm] = norm(list(nz.get("w3", [])[i * h2:(i + 1) * h2]) + list(nz.get("b3", [])[i:i + 1]))
        for j, r in enumerate(g.get("w", [])):
            nm = names["job_names"][j] if j < len(names.get("job_names", [])) else names["jobs"][j]
            rows.append({"gruppe": "Berufe", "name": "Beruf: " + nm, "netz": nstr.get("job:" + names["jobs"][j]), "staerke": norm(r), "einfluss": tops(r, FEATURES), "rauschen": unseen(r, FEATURES)})
        for k, r in g.get("a", {}).items():
            rows.append({"gruppe": GROUPS.get(group_of(k, names), ""), "name": act_label(k, names), "staerke": norm(r), "netz": nstr.get(k),
                         "neigung": round(r[0], 3), "einfluss": tops(r, FEATURES[:len(r) - len(ACT_X)] + ACT_X), "rauschen": unseen(r, FEATURES[:len(r) - len(ACT_X)] + ACT_X)})
        t = g.get("t", [])
        if t:
            rows.append({"gruppe": "Forschung", "name": "Welche Forschung als Nächstes", "staerke": norm(t), "einfluss": [{"was": TECH_F[i], "w": round(t[i], 3), "oft": 1.0} for i in sorted(range(len(t)), key=lambda i: -abs(t[i]))[:8] if abs(t[i]) > 1e-9], "rauschen": []})
        return {"zeilen": rows, "runde": g.get("runde"), "punkte": g.get("punkte"), "spiele": int(st.get("gesehen_spiele", 0)), "netz": bool(nz)}


def norm(r):
    return round(sum(x * x for x in r) ** 0.5, 3)


def group_of(act, names):
    try:
        return names["groups"][names["acts"].index(act)]
    except Exception:
        return ""


def act_label(act, names):
    if act in ACT_LABELS:
        return ACT_LABELS[act]
    jobs = dict(zip(names.get("jobs", []), names.get("job_names", [])))
    if act.startswith("ot:"):
        return "Überstunden: " + jobs.get(act[3:], act[3:])
    if act.startswith("schicht:"):
        return "Schichtarbeit: " + jobs.get(act[8:], act[8:])
    if act.startswith("bau:"):
        try:
            return "Bauen: " + names["act_names"][names["acts"].index(act)]
        except Exception:
            return "Bauen: " + act[4:]
    return act


def make_handler(app, password=""):
    want = ("Basic " + base64.b64encode(("insel:" + password).encode("utf-8")).decode("ascii")) if password else ""

    class H(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def allowed(self):
            """Mit Passwort (INSEL_PASSWORT): der Browser fragt einmal danach (Name: insel)."""
            if not want or hmac.compare_digest(self.headers.get("Authorization") or "", want):
                return True
            self.send_response(401)
            self.send_header("WWW-Authenticate", 'Basic realm="Insel-KI-Training", charset="UTF-8"')
            self.send_header("Content-Length", "0")
            self.end_headers()
            return False

        def send(self, code, body, ctype="application/json; charset=utf-8"):
            data = body if isinstance(body, bytes) else body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def js(self, obj, code=200):
            self.send(code, json.dumps(obj, ensure_ascii=False))

        def do_GET(self):
            if not self.allowed():
                return
            u = urlparse(self.path)
            q = parse_qs(u.query)
            try:
                if u.path in ("/", "/index.html"):
                    with open(os.path.join(HERE, "web", "index.html"), "rb") as f:
                        return self.send(200, f.read(), "text/html; charset=utf-8")
                if u.path == "/api/status":
                    return self.js(app.status())
                if u.path == "/api/dateien":
                    return self.js(app.files())
                if u.path == "/api/datei":
                    t = app.file(q.get("p", [""])[0])
                    return self.js({"text": t}) if t is not None else self.js({"fehler": "Datei nicht gefunden"}, 404)
                if u.path == "/api/pruefung":
                    c = app.check(int(q.get("runde", ["-1"])[0]))
                    return self.js(c if c is not None else {"leer": True})
                if u.path == "/api/einstellungen":
                    return self.js(app.settings())
                if u.path == "/api/gelernt":
                    return self.js(app.learned(q.get("welche", ["aktuell"])[0]))
                return self.js({"fehler": "unbekannt"}, 404)
            except Exception as e:
                return self.js({"fehler": str(e)}, 500)

        def do_POST(self):
            if not self.allowed():
                return
            # Befehle nur von der eigenen Seite (Schutz gegen fremde Webseiten im selben Browser)
            org = self.headers.get("Origin")
            if org and urlparse(org).netloc != (self.headers.get("Host") or ""):
                return self.js({"fehler": "nur von der Seite des Trainings"}, 403)
            if self.path.startswith("/api/start"):
                q = parse_qs(urlparse(self.path).query)
                try:
                    n = int(q.get("durchgaenge", ["10"])[0])
                    st = int(q.get("stufe", ["0"])[0])
                except ValueError:
                    return self.js({"fehler": "Zahl erwartet"}, 400)
                return self.js({"ok": app.start(n, st)})
            if self.path == "/api/einstellungen":
                n = min(int(self.headers.get("Content-Length") or 0), 200000)
                return self.js(app.save_settings(self.rfile.read(n).decode("utf-8", "replace")))
            if self.path.startswith("/api/import_weg"):
                return self.js(app.drop_import())
            if self.path.startswith("/api/import"):
                q = parse_qs(urlparse(self.path).query)
                return self.js(app.do_import(q.get("ordner", [""])[0]))
            if self.path == "/api/ordner":
                return self.js(app.choose_folder())
            if self.path == "/api/stop":
                return self.js({"ok": app.stop()})
            if self.path.startswith("/api/zusehen"):
                q = parse_qs(urlparse(self.path).query)
                return self.js({"ok": app.watch(q.get("welche", ["best"])[0], int(q.get("saat", ["900000"])[0]), q.get("tempo", ["3"])[0])})
            return self.js({"fehler": "unbekannt"}, 404)
    return H


def main():
    ap = argparse.ArgumentParser(description="Oberfläche für das KI-Training")
    ap.add_argument("--godot", required=True, help="Pfad zum Programm Godot 4.7.2")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--lauf", default="", help="Ordner für Zustand und Ergebnisse (nur im Repo nötig)")
    ap.add_argument("--init", default="", help="Startgewichte für ein neues Training")
    ap.add_argument("--start", action="store_true", help="Training sofort starten")
    ap.add_argument("--open", action="store_true", help="Seite im Browser öffnen")
    ap.add_argument("--host", default=os.environ.get("INSEL_HOST", "127.0.0.1"),
                    help="Adresse des Servers; 0.0.0.0 = auch von anderen Rechnern erreichbar (Docker)")
    a = ap.parse_args()
    a.port = int(os.environ.get("INSEL_PORT", a.port))
    app = App(a)
    pw = os.environ.get("INSEL_PASSWORT", "")
    srv = ThreadingHTTPServer((a.host, a.port), make_handler(app, pw))
    url = "http://%s:%d/" % ("127.0.0.1" if a.host in ("0.0.0.0", "::") else a.host, a.port)
    print("Oberfläche: %s   (Fenster offen lassen, Strg+C beendet alles)" % url, flush=True)
    if a.host not in ("127.0.0.1", "localhost", "::1"):
        print("Erreichbar auf allen Netzwerkadressen dieses Rechners, Port %d. Passwort: %s" % (a.port, "an (Name insel)" if pw else "AUS"), flush=True)
    if a.start:
        app.start()
    if a.open:
        threading.Timer(1.0, lambda: webbrowser.open(url)).start()

    def bye(*_):
        app.stop()
        os._exit(0)
    signal.signal(signal.SIGINT, bye)
    signal.signal(signal.SIGTERM, bye)
    srv.serve_forever()


if __name__ == "__main__":
    main()
