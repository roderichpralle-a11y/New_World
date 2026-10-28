"""Wege und Hecken für Version 2 in Siedler-Auflösung (josh 2026-10-28): 64 x 64 Bildpunkte je Feld
(1 Punkt = Viertel-Spielpixel), Muster angelehnt an die Wege und Hecken der Bögen, nahtlos mit Feldbreite.
Jedes Stück feldbreit, an offenen Seiten 1 Spielpixel Abstand, nur offene Enden rund.
tiles(kind) liefert 16 Kacheln (Maske N=1, O=2, S=4, W=8)."""
import random
import numpy as np
from PIL import Image

N = 64


def _noise(seed, sigma):
    rs = np.random.RandomState(seed)
    f = np.fft.fftfreq(N)
    r = np.sqrt(f[:, None] ** 2 + f[None, :] ** 2)
    a = np.real(np.fft.ifft2(np.fft.fft2(rs.randn(N, N)) * np.exp(-(r / sigma) ** 2)))
    return a / a.std()


def _clamp(c):
    return tuple(max(0, min(255, int(v))) for v in c)


def texture(kind):
    rnd = random.Random({"road": 21, "gravel": 22, "bricks": 23, "hedge": 24}[kind])
    img = Image.new("RGBA", (N, N))
    px = img.load()

    def put(x, y, c):
        px[x % N, y % N] = _clamp(c) + (255,)

    def get(x, y):
        return px[x % N, y % N][:3]
    if kind == "road":
        f = _noise(5, 0.08)
        for y in range(N):
            for x in range(N):
                v = f[y, x] + rnd.uniform(-0.6, 0.6)
                base = (222, 174, 98) if v > -0.6 else (208, 160, 88)
                if v > 0.9:
                    base = (232, 188, 112)
                put(x, y, base)
        for _ in range(40):  # Steinchen mit Licht und Schatten
            x, y = rnd.randrange(N), rnd.randrange(N)
            w, h = rnd.choice([(2, 2), (3, 2), (3, 3), (4, 3)])
            c = rnd.choice([(186, 156, 122), (200, 176, 146), (170, 140, 110)])
            for yy in range(h):
                for xx in range(w):
                    put(x + xx, y + yy, c)
            put(x, y, tuple(k + 26 for k in c))
            for xx in range(w):
                put(x + xx, y + h, (178, 132, 74))
        for _ in range(60):
            put(rnd.randrange(N), rnd.randrange(N), (190, 142, 78))
    elif kind == "gravel":
        for y in range(N):
            for x in range(N):
                put(x, y, (98, 98, 112))
        for _ in range(260):
            x, y = rnd.randrange(N), rnd.randrange(N)
            r = rnd.choice([2, 2, 3])
            c = rnd.choice([(150, 150, 164), (168, 166, 176), (136, 136, 150), (182, 180, 186), (158, 150, 142)])
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    d2 = dx * dx + dy * dy
                    if d2 <= r * r:
                        s = 22 if (dx + dy) < -r * 0.6 else (-24 if (dx + dy) > r * 0.6 else 0)
                        put(x + dx, y + dy, tuple(k + s for k in c))
    elif kind == "bricks":
        mortar = (124, 70, 52)
        for y in range(N):
            for x in range(N):
                put(x, y, mortar)
        bw, bh = 16, 8
        for row in range(N // bh):
            off = 0 if row % 2 == 0 else bw // 2
            for b in range(N // bw):
                x0, y0 = b * bw + off, row * bh
                c = rnd.choice([(188, 110, 78), (198, 122, 88), (178, 104, 72), (192, 118, 84), (206, 130, 94)])
                for yy in range(1, bh):
                    for xx in range(1, bw):
                        if (xx in (1, bw - 1)) and (yy in (1, bh - 1)):
                            continue  # runde Ecken
                        s = 0
                        if yy == 1 or xx == 1:
                            s = 26
                        elif yy == bh - 1 or xx == bw - 1:
                            s = -30
                        elif rnd.random() < 0.08:
                            s = rnd.choice([-14, 12])
                        put(x0 + xx, y0 + yy, tuple(k + s for k in c))
    else:  # hedge
        f = _noise(9, 0.06)
        for y in range(N):
            for x in range(N):
                put(x, y, (22, 88, 50) if f[y, x] > -0.4 else (16, 70, 44))
        greens = [(28, 100, 56), (40, 120, 60), (64, 146, 62), (98, 172, 60), (136, 196, 72)]
        for _ in range(420):
            x, y = rnd.randrange(N), rnd.randrange(N)
            lvl = max(0, min(4, int(2 + f[y, x] * 1.2 + rnd.uniform(-1, 1))))
            c = greens[lvl]
            # Blatt: kleines Oval, oben hell, unten dunkel
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, -1), (0, 1), (1, -1)):
                put(x + dx, y + dy, c)
            put(x, y - 1, greens[min(4, lvl + 1)])
            put(x + 1, y + 1, (14, 60, 40))
        for _ in range(30):
            put(rnd.randrange(N), rnd.randrange(N), (170, 214, 92))
    return img


