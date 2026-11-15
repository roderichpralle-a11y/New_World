#!/usr/bin/env python3
"""Oberfläche für das KI-Training (josh 2026-11-15).

Ein kleiner Web-Server nur auf diesem Rechner (127.0.0.1). Er zeigt im Browser drei Dinge:
  1. den Programmcode (Trainingsprogramm und die KI im Spiel),
  2. den Status des Trainings insgesamt und was gerade läuft,
  3. was die KI gelernt hat (Prüfspiele mit allen Entscheidungen, Vergleich über die Runden, Gewichte in Worten).
Er startet und stoppt außerdem das Trainingsprogramm trainer.py.

Aufruf:  python3 server.py --godot <Pfad zu Godot> [--start] [--open]
Nur Python-Standardbibliothek.
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Die 96 Eingänge der KI (Reihenfolge wie in ki_brain.gd features() und ki_acts.gd more_features())
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
]
ACT_X = ["davon stehen schon viele", "davon steht noch keins", "wird gerade gebraucht (Forschung oder Prüfung)", "die vorhandenen sind voll besetzt"]
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

    def start(self):
        with self.lock:
            if self.running():
                return "läuft schon"
            log = open(os.path.join(self.p["lauf"], "trainer.log"), "a", encoding="utf-8")
            log.write("\n--- Start %s ---\n" % time.strftime("%Y-%m-%d %H:%M:%S"))
            log.flush()
            cmd = [sys.executable, "-u", os.path.join(HERE, "trainer.py"), "--godot", self.a.godot, "--spiel", self.p["spiel"], "--lauf", self.p["lauf"]]
            if self.a.init:
                cmd += ["--init", self.a.init]
            self.proc = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
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

        def tops(row, labels, n=5):
            idx = sorted(range(len(row)), key=lambda i: -abs(row[i]))[:n]
            return [{"was": labels[i] if i < len(labels) else "Eingang %d" % i, "w": round(row[i], 3)} for i in idx if abs(row[i]) > 1e-9]
        for j, r in enumerate(g.get("w", [])):
            nm = names["job_names"][j] if j < len(names.get("job_names", [])) else names["jobs"][j]
            rows.append({"gruppe": "Berufe", "name": "Beruf: " + nm, "staerke": norm(r), "einfluss": tops(r, FEATURES)})
        for k, r in g.get("a", {}).items():
            rows.append({"gruppe": GROUPS.get(group_of(k, names), ""), "name": act_label(k, names), "staerke": norm(r),
                         "neigung": round(r[0], 3), "einfluss": tops(r, FEATURES[:F] + ACT_X)})
        t = g.get("t", [])
        if t:
            rows.append({"gruppe": "Forschung", "name": "Welche Forschung als Nächstes", "staerke": norm(t), "einfluss": tops(t, TECH_F, 8)})
        return {"zeilen": rows, "runde": g.get("runde"), "punkte": g.get("punkte")}


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


def make_handler(app):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

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
                if u.path == "/api/gelernt":
                    return self.js(app.learned(q.get("welche", ["aktuell"])[0]))
                return self.js({"fehler": "unbekannt"}, 404)
            except Exception as e:
                return self.js({"fehler": str(e)}, 500)

        def do_POST(self):
            if self.headers.get("Origin") and "127.0.0.1" not in self.headers.get("Origin") and "localhost" not in self.headers.get("Origin"):
                return self.js({"fehler": "nur von diesem Rechner"}, 403)
            if self.path == "/api/start":
                return self.js({"ok": app.start()})
            if self.path == "/api/stop":
                return self.js({"ok": app.stop()})
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
    a = ap.parse_args()
    app = App(a)
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), make_handler(app))
    url = "http://127.0.0.1:%d/" % a.port
    print("Oberfläche: %s   (Fenster offen lassen, Strg+C beendet alles)" % url, flush=True)
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
