#!/usr/bin/env python3
"""Reinforcement Learning für den Inselrat der KI-Variante (Evolution Strategies).

Das Spiel läuft ohne Bild und beschleunigt (main.gd --rl=Tage). Jede Spielrunde ist ein
eigener Godot-Prozess, der mit einem Netz (--policy=Datei) spielt und am Ende Kennzahlen
als JSON schreibt (Siedler, Forschung, Tote, Hunger, Vorrat ...). Daraus wird eine
Belohnung. OpenAI-ES: Gewichte zufällig in beide Richtungen verändern (antithetisch),
beide Varianten auf denselben Inseln (gleiche Startwerte) spielen lassen und die Gewichte
in die Richtung schieben, die mehr Belohnung bringt.

Aufruf (aus dem Projektordner):
  python3 tools/rl/train.py --gens 30 --out data/ki_policy.json
  python3 tools/rl/train.py --eval data/ki_policy.json --seeds 100-115   # Netz gegen Regeln

Braucht numpy und godot (4.7) im Pfad. Läuft komplett in der Cloud, kein Godot-Fenster.
"""
import argparse
import json
import os
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor

import numpy as np

N_IN, N_HID, N_OUT = 33, 16, 17  # wie scripts/ai/council_net.gd
N_PARAMS = N_HID * N_IN + N_HID + N_OUT * N_HID + N_OUT
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.environ.get("RL_WORK", "/tmp/rl/train")


def reward(r):
    """Ein Spiel als eine Zahl: viele gesunde Siedler, Fortschritt, keine Not."""
    if r is None:
        return -50.0
    return (1.0 * r["pop"] + 0.5 * r["peak"] + 0.5 * r["techs"] + 0.1 * r["buildings"]
            - 2.0 * r["deaths"] - 20.0 * r["hungry"] + 1.0 * min(r["food_avg"], 4.0)
            + 1.0 * min(r["food_min"], 1.0) - 3.0 * r["idle"] - (30.0 if r["over"] else 0.0))


def init_params(rng):
    p = np.zeros(N_PARAMS, dtype=np.float64)
    # Versteckte Schicht zufällig, Ausgabeschicht 0: Start = genau die Regeln.
    p[: N_HID * N_IN] = rng.normal(0.0, 1.0 / np.sqrt(N_IN), N_HID * N_IN)
    return p


def write_policy(path, p, info):
    with open(path, "w") as f:
        json.dump({"params": [round(float(v), 5) for v in p], "info": info}, f)


class Runner:
    def __init__(self, workers, days, scale, fps):
        self.days, self.scale, self.fps = days, scale, fps
        self.pool = ThreadPoolExecutor(workers)
        self.free = list(range(workers))
        self.lock = threading.Lock()
        os.makedirs(WORK, exist_ok=True)

    def _one(self, policy, seed):
        with self.lock:
            k = self.free.pop()
        try:
            out = tempfile.mktemp(prefix="res_", suffix=".json", dir=WORK)
            env = dict(os.environ, XDG_DATA_HOME=os.path.join(WORK, "w%d" % k))
            cmd = ["godot", "--headless", "--fixed-fps", str(self.fps), "--path", ROOT, "--",
                   "--kimode=1", "--rl=%g" % self.days, "--seed=%d" % seed, "--policy=" + policy,
                   "--scale=%g" % self.scale, "--rlout=" + out]
            try:
                subprocess.run(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                               timeout=900)
                with open(out) as f:
                    r = json.load(f)
                os.remove(out)
                return r
            except Exception as e:  # abgestürzt oder zu langsam: schlechte Runde
                print("  Lauf fehlgeschlagen:", seed, e, flush=True)
                return None
        finally:
            with self.lock:
                self.free.append(k)

    def run(self, jobs):
        """jobs: Liste (policy_pfad, seed) -> Liste Ergebnisse in derselben Reihenfolge."""
        futs = [self.pool.submit(self._one, p, s) for p, s in jobs]
        return [f.result() for f in futs]


def centered_ranks(x):
    r = np.empty(len(x))
    r[np.argsort(x)] = np.arange(len(x))
    return r / (len(x) - 1) - 0.5


