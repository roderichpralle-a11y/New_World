#!/usr/bin/env python3
"""Erzeugt alle Pixel-Grafiken des Spiels (eigene Werke, CC0).

Aufruf:  python3 tools/gen_art.py
Ausgabe: assets/sprites/*.png

Alles ist prozedural oder als ASCII-Pixelmaske beschrieben, damit spaetere
Etappen neue Sprites im gleichen Stil ergaenzen koennen.
"""
import math
import os
import random

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites")
T = 16  # Kachelgroesse

# ---------------------------------------------------------------- Palette
OUTLINE = (40, 28, 36, 255)
WATER = [(40, 96, 168), (52, 124, 196), (72, 152, 214), (110, 188, 232), (200, 236, 250)]
SAND = [(204, 168, 104), (226, 196, 132), (240, 216, 156), (250, 234, 186)]
FOAM = (236, 248, 252)
WET_SAND = (186, 160, 112)
GRASS = [(48, 104, 56), (72, 140, 62), (100, 172, 74), (134, 200, 90), (170, 222, 112)]
SOIL = [(96, 62, 44), (126, 84, 56), (152, 106, 70)]
WOOD = [(86, 54, 40), (122, 78, 50), (160, 108, 66), (196, 146, 92)]
STONE = [(70, 72, 90), (106, 108, 126), (142, 144, 160), (184, 186, 198), (220, 222, 230)]
LEAF = [(30, 74, 52), (44, 104, 60), (62, 138, 68), (96, 172, 82), (138, 202, 98)]
THATCH = [(140, 96, 46), (178, 130, 58), (214, 170, 82), (240, 204, 118)]
BERRY = [(120, 30, 60), (180, 46, 78), (232, 88, 110)]
FLOWER = [(250, 250, 240), (250, 214, 80), (236, 110, 140), (150, 170, 250)]
WHEAT = [(170, 124, 48), (214, 170, 72), (240, 210, 110), (110, 150, 60), (140, 180, 70)]
FIRE = [(150, 40, 30), (220, 80, 30), (250, 160, 50), (255, 230, 140)]


def rgba(c, a=255):
    return (c[0], c[1], c[2], a)


def new(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def put(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), rgba(c) if len(c) == 3 else c)


def get_a(img, x, y):
    if 0 <= x < img.width and 0 <= y < img.height:
        return img.getpixel((x, y))[3]
    return 0


def add_outline(img, color=OUTLINE, diagonal=False):
    """Zeichnet eine 1px Kontur um alle nicht-transparenten Pixel."""
    src = img.copy()
    for y in range(img.height):
        for x in range(img.width):
            if src.getpixel((x, y))[3] != 0:
                continue
            n = [(1, 0), (-1, 0), (0, 1), (0, -1)]
            if diagonal:
                n += [(1, 1), (-1, -1), (1, -1), (-1, 1)]
            if any(get_a(src, x + dx, y + dy) > 0 for dx, dy in n):
                img.putpixel((x, y), color)
    return img


# ---------------------------------------------------------- Periodisches Rauschen
def periodic_noise(seed, period=16, cells=4):
    """Wertrauschen, das mit 'period' Pixeln kachelt (nahtlos)."""
    rnd = random.Random(seed)
    grid = [[rnd.random() for _ in range(cells)] for _ in range(cells)]
    step = period / cells

    def f(x, y):
        gx, gy = x / step, y / step
        x0, y0 = int(math.floor(gx)), int(math.floor(gy))
        tx, ty = gx - x0, gy - y0
        tx = tx * tx * (3 - 2 * tx)
        ty = ty * ty * (3 - 2 * ty)

        def g(i, j):
            return grid[j % cells][i % cells]

        a = g(x0, y0) * (1 - tx) + g(x0 + 1, y0) * tx
        b = g(x0, y0 + 1) * (1 - tx) + g(x0 + 1, y0 + 1) * tx
        return a * (1 - ty) + b * ty

    return f


BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def dither(v, x, y):
    """v in [0,1] -> bool, geordnetes Dithering."""
    return v > (BAYER[y % 4][x % 4] + 0.5) / 16.0


# ------------------------------------------------------------------ Terrain
def tex_grass(x, y, variant):
    """Ruhiger Grasgrund: kaum Muster, damit keine Kachelwiederholung auffaellt."""
    return GRASS[2]


def grass_blades(img, rnd, count, flowers=0):
    for _ in range(count):
        x, y = rnd.randint(2, 13), rnd.randint(3, 13)
        put(img, x, y, GRASS[1])
        put(img, x - 1, y - 1, GRASS[1])
        put(img, x + 1, y - 1, GRASS[3])
        put(img, x + 1, y - 2, GRASS[4])
    for _ in range(flowers):
        x, y = rnd.randint(2, 13), rnd.randint(2, 13)
        col = FLOWER[rnd.randint(0, 3)]
        put(img, x, y, col)
        put(img, x + 1, y, FLOWER[1] if col != FLOWER[1] else FLOWER[0])
        put(img, x, y + 1, GRASS[1])


def tex_sand(x, y, variant):
    n = periodic_noise(5)(x, y)
    c = SAND[1]
    if n > 0.6 and dither((n - 0.6) * 3, x, y):
        c = SAND[2]
    if n < 0.32 and dither((0.32 - n) * 3, x, y):
        c = SAND[0]
    return c