EDGE = {"road": ((168, 122, 66), (204, 156, 86)), "gravel": ((70, 70, 84), (116, 116, 130)),
        "bricks": ((98, 50, 38), (150, 84, 60)), "hedge": ((8, 50, 34), (18, 72, 44))}


def tiles(kind):
    t = texture(kind)
    tp = t.load()
    out = []
    dark, rim = EDGE[kind]
    e, r = 4, 18
    for m in range(16):
        con = [bool(m & 1), bool(m & 2), bool(m & 4), bool(m & 8)]
        x0 = 0 if con[3] else e
        x1 = N - 1 if con[1] else N - 1 - e
        y0 = 0 if con[0] else e
        y1 = N - 1 if con[2] else N - 1 - e
        ins = np.zeros((N, N), bool)
        ins[y0:y1 + 1, x0:x1 + 1] = True
        for oa, ob, cx, cy, sx, sy in ((0, 3, x0 + r, y0 + r, -1, -1), (0, 1, x1 - r, y0 + r, 1, -1),
                                       (2, 3, x0 + r, y1 - r, -1, 1), (2, 1, x1 - r, y1 - r, 1, 1)):
            if con[oa] or con[ob]:
                continue
            for y in range(N):
                for x in range(N):
                    if (x - cx) * sx > 0 and (y - cy) * sy > 0 and (x - cx) ** 2 + (y - cy) ** 2 > r * r:
                        ins[y, x] = False
        img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
        ip = img.load()

        def dist_edge(x, y):
            for d in (1, 2):
                for dx, dy, side in ((0, -d, 0), (d, 0, 1), (0, d, 2), (-d, 0, 3)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < N and 0 <= ny < N:
                        if not ins[ny, nx]:
                            return d
                    elif not con[side]:
                        return d
            return 0
        for y in range(N):
            for x in range(N):
                if not ins[y, x]:
                    continue
                d = dist_edge(x, y)
                c = (dark + (255,)) if d == 1 else ((rim + (255,)) if d == 2 else tp[x, y])
                if kind == "hedge" and d != 1:  # Hecke rund: oben Licht, unten Schatten
                    up = next((k for k in range(1, 9) if y - k < 0 and not con[0] or y - k >= 0 and not ins[y - k, x]), 9)
                    dn = next((k for k in range(1, 9) if y + k >= N and not con[2] or y + k < N and not ins[y + k, x]), 9)
                    sh = (6 - dn) * 9 if dn < 6 else (-(5 - up) * 7 if up < 5 else 0)
                    c = _clamp((c[0] - sh, c[1] - sh, c[2] - sh)) + (255,)
                ip[x, y] = c
        out.append(img)
    return out
