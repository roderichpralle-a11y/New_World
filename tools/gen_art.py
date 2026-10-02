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
PLASTER = [(206, 186, 150), (230, 214, 180), (246, 236, 210)]
SLATE = [(52, 60, 90), (72, 84, 120), (96, 112, 150), (130, 148, 186)]
ROOF_RED = [(110, 40, 36), (150, 58, 44), (190, 84, 56), (222, 120, 80)]
BRICK = [(120, 52, 40), (160, 72, 50), (196, 100, 66)]
SHINGLE = [(70, 46, 40), (98, 64, 50), (128, 86, 62), (156, 112, 78)]
DARK = (36, 26, 30)
GLOW = [(200, 70, 30), (250, 150, 50), (255, 220, 120)]
CLAY = [(150, 92, 56), (184, 120, 72), (210, 150, 96)]
IRON = [(60, 64, 76), (100, 104, 118), (150, 154, 168), (200, 204, 214)]


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
        atlas.paste(orchard_tile(s), (64 + s * 16, 128))
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
    atlas = new(144, 16)
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
    for i, im in enumerate([axe, pick, basket, rod, hammer, sickle] + tools2()):
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


ICONS.update({
    "bretter": (["................",
                 "................",
                 "................",
                 "..1111111111113.",
                 ".222222222222223",
                 ".333333333333333",
                 "................",
                 ".1111111111113..",
                 "2222222222222223",
                 "3333333333333333",
                 "................",
                 "..1111111111113.",
                 ".222222222222223",
                 ".333333333333333",
                 "................",
                 "................"],
                {"1": WOOD[3], "2": WOOD[2], "3": WOOD[1]}),
    "lehm": (["................",
              "................",
              "................",
              "................",
              "......1111......",
              "....11222211....",
              "...1222332221...",
              "..122233332221..",
              "..122222222221..",
              ".12222222222221.",
              ".11222222222211.",
              "..111111111111..",
              "................",
              "................",
              "................",
              "................"],
             {"1": CLAY[0], "2": CLAY[1], "3": CLAY[2]}),
    "ziegel": (["................",
                "................",
                "................",
                "....33333333....",
                "...3222222221...",
                "...2222222221...",
                "...1111111111...",
                ".33333333.333...",
                "3222222221221...",
                "2222222221221...",
                "1111111111111...",
                "................",
                "................",
                "................",
                "................",
                "................"],
               {"1": BRICK[0], "2": BRICK[1], "3": BRICK[2]}),
    "kohle": (["................",
               "................",
               "................",
               "................",
               ".....11.........",
               "....1332.112....",
               "...133222132....",
               "...1222221222...",
               "..11222211122...",
               ".1332211222221..",
               ".1222221122211..",
               "..11111111111...",
               "................",
               "................",
               "................",
               "................"],
              {"1": (24, 24, 30), "2": (48, 48, 58), "3": (96, 96, 110)}),
    "erz": (["................",
             "................",
             "................",
             "................",
             ".....1111.......",
             "....122441......",
             "...12224421.....",
             "...122222221....",
             "..1244222221....",
             "..1244222441....",
             "..12222224421...",
             "...111111111....",
             "................",
             "................",
             "................",
             "................"],
            {"1": STONE[0], "2": STONE[1], "4": (200, 120, 80)}),
    "eisen": (["................",
               "................",
               "................",
               "................",
               "................",
               ".....444444.....",
               "....43333332....",
               "...4333333322...",
               "..433333333222..",
               ".11111111111222.",
               ".12222222222122.",
               ".11111111111111.",
               "................",
               "................",
               "................",
               "................"],
              {"1": IRON[0], "2": IRON[1], "3": IRON[2], "4": IRON[3]}),
    "werkzeug": (["................",
                  "..44.......333..",
                  ".4334.....33.3..",
                  ".4334....3......",
                  "..444...1.......",
                  "....1..1........",
                  ".....11.........",
                  ".....11.........",
                  "....1..1........",
                  "...1....1.......",
                  "..1......1......",
                  ".1........1.....",
                  "1..........1....",
                  "................",
                  "................",
                  "................"],
                 {"1": WOOD[2], "3": IRON[2], "4": IRON[3]}),
    "mehl": (["................",
              "................",
              "......1..1......",
              ".......11.......",
              "......2222......",
              ".....233332.....",
              "....23333332....",
              "...2333333332...",
              "...2333443332...",
              "...2333443332...",
              "...2333333332...",
              "....23333332....",
              ".....222222.....",
              "................",
              "................",
              "................"],
             {"1": (150, 120, 80), "2": (190, 172, 136), "3": (236, 226, 200), "4": WHEAT[1]}),
    "aepfel": (["................",
                "........5.......",
                ".......544......",
                "........4.......",
                "....111.111.....",
                "...13311112l....",
                "...1311111ll....",
                "...111111122....",
                "...11111112l....",
                "....1111122.....",
                ".....l1.l2......",
                "................",
                "................",
                "................",
                "................",
                "................"],
               {"1": (220, 50, 50), "2": (180, 36, 40), "3": (255, 150, 140), "4": LEAF[3], "5": WOOD[1],
                "l": (140, 26, 30)}),
    "eier": (["................",
              "................",
              "................",
              "......11........",
              ".....1331.......",
              "....133221......",
              "....1322221.11..",
              "....132222113321",
              ".....1222113322.",
              "......11..132221",
              "..........122221",
              "...........1111.",
              "................",
              "................",
              "................",
              "................"],
             {"1": (200, 186, 160), "2": (246, 238, 222), "3": (255, 255, 250)}),
    "raeucherfisch": (["................",
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
                      {"1": (110, 60, 30), "2": (210, 150, 80), "3": (170, 100, 50), "4": (130, 76, 40),
                       "e": (20, 20, 30)}),
    "brot": (["................",
              "................",
              "................",
              "................",
              ".....111111.....",
              "...1123232211...",
              "..122323232321..",
              ".12222222222221.",
              ".12222222222221.",
              ".11222222222211.",
              "..111111111111..",
              "................",
              "................",
              "................",
              "................",
              "................"],
             {"1": (150, 84, 40), "2": (200, 130, 60), "3": (240, 196, 120)}),
    "wissen": (["................",
                "................",
                "..11111..11111..",
                ".1222221122222l.",
                ".1233321123332l.",
                ".1222221122222l.",
                ".1233321123332l.",
                ".1222221122222l.",
                ".1233321123332l.",
                ".1222221122222l.",
                ".11111111111111.",
                "......4444......",
                "................",
                "................",
                "................",
                "................"],
               {"1": (150, 46, 40), "2": (246, 236, 210), "3": (150, 140, 130), "l": (120, 36, 32),
                "4": (180, 60, 50)}),
    "axt": (["................",
             "........4444....",
             ".......433334...",
             "......4333334...",
             "......433.334...",
             ".......1..44....",
             "......1.........",
             ".....1..........",
             "....1...........",
             "...1............",
             "..1.............",
             ".1..............",
             "................",
             "................",
             "................",
             "................"],
            {"1": WOOD[2], "3": STONE[2], "4": STONE[3]}),
    "korb": (["................",
              "................",
              "......3333......",
              ".....3....3.....",
              "....3......3....",
              "...1111111111...",
              "...1212121212...",
              "...2121212121...",
              "...1212121212...",
              "....12121212....",
              "....21212121....",
              ".....111111.....",
              "................",
              "................",
              "................",
              "................"],
             {"1": THATCH[1], "2": THATCH[2], "3": THATCH[0]}),
    "wasser": (["................",
                ".......1........",
                ".......1........",
                "......121.......",
                "......121.......",
                ".....12221......",
                "....1223221.....",
                "....1232222.....",
                "...122322221....",
                "...122222221....",
                "...112222211....",
                "....1122211.....",
                "......111.......",
                "................",
                "................",
                "................"],
               {"1": WATER[0], "2": WATER[2], "3": WATER[4]}),
    "karren": (["................",
                "................",
                "................",
                "................",
                "..1111111111....",
                "..1222222221....",
                "..1222222221111.",
                "..111111111111..",
                "....3.....3.....",
                "...343...343....",
                "...333...333....",
                "................",
                "................",
                "................",
                "................",
                "................"],
               {"1": WOOD[1], "2": WOOD[2], "3": WOOD[0], "4": IRON[2]}),
    "pflug": (["................",
               "1...............",
               ".1..............",
               "..1.............",
               "...1............",
               "....1...........",
               ".....1..........",
               "......1.........",
               ".......1222.....",
               "........13332...",
               ".......1.13332..",
               "......1....1332.",
               ".....1.......12.",
               "................",
               "................",
               "................"],
              {"1": WOOD[2], "2": IRON[1], "3": IRON[3]}),
    "schiff": (["................",
                ".......1........",
                ".......12.......",
                ".......122......",
                ".......1222.....",
                ".......12222....",
                ".......122222...",
                ".......1........",
                ".3333333333333..",
                "..344444444443..",
                "...3444444443...",
                "....33333333....",
                "..5555555555555.",
                "................",
                "................",
                "................"],
               {"1": WOOD[1], "2": (246, 236, 210), "3": WOOD[0], "4": WOOD[2], "5": WATER[2]}),
    "schwert": (["................",
                 "...........11...",
                 "..........1331..",
                 ".........1331...",
                 "........1331....",
                 ".......1331.....",
                 "......1331......",
                 "..4..1331.......",
                 "...4131.........",
                 "....41..........",
                 "...5.44.........",
                 "..5...4.........",
                 ".5..............",
                 "................",
                 "................",
                 "................"],
                {"1": IRON[1], "3": IRON[3], "4": (200, 160, 60), "5": WOOD[1]}),
    "kiste": (["................",
               "................",
               "................",
               "..111111111111..",
               "..133333333331..",
               "..122222222221..",
               "..111111111111..",
               "..122222222221..",
               "..123332233321..",
               "..122222222221..",
               "..122222222221..",
               "..111111111111..",
               "................",
               "................",
               "................",
               "................"],
              {"1": WOOD[0], "2": WOOD[2], "3": WOOD[3]}),
})


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
    files = ["terrain.png", "objects.png", "buildings.png", "icons.png", "tools.png", "ui.png",
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


# ================================================================== Etappe 2


def rect(img, x0, y0, w, h, c):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            put(img, x, y, c)


def ground_line(img, x0, x1, y=59):
    """Weicher Schatten-Sockel unter Gebaeuden."""
    for x in range(x0, x1):
        put(img, x, y + 1, (60, 90, 50, 110))


def stone_wall(img, x0, y0, w, h, cols=STONE):
    for y in range(h):
        row = y // 4
        for x in range(w):
            c = cols[2] if (x + row * 3) % 7 else cols[3]
            if y % 4 == 3 or (x + (row % 2) * 4) % 8 == 0:
                c = cols[1]
            if x in (0, w - 1):
                c = cols[1]
            put(img, x0 + x, y0 + y, c)


def brick_wall(img, x0, y0, w, h):
    for y in range(h):
        row = y // 3
        for x in range(w):
            c = BRICK[1] if (x // 3 + row) % 3 else BRICK[2]
            if y % 3 == 2 or (x + (row % 2) * 3) % 6 == 0:
                c = BRICK[0]
            put(img, x0 + x, y0 + y, c)


def plaster_wall(img, x0, y0, w, h, beams=True):
    """Fachwerk: heller Putz mit dunklen Balken."""
    for y in range(h):
        for x in range(w):
            c = PLASTER[1] if (x * 7 + y * 3) % 11 else PLASTER[0]
            if y < 2:
                c = PLASTER[2]
            put(img, x0 + x, y0 + y, c)
    if beams:
        for x in range(w):
            put(img, x0 + x, y0, WOOD[0])
            put(img, x0 + x, y0 + h // 2, WOOD[1])
            put(img, x0 + x, y0 + h - 1, WOOD[0])
        for bx in range(0, w, 10):
            for y in range(h):
                put(img, x0 + bx, y0 + y, WOOD[1])
        for y in range(h):
            put(img, x0 + w - 1, y0 + y, WOOD[0])
        # Diagonalstreben
        for bx in range(0, w - 10, 20):
            for i in range(h // 2):
                put(img, x0 + bx + 1 + i * 9 // max(1, h // 2), y0 + h // 2 + i, WOOD[1])


def tile_roof(img, x0, y0, w, h, cols=ROOF_RED, overhang=3):
    """Ziegel- oder Schieferdach: Reihen mit Schuppen, oben schmaler."""
    for y in range(h):
        inset = max(0, (h - y) // 3 - 1)
        xa = x0 + inset - overhang * y // h
        xb = x0 + w - inset + overhang * y // h
        for x in range(xa, xb):
            c = cols[2]
            if y % 4 == 3:
                c = cols[1]
            elif (x + (y // 4) * 2) % 4 == 0 and y % 4 == 2:
                c = cols[1]
            if y % 4 == 0 and (x + y) % 3 == 0:
                c = cols[3]
            if x - xa < 2:
                c = cols[3] if y % 4 != 3 else cols[2]
            if xb - x <= 2:
                c = cols[1]
            if y >= h - 2:
                c = cols[0] if y == h - 1 else cols[1]
            put(img, x, y0 + y, c)


def door(img, x0, y0, w, h, cols=None, arch=False):
    for y in range(h):
        for x in range(w):
            if arch and y == 0 and x in (0, w - 1):
                continue
            c = (70, 44, 34)
            if x in (0, w - 1) or y == 0:
                c = WOOD[0]
            elif x % 3 == 0:
                c = (86, 54, 40)
            put(img, x0 + x, y0 + y, c)
    put(img, x0 + w - 3, y0 + h // 2, THATCH[3])


def window(img, x0, y0, w=6, h=6, lit=True, shutters=False):
    for y in range(h):
        for x in range(w):
            edge = x in (0, w - 1) or y in (0, h - 1)
            put(img, x0 + x, y0 + y, WOOD[0] if edge else ((250, 220, 130) if (x + y) % 3 else (230, 190, 100)) if lit
                else (60, 80, 110))
    for x in range(w):
        put(img, x0 + x, y0 + h // 2, WOOD[1])
    if shutters:
        for y in range(h):
            put(img, x0 - 2, y0 + y, (60, 110, 80))
            put(img, x0 - 1, y0 + y, (80, 140, 100))
            put(img, x0 + w, y0 + y, (80, 140, 100))
            put(img, x0 + w + 1, y0 + y, (60, 110, 80))


def chimney(img, x0, y0, h, cols=STONE):
    for y in range(h):
        for x in range(4):
            put(img, x0 + x, y0 + y, cols[2] if x < 3 else cols[1])
    for x in range(-1, 5):
        put(img, x0 + x, y0, cols[3])


def barrel(img, x0, y0):
    for y in range(7):
        for x in range(6):
            c = WOOD[2] if 1 <= x <= 3 else WOOD[1]
            if y in (1, 5):
                c = IRON[1]
            put(img, x0 + x, y0 + y, c)


def sack(img, x0, y0, c=(222, 206, 170)):
    for y in range(6):
        for x in range(6):
            if (y == 0 and x in (0, 5)) or (y == 5 and x in (0, 5)):
                continue
            put(img, x0 + x, y0 + y, c if x < 4 else (190, 172, 136))
    put(img, x0 + 2, y0 - 1, (190, 172, 136))
    put(img, x0 + 3, y0 - 1, (190, 172, 136))


def house_wood():
    img = new(64, 64)
    plank_wall(img, 10, 38, 44, 22)
    # Querbalken und Ecken
    for y in range(38, 60):
        put(img, 10, y, WOOD[0])
        put(img, 53, y, WOOD[0])
    door(img, 28, 46, 8, 14)
    window(img, 14, 43, 7, 7, shutters=True)
    window(img, 43, 43, 7, 7, shutters=True)
    # Blumenkasten
    for x in range(13, 22):
        put(img, x, 51, WOOD[1])
    for x, c in [(14, FLOWER[2]), (16, FLOWER[1]), (18, FLOWER[2]), (20, FLOWER[3])]:
        put(img, x, 50, c)
    tile_roof(img, 9, 12, 46, 28, SHINGLE)
    # Giebelfenster
    window(img, 29, 22, 6, 6)
    chimney(img, 42, 8, 10)
    ground_line(img, 10, 54)
    add_outline(img)
    return img


def house_stone():
    img = new(64, 64)
    stone_wall(img, 9, 34, 46, 26)
    door(img, 28, 45, 8, 15, arch=True)
    window(img, 13, 38, 7, 8, shutters=True)
    window(img, 44, 38, 7, 8, shutters=True)
    window(img, 13, 50, 7, 6)
    window(img, 44, 50, 7, 6)
    tile_roof(img, 8, 6, 48, 30, ROOF_RED)
    # Gaube
    for y in range(16, 26):
        for x in range(26, 38):
            put(img, x, y, PLASTER[1])
    window(img, 29, 18, 6, 6)
    for i, x in enumerate(range(24, 40)):
        put(img, x, 15, ROOF_RED[3] if i % 2 else ROOF_RED[2])
    chimney(img, 14, 2, 12)
    chimney(img, 46, 4, 10)
    ground_line(img, 9, 55)
    add_outline(img)
    return img


def store_big():
    img = new(64, 64)
    stone_wall(img, 3, 32, 58, 28)
    # grosses Tor
    for y in range(40, 60):
        for x in range(22, 42):
            c = WOOD[1] if (x - 22) % 4 else WOOD[0]
            if y == 40:
                c = WOOD[0]
            put(img, x, y, c)
    for x in range(22, 42):
        put(img, x, 49, WOOD[0])
    for i in range(10):
        put(img, 23 + i * 2, 41 + i * 2 - 1 if i < 9 else 58, WOOD[3])
    window(img, 7, 38, 6, 5, lit=False)
    window(img, 51, 38, 6, 5, lit=False)
    tile_roof(img, 2, 8, 60, 26, ROOF_RED)
    # Lastkran-Balken
    for x in range(28, 37):
        put(img, x, 22, WOOD[1])
    for y in range(22, 29):
        put(img, 35, y, (220, 210, 180))
    barrel(img, 5, 52)
    barrel(img, 12, 53)
    sack(img, 48, 54)
    sack(img, 54, 53, (200, 184, 150))
    ground_line(img, 3, 61)
    add_outline(img)
    return img


def mill(frame):
    img = new(64, 64)
    # Turm, nach oben schmaler
    for y in range(26, 60):
        t = (y - 26) / 34
        half = int(9 + t * 5)
        for x in range(32 - half, 32 + half):
            c = PLASTER[1] if (x * 5 + y * 3) % 13 else PLASTER[0]
            if x - (32 - half) < 2:
                c = PLASTER[2]
            if (32 + half) - x <= 2:
                c = PLASTER[0]
            put(img, x, y, c)
    # Sockel aus Stein
    stone_wall(img, 18, 54, 28, 6)
    door(img, 28, 48, 8, 12, arch=True)
    window(img, 29, 34, 5, 6)
    # Kegeldach
    for y in range(14, 28):
        half = int((y - 14) * 0.85) + 2
        for x in range(32 - half, 32 + half):
            c = SHINGLE[2] if x < 32 else SHINGLE[1]
            if (y + x) % 5 == 0:
                c = SHINGLE[3] if x < 32 else SHINGLE[2]
            put(img, x, y, c)
    add_outline(img)
    # Fluegel (vierzaehlig, 4 Frames = Vierteldrehung)
    sails = new(64, 64)
    cx, cy = 32, 22
    for k in range(4):
        a = math.radians(frame * 22.5 + k * 90)
        dx, dy = math.cos(a), math.sin(a)
        px, py = -dy, dx
        for r in range(3, 22):
            x = cx + dx * r
            y = cy + dy * r * 0.95
            put(sails, int(round(x)), int(round(y)), WOOD[1])
            if r > 6:
                for w in range(1, 6):
                    sx = x + px * w
                    sy = y + py * w * 0.95
                    c = (240, 232, 214) if (r + w) % 4 else (200, 186, 160)
                    if w == 5 or r == 21:
                        c = WOOD[1]
                    put(sails, int(round(sx)), int(round(sy)), c)
    add_outline(sails)
    img.alpha_composite(sails)
    for (x, y) in [(31, 21), (32, 21), (31, 22), (32, 22)]:
        put(img, x, y, IRON[1])
    return img


def bakery():
    img = new(64, 64)
    plaster_wall(img, 8, 36, 48, 24)
    door(img, 30, 46, 8, 14)
    window(img, 13, 42, 8, 7)
    window(img, 44, 42, 7, 7)
    # Ladenschild mit Brezel
    for y in range(28, 35):
        put(img, 19, y, WOOD[0])
    for y in range(32, 38):
        for x in range(12, 20):
            put(img, x, y, WOOD[2] if 0 < x - 12 < 7 and 32 < y < 37 else WOOD[0])
    for (x, y) in [(14, 34), (15, 33), (16, 34), (17, 33), (18, 34), (15, 35), (17, 35), (16, 36)]:
        put(img, x, y, (200, 130, 60))
    thatch_roof(img, 7, 12, 50, 26)
    # Backofen-Kamin aus Ziegeln (Rauch bei 42,20)
    for y in range(20, 34):
        for x in range(40, 46):
            put(img, x, y, BRICK[1] if (y // 2 + x // 3) % 2 else BRICK[2])
    for x in range(39, 47):
        put(img, x, 20, BRICK[0])
    # Brotlaibe auf dem Fensterbrett
    for x0 in (13, 17):
        for x in range(x0, x0 + 3):
            put(img, x, 49, (190, 120, 60))
    ground_line(img, 8, 56)
    add_outline(img)
    return img


def smokehouse():
    img = new(64, 64)
    for y in range(40, 60):
        for x in range(17, 47):
            c = SHINGLE[1] if (x - 17) % 5 else SHINGLE[0]
            if y % 6 == 0:
                c = SHINGLE[0]
            put(img, x, y, c)
    door(img, 28, 48, 8, 12)
    thatch_roof(img, 15, 24, 34, 18, [(90, 64, 40), (120, 86, 50), (150, 110, 64), (176, 136, 82)])
    # Rauchloch
    for x in range(29, 36):
        put(img, x, 25, DARK)
        put(img, x, 26, DARK)
    # Fischleine
    for x in range(8, 57):
        if x < 17 or x > 46:
            put(img, x, 44, (220, 210, 180))
    for y in range(44, 60):
        put(img, 8, y, WOOD[1])
        put(img, 56, y, WOOD[1])
    for fx in (10, 13, 50, 53):
        for y in range(45, 50):
            put(img, fx, y, (170, 110, 60) if y < 49 else (130, 80, 40))
            put(img, fx + 1, y, (200, 140, 80) if y < 48 else (150, 96, 50))
    ground_line(img, 8, 57)
    add_outline(img)
    return img


def henhouse():
    img = new(64, 64)
    # Stall links
    plank_wall(img, 6, 40, 24, 20)
    for y in range(50, 56):
        for x in range(14, 20):
            put(img, x, y, DARK)
    thatch_roof(img, 4, 26, 28, 16)
    # Leiter
    for i in range(6):
        put(img, 20 + i, 59 - i, WOOD[3])
    # Zaun rechts
    for x in range(32, 60):
        put(img, x, 46, WOOD[2])
        put(img, x, 52, WOOD[2])
    for x in range(32, 60, 5):
        for y in range(44, 60):
            put(img, x, y, WOOD[1])
    # Huehner
    for (hx, hy) in [(38, 54), (47, 50), (53, 55)]:
        for (dx, dy) in [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (1, -1), (2, -1), (3, 1)]:
            put(img, hx + dx, hy + dy, (248, 244, 236))
        put(img, hx + 2, hy - 2, (220, 50, 50))
        put(img, hx + 3, hy - 1, (240, 180, 40))
        put(img, hx + 1, hy + 2, (240, 180, 40))
    # Koerner
    for (x, y) in [(41, 57), (44, 56), (50, 58), (35, 58)]:
        put(img, x, y, WHEAT[2])
    ground_line(img, 6, 60)
    add_outline(img)
    return img


def sawpit():
    img = new(64, 64)
    # Pfosten und Pultdach
    for x in (16, 47):
        for y in range(30, 60):
            put(img, x, y, WOOD[1])
            put(img, x + 1, y, WOOD[2])
    thatch_roof(img, 12, 22, 40, 10, [(110, 72, 40), (140, 96, 50), (170, 120, 64), (196, 150, 86)])
    # Saegebock
    for x in range(20, 44):
        put(img, x, 50, WOOD[1])
        put(img, x, 51, WOOD[0])
    for (x0, d) in [(22, 1), (41, -1)]:
        for i in range(8):
            put(img, x0 + d * (i // 2), 51 + i, WOOD[1])
            put(img, x0 - d * (i // 2), 51 + i, WOOD[1])
    # Stamm auf dem Bock
    for y in range(44, 50):
        for x in range(19, 46):
            c = WOOD[2] if y < 46 else WOOD[1]
            if y == 44:
                c = WOOD[3]
            put(img, x, y, c)
    for y in range(44, 50):
        put(img, 46, y, (220, 180, 120))
    # Saege
    for y in range(36, 56):
        put(img, 33, y, IRON[3] if y % 2 else IRON[2])
    for x in range(30, 37):
        put(img, x, 35, WOOD[1])
    # Bretterstapel
    for y in range(54, 60):
        for x in range(48, 62):
            put(img, x, y, WOOD[3] if y % 2 == 0 else WOOD[2])
    # Saegespaene
    for (x, y) in [(28, 58), (31, 59), (36, 58), (39, 59), (34, 57)]:
        put(img, x, y, (230, 200, 140))
    ground_line(img, 16, 62)
    add_outline(img)
    return img


def claypit():
    img = new(64, 64)
    # Grube (Ellipse)
    for y in range(36, 61):
        for x in range(10, 54):
            dx = (x + 0.5 - 32) / 21
            dy = (y + 0.5 - 49) / 11
            d = dx * dx + dy * dy
            if d <= 1:
                c = CLAY[2]
                if d < 0.75:
                    c = CLAY[1]
                if d < 0.75 and dy < -0.2:
                    c = CLAY[0]
                if d < 0.4 and (x + y) % 5 == 0:
                    c = (128, 78, 46)
                put(img, x, y, c)
    # Wasserpfuetze
    for y in range(50, 55):
        for x in range(34, 44):
            if (x - 39) ** 2 / 25 + (y - 52.5) ** 2 / 6 <= 1:
                put(img, x, y, WATER[2] if y < 52 else WATER[1])
    # Lehmhaufen
    blob(img, 52, 54, 7, 5, [CLAY[0], CLAY[1], CLAY[2], (230, 176, 120)], noise_seed=41)
    # Schaufel
    for i in range(14):
        put(img, 18 + i // 3, 30 + i, WOOD[2])
    for y in range(44, 49):
        for x in range(21, 25):
            put(img, x, y, IRON[2])
    ground_line(img, 10, 60)
    add_outline(img)
    return img


def brickworks():
    img = new(64, 64)
    # Brennofen (Kuppel) links
    for y in range(28, 60):
        for x in range(4, 40):
            dx = (x + 0.5 - 22) / 18
            dy = (y + 0.5 - 60) / 30
            if dx * dx + dy * dy <= 1:
                c = BRICK[1] if ((x // 3) + (y // 3)) % 2 else BRICK[2]
                if y % 3 == 2:
                    c = BRICK[0]
                if dx < -0.5:
                    c = BRICK[2] if y % 3 != 2 else BRICK[1]
                put(img, x, y, c)
    # Feuerloch
    for y in range(48, 60):
        for x in range(16, 28):
            dx = (x + 0.5 - 22) / 6
            dy = (y + 0.5 - 60) / 12
            if dx * dx + dy * dy <= 1:
                c = GLOW[0]
                if dx * dx + dy * dy < 0.5:
                    c = GLOW[1]
                if dx * dx + dy * dy < 0.2:
                    c = GLOW[2]
                put(img, x, y, c)
    # Schornstein (Rauch bei 46,20)
    for y in range(20, 52):
        for x in range(43, 50):
            put(img, x, y, BRICK[1] if (y // 3 + x // 3) % 2 else BRICK[2])
    for x in range(42, 51):
        put(img, x, 20, BRICK[0])
        put(img, x, 21, BRICK[0])
    # Ziegelstapel rechts
    for (x0, y0) in [(50, 52), (50, 46), (56, 52)]:
        for y in range(y0, y0 + 6):
            for x in range(x0, x0 + 6):
                c = ROOF_RED[2] if y % 2 else ROOF_RED[1]
                put(img, x, y, c)
    ground_line(img, 4, 62)
    add_outline(img)
    return img


def quarry():
    img = new(64, 64)
    blob(img, 32, 44, 26, 17, STONE[0:5], noise_seed=51, jag=0.05)
    # Abgebaute, flache Stufen
    for (y0, x0, x1) in [(36, 14, 34), (44, 20, 46), (52, 12, 30)]:
        for x in range(x0, x1):
            put(img, x, y0, STONE[4])
            put(img, x, y0 + 1, STONE[3])
            for y in range(y0 + 2, y0 + 5):
                put(img, x, y, STONE[1])
    # Bloecke vorne
    for (x0, y0) in [(42, 54), (50, 52)]:
        for y in range(y0, y0 + 6):
            for x in range(x0, x0 + 7):
                put(img, x, y, STONE[3] if y == y0 or x == x0 else STONE[2])
    # Keil und Hammer
    for i in range(6):
        put(img, 24 + i, 30 - i, WOOD[2])
    ground_line(img, 8, 58)
    add_outline(img)
    return img


def charcoal():
    img = new(64, 64)
    # Meiler: Erdkuppel mit Rauchloch (Rauch bei 32,34)
    cols = [(52, 40, 36), (76, 58, 48), (100, 78, 60), (124, 98, 74)]
    blob(img, 32, 52, 20, 16, cols, noise_seed=61)
    for (x, y) in [(31, 37), (32, 37), (33, 37), (32, 36)]:
        put(img, x, y, DARK)
    for (x, y) in [(22, 50), (40, 48), (30, 56), (38, 55)]:
        put(img, x, y, GLOW[0])
        put(img, x + 1, y, GLOW[1])
    # Holzstapel
    for y in range(50, 60):
        for x in range(50, 62):
            c = WOOD[2]
            if (x - 50) % 4 == 0 or y % 5 == 0:
                c = WOOD[1]
            put(img, x, y, c)
    for y in range(50, 60, 5):
        for x in range(51, 61, 4):
            put(img, x + 1, y + 2, WOOD[3])
    ground_line(img, 12, 62)
    add_outline(img)
    return img


def mine():
    img = new(64, 64)
    blob(img, 32, 42, 28, 20, [STONE[0], (90, 86, 96), STONE[1], STONE[2], STONE[3]], noise_seed=71, jag=0.05)
    for (x, y) in [(14, 36), (15, 35), (16, 36), (46, 32), (47, 33)]:
        put(img, x, y, GRASS[2])
    # Stollen
    for y in range(40, 60):
        for x in range(23, 41):
            put(img, x, y, DARK if y > 42 else (60, 50, 50))
    for y in range(38, 60):
        for x in (21, 22, 41, 42):
            put(img, x, y, WOOD[2] if x in (21, 41) else WOOD[1])
    for x in range(19, 45):
        put(img, x, 38, WOOD[2])
        put(img, x, 39, WOOD[1])
    # Gleise
    for y in range(48, 64, 3):
        for x in range(27, 37):
            put(img, x, y, WOOD[1])
    for y in range(46, 64):
        put(img, 28, y, IRON[2])
        put(img, 35, y, IRON[2])
    # Lore mit Erz
    for y in range(52, 58):
        for x in range(26, 38):
            put(img, x, y, IRON[1] if y > 52 else IRON[2])
    for x in range(27, 37, 2):
        put(img, x, 51, (180, 110, 80))
        put(img, x + 1, 51, (140, 80, 60))
    # Erzbrocken neben dem Eingang
    for (x0, y0) in [(48, 54), (12, 55)]:
        blob(img, x0 + 3, y0 + 3, 4, 3, [STONE[0], STONE[1], (160, 100, 80), (200, 130, 90)], noise_seed=x0)
    ground_line(img, 6, 60)
    add_outline(img)
    return img


def smelter():
    img = new(64, 64)
    # Hoher Ofen (Rauch bei 38,14)
    for y in range(14, 60):
        t = (y - 14) / 46
        half = int(6 + t * 9)
        for x in range(38 - half, 38 + half):
            c = STONE[2] if (x + (y // 4) * 3) % 6 else STONE[3]
            if y % 4 == 3:
                c = STONE[1]
            if x - (38 - half) < 2:
                c = STONE[3]
            put(img, x, y, c)
    for x in range(31, 46):
        put(img, x, 14, STONE[4])
        put(img, x, 15, STONE[1])
    # Glut-Oeffnung
    for y in range(46, 58):
        for x in range(33, 44):
            dx = (x + 0.5 - 38.5) / 5.5
            dy = (y + 0.5 - 58) / 12
            if dx * dx + dy * dy <= 1:
                put(img, x, y, GLOW[2] if dx * dx + dy * dy < 0.25 else GLOW[1] if dx * dx + dy * dy < 0.6 else GLOW[0])
    # Blasebalg und Kohlehaufen
    for y in range(48, 56):
        for x in range(10, 22):
            if abs(x - 16) * 2 + abs(y - 52) * 3 < 14:
                put(img, x, y, (120, 80, 50) if y < 52 else (90, 60, 40))
    for x in range(21, 25):
        put(img, x, 52, WOOD[0])
    blob(img, 54, 56, 6, 4, [(30, 30, 36), (50, 50, 58), (70, 70, 80)], noise_seed=81)
    # Eisenbarren
    for x in range(12, 22):
        put(img, x, 58, IRON[2])
        put(img, x, 59, IRON[1])
    ground_line(img, 10, 61)
    add_outline(img)
    return img


def smithy():
    img = new(64, 64)
    # Rueckwand und Esse
    stone_wall(img, 8, 32, 48, 28)
    for y in range(40, 52):
        for x in range(12, 28):
            put(img, x, y, STONE[1])
    for y in range(46, 52):
        for x in range(14, 26):
            put(img, x, y, GLOW[1] if (x + y) % 3 else GLOW[2])
    # Kamin (Rauch bei 46,18)
    chimney(img, 44, 18, 16)
    # Dach auf Pfosten (offene Front)
    tile_roof(img, 6, 20, 52, 14, SHINGLE, overhang=2)
    for x in (8, 54):
        for y in range(34, 60):
            put(img, x, y, WOOD[1])
            put(img, x + 1, y, WOOD[2])
    # Amboss
    for y in range(50, 54):
        for x in range(36, 48):
            if y == 50 or 38 <= x <= 45:
                put(img, x, y, IRON[2] if y == 50 else IRON[1])
    for y in range(54, 60):
        for x in range(39, 45):
            put(img, x, y, WOOD[1])
    # Werkzeuge an der Wand
    for (x0, c) in [(32, IRON[3]), (35, IRON[2])]:
        for y in range(36, 44):
            put(img, x0, y, WOOD[2])
        put(img, x0 - 1, 36, c)
        put(img, x0 + 1, 36, c)
    ground_line(img, 8, 56)
    add_outline(img)
    return img


def scriptorium():
    img = new(64, 64)
    plaster_wall(img, 9, 36, 46, 24)
    door(img, 28, 46, 8, 14, arch=True)
    window(img, 13, 41, 8, 8)
    window(img, 43, 41, 8, 8)
    tile_roof(img, 8, 12, 48, 26, SLATE)
    # kleiner Turm mit Glocke
    for y in range(4, 16):
        for x in range(28, 36):
            put(img, x, y, PLASTER[1] if x < 34 else PLASTER[0])
    for y in range(7, 12):
        for x in range(30, 34):
            put(img, x, y, DARK)
    put(img, 31, 9, (230, 190, 70))
    put(img, 32, 9, (230, 190, 70))
    put(img, 31, 10, (200, 150, 50))
    put(img, 32, 10, (200, 150, 50))
    for y in range(0, 5):
        for x in range(30 - y, 34 + y):
            put(img, x, y + 1, SLATE[2] if x < 32 else SLATE[1])
    # Schild mit Feder
    for y in range(29, 34):
        for x in range(42, 50):
            put(img, x, y, (240, 230, 200))
    for i in range(5):
        put(img, 44 + i, 33 - i, (60, 60, 120))
    ground_line(img, 9, 55)
    add_outline(img)
    return img


def library():
    img = new(64, 64)
    stone_wall(img, 6, 30, 52, 30, [STONE[1], STONE[2], STONE[3], STONE[4], STONE[4]])
    # Saeulen
    for x0 in (10, 20, 40, 50):
        for y in range(34, 58):
            for x in range(x0, x0 + 4):
                put(img, x, y, (236, 232, 222) if x < x0 + 2 else (200, 196, 186))
        for x in range(x0 - 1, x0 + 5):
            put(img, x, 33, (250, 246, 236))
            put(img, x, 58, (200, 196, 186))
    door(img, 27, 42, 10, 18, arch=True)
    window(img, 14, 38, 5, 9) if False else None
    # Treppe
    for i, y in enumerate(range(58, 61)):
        for x in range(4 - i, 60 + i):
            put(img, x, y, STONE[3] if i % 2 == 0 else STONE[2])
    # Giebel mit Rundfenster
    tile_roof(img, 4, 6, 56, 26, SLATE)
    for y in range(13, 23):
        for x in range(27, 37):
            d = (x + 0.5 - 32) ** 2 + (y + 0.5 - 18) ** 2
            if d <= 22:
                put(img, x, y, WOOD[0] if d > 14 else ((250, 220, 130) if (x + y) % 2 else (120, 160, 220)))
    for x in range(30, 34):
        put(img, x, 4, (230, 190, 70))
    for y in range(1, 5):
        put(img, 31, y, (230, 190, 70))
        put(img, 32, y, (200, 150, 50))
    ground_line(img, 4, 60)
    add_outline(img)
    return img


def orchard_tile(stage):
    """Obstgarten-Kachel 16x16: 0 Setzlinge, 1 klein, 2 gruen, 3 Aepfel."""
    img = new(16, 16)
    for y in range(16):
        for x in range(16):
            c = GRASS[1] if (x * 3 + y * 5) % 7 else GRASS[0]
            put(img, x, y, c)
    for x in range(0, 16, 2):
        put(img, x, 15, SOIL[1])
    cx, cy = 8, 8
    if stage == 0:
        for y in range(8, 13):
            put(img, cx, y, WOOD[2])
        put(img, cx - 1, 8, LEAF[3])
        put(img, cx + 1, 9, LEAF[3])
        for x in range(5, 12):
            put(img, x, 13, SOIL[0])
    else:
        for y in range(9, 14):
            put(img, cx, y, WOOD[1])
            put(img, cx + 1, y, WOOD[2])
        r = 4.0 if stage == 1 else 6.0
        crown = new(16, 16)
        blob(crown, 8.5, 7, r, r * 0.85, LEAF[1:5], noise_seed=90 + stage)
        if stage == 3:
            for (x, y) in [(5, 6), (10, 5), (8, 9), (12, 8), (6, 9), (9, 3)]:
                put(crown, x, y, (220, 50, 50))
                put(crown, x, y - 1, (255, 140, 120)) if (x + y) % 2 else None
        add_outline(crown)
        img.alpha_composite(crown)
    return img


def gen_buildings2():
    """buildings.png: Zellen 64x64, 8 je Zeile (Reihenfolge = Data.BUILDING_CELLS)."""
    order = [house_wood(), house_stone(), store_big(), mill(0), mill(1), mill(2), mill(3),
             bakery(), smokehouse(), henhouse(), sawpit(), claypit(), brickworks(), quarry(),
             charcoal(), mine(), smelter(), smithy(), scriptorium(), library()]
    atlas = new(512, 64 * ((len(order) + 7) // 8))
    for i, im in enumerate(order):
        atlas.paste(im, ((i % 8) * 64, (i // 8) * 64))
    atlas.save(os.path.join(OUT, "buildings.png"))


def tools2():
    """Zusaetzliche Werkzeuge: Kochloeffel, Buch, Schaufel (an tools.png angehaengt)."""
    spoon = new(16, 16)
    for i in range(9):
        put(spoon, 3 + i, 13 - i, WOOD[2])
    blob(spoon, 12.5, 3.5, 2.5, 2.2, [WOOD[1], WOOD[2], WOOD[3]], noise_seed=5)
    add_outline(spoon)
    book = new(16, 16)
    for y in range(4, 13):
        for x in range(3, 13):
            c = (180, 60, 50) if x < 4 or x > 11 else (246, 236, 210)
            if y in (4, 12):
                c = (150, 46, 40)
            if 4 < y < 12 and x == 8:
                c = (200, 186, 160)
            put(book, x, y, c)
    for x in range(5, 8):
        put(book, x, 7, (120, 110, 100))
        put(book, x + 4, 9, (120, 110, 100))
    add_outline(book)
    shovel = new(16, 16)
    for i in range(9):
        put(shovel, 2 + i, 14 - i, WOOD[2])
    for y in range(1, 6):
        for x in range(10, 15):
            if abs(x - 12) + abs(y - 3) < 4:
                put(shovel, x, y, STONE[3])
    add_outline(shovel)
    return [spoon, book, shovel]


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gen_terrain()
    gen_objects()
    gen_buildings2()
    gen_settlers()
    tools()
    gen_icons()
    ui_panel()
    preview()
    print("ok")
