#!/usr/bin/env python3
"""Training der lernenden KI für die Berufswahl (josh 2026-11-07).

Augmented Random Search (ARS, Mania, Guy, Recht 2018): eine lineare Strategie (8 Berufe x 39 Eingänge,
scripts/autoload/ki_brain.gd) wird zufällig in N Richtungen gestört, jede Störung spielt einmal +Richtung und
einmal -Richtung mit denselben Würfeln (--kiseed), das Spiel läuft ohne Grafik ab einem Spielstand. Die besten b
Richtungen schieben die Gewichte dorthin, wo mehr Punkte kamen.

Aufruf:
  python3 tools/ki_train/train.py --save spielstand.json --days 3 --iters 40 --out run1
  python3 tools/ki_train/train.py --save spielstand.json --days 12 --iters 20 --init run1/best.json --out run2
Ergebnis: <out>/best.json (Gewichte, beste Prüfung), <out>/log.jsonl (je Runde), <out>/evals.jsonl.
"""
import argparse
import json
import os
import random
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

JOBS = 9
FEAT = 50
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def run_episode(godot, save, weights, days, seed, slot, kioff=False, timeout=3600, events=False):
    """Ein Spiel ohne Grafik; gibt (Punkte, Ergebnis) zurück."""
    tmp = tempfile.mkdtemp(prefix="ki_")
    wpath = os.path.join(tmp, "w.json")
    out = os.path.join(tmp, "r.json")
    with open(wpath, "w") as f:
        json.dump({"w": weights, "info": "train"}, f)
    env = dict(os.environ)
    env["XDG_DATA_HOME"] = os.path.join(tempfile.gettempdir(), "ki_slot_%d" % slot)  # eigener Speicherplatz je Prozess
    cmd = [godot, "--headless", "--fixed-fps", "60", "--path", os.environ.get("KI_ROOT", ROOT), "--", "--autotest=999999", "--scale=10",
           "--fixture=" + save, "--kitrain=1", "--kiw=" + wpath, "--kidays=%d" % days,
           "--kiseed=%d" % seed, "--kiout=" + out]
    if kioff:
        cmd.append("--kioff=1")
    if not events:
        cmd.append("--noevents=1")
    try:
        subprocess.run(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=timeout)
        with open(out) as f:
            res = json.load(f)
        return float(res["score"]), res
    except Exception as e:  # abgestürzt oder zu langsam: schlechteste Wertung, damit die Richtung nicht gewinnt
        print("  Lauf fehlgeschlagen:", e, file=sys.stderr)
        return None, None


class Pool:
    def __init__(self, n):
        self.n = n
        self.ex = ThreadPoolExecutor(max_workers=n)
        self.slots = list(range(n))
        self.lock = __import__("threading").Lock()

    def map(self, fn, jobs):
        def wrap(j):
            with self.lock:
                slot = self.slots.pop()
            try:
                return fn(slot, *j)
            finally:
                with self.lock:
                    self.slots.append(slot)
        return list(self.ex.map(wrap, jobs))


def add(a, b, s=1.0):
    return [[a[i][k] + s * b[i][k] for k in range(FEAT)] for i in range(JOBS)]