def water_frame(f):
    """Animiertes Wasser, Frame 0..3, nahtlos."""
    img = new(T, T)
    n = periodic_noise(77)
    for y in range(T):
        for x in range(T):
            v = n(x, y)
            c = WATER[1]
            if v < 0.4 and dither((0.4 - v) * 2.5, x, y):
                c = WATER[0]
            # Wellenlinien, wandern pro Frame
            w = math.sin((x + f * 4) * 2 * math.pi / 16 + y * 2 * math.pi / 8 * 2)
            if w > 0.92 and (y % 8) in (2, 3):
                c = WATER[2]
            put(img, x, y, c)
    # Glitzer
    rnd = random.Random(f)
    for (sx, sy) in [(3, 4), (11, 12), (13, 3), (6, 10)]:
        if (sx + sy + f) % 4 == 0:
            put(img, sx, sy, WATER[4])
            put(img, sx + 1, sy, WATER[3])
    return img


def corner_value(mask, x, y):
    """Bilineare Interpolation der vier Ecken (TL=1,TR=2,BL=4,BR=8)."""
    tl = 1.0 if mask & 1 else 0.0
    tr = 1.0 if mask & 2 else 0.0
    bl = 1.0 if mask & 4 else 0.0
    br = 1.0 if mask & 8 else 0.0
    u = (x + 0.5) / T
    v = (y + 0.5) / T
    return (tl * (1 - u) + tr * u) * (1 - v) + (bl * (1 - u) + br * u) * v


def edge_noise(seed):
    n = periodic_noise(seed, cells=4)
    return lambda x, y: (n(x, y) - 0.5) * 0.36


def terrain_tile(mask, kind, variant=0):
    """Dual-Grid Kachel: Inhalt nur dort, wo die Ecken 'innen' sind."""
    img = new(T, T)
    en = edge_noise(101 if kind == "sand" else 202)
    for y in range(T):
        for x in range(T):
            v = corner_value(mask, x, y) + en(x, y)
            if kind == "sand":
                if v > 0.5:
                    c = tex_sand(x, y, variant)
                    if v < 0.62:
                        c = SAND[2] if (x + y) % 3 else SAND[3]
                    put(img, x, y, c)
                elif v > 0.40:
                    put(img, x, y, (*WET_SAND, 255))
                elif v > 0.30:
                    put(img, x, y, (*FOAM, 200))
                elif v > 0.24 and (x * 7 + y * 3) % 5 == 0:
                    put(img, x, y, (*FOAM, 120))
            else:  # grass
                if v > 0.5:
                    c = tex_grass(x, y, variant)
                    if v < 0.6:
                        c = GRASS[1]
                    put(img, x, y, c)
                elif v > 0.43:
                    put(img, x, y, GRASS[0])
                elif v > 0.37:
                    put(img, x, y, (*SAND[0], 255))
    return img


def grass_variant(variant):
    img = terrain_tile(15, "grass")
    rnd = random.Random(1000 + variant)
    if variant == 0:
        grass_blades(img, rnd, 3)
    elif variant == 1:
        grass_blades(img, rnd, 2, flowers=2)
    elif variant == 2:
        grass_blades(img, rnd, 1, flowers=1)
    elif variant == 3:  # Kleine Steinchen
        grass_blades(img, rnd, 1)
        x, y = rnd.randint(3, 11), rnd.randint(3, 11)
        for dx, dy, c in [(0, 0, STONE[3]), (1, 0, STONE[2]), (0, 1, STONE[2]), (1, 1, STONE[1])]:
            put(img, x + dx, y + dy, c)
    return img


def sand_variant(variant):
    img = terrain_tile(15, "sand")
    rnd = random.Random(2000 + variant)
    if variant == 1:  # Muschel
        x, y = rnd.randint(3, 11), rnd.randint(3, 11)
        for dx, dy, c in [(0, 0, (250, 220, 220)), (1, 0, (240, 180, 180)), (2, 0, (250, 220, 220)),
                          (0, 1, (220, 160, 160)), (1, 1, (250, 220, 220)), (2, 1, (220, 160, 160))]:
            put(img, x + dx, y + dy, c)
    elif variant == 2:  # Kiesel
        for _ in range(2):
            x, y = rnd.randint(2, 13), rnd.randint(2, 13)
            put(img, x, y, SAND[0])
            put(img, x + 1, y, STONE[3])
    elif variant == 3:  # Wellenlinien im Sand
        for x in range(3, 12):
            put(img, x, 6 + (1 if x % 4 < 2 else 0), SAND[0])
    return img


def gen_terrain():
    """terrain.png: Zeile 0 Wasser (4 Frames) + Wasser-Varianten,
    Zeile 1 Sand-Masken 0..15, Zeile 2 Gras-Masken 0..15,
    Zeile 3 Sand-Varianten (4), Gras-Varianten (4), Ackerboden."""
    atlas = new(16 * T, 4 * T)
    for f in range(4):
        atlas.paste(water_frame(f), (f * T, 0))
    for m in range(16):
        atlas.paste(terrain_tile(m, "sand"), (m * T, T))
        atlas.paste(terrain_tile(m, "grass"), (m * T, 2 * T))
    for v in range(4):
        atlas.paste(sand_variant(v), (v * T, 3 * T))
        atlas.paste(grass_variant(v), ((4 + v) * T, 3 * T))
    atlas.save(os.path.join(OUT, "terrain.png"))


# ------------------------------------------------------------------ Objekte
def blob(img, cx, cy, rx, ry, colors, light=(-0.6, -0.8), noise_seed=0, jag=0.0):
    """Gefuellte, schattierte Ellipse (Baumkrone, Busch, Fels)."""
    rnd = random.Random(noise_seed)
    lx, ly = light
    for y in range(img.height):
        for x in range(img.width):
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            d = dx * dx + dy * dy
            if jag:
                ang = math.atan2(dy, dx)
                d *= 1 + jag * math.sin(ang * 7 + noise_seed)
            if d <= 1.0:
                shade = -(dx * lx + dy * ly) * 0.55 + (1 - d) * 0.45
                n = len(colors)
                idx = int((shade + 0.6) / 1.4 * n)
                # Dithering an den Uebergaengen
                frac = (shade + 0.6) / 1.4 * n - idx
                if frac > 0.75 and (x + y) % 2 == 0:
                    idx += 1
                idx = max(0, min(n - 1, idx))
                put(img, x, y, colors[idx])


