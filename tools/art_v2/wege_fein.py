"""Wege und Hecken für Version 2 (josh 2026-10-28): 128 x 128 Bildpunkte je Feld, also feiner als die
Siedler (1 Punkt = Achtel-Spielpixel). Muster wie die früheren Wege und Hecken aus dem Bogen
landschaft_verbindungen: Sandweg und Kies mit ausgefranstem Rand, Ziegel mit dunklem Bord, Hecke aus
runden Büschen. Jedes Stück feldbreit, an offenen Seiten etwas Abstand, nur offene Enden rund.
tiles(kind) liefert 16 Kacheln (Maske N=1, O=2, S=4, W=8)."""
import random
import numpy as np
from PIL import Image

N = 128
E, R = 8, 40  # Abstand an offenen Seiten, Rundung der Enden


def _noise(seed, sigma):
    rs = np.random.RandomState(seed)
    f = np.fft.fftfreq(N)
    r = np.sqrt(f[:, None] ** 2 + f[None, :] ** 2)
    a = np.real(np.fft.ifft2(np.fft.fft2(rs.randn(N, N)) * np.exp(-(r / sigma) ** 2)))
    return a / a.std()


def _sdf(m):
    """Abstand jedes Punkts zum Rand der Form (positiv innen)."""
    con = [bool(m & 1), bool(m & 2), bool(m & 4), bool(m & 8)]
    ys, xs = np.mgrid[0:N, 0:N] + 0.5
    inf = np.full((N, N), 1e9)
    dn = inf if con[0] else ys - E
    de = inf if con[1] else (N - E) - xs
    ds = inf if con[2] else (N - E) - ys
    dw = inf if con[3] else xs - E
    d = np.minimum(np.minimum(dn, ds), np.minimum(de, dw))
    for a, b, cx, cy in ((0, 3, E + R, E + R), (0, 1, N - E - R, E + R), (2, 3, E + R, N - E - R), (2, 1, N - E - R, N - E - R)):
        if con[a] or con[b]:
            continue
        sx = -1 if cx < N / 2 else 1
        sy = -1 if cy < N / 2 else 1
        q = ((xs - cx) * sx > 0) & ((ys - cy) * sy > 0)
        d = np.where(q, R - np.hypot(xs - cx, ys - cy), d)
    for a, b, cx, cy in ((0, 3, 0, 0), (0, 1, N, 0), (2, 3, 0, N), (2, 1, N, N)):
        if con[a] and con[b]:  # Innenecke zum Nachbarn: kleine Hohlkehle statt Stufe
            d = np.minimum(d, np.hypot(xs - cx, ys - cy) - E)
    return d


def _clamp(a):
    return np.clip(a, 0, 255).astype(np.uint8)


def _speckle(rgb, rnd, count, colors, sizes):
    for _ in range(count):
        x, y = rnd.randrange(N), rnd.randrange(N)
        w, h = rnd.choice(sizes)
        c = np.array(rnd.choice(colors), float)
        for yy in range(h):
            for xx in range(w):
                rgb[(y + yy) % N, (x + xx) % N] = c
        if w > 1 and h > 1:  # Licht oben links, Schatten unten
            rgb[y % N, x % N] = np.minimum(c + 34, 255)
            for xx in range(w):
                rgb[(y + h) % N, (x + xx) % N] *= 0.8