def randn_dir(rng):
    return [[rng.gauss(0.0, 1.0) for _ in range(FEAT)] for _ in range(JOBS)]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--save", required=True, help="ein oder mehrere Spielstände, mit Komma getrennt")
    ap.add_argument("--events", action="store_true", help="mit Ereignissen (harte Winter, Piraten ...)")
    ap.add_argument("--godot", default=os.path.expanduser("~/gd/godot"))
    ap.add_argument("--days", type=int, default=3)
    ap.add_argument("--iters", type=int, default=40)
    ap.add_argument("--dirs", type=int, default=8)
    ap.add_argument("--top", type=int, default=4)
    ap.add_argument("--noise", type=float, default=0.3)
    ap.add_argument("--lr", type=float, default=0.1)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--eval_every", type=int, default=5)
    ap.add_argument("--eval_seeds", type=int, default=4)
    ap.add_argument("--init", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    rng = random.Random(a.seed)
    theta = [[0.0] * FEAT for _ in range(JOBS)]
    if a.init:
        theta = json.load(open(a.init))["w"]
    pool = Pool(a.workers)
    saves = [x for x in a.save.split(",") if x]
    ep = lambda slot, w, seed, si=0, off=False: run_episode(a.godot, saves[si], w, a.days, seed, slot, off, events=a.events)
    base = [1.0] * len(saves)  # Punkte je Spielstand im Startlauf: Läufe verschiedener Stände werden daran gemessen
    logf = open(os.path.join(a.out, "log.jsonl"), "a")
    evf = open(os.path.join(a.out, "evals.jsonl"), "a")
    best = {"mean": -1e18, "w": theta}

    def evaluate(w, tag, it):
        seeds = [100000 + s for s in range(a.eval_seeds)]  # immer dieselben Prüfwürfel
        jl = [(w, s, si) for si in range(len(saves)) for s in seeds]
        rs = pool.map(ep, jl)
        per = {}
        for (w_, s_, si), r in zip(jl, rs):
            if r[0] is not None:
                per.setdefault(si, []).append(r[0])
        if tag == "start":
            for si in per:
                base[si] = max(1.0, sum(per[si]) / len(per[si]))
        sc = [r[0] for r in rs if r[0] is not None]
        mean = sum(sum(v) / len(v) / base[si] for si, v in per.items()) / max(1, len(per)) * 1000.0  # 1000 = Startstand
        parts = {}
        for r in rs:
            if r[1]:
                for d in r[1]["days"]:
                    for k in ("food", "wood", "proc", "res", "sat", "mood", "dead"):
                        parts[k] = parts.get(k, 0.0) + float(d.get(k, 0.0)) / len(sc)
        jobs = [r[1]["jobs"] for r in rs if r[1]]
        rec = {"iter": it, "tag": tag, "mean": mean, "per_save": {saves[k]: sum(v) / len(v) for k, v in per.items()}, "scores": sc, "parts": parts, "jobs": jobs[:1], "t": time.time()}
        evf.write(json.dumps(rec) + "\n")
        evf.flush()
        print("PRUEFUNG %s Runde %d: %.1f %s %s" % (tag, it, mean, [round(s) for s in sc], {k: round(v) for k, v in parts.items()}), flush=True)
        return mean

    m = evaluate(theta, "start", 0)
    best = {"mean": m, "w": theta, "iter": 0}
    json.dump({"w": theta, "iter": 0, "eval": m, "days": a.days}, open(os.path.join(a.out, "best.json"), "w"))
    for it in range(1, a.iters + 1):
        t0 = time.time()
        dirs = [randn_dir(rng) for _ in range(a.dirs)]
        jobs = []
        for k, d in enumerate(dirs):
            sd = it * 1000 + k
            si = k % len(saves)
            jobs.append((add(theta, d, a.noise), sd, si))
            jobs.append((add(theta, d, -a.noise), sd, si))
        rs = pool.map(ep, jobs)
        pairs = []
        for k in range(a.dirs):
            rp, rm = rs[2 * k][0], rs[2 * k + 1][0]
            if rp is None or rm is None:
                continue
            rp, rm = rp / base[k % len(saves)] * 1000.0, rm / base[k % len(saves)] * 1000.0
            pairs.append((max(rp, rm), rp, rm, dirs[k]))
        pairs.sort(key=lambda p: -p[0])
        top = pairs[:a.top]
        allr = [p[1] for p in top] + [p[2] for p in top]
        mu = sum(allr) / len(allr)
        sd_r = (sum((x - mu) ** 2 for x in allr) / len(allr)) ** 0.5 or 1.0
        step = [[0.0] * FEAT for _ in range(JOBS)]
        for _, rp, rm, d in top:
            step = add(step, d, (rp - rm))
        theta = add(theta, step, a.lr / (len(top) * sd_r))
        rec = {"iter": it, "mean_r": sum(p[1] + p[2] for p in pairs) / (2 * max(1, len(pairs))), "best_r": top[0][0] if top else None,
               "sd": sd_r, "secs": time.time() - t0}
        logf.write(json.dumps(rec) + "\n")
        logf.flush()
        print("Runde %d: Mittel %.1f, bestes %.1f, %.0f s" % (it, rec["mean_r"], rec["best_r"] or 0, rec["secs"]), flush=True)
        json.dump({"w": theta, "iter": it}, open(os.path.join(a.out, "last.json"), "w"))
        if it % a.eval_every == 0 or it == a.iters:
            m = evaluate(theta, "theta", it)
            if m > best["mean"]:
                best = {"mean": m, "w": theta, "iter": it}
                json.dump({"w": theta, "iter": it, "eval": m, "days": a.days}, open(os.path.join(a.out, "best.json"), "w"))
    print("FERTIG bestes Runde %d mit %.1f" % (best["iter"], best["mean"]), flush=True)


if __name__ == "__main__":
    main()