def tree(kind=0):
    """Baum 32x48, Stamm unten mittig. kind 0: Laubbaum, 1: Laubbaum hell, 2: Nadelbaum"""
    img = new(32, 48)
    # Stamm
    for y in range(30, 45):
        for x in range(13, 19):
            c = WOOD[1]
            if x == 13:
                c = WOOD[0]
            elif x >= 17:
                c = WOOD[2]
            if (y * 3 + x) % 7 == 0:
                c = WOOD[0]
            put(img, x, y, c)
    # Wurzeln
    for x, y in [(11, 44), (12, 44), (12, 43), (19, 44), (20, 44), (19, 43)]:
        put(img, x, y, WOOD[1])
    if kind == 2:
        cols = [LEAF[0], (36, 90, 64), (48, 120, 74), (74, 150, 84)]
        for i, (cy, r) in enumerate([(30, 12), (22, 10), (14, 7.5), (8, 5)]):
            for y in range(img.height):
                for x in range(img.width):
                    dy = y - cy
                    if -r * 0.9 <= dy <= 3 and abs(x + 0.5 - 16) <= (dy + r * 0.9) * 0.62:
                        side = (x + 0.5 - 16) / max(1, r)
                        idx = 2 if side < -0.1 else 1
                        if dy > 1:
                            idx = 0
                        if side < -0.45 and dy < 0:
                            idx = 3
                        put(img, x, y, cols[idx])
    else:
        cols = LEAF if kind == 0 else [LEAF[1], LEAF[2], LEAF[3], LEAF[4], (180, 226, 120)]
        blob(img, 16, 20, 14, 12.5, cols[:4], noise_seed=3 + kind, jag=0.08)
        blob(img, 11, 15, 7, 6.5, cols[1:], noise_seed=4 + kind)
        blob(img, 20, 13, 7, 6, cols[1:], noise_seed=5 + kind)
        blob(img, 15, 9, 6, 5, cols[2:], noise_seed=6 + kind)
        # Lichtpunkte
        rnd = random.Random(kind)
        for _ in range(10):
            x, y = rnd.randint(6, 24), rnd.randint(5, 24)
            if img.getpixel((x, y))[3] and img.getpixel((x, y))[:3] in [c[:3] for c in cols[2:]]:
                put(img, x, y, cols[-1])
    add_outline(img)
    return img


def stump():
    img = new(32, 48)
    for y in range(39, 45):
        for x in range(12, 20):
            put(img, x, y, WOOD[1] if x > 12 else WOOD[0])
    for x in range(12, 20):
        put(img, x, 38, WOOD[3])
        put(img, x, 37, WOOD[3])
    put(img, 15, 37, WOOD[2])
    put(img, 16, 38, WOOD[2])
    for x, y in [(11, 44), (20, 44)]:
        put(img, x, y, WOOD[1])
    add_outline(img)
    return img


def sapling():
    img = new(32, 48)
    for y in range(36, 45):
        put(img, 16, y, WOOD[2])
    blob(img, 16, 35, 5, 4.5, LEAF[1:], noise_seed=9)
    blob(img, 13, 38, 3, 2.5, LEAF[1:], noise_seed=10)
    blob(img, 19, 39, 3, 2.5, LEAF[1:], noise_seed=11)
    add_outline(img)
    return img


def rock(big=True):
    img = new(16, 16)
    if big:
        blob(img, 8, 9, 7, 5.6, STONE[0:5], noise_seed=21, jag=0.06)
        # Risse
        for x, y in [(6, 8), (7, 9), (7, 10), (10, 6), (11, 7)]:
            put(img, x, y, STONE[1])
        # Moos
        for x, y in [(3, 7), (4, 6), (5, 6), (4, 7)]:
            put(img, x, y, GRASS[2])
    else:
        blob(img, 8, 11, 4.5, 3.3, STONE[0:5], noise_seed=22)
    add_outline(img)
    return img


def bush(berries=True):
    img = new(16, 16)
    blob(img, 8, 9, 7, 6, LEAF[0:4], noise_seed=31, jag=0.1)
    blob(img, 6, 7, 3.5, 3, LEAF[2:], noise_seed=32)
    if berries:
        for x, y in [(4, 9), (8, 6), (11, 9), (7, 11), (12, 6), (5, 5)]:
            put(img, x, y, BERRY[1])
            put(img, x + 1, y, BERRY[0])
            put(img, x, y - 1, BERRY[2])
    add_outline(img)
    return img


def fish_spot(f):
    img = new(16, 16)
    r = 2 + f * 1.5
    for a in range(0, 360, 6):
        x = 8 + math.cos(math.radians(a)) * r
        y = 8 + math.sin(math.radians(a)) * r * 0.55
        alpha = max(0, 220 - f * 50)
        put(img, int(x), int(y), (*WATER[4], alpha))
    # Fisch-Silhouette
    if f in (0, 1):
        for x, y in [(6, 8), (7, 8), (8, 8), (9, 8), (7, 7), (8, 9), (10, 7), (10, 9)]:
            put(img, x, y, (30, 70, 120, 200))
    return img