def train(a):
    rng = np.random.default_rng(a.rng)
    ck = os.path.join(WORK, "checkpoint.npz")
    runner = Runner(a.workers, a.days, a.scale, a.fps)
    if a.resume and os.path.exists(ck):
        d = np.load(ck)
        theta, m, v, gen0 = d["theta"], d["m"], d["v"], int(d["gen"])
        best = float(d["best"])
        print("weiter ab Generation", gen0, flush=True)
    else:
        theta, gen0, best = init_params(rng), 0, -1e9
        m, v = np.zeros(N_PARAMS), np.zeros(N_PARAMS)
    b1, b2, eps = 0.9, 0.999, 1e-8
    log = open(os.path.join(WORK, "log.jsonl"), "a")
    for gen in range(gen0, a.gens):
        t0 = time.time()
        seeds = [int(s) for s in rng.integers(1000, 10**6, a.seeds_per_gen)]
        eps_list = [rng.normal(0, 1, N_PARAMS) for _ in range(a.pairs)]
        jobs, files = [], []
        cands = [theta] + [theta + a.sigma * e for e in eps_list] + [theta - a.sigma * e for e in eps_list]
        for i, c in enumerate(cands):
            fn = os.path.join(WORK, "cand_%d.json" % i)
            write_policy(fn, c, {"gen": gen})
            files.append(fn)
        # Regel-Rat (ohne Netz) auf denselben Inseln als Vergleich
        for s in seeds:
            jobs.append(("none", s))
        for fn in files:
            for s in seeds:
                jobs.append((fn, s))
        res = runner.run(jobs)
        ns = len(seeds)
        base_r = [reward(r) for r in res[:ns]]
        R = np.array([[reward(r) for r in res[ns + i * ns: ns + (i + 1) * ns]] for i in range(len(cands))])
        Rm = R.mean(axis=1)
        center = Rm[0]
        rp, rn = Rm[1:1 + a.pairs], Rm[1 + a.pairs:]
        ranks = centered_ranks(np.concatenate([rp, rn]))
        w = ranks[: a.pairs] - ranks[a.pairs:]
        g = sum(wi * e for wi, e in zip(w, eps_list)) / (a.pairs * a.sigma)
        g -= a.l2 * theta  # Gewichte klein halten
        # Adam, Schritt bergauf
        t = gen + 1
        m = b1 * m + (1 - b1) * g
        v = b2 * v + (1 - b2) * g * g
        theta = theta + a.lr * (m / (1 - b1 ** t)) / (np.sqrt(v / (1 - b2 ** t)) + eps)
        rec = {"gen": gen, "center": round(float(center), 3), "rules": round(float(np.mean(base_r)), 3),
               "adv": round(float(center - np.mean(base_r)), 3), "best_cand": round(float(Rm.max()), 3),
               "mean_cand": round(float(Rm.mean()), 3), "secs": round(time.time() - t0, 1)}
        print(json.dumps(rec), flush=True)
        log.write(json.dumps(rec) + "\n")
        log.flush()
        # bestes Netz = Mitte mit dem größten Vorsprung vor den Regeln (gleitend über 3 Generationen)
        if gen >= 2 and rec["adv"] > best:
            best = rec["adv"]
            write_policy(a.out + ".best", cands[0], {"gen": gen, "adv": best})
        np.savez(ck, theta=theta, m=m, v=v, gen=gen + 1, best=best)
        write_policy(a.out + ".last", theta, {"gen": gen + 1})


def evaluate(a):
    lo, hi = [int(x) for x in a.seeds.split("-")]
    seeds = list(range(lo, hi + 1))
    runner = Runner(a.workers, a.days, a.scale, a.fps)
    pol = os.path.abspath(a.eval)
    res = runner.run([("none", s) for s in seeds] + [(pol, s) for s in seeds])
    rules, net = res[: len(seeds)], res[len(seeds):]
    keys = ["pop", "peak", "techs", "buildings", "births", "deaths", "food_avg", "food_min", "hungry", "idle"]

    def mean(rs, k):
        vals = [r[k] for r in rs if r]
        return sum(vals) / max(1, len(vals))
    out = {"seeds": a.seeds, "days": a.days, "rules": {}, "net": {}}
    for k in keys:
        out["rules"][k] = round(mean(rules, k), 3)
        out["net"][k] = round(mean(net, k), 3)
    out["rules"]["reward"] = round(float(np.mean([reward(r) for r in rules])), 3)
    out["net"]["reward"] = round(float(np.mean([reward(r) for r in net])), 3)
    out["rules"]["over"] = sum(1 for r in rules if r and r["over"])
    out["net"]["over"] = sum(1 for r in net if r and r["over"])
    wins = sum(1 for x, y in zip(rules, net) if reward(y) > reward(x))
    out["net_better_on"] = "%d of %d" % (wins, len(seeds))
    print(json.dumps(out, indent=1))
    if a.report:
        with open(a.report, "w") as f:
            json.dump(out, f, indent=1)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--gens", type=int, default=30)
    ap.add_argument("--pairs", type=int, default=8)
    ap.add_argument("--seeds-per-gen", type=int, default=2)
    ap.add_argument("--sigma", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=0.03)
    ap.add_argument("--l2", type=float, default=0.005)
    ap.add_argument("--days", type=float, default=36)
    ap.add_argument("--scale", type=float, default=16)
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--rng", type=int, default=1)
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "ki_policy.json"))
    ap.add_argument("--eval", default="")
    ap.add_argument("--seeds", default="100-115")
    ap.add_argument("--report", default="")
    a = ap.parse_args()
    if a.eval:
        evaluate(a)
    else:
        train(a)