def texture(kind):
    rnd = random.Random({"road": 31, "gravel": 32, "bricks": 33, "hedge": 34}[kind])
    rgb = np.zeros((N, N, 3), float)
    if kind == "road":
        f = _noise(5, 0.05) + 0.5 * _noise(6, 0.2)
        rgb[:] = np.array([222, 168, 98])
        rgb += f[..., None] * np.array([9, 8, 6])
        _speckle(rgb, rnd, 160, [(240, 206, 150), (232, 196, 140)], [(1, 1), (2, 1)])
        _speckle(rgb, rnd, 70, [(196, 142, 82), (184, 132, 76)], [(1, 1), (2, 2)])
        _speckle(rgb, rnd, 14, [(176, 150, 124), (196, 172, 144)], [(3, 2), (4, 3)])
    elif kind == "gravel":
        f = _noise(7, 0.05)
        rgb[:] = np.array([150, 150, 164])
        rgb += f[..., None] * np.array([10, 10, 11])
        _speckle(rgb, rnd, 520, [(204, 204, 212), (226, 226, 230), (122, 122, 138), (176, 172, 168)], [(1, 1), (2, 1), (2, 2), (3, 2)])
        _speckle(rgb, rnd, 120, [(110, 110, 126)], [(1, 1)])
    elif kind == "bricks":
        mortar = np.array([116, 64, 46])
        rgb[:] = mortar
        bw, bh = 32, 20
        for row in range(N // bh + 1):
            off = 0 if row % 2 == 0 else bw // 2
            for b in range(-1, N // bw + 1):
                x0, y0 = b * bw + off, row * bh
                c = np.array(rnd.choice([(184, 102, 70), (194, 114, 80), (176, 98, 66), (200, 120, 86)]), float)
                for yy in range(2, bh - 1):
                    for xx in range(2, bw - 1):
                        if (xx in (2, bw - 2)) and (yy in (2, bh - 2)):
                            continue
                        s = 0
                        if yy == 2 or xx == 2:
                            s = 30
                        elif yy == bh - 2 or xx == bw - 2:
                            s = -34
                        elif yy == 3:
                            s = 12
                        elif rnd.random() < 0.06:
                            s = rnd.choice([-16, 12])
                        rgb[(y0 + yy) % N, (x0 + xx) % N] = c + s
    return rgb


def _hedge(m, d):
    """Hecke aus runden Büschen: Busch in der Mitte und auf jeder verbundenen Kante."""
    con = [bool(m & 1), bool(m & 2), bool(m & 4), bool(m & 8)]
    cs = [(64, 64)]
    for b, (x, y) in enumerate([(64, 0), (128, 64), (64, 128), (0, 64)]):
        if con[b]:
            cs.append((x, y))
    ys, xs = np.mgrid[0:N, 0:N] + 0.5
    dist = np.stack([np.hypot(xs - x, ys - y) for x, y in cs])
    order = np.argsort(dist, axis=0)
    near = np.take_along_axis(dist, order[:1], 0)[0]
    second = np.take_along_axis(dist, order[1:2], 0)[0] if len(cs) > 1 else np.full((N, N), 1e9)
    ci = order[0]
    cx = np.array([c[0] for c in cs])[ci]
    cy = np.array([c[1] for c in cs])[ci]
    rr = 44.0
    # Licht von oben links auf jedem Busch, Falte zwischen zwei Büschen
    light = (-(xs - cx) * 0.5 - (ys - cy)) / rr
    light = np.clip(light, -1, 1) - np.clip(near / rr - 0.75, 0, 1) * 0.6
    crease = np.clip(1 - (second - near) / 6, 0, 1)
    base = light * 1.3 - crease * 0.6 + 0.25
    pal = np.array([[12, 52, 34], [22, 78, 42], [34, 104, 48], [58, 134, 52], [94, 164, 58], [138, 192, 74]], float)
    # Blattbüschel: viele kleine runde Tupfen, von oben nach unten gelegt, jeder oben hell und unten dunkel
    v = base - 0.6
    rnd = random.Random(77)
    pts = []
    for gy in range(-8, N + 8, 7):
        for gx in range(-8, N + 8, 7):
            pts.append((gx + rnd.uniform(0, 7), gy + rnd.uniform(0, 7), rnd.uniform(4.0, 6.5)))
    pts.sort(key=lambda p: p[1])
    for px, py, pr in pts:
        x0, x1 = int(max(0, px - pr)), int(min(N, px + pr + 1))
        y0, y1 = int(max(0, py - pr)), int(min(N, py + pr + 1))
        if x0 >= x1 or y0 >= y1:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1] + 0.5
        rr2 = ((xx - px) ** 2 + (yy - py) ** 2) / (pr * pr)
        inside = rr2 <= 1
        local = base[y0:y1, x0:x1] + (-(yy - py) * 0.8 - (xx - px) * 0.3) / pr * 0.7 - rr2 * 0.35
        v[y0:y1, x0:x1] = np.where(inside, local, v[y0:y1, x0:x1])
    idx = np.clip(np.round((v + 1.4) / 2.8 * 5), 0, 5).astype(int)
    rgb = pal[idx]
    for _ in range(70):  # helle Blattspitzen
        x, y = rnd.randrange(N), rnd.randrange(N)
        if v[y, x] > 0.4:
            rgb[y, x] = (176, 214, 96)
    return rgb


RIM = {"road": ((150, 104, 56), (196, 146, 84), 2.2), "gravel": ((84, 84, 98), (118, 118, 132), 2.2),
       "bricks": ((70, 34, 26), (176, 100, 70), 0), "hedge": ((8, 36, 24), (16, 60, 36), 2.6)}


def tiles(kind):
    tex = None if kind == "hedge" else texture(kind)
    jag = _noise(40, 0.12)
    dark, rim, jitter = RIM[kind]
    out = []
    for m in range(16):
        d = _sdf(m) - jag * jitter
        rgb = _hedge(m, d) if kind == "hedge" else tex.copy()
        if kind == "bricks":  # Bord: dunkle Linie, heller Stein, dunkle Linie
            curb = np.array([168, 92, 64], float)
            rgb = np.where(((d >= 2) & (d < 9))[..., None], curb + np.where(((d >= 3) & (d < 5))[..., None], 26, 0), rgb)
            rgb = np.where(((d >= 9) & (d < 11))[..., None], np.array([92, 46, 34], float), rgb)
        elif kind != "hedge":
            rgb = np.where(((d >= 2) & (d < 4))[..., None], np.array(rim, float), rgb)
        rgb = np.where((d < 2)[..., None], np.array(dark, float), rgb)
        a = np.where(d >= 0, 255, 0).astype(np.uint8)
        out.append(Image.fromarray(np.dstack([_clamp(rgb), a]), "RGBA"))
    return out