def campfire(f):
    img = new(16, 16)
    # Steinkreis
    for a in range(0, 360, 40):
        x = 8 + math.cos(math.radians(a)) * 6
        y = 11 + math.sin(math.radians(a)) * 3
        put(img, int(x), int(y), STONE[2])
        put(img, int(x) + 1, int(y), STONE[1])
    # Holzscheite
    for x in range(4, 12):
        put(img, x, 12, WOOD[1])
        put(img, x, 11 - (1 if x in (6, 9) else 0), WOOD[2])
    # Flammen
    rnd = random.Random(f * 13)
    heights = [3, 6, 8, 6, 4]
    for i, h in enumerate(heights):
        h = h + rnd.randint(-1, 1)
        x = 6 + i
        for y in range(11 - h, 11):
            t = (11 - y) / h
            c = FIRE[3] if t < 0.3 and i in (1, 2, 3) else FIRE[2] if t < 0.6 else FIRE[1]
            put(img, x, y, c)
    put(img, 8 + (f % 2), 1 + f % 3, FIRE[2])
    return img


def thatch_roof(img, x0, y0, w, h, cols=THATCH):
    """Strohdach als Trapez mit Halmen."""
    for y in range(h):
        inset = max(0, (h - y) // 3 - 1)
        for x in range(x0 + inset - (y // 4), x0 + w - inset + (y // 4)):
            c = cols[2]
            if (x * 3 + y * 5) % 7 == 0 or y % 4 == 3:
                c = cols[1]
            if y >= h - 2:
                c = cols[0] if y == h - 1 else cols[1]
            if (x - x0) < 3 and y < h - 2:
                c = cols[3] if (x + y) % 2 else cols[2]
            put(img, x, y0 + y, c)


def plank_wall(img, x0, y0, w, h):
    for y in range(h):
        for x in range(w):
            c = WOOD[2]
            if y % 4 == 3:
                c = WOOD[1]
            if x in (0, w - 1):
                c = WOOD[0]
            if (x * 5 + (y // 4) * 3) % 11 == 0:
                c = WOOD[1]
            put(img, x0 + x, y0 + y, c)


def hut():
    """Huette 48x48 (Grundflaeche 3x2 Kacheln)."""
    img = new(48, 48)
    plank_wall(img, 6, 26, 36, 18)
    # Tuer
    for y in range(32, 44):
        for x in range(20, 28):
            put(img, x, y, WOOD[0] if x in (20, 27) or y == 32 else (70, 44, 34))
    put(img, 25, 38, THATCH[3])
    # Fenster
    for (wx, wy) in [(10, 31), (32, 31)]:
        for y in range(wy, wy + 6):
            for x in range(wx, wx + 6):
                edge = x in (wx, wx + 5) or y in (wy, wy + 5)
                put(img, x, y, WOOD[0] if edge else (250, 220, 130) if (x + y) % 3 else (230, 190, 100))
        for x in range(wx, wx + 6):
            put(img, x, wy + 3, WOOD[1])
    thatch_roof(img, 6, 6, 36, 22)
    # Schornstein
    for y in range(4, 12):
        for x in range(32, 36):
            put(img, x, y, STONE[2] if x < 35 else STONE[1])
    add_outline(img)
    return img


def storehouse():
    """Lagerhaus 48x48, mit Kisten und Faessern."""
    img = new(48, 48)
    plank_wall(img, 4, 24, 40, 20)
    # grosses Tor
    for y in range(28, 44):
        for x in range(16, 32):
            c = WOOD[1] if (x - 16) % 4 else WOOD[0]
            if y == 28:
                c = WOOD[0]
            put(img, x, y, c)
    for x in range(16, 32):
        put(img, x, 35, WOOD[0])
    # Dach aus Brettern (rot-braun)
    roof = [(110, 50, 40), (150, 66, 48), (186, 90, 60), (214, 124, 82)]
    thatch_roof(img, 4, 4, 40, 22, roof)
    # Kisten
    for (bx, by) in [(36, 38), (2, 38)]:
        for y in range(by, by + 7):
            for x in range(bx, bx + 8):
                c = WOOD[3] if (x == bx or y == by) else WOOD[2]
                if x == bx + 7 or y == by + 6:
                    c = WOOD[1]
                put(img, x, y, c)
        put(img, bx + 3, by + 3, WOOD[1])
    add_outline(img)
    return img


def construction():
    """Baustelle 48x48: Geruest und Holzbalken."""
    img = new(48, 48)
    for x in (8, 22, 38):
        for y in range(18, 44):
            put(img, x, y, WOOD[2])
            put(img, x + 1, y, WOOD[1])
    for y in (22, 32):
        for x in range(6, 42):
            put(img, x, y, WOOD[2])
            put(img, x, y + 1, WOOD[1])
    for i in range(12):
        put(img, 10 + i, 42 - i, WOOD[3])
        put(img, 24 + i, 31 - i, WOOD[3])
    # Brettstapel
    for y in range(40, 44):
        for x in range(28, 44):
            put(img, x, y, WOOD[3] if y % 2 == 0 else WOOD[1])
    add_outline(img)
    return img


def field_tile(stage):
    """Acker-Kachel 16x16; stage 0 leer, 1 Saat, 2 wachsend, 3 reif."""
    img = new(16, 16)
    for y in range(16):
        for x in range(16):
            c = SOIL[1]
            if y % 4 == 1:
                c = SOIL[2]
            if y % 4 == 3:
                c = SOIL[0]
            put(img, x, y, c)
    for row in (2, 6, 10, 14):
        for col in (2, 6, 10, 14):
            if stage == 1:
                put(img, col, row, WHEAT[3])
                put(img, col + 1, row - 1, WHEAT[4])
            elif stage == 2:
                for y in range(row - 4, row + 1):
                    put(img, col, y, WHEAT[3] if y > row - 3 else WHEAT[4])
                put(img, col - 1, row - 2, WHEAT[4])
                put(img, col + 1, row - 3, WHEAT[4])
            elif stage == 3:
                for y in range(row - 5, row + 1):
                    put(img, col, y, WHEAT[1])
                put(img, col - 1, row - 4, WHEAT[2])
                put(img, col + 1, row - 5, WHEAT[2])
                put(img, col, row - 6, WHEAT[2])
                put(img, col + 1, row - 3, WHEAT[0])
    return img


def grave():
    img = new(16, 16)
    for y in range(4, 13):
        for x in range(5, 11):
            if y == 4 and x in (5, 10):
                continue
            put(img, x, y, STONE[3] if x < 7 else STONE[2])
    for x in range(7, 9):
        for y in range(6, 11):
            put(img, x, y, STONE[1]) if False else None
    for y in range(6, 10):
        put(img, 8, y, STONE[1])
    for x in range(7, 10):
        put(img, x, 7, STONE[1])
    for x in range(3, 13):
        put(img, x, 13, SOIL[1])
    add_outline(img)
    return img


def shadow(w=12, h=5, iw=16):
    img = new(iw, 8)
    for y in range(8):
        for x in range(iw):
            dx = (x + 0.5 - iw / 2) / (w / 2)
            dy = (y + 0.5 - 4) / (h / 2)
            if dx * dx + dy * dy <= 1:
                put(img, x, y, (20, 30, 40, 80))
    return img


def gen_objects():
    """objects.png: Atlas mit festen Regionen (siehe REGIONS in DESIGN.md)."""
    atlas = new(256, 256)
    # Zeile A (y=0, h=48): Baeume 3 Arten, Stumpf, Setzling
    for i, im in enumerate([tree(0), tree(1), tree(2), stump(), sapling()]):
        atlas.paste(im, (i * 32, 0))
    # Zeile B (y=48, h=48): Huette, Lagerhaus, Baustelle
    for i, im in enumerate([hut(), storehouse(), construction()]):
        atlas.paste(im, (i * 48, 48))
    # Zeile C (y=96, h=16): Fels gross, Fels klein, Busch voll, Busch leer, Grab, Schatten
    for i, im in enumerate([rock(True), rock(False), bush(True), bush(False), grave()]):
        atlas.paste(im, (i * 16, 96))
    atlas.paste(shadow(), (80, 96))
    atlas.paste(shadow(26, 6, 32), (96, 96))
    # Zeile D (y=112): Lagerfeuer 4 Frames, Fischschwarm 4 Frames
    for f in range(4):
        atlas.paste(campfire(f), (f * 16, 112))
        atlas.paste(fish_spot(f), (64 + f * 16, 112))
    # Zeile E (y=128): Acker 4 Stufen
    for s in range(4):
        atlas.paste(field_tile(s), (s * 16, 128))
    atlas.save(os.path.join(OUT, "objects.png"))


# -------------------------------------------------------------- Siedler
# Legende: o Kontur, e Auge, B Stiefel (feste Farben)
#          S/s Haut, H/h Haar, C/c Hemd, P/p Hose  (Graustufen, im Spiel eingefaerbt)
BODY_DOWN = [
    "................",
    "................",
    "................",
    ".....oooooo.....",
    "....oHHHHHHo....",
    "...oHHHHHHHHo...",
    "...oHHHHHHHHo...",
    "...oHhHHHHhHo...",
    "...ohSSSSSShho..",
    "...oSSeSSeSSo...",
    "...oSSSSSSSSo...",
    "....osSSSSso....",
    "...ooCCCCCCoo...",
    "..oCCCCCCCCCCo..",
    "..oCcCCCCCCcCo..",
    "..oScCCCCCCcSo..",
    "..oSoPPPPPPoSo..",
    "...ooPPPPPPoo...",
    "....oPPppPPo....",
    "....oPPooPPo....",
    "....oBBooBBo....",
    "....oooo.ooo....",
    "................",
    "................",
]
BODY_UP = [
    "................",
    "................",
    "................",
    ".....oooooo.....",
    "....oHHHHHHo....",
    "...oHHHHHHHHo...",
    "...oHHHHHHHHo...",
    "...oHHHHHHHHo...",
    "...ohHHHHHHho...",
    "...ohhHHHHhho...",
    "...oShhhhhhSo...",
    "....osSSSSso....",
    "...ooCCCCCCoo...",
    "..oCCCCCCCCCCo..",
    "..oCCCCCCCCCCo..",
    "..oScCCCCCCcSo..",
    "..oSoPPPPPPoSo..",
    "...ooPPPPPPoo...",
    "....oPPppPPo....",
    "....oPPooPPo....",
    "....oBBooBBo....",
    "....oooo.ooo....",
    "................",
    "................",
]
BODY_SIDE = [
    "................",
    "................",
    "................",
    ".....ooooo......",
    "....oHHHHHo.....",
    "...oHHHHHHHo....",
    "...oHHHHHHHHo...",
    "...oHHHhSSSSo...",
    "...ohHhSSSSSo...",
    "...ohHSSSSeSo...",
    "...ohSSSSSSSo...",
    "....osSSSSso....",
    ".....oCCCCo.....",
    "....oCCCCCCo....",
    "....oCCCCCCo....",
    "....ocCSSCco....",
    "....oPPSSPPo....",
    "....oPPPPPPo....",
    ".....oPPpPo.....",
    ".....oPPoPo.....",
    ".....oBBoBBo....",
    ".....ooooooo....",
    "................",
    "................",
]

# Haarstile: Ueberlagerung (nur H/h/o), 0 = kurz (in Koerper), 1 = lang, 2 = Dutt
HAIR_LONG = {"down": [(3, 9), (3, 10), (3, 11), (12, 9), (12, 10), (12, 11), (4, 11), (11, 11)],
             "up": [(4, 11), (5, 11), (6, 11), (7, 11), (8, 11), (9, 11), (10, 11), (11, 11), (4, 12), (11, 12)],
             "side": [(4, 11), (4, 12), (3, 11)]}
HAIR_BUN = [(6, 1), (7, 1), (8, 1), (9, 1), (5, 2), (6, 2), (7, 2), (8, 2), (9, 2), (10, 2)]

LAYER_OF = {"S": "skin", "s": "skin", "H": "hair", "h": "hair", "C": "shirt", "c": "shirt",
            "P": "pants", "p": "pants", "o": "fixed", "e": "fixed", "B": "fixed"}
SHADE = {"S": 255, "s": 200, "H": 255, "h": 190, "C": 255, "c": 196, "P": 255, "p": 196}
FIXED = {"o": OUTLINE, "e": (30, 20, 30, 255), "B": (92, 60, 44, 255)}


def walk_variant(rows, frame, side=False):
    """Frame 0/2 neutral, 1/3 mit Schrittbewegung und 1px Wippen."""
    rows = [list(r) for r in rows]
    if frame in (1, 3):
        # Koerper (bis Huefte) 1px nach oben
        bob = [list(r) for r in rows]
        for y in range(1, 18):
            bob[y - 1] = rows[y][:]
        bob[17] = rows[17][:]
        rows = bob
        if not side:
            # ein Bein anheben
            lx = range(4, 8) if frame == 1 else range(8, 12)
            for x in lx:
                rows[20][x] = rows[21][x] if False else "."
                rows[19][x] = "B" if rows[19][x] in "Pp" else rows[19][x]
            for x in lx:
                if rows[21][x] == "o":
                    rows[21][x] = "."
                if rows[19][x] == "B":
                    rows[20][x] = "o"
        else:
            # Beine gespreizt
            rows[18] = list("....oPPpPPo.....") if frame == 1 else list("......oPPPPo....")
            rows[19] = list("...oPPo.oPPo....") if frame == 1 else list(".....oPPPPo.....")
            rows[20] = list("...oBBo.oBBo....") if frame == 1 else list(".....oBBBBo.....")
            rows[21] = list("...oooo.oooo....") if frame == 1 else list(".....oooooo.....")
    return ["".join(r) for r in rows]


def render_layers(rows, hair_style, direction):
    layers = {k: new(16, 24) for k in ("fixed", "skin", "hair", "shirt", "pants")}
    extra = []
    if hair_style == 1:
        extra = HAIR_LONG[direction]
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch == ".":
                continue
            lay = LAYER_OF[ch]
            if lay == "fixed":
                layers["fixed"].putpixel((x, y), FIXED[ch])
            else:
                g = SHADE[ch]
                layers[lay].putpixel((x, y), (g, g, g, 255))
    if hair_style == 1:
        for (x, y) in extra:
            layers["hair"].putpixel((x, y), (190, 190, 190, 255))
            for k in ("skin", "fixed"):
                layers[k].putpixel((x, y), (0, 0, 0, 0))
    if hair_style == 2:
        for (x, y) in HAIR_BUN:
            layers["hair"].putpixel((x, y + 1), (235, 235, 235, 255))
        # Kontur um Dutt
        for (x, y) in [(5, 1), (6, 0), (7, 0), (8, 0), (9, 0), (10, 1), (4, 2), (11, 2)]:
            layers["fixed"].putpixel((x, y + 1), OUTLINE)
    return layers


def gen_settlers():
    """settler_<layer>[_<style>].png: Spalten = 4 Lauf-Frames, Zeilen = unten, oben, seitlich."""
    dirs = [("down", BODY_DOWN, False), ("up", BODY_UP, False), ("side", BODY_SIDE, True)]
    sheets = {}
    for style in range(3):
        for di, (dname, rows, side) in enumerate(dirs):
            for f in range(4):
                layers = render_layers(walk_variant(rows, f, side), style, dname)
                for k, im in layers.items():
                    key = f"hair_{style}" if k == "hair" else k
                    if style > 0 and k != "hair":
                        if k == "fixed" and style == 2:
                            key = "fixed_bun"
                        else:
                            continue
                    if key not in sheets:
                        sheets[key] = new(64, 72)
                    sheets[key].paste(im, (f * 16, di * 24))
    for k, im in sheets.items():
        im.save(os.path.join(OUT, f"settler_{k}.png"))


# ------------------------------------------------------------------ Werkzeuge
def tools():
    """tools.png: 16x16 Werkzeuge in der Hand: Axt, Spitzhacke, Korb, Angel, Hammer, Sichel."""
    atlas = new(96, 16)
    axe = new(16, 16)
    for i in range(10):
        put(axe, 3 + i, 13 - i, WOOD[2])
    for x, y in [(9, 2), (10, 2), (11, 2), (9, 3), (10, 3), (11, 3), (12, 4), (9, 4), (10, 5), (11, 4)]:
        put(axe, x + 1, y, STONE[3])
    add_outline(axe)
    pick = new(16, 16)
    for i in range(10):
        put(pick, 3 + i, 13 - i, WOOD[2])
    for x, y in [(6, 3), (7, 2), (8, 2), (9, 2), (10, 2), (11, 3), (12, 4), (13, 6)]:
        put(pick, x, y, STONE[3])
    add_outline(pick)
    basket = new(16, 16)
    for y in range(8, 14):
        for x in range(4, 12):
            put(basket, x, y, THATCH[2] if (x + y) % 2 else THATCH[1])
    for x in range(5, 11):
        put(basket, x, 4 if 6 < x < 9 else 5, THATCH[1])
    for x, y in [(5, 7), (7, 7), (9, 7)]:
        put(basket, x, y, BERRY[1])
    add_outline(basket)
    rod = new(16, 16)
    for i in range(12):
        put(rod, 2 + i, 14 - i, WOOD[2])
    for y in range(3, 12):
        put(rod, 14, y, (230, 230, 230, 160))
    add_outline(rod)
    hammer = new(16, 16)
    for i in range(9):
        put(hammer, 3 + i, 13 - i, WOOD[2])
    for x in range(9, 15):
        for y in range(2, 6):
            if abs((x - 12) + (y - 4)) < 4:
                put(hammer, x, y, STONE[2])
    add_outline(hammer)
    sickle = new(16, 16)
    for i in range(6):
        put(sickle, 3 + i, 13 - i, WOOD[2])
    for a in range(200, 360, 12):
        put(sickle, int(10 + math.cos(math.radians(a)) * 4), int(6 + math.sin(math.radians(a)) * 4), STONE[4])
    add_outline(sickle)
    for i, im in enumerate([axe, pick, basket, rod, hammer, sickle]):
        atlas.paste(im, (i * 16, 0))
    atlas.save(os.path.join(OUT, "tools.png"))


# ------------------------------------------------------------------ Icons
def icon_from_ascii(rows, palette):
    img = new(16, 16)
    for y, r in enumerate(rows):
        for x, ch in enumerate(r):
            if ch in palette:
                put(img, x, y, palette[ch])
    return add_outline(img)


ICONS = {
    "holz": (["................",
              "................",
              "....11111111....",
              "...2111111113...",
              "...2111111113...",
              "...22222222333..",
              "..11111111113...",
              ".211111111113...",
              ".211111111133...",
              ".222222222233...",
              "..111111113.....",
              ".21111111113....",
              ".21111111113....",
              ".22222222233....",
              "................",
              "................"],
             {"1": WOOD[2], "2": WOOD[1], "3": WOOD[3]}),
    "stein": (["................",
               "................",
               "................",
               ".....3333.......",
               "....344223......",
               "...34442223.....",
               "...344222223....",
               "....3322211.....",
               "......33333.....",
               "..3333..34423...",
               ".344223.344223..",
               ".344222134222213",
               "..33221.332211..",
               "...3333..3333...",
               "................",
               "................"],
              {"1": STONE[0], "2": STONE[1], "3": STONE[2], "4": STONE[4]}),
    "beeren": (["................",
                "........55......",
                ".......55.......",
                "......4.........",
                ".....4.4........",
                "....12..12......",
                "...1312131213...",
                "...1112.1112....",
                "....22...22.....",
                "......12........",
                ".....1312.......",
                ".....1112.......",
                "......22........",
                "................",
                "................",
                "................"],
               {"1": BERRY[1], "2": BERRY[0], "3": BERRY[2], "4": LEAF[1], "5": LEAF[3]}),
    "fisch": (["................",
               "................",
               "................",
               "................",
               "......1111......",
               "4...11133311....",
               "44.1133333311...",
               "4441333333e31...",
               "4441222222221...",
               "44.1122222211...",
               "4...11222211....",
               "......1111......",
               "................",
               "................",
               "................",
               "................"],
              {"1": (44, 96, 150), "2": (150, 200, 230), "3": (90, 150, 200), "4": (60, 120, 180),
               "e": (20, 20, 30)}),
    "weizen": (["................",
                ".....2...2......",
                "....212.212.....",
                "....212.212.2...",
                "....121.121212..",
                ".....2...2.121..",
                ".....3...3..2...",
                "......3.3..3....",
                "......3.3.3.....",
                ".......333......",
                "......44444.....",
                ".......333......",
                "......3.3.3.....",
                ".....3..3..3....",
                "................",
                "................"],
               {"1": WHEAT[2], "2": WHEAT[1], "3": WHEAT[0], "4": WOOD[1]}),
    "nahrung": (["................",
                 "................",
                 "......55........",
                 ".......5........",
                 ".....1111.......",
                 "....133111......",
                 "...13311111.....",
                 "...11111112.....",
                 "...11111112.....",
                 "....111122......",
                 ".....2222.......",
                 "................",
                 "................",
                 "................",
                 "................",
                 "................"],
                {"1": (220, 70, 60), "2": (160, 40, 40), "3": (255, 170, 150), "5": LEAF[2]}),
    "person": (["................",
                "......1111......",
                ".....111111.....",
                ".....122221.....",
                ".....222222.....",
                "......2222......",
                "....33333333....",
                "...3333333333...",
                "...3333333333...",
                "...2.333333.2...",
                ".....444444.....",
                ".....44..44.....",
                ".....44..44.....",
                ".....55..55.....",
                "................",
                "................"],
               {"1": (120, 80, 50), "2": (240, 200, 160), "3": (70, 130, 200), "4": (90, 80, 120),
                "5": (90, 60, 40)}),
    "haus": (["................",
              ".......11.......",
              "......1221......",
              ".....122221.....",
              "....12222221....",
              "...1222222221...",
              "..122222222221..",
              "...3333333333...",
              "...3444334443...",
              "...3444334443...",
              "...3333553333...",
              "...3333553333...",
              "...3333553333...",
              "................",
              "................",
              "................"],
             {"1": THATCH[1], "2": THATCH[2], "3": WOOD[2], "4": (250, 220, 130), "5": WOOD[0]}),
    "hammer": (["................",
                "........1111....",
                ".......111111...",
                "......1112111...",
                ".......2.1111...",
                "......2...11....",
                ".....2..........",
                "....2...........",
                "...2............",
                "..2.............",
                ".2..............",
                "................",
                "................",
                "................",
                "................",
                "................"],
               {"1": STONE[2], "2": WOOD[2]}),
    "herz": (["................",
              "................",
              "...111...111....",
              "..13311.12211...",
              "..1311112222l...",
              "..1111111222l...",
              "..1111111122l...",
              "...11111112l....",
              "....111112l.....",
              ".....1112l......",
              "......12l.......",
              ".......l........",
              "................",
              "................",
              "................",
              "................"],
             {"1": (230, 60, 80), "2": (190, 40, 60), "3": (255, 180, 190), "l": (150, 30, 50)}),
    "sonne": (["................",
               ".......1........",
               "...1...1...1....",
               "....1.....1.....",
               "......222.......",
               ".....23332......",
               "11..2333332..11.",
               "....2333332.....",
               ".....23332......",
               "......222.......",
               "....1.....1.....",
               "...1...1...1....",
               ".......1........",
               "................",
               "................",
               "................"],
              {"1": (250, 200, 60), "2": (240, 170, 40), "3": (255, 230, 110)}),
    "mond": (["................",
              "......111.......",
              "....11222.......",
              "...1222.........",
              "...122..........",
              "..1222..........",
              "..1222..........",
              "..1222..........",
              "..12222.........",
              "...12222....1...",
              "...112222221....",
              ".....1111111....",
              "................",
              "................",
              "................",
              "................"],
             {"1": (180, 180, 210), "2": (230, 230, 250)}),
    "pause": (["................",
               "................",
               "...1111..1111...",
               "...1221..1221...",
               "...1221..1221...",
               "...1221..1221...",
               "...1221..1221...",
               "...1221..1221...",
               "...1221..1221...",
               "...1221..1221...",
               "...1221..1221...",
               "...1111..1111...",
               "................",
               "................",
               "................",
               "................"],
              {"1": (60, 50, 60), "2": (250, 240, 220)}),
    "play": (["................",
              "................",
              "....11..........",
              "....1211........",
              "....122211......",
              "....12222211....",
              "....122222221...",
              "....12222211....",
              "....122211......",
              "....1211........",
              "....11..........",
              "................",
              "................",
              "................",
              "................",
              "................"],
             {"1": (60, 50, 60), "2": (250, 240, 220)}),
    "schnell": (["................",
                 "................",
                 "..11....11......",
                 "..1211..1211....",
                 "..122211122211..",
                 "..1222221222221.",
                 "..122211122211..",
                 "..1211..1211....",
                 "..11....11......",
                 "................",
                 "................",
                 "................",
                 "................",
                 "................",
                 "................",
                 "................"],
                {"1": (60, 50, 60), "2": (250, 240, 220)}),
    "menu": (["................",
              "................",
              "..111111111111..",
              "..122222222221..",
              "..111111111111..",
              "................",
              "..111111111111..",
              "..122222222221..",
              "..111111111111..",
              "................",
              "..111111111111..",
              "..122222222221..",
              "..111111111111..",
              "................",
              "................",
              "................"],
             {"1": (60, 50, 60), "2": (250, 240, 220)}),
    "abriss": (["................",
                "................",
                "..11........11..",
                "..121......121..",
                "...121....121...",
                "....121..121....",
                ".....121121.....",
                "......1221......",
                "......1221......",
                ".....121121.....",
                "....121..121....",
                "...121....121...",
                "..121......121..",
                "..11........11..",
                "................",
                "................"],
               {"1": (120, 30, 30), "2": (230, 80, 70)}),
}


def gen_icons():
    names = list(ICONS.keys())
    atlas = new(16 * len(names), 16)
    for i, n in enumerate(names):
        rows, pal = ICONS[n]
        atlas.paste(icon_from_ascii(rows, pal), (i * 16, 0))
    atlas.save(os.path.join(OUT, "icons.png"))
    with open(os.path.join(OUT, "icons.txt"), "w") as fh:
        fh.write("\n".join(names) + "\n")


# ------------------------------------------------------------------ UI
def ui_panel():
    """9-Patch Holzrahmen-Panel 24x24 (Rand 8) und Knopf-Varianten."""
    def panel(fill, border, light, dark):
        img = new(24, 24)
        for y in range(24):
            for x in range(24):
                edge = min(x, y, 23 - x, 23 - y)
                if edge == 0:
                    if (x in (0, 23)) and (y in (0, 23)):
                        continue
                    put(img, x, y, OUTLINE)
                elif edge == 1:
                    put(img, x, y, light if (x < 12 and y < 12) or y == 1 or x == 1 else border)
                elif edge == 2:
                    put(img, x, y, border)
                elif edge == 3:
                    put(img, x, y, dark)
                else:
                    put(img, x, y, fill)
        return img
    atlas = new(96, 24)
    atlas.paste(panel((246, 230, 196), WOOD[2], WOOD[3], WOOD[1]), (0, 0))      # Panel
    atlas.paste(panel((214, 170, 110), WOOD[2], WOOD[3], WOOD[1]), (24, 0))     # Knopf
    atlas.paste(panel((236, 196, 130), WOOD[3], (240, 200, 140), WOOD[2]), (48, 0))  # Knopf hover
    atlas.paste(panel((170, 120, 76), WOOD[1], WOOD[2], WOOD[0]), (72, 0))      # Knopf gedrueckt
    atlas.save(os.path.join(OUT, "ui.png"))


def preview():
    """Vorschaubild zur Kontrolle (nicht im Spiel benutzt)."""
    files = ["terrain.png", "objects.png", "icons.png", "tools.png", "ui.png",
             "settler_fixed.png", "settler_skin.png", "settler_hair_0.png", "settler_hair_1.png",
             "settler_hair_2.png", "settler_shirt.png", "settler_pants.png"]
    ims = [Image.open(os.path.join(OUT, f)) for f in files]
    w = max(i.width for i in ims)
    h = sum(i.height + 4 for i in ims)
    sheet = Image.new("RGBA", (w, h), (90, 90, 110, 255))
    y = 0
    for im in ims:
        sheet.alpha_composite(im, (0, y))
        y += im.height + 4
    sheet = sheet.resize((w * 3, h * 3), Image.NEAREST)
    os.makedirs(os.path.join(ROOT, "tools", "preview"), exist_ok=True)
    sheet.save(os.path.join(ROOT, "tools", "preview", "atlas_preview.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_terrain()
    gen_objects()
    gen_settlers()
    tools()
    gen_icons()
    ui_panel()
    preview()
    print("ok")
