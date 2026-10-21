#!/usr/bin/env python3
"""Schmuck: Blumen, Statuen, Brunnen, Wege, Park (josh 2026-10-20).

Wird aus gen_art.py aufgerufen:
  decor_buildings()  Bilder in der Reihenfolge der Zellen ab 60 in buildings.png (Data.BUILDING_CELLS;
                 Bilder mit mehreren Frames liegen in aufeinanderfolgenden Zellen)
  gravel(m), bricks(m), hedge(m)
                 Kies-, Ziegelweg und Hecke 16x16 mit Nachbarmaske N=1 O=2 S=4 W=8
                 (objects3.png Zeilen y=64, 80, 96; tools/gen_art_land.py)
  ICONS_DECOR    Symbol "schmuck" fuer den Bau-Reiter

Zellen 64x64: Grundflaeche unten mittig, Unterkante y=60 (1x1: x 24..39, 2x2: x 16..47, 3x3: x 8..55).
"""
import math
import random

from gen_art import (new, put, add_outline, blob, WOOD, STONE, LEAF, GRASS, SOIL, SAND, WATER, FOAM, BRICK,
                     ROOF_RED, IRON, CLAY, OUTLINE, ground_line, get_a)

N, E, S, W = 1, 2, 4, 8

MARBLE = [(150, 150, 160), (188, 188, 196), (222, 222, 226), (246, 246, 248)]
GRANITE = [(84, 86, 100), (116, 118, 132), (150, 152, 164), (186, 188, 198)]
BRONZE = [(66, 82, 66), (88, 118, 92), (116, 150, 112), (156, 186, 140)]
GOLD = [(150, 104, 30), (204, 156, 48), (240, 204, 88), (255, 240, 170)]
TERRA = [(130, 62, 40), (172, 88, 54), (206, 120, 74), (232, 160, 108)]
MOSS = [(70, 104, 56), (96, 136, 70)]
GLASS = [(250, 236, 160), (255, 250, 214)]
HOLO = [(40, 200, 230), (120, 236, 250), (210, 252, 255)]
FLOWER_SETS = {
    "rot": [(150, 30, 46), (214, 52, 64), (250, 110, 110), (255, 200, 190)],
    "gelb": [(196, 132, 20), (240, 190, 40), (255, 228, 96), (255, 250, 200)],
    "blau": [(70, 60, 160), (110, 100, 220), (160, 156, 250), (220, 220, 255)],
}
GROUND_SHADOW = (60, 90, 50, 110)


def rect(img, x0, y0, w, h, c):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            put(img, x, y, c)


def span_shade(img, rows, pal, light_left=True):
    """rows: {y: (x_a, x_b)} -> von links hell nach rechts dunkel schattiert (4 Farben)."""
    for y, (a, b) in rows.items():
        w = max(1, b - a)
        for x in range(a, b + 1):
            t = (x - a) / w
            if not light_left:
                t = 1 - t
            i = 3 if t < 0.22 else 2 if t < 0.55 else 1 if t < 0.85 else 0
            put(img, x, y, pal[i])


def ellipse(img, cx, cy, rx, ry, c, only_edge=False):
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            if d <= 1.0 and (not only_edge or d > 0.6):
                put(img, x, y, c)


def in_ellipse(x, y, cx, cy, rx, ry):
    return ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0


def pedestal(img, x0, x1, y0, y1, pal=GRANITE, steps=2):
    """Gestufter Sockel: unten breit, oben schmaler, Kanten hell."""
    h = y1 - y0
    for s in range(steps):
        ya = y0 + h * s // steps
        yb = y0 + h * (s + 1) // steps
        inset = (steps - 1 - s) * 2
        for y in range(ya, yb):
            for x in range(x0 + inset, x1 - inset):
                c = pal[2]
                if y == ya:
                    c = pal[3]
                elif x == x0 + inset:
                    c = pal[3]
                elif x >= x1 - inset - 2:
                    c = pal[1]
                elif y == yb - 1:
                    c = pal[1]
                put(img, x, y, c)


# ------------------------------------------------------------------ Blumen
def flowerbed(colors):
    """Blumenbeet 1x1: Holzrand, dunkle Erde, Bluetenbueschel in einer Farbe mit weissen Tupfen."""
    img = new(64, 64)
    pal = FLOWER_SETS[colors]
    # Rand aus Holzbohlen (leicht schraeg von oben gesehen)
    for y in range(47, 60):
        for x in range(23, 41):
            edge = y in (47, 48) or y >= 57 or x in (23, 24, 39, 40)
            if edge:
                c = WOOD[3] if y in (47, 57) else WOOD[2] if y in (48, 58) else WOOD[1]
                if x in (23, 24, 39, 40) and not y in (47, 57):
                    c = WOOD[2] if x in (23, 39) else WOOD[1]
            else:
                c = SOIL[0] if (x + y) % 3 else SOIL[1]
            put(img, x, y, c)
    # Blaetter und Blueten
    rnd = random.Random({"rot": 1, "gelb": 2, "blau": 3}[colors])
    for (cx, cy) in [(27, 50), (32, 49), (36, 50), (29, 54), (34, 54), (31, 52)]:
        blob(img, cx + 0.5, cy + 0.5, 3.2, 2.6, [LEAF[1], LEAF[2], LEAF[3]], noise_seed=cx + cy)
    for (cx, cy) in [(27, 48), (32, 47), (37, 48), (29, 52), (35, 52), (32, 51), (26, 52), (38, 52)]:
        cx += rnd.randint(-1, 0)
        put(img, cx, cy - 1, pal[2])
        put(img, cx - 1, cy, pal[1])
        put(img, cx + 1, cy, pal[1])
        put(img, cx, cy + 1, pal[0])
        put(img, cx, cy, pal[3])
    add_outline(img)
    return img


def flower_tub():
    """Blumenkuebel 1x1: Terrakotta-Topf mit Blumen in drei Farben."""
    img = new(64, 64)
    # Topf: oben breiter Rand, nach unten schmaler
    for y in range(47, 60):
        half = 7 if y <= 48 else 6 - (y - 49) // 4
        for x in range(32 - half, 32 + half):
            t = (x - (32 - half)) / (2 * half)
            c = TERRA[3] if t < 0.2 else TERRA[2] if t < 0.6 else TERRA[1]
            if y in (47, 48):
                c = TERRA[3] if y == 47 else TERRA[1]
            if y == 53 and 0.1 < t < 0.9:
                c = TERRA[0]
            put(img, x, y, c)
    # Gruen und Blueten
    blob(img, 32, 42, 9, 6.5, [LEAF[0], LEAF[1], LEAF[2], LEAF[3]], noise_seed=7, jag=0.12)
    rnd = random.Random(11)
    sets = [FLOWER_SETS["rot"], FLOWER_SETS["gelb"], [(150, 50, 120), (206, 80, 170), (240, 140, 210), (255, 220, 240)],
            [(200, 200, 200), (236, 236, 236), (255, 255, 255), (255, 255, 255)]]
    for i, (cx, cy) in enumerate([(27, 40), (31, 37), (36, 39), (29, 44), (34, 43), (38, 43), (25, 43), (33, 40)]):
        pal = sets[i % len(sets)]
        put(img, cx, cy - 1, pal[2])
        put(img, cx - 1, cy, pal[1])
        put(img, cx + 1, cy, pal[1])
        put(img, cx, cy + 1, pal[0])
        put(img, cx, cy, (255, 236, 120))
    ground_line(img, 25, 40, 59)
    add_outline(img)
    return img


def rose_arch():
    """Rosenbogen 1x1: zwei Holzpfosten, runder Bogen, Ranken mit roten und rosa Rosen."""
    img = new(64, 64)
    for x in (22, 23, 40, 41):
        for y in range(30, 60):
            put(img, x, y, WOOD[2] if x in (22, 40) else WOOD[1])
    for i in range(0, 181, 3):
        a = math.radians(i)
        for r in (9.5, 10.5):
            x = 32 + math.cos(a) * r - 0.5
            y = 31 - math.sin(a) * r * 0.9
            put(img, int(round(x)), int(round(y)), WOOD[2] if r < 10 else WOOD[1])
    # Ranken
    rnd = random.Random(5)
    pts = []
    for i in range(0, 181, 12):
        a = math.radians(i)
        pts.append((32 + math.cos(a) * 10, 31 - math.sin(a) * 9))
    for y in range(32, 58, 4):
        pts.append((22.5, y))
        pts.append((40.5, y + 2))
    for (px, py) in pts:
        blob(img, px, py, 2.6, 2.2, [LEAF[1], LEAF[2], LEAF[3]], noise_seed=int(px * 3 + py))
    roses = [FLOWER_SETS["rot"], [(170, 60, 100), (226, 100, 150), (250, 160, 190), (255, 230, 240)]]
    for k, (px, py) in enumerate(pts[::2]):
        pal = roses[k % 2]
        x, y = int(px) + rnd.randint(-1, 1), int(py) + rnd.randint(-1, 1)
        put(img, x, y, pal[2])
        put(img, x + 1, y, pal[1])
        put(img, x, y + 1, pal[1])
        put(img, x + 1, y + 1, pal[0])
    ground_line(img, 20, 44, 59)
    add_outline(img)
    return img


# ------------------------------------------------------------------ Moebel und Lampen
def bench():
    """Holzbank 1x1 von vorn: Lehne aus zwei Latten, Sitz, vier Beine, eiserne Seitenteile."""
    img = new(64, 64)
    x0, x1 = 21, 43
    for y, c in [(42, WOOD[3]), (43, WOOD[2]), (45, WOOD[3]), (46, WOOD[2])]:
        for x in range(x0 + 1, x1 - 1):
            put(img, x, y, c if (x - x0) % 9 else WOOD[1])
    # Sitzflaeche (von oben etwas sichtbar)
    for y in range(49, 53):
        for x in range(x0, x1):
            c = WOOD[3] if y == 49 else WOOD[2] if y < 52 else WOOD[1]
            if y == 51 and (x - x0) % 7 == 0:
                c = WOOD[1]
            put(img, x, y, c)
    # Seitenteile und Beine (Eisen)
    for x in (x0 + 1, x1 - 2):
        for y in range(41, 60):
            if 47 <= y <= 48 or y >= 53 or y <= 46:
                put(img, x, y, IRON[1] if x == x0 + 1 else IRON[0])
        put(img, x, 40, IRON[2])
    for x in (x0 + 4, x1 - 5):
        for y in range(53, 59):
            put(img, x, y, WOOD[0])
    ground_line(img, x0, x1, 59)
    add_outline(img)
    return img


def lantern():
    """Laterne 1x1 (Oellampe): Eisenpfahl, Glaskasten mit Flamme, Dach mit Knauf."""
    img = new(64, 64)
    for y in range(26, 58):
        put(img, 31, y, IRON[2])
        put(img, 32, y, IRON[1])
    rect(img, 29, 56, 6, 3, IRON[1])
    rect(img, 29, 56, 6, 1, IRON[2])
    # Laternenkasten
    for y in range(15, 26):
        for x in range(27, 37):
            edge = x in (27, 36) or y in (15, 25)
            c = IRON[0] if edge else GLASS[0] if (x + y) % 4 else GLASS[1]
            if x == 32 and not edge:
                c = IRON[1]
            put(img, x, y, c)
    for (x, y) in [(31, 20), (31, 21), (30, 21), (31, 22), (30, 22)]:
        put(img, x, y, (250, 160, 50))
    for y in range(11, 15):
        half = 6 - (y - 11)
        for x in range(32 - half, 32 + half):
            put(img, x, y, IRON[2] if x < 32 else IRON[1])
    put(img, 31, 10, GOLD[2])
    put(img, 32, 10, GOLD[1])
    # Querarm mit Ranke
    for x in range(28, 36):
        put(img, x, 27, IRON[1])
    ground_line(img, 28, 36, 59)
    add_outline(img)
    return img


def street_lamp():
    """Strassenlaterne 1x1 (elektrisch): hoher gruener Mast, Bogenarm, Lampenschirm mit hellem Licht."""
    img = new(64, 64)
    MAST = [(34, 64, 60), (52, 92, 84), (78, 124, 112), (120, 166, 150)]
    for y in range(9, 58):
        w = 1 if y < 48 else 2
        for x in range(31 - (w - 1), 33 + (w - 1)):
            put(img, x, y, MAST[2] if x <= 31 else MAST[1])
    for x in range(28, 36):
        for y in range(55, 60):
            put(img, x, y, MAST[2] if y == 55 else MAST[1] if x < 34 else MAST[0])
    for y in (46, 47):
        for x in range(29, 35):
            put(img, x, y, MAST[3] if y == 46 else MAST[1])
    # Bogen nach rechts
    for i in range(0, 91, 4):
        a = math.radians(i)
        put(img, int(round(36 - math.cos(a) * 4)), int(round(13 - math.sin(a) * 4)), MAST[2])
    for x in range(36, 42):
        put(img, x, 9, MAST[2])
    # Lampenschirm und Leuchtkoerper
    for y in range(10, 14):
        half = 2 + (y - 10)
        for x in range(42 - half, 42 + half):
            put(img, x, y, MAST[2] if x < 42 else MAST[1])
    for y in range(14, 17):
        for x in range(39, 45):
            put(img, x, y, (255, 252, 220) if 40 <= x <= 43 else (240, 230, 170))
    # zweiter Arm links
    for x in range(24, 31):
        put(img, x, 9, MAST[2])
    for y in range(10, 14):
        half = 2 + (y - 10)
        for x in range(22 - half, 22 + half):
            put(img, x, y, MAST[2] if x < 22 else MAST[1])
    for y in range(14, 17):
        for x in range(19, 25):
            put(img, x, y, (255, 252, 220) if 20 <= x <= 23 else (240, 230, 170))
    for x in range(30, 34):
        put(img, x, 7, GOLD[2])
    put(img, 31, 6, GOLD[3])
    ground_line(img, 27, 37, 59)
    add_outline(img)
    return img


def sundial():
    """Sonnenuhr 1x1: Saeule aus Stein, Zifferblatt von oben, schraeger Zeiger aus Messing."""
    img = new(64, 64)
    pedestal(img, 26, 38, 54, 60, MARBLE, 2)
    for y in range(42, 54):
        for x in range(29, 35):
            c = MARBLE[3] if x == 29 else MARBLE[2] if x < 33 else MARBLE[1]
            if y in (45, 51):
                c = MARBLE[1]
            put(img, x, y, c)
    for y in range(36, 43):
        for x in range(22, 42):
            if in_ellipse(x, y, 32, 39.5, 10, 4):
                c = MARBLE[3] if y < 39 else MARBLE[2]
                if not in_ellipse(x, y, 32, 39.5, 8.5, 3):
                    c = MARBLE[1] if y >= 40 else MARBLE[2]
                put(img, x, y, c)
    # Stundenstriche
    for i in range(0, 181, 30):
        a = math.radians(i)
        put(img, int(round(32 - math.cos(a) * 7.5)), int(round(39.5 - math.sin(a) * 2.5)), OUTLINE[:3])
    # Zeiger (Gnomon) und Schatten
    for i in range(6):
        for y in range(39 - i, 40):
            put(img, 30 + i, y, GOLD[2] if y == 39 - i else GOLD[1])
    for x in range(36, 40):
        put(img, x, 40, (110, 110, 120))
    ground_line(img, 25, 39, 59)
    add_outline(img)
    return img


# ------------------------------------------------------------------ Steine und Statuen
def menhir():
    """Menhir 1x1: grosser Stein mit Moos und eingeritzter Spirale, zwei kleine Steine davor."""
    img = new(64, 64)
    rows = {}
    for y in range(26, 59):
        t = (y - 26) / 32
        half = 3.5 + 2.5 * math.sin(min(1.0, t * 1.6) * math.pi / 2)
        lean = int((1 - t) * 2)
        rows[y] = (int(32 - half) + lean, int(32 + half) - 1 + lean)
    span_shade(img, rows, GRANITE)
    # Moos am Fuss und an der Seite
    for y in range(50, 59):
        a, b = rows[y]
        for x in range(a, b + 1):
            if (x * 5 + y * 3) % 7 < 3 - (58 - y) // 4:
                put(img, x, y, MOSS[(x + y) % 2])
    # Spirale
    for i in range(40):
        a = i * 0.45
        r = 0.4 + i * 0.07
        x = 32 + math.cos(a) * r
        y = 38 + math.sin(a) * r * 1.2
        put(img, int(round(x)), int(round(y)), GRANITE[0])
    for (cx, r) in [(25, 2.2), (39, 2.6)]:
        blob(img, cx, 57.5, r + 0.6, r, GRANITE, noise_seed=cx)
    ground_line(img, 22, 42, 59)
    add_outline(img)
    return img


def _figure(img, cx, top, pal, pose="staff"):
    """Stehende Figur im Gewand (Statue): Kopf, Hals, breite Schultern, Arme am Koerper, nach unten
    weiter werdendes Gewand. pose: staff (rechter Arm mit Stab erhoben), book (Buch vor der Brust)."""
    rows = {}
    bot = top + 27
    rows[top + 6] = (cx - 1, cx)  # Hals
    for y in range(top + 7, bot):
        k = y - top - 7
        if k < 2:
            half = 3.5 + k * 0.5
        elif k < 8:
            half = 4.0 - (k - 2) * 0.12
        else:
            half = 3.3 + (k - 8) * 0.17
        rows[y] = (int(round(cx - half)), int(round(cx + half - 1)))
    span_shade(img, rows, pal)
    # Arm links am Koerper, Guertel, Faltenwurf
    for y in range(top + 8, top + 17):
        put(img, rows[y][0] + 1, y, pal[2])
    put(img, rows[top + 17][0] + 1, top + 17, pal[3])
    for x in range(rows[top + 15][0] + 1, rows[top + 15][1]):
        put(img, x, top + 15, pal[1])
    for y in range(top + 17, bot):
        if (y - top) % 3:
            put(img, cx - 1, y, pal[1])
        if y > top + 20:
            put(img, cx + 2, y, pal[0])
    # Kopf mit Haar
    for y in range(top, top + 6):
        for x in range(cx - 3, cx + 3):
            if in_ellipse(x, y, cx, top + 3, 2.6, 3.0):
                c = pal[3] if x < cx - 1 else pal[2] if x < cx + 1 else pal[1]
                if y <= top + 1:
                    c = pal[1] if x >= cx else pal[2]
                put(img, x, y, c)
    if pose == "staff":
        # rechter Arm hoch, Stab
        for i in range(7):
            put(img, cx + 3 + i // 3, top + 9 - i, pal[2])
            put(img, cx + 4 + i // 3, top + 9 - i, pal[1])
        for y in range(top - 7, bot):
            put(img, cx + 6, y, pal[1] if y > top - 5 else pal[3])
        for (dx, dy) in [(5, -7), (7, -7), (6, -8), (6, -6)]:
            put(img, cx + dx, top + dy, pal[3])
    else:
        # rechter Arm angewinkelt, Buch vor der Brust
        for y in range(top + 10, top + 15):
            for x in range(cx - 2, cx + 4):
                edge = x in (cx - 2, cx + 3) or y == top + 14
                put(img, x, y, GOLD[1] if edge else (246, 238, 214) if x < cx + 1 else (214, 204, 180))
        for y in range(top + 10, top + 15):
            put(img, cx + 1, y, GOLD[0])


def stone_statue():
    """Steinstatue 1x1: Figur mit erhobenem Stab auf gestuftem Granitsockel."""
    img = new(64, 64)
    pedestal(img, 23, 41, 49, 60, GRANITE, 2)
    _figure(img, 32, 21, MARBLE, "staff")
    ground_line(img, 23, 41, 59)
    add_outline(img)
    return img


def bronze_statue():
    """Bronzestatue 1x1: Gelehrter mit Buch in gruener Bronze auf hohem Marmorsockel mit Goldschild."""
    img = new(64, 64)
    pedestal(img, 22, 42, 44, 60, MARBLE, 3)
    for x in range(28, 36):
        for y in range(50, 54):
            put(img, x, y, GOLD[2] if y == 50 else GOLD[1])
    _figure(img, 32, 17, BRONZE, "book")
    ground_line(img, 22, 42, 59)
    add_outline(img)
    return img


def obelisk():
    """Obelisk 1x1: hoher Granitpfeiler mit goldener Spitze und Zeichen, Stufensockel."""
    img = new(64, 64)
    pedestal(img, 23, 41, 51, 60, MARBLE, 2)
    rows = {}
    for y in range(12, 51):
        t = (y - 12) / 38
        half = 2.5 + t * 2.5
        rows[y] = (int(round(32 - half)), int(round(32 + half - 1)))
    span_shade(img, rows, [(150, 120, 104), (186, 150, 122), (214, 184, 150), (236, 214, 182)])
    for y in range(6, 12):
        half = (y - 6) * 0.5 + 0.5
        for x in range(int(round(32 - half)), int(round(32 + half))):
            put(img, x, y, GOLD[3] if x < 32 else GOLD[1])
    # Zeichen
    for y in range(16, 48, 5):
        put(img, 31, y, (120, 90, 80))
        put(img, 32, y + 1, (120, 90, 80))
        put(img, 31, y + 2, (120, 90, 80))
    ground_line(img, 23, 41, 59)
    add_outline(img)
    return img


HORSE = [
    "..........................S...",
    ".........................S....",
    "........................S.....",
    "...............##......S......",
    "..............####....#.......",
    "..............####...#........",
    "...............##..##.........",
    "..............######..........",
    ".............#######..........",
    "....##.......######...........",
    "...####......######...........",
    "..######.....#####............",
    ".###.####...######............",
    ".##...####.#######............",
    ".......####################...",
    "........###################.#.",
    "........####################.#",
    "........###################..#",
    ".........#################...#",
    ".........################....#",
    ".........##.##.......##.##....",
    ".........##.##.......##.##....",
    ".........##..##......##..##...",
    ".........##...#......##...#...",
    ".........##...#......##...#...",
    "........###..##.....###..##...",
]


def mask_shade(img, rows, x0, y0, pal, special=None):
    """ASCII-Maske ('#') mit einfacher Licht-von-oben-links-Schattierung zeichnen."""
    special = special or {}
    on = lambda x, y: 0 <= y < len(rows) and 0 <= x < len(rows[y]) and rows[y][x] == "#"
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in special:
                put(img, x0 + x, y0 + y, special[ch])
                continue
            if ch != "#":
                continue
            if not on(x, y - 1) or not on(x - 1, y):
                c = pal[3]
            elif not on(x, y + 1) or not on(x + 1, y):
                c = pal[0]
            elif not on(x - 2, y) or not on(x, y - 2):
                c = pal[2]
            else:
                c = pal[1] if (x + y) % 5 else pal[2]
            put(img, x0 + x, y0 + y, c)


def equestrian():
    """Reiterdenkmal 2x2: Reiter mit erhobenem Saebel auf einem Pferd, Bronze auf Granitsockel."""
    img = new(64, 64)
    pedestal(img, 15, 49, 44, 60, GRANITE, 2)
    for x in range(27, 37):
        for y in range(51, 55):
            put(img, x, y, GOLD[2] if y == 51 else GOLD[1])
    mask_shade(img, HORSE, 17, 18, BRONZE, {"S": IRON[3]})
    put(img, 20, 29, BRONZE[0])  # Auge
    ground_line(img, 15, 49, 59)
    add_outline(img)
    return img


def hologram(f):
    """Hologramm-Statue 1x1 (Zukunft): Metallsockel mit Projektor, darueber eine durchscheinende
    Figur in Tuerkis mit wandernden Bildzeilen (4 Frames)."""
    img = new(64, 64)
    for y in range(52, 60):
        for x in range(23, 41):
            if in_ellipse(x, y, 32, 55.5, 9, 4.2):
                c = IRON[2] if y < 55 else IRON[1]
                if in_ellipse(x, y, 32, 54.5, 4, 1.5):
                    c = HOLO[1] if (x + f) % 2 else HOLO[2]
                put(img, x, y, c)
    ground_line(img, 23, 41, 59)
    add_outline(img)
    fig = new(64, 64)
    _figure(fig, 32, 22 - (1 if f in (1, 2) else 0), HOLO + [(240, 255, 255)], "staff")
    # Lichtkegel
    for y in range(30, 54):
        half = (y - 30) * 0.15 + 2
        for x in range(int(32 - half * 2), int(32 + half * 2)):
            if get_a(fig, x, y) == 0 and in_ellipse(x, y, 32, 54, 8, 26):
                put(fig, x, y, (HOLO[0][0], HOLO[0][1], HOLO[0][2], 40))
    for y in range(64):
        for x in range(64):
            p = fig.getpixel((x, y))
            if p[3] == 0:
                continue
            a = p[3] if p[3] < 255 else 170
            if (y + f * 2) % 4 == 0 and p[3] == 255:
                a = 90
            if (y + f * 2) % 8 == 1 and p[3] == 255:
                p = (255, 255, 255, 255)
            fig.putpixel((x, y), (p[0], p[1], p[2], a))
    img.alpha_composite(fig)
    return img


# ------------------------------------------------------------------ Wasser
def fountain(f):
    """Brunnen 2x2: runde Steinschale, Saeule mit oberer Schale, Wasserstrahl (4 Frames)."""
    img = new(64, 64)
    cx, cy = 32, 50
    # Becken: aeusserer Rand, Wasser innen
    for y in range(38, 61):
        for x in range(14, 51):
            if in_ellipse(x, y, cx, cy, 17, 10):
                inner = in_ellipse(x, y, cx, cy - 1, 14, 7.5)
                if inner:
                    wv = (x * 2 + y * 3 + f * 3) % 11
                    c = WATER[2] if wv > 3 else WATER[3]
                    if y < cy - 5:
                        c = WATER[1]
                    if wv == 0:
                        c = WATER[4]
                else:
                    c = MARBLE[3] if y < cy - 3 else MARBLE[2] if x < cx + 8 else MARBLE[1]
                    if y > cy + 5:
                        c = MARBLE[1] if (x + y) % 5 else MARBLE[0]
                put(img, x, y, c)
    # Ringe, wo das Wasser auftrifft
    for i in range(0, 360, 20):
        a = math.radians(i + f * 10)
        r = 5 + f % 2
        put(img, int(round(cx + math.cos(a) * r)), int(round(cy - 1 + math.sin(a) * r * 0.45)), WATER[4])
    # Saeule
    for y in range(32, 50):
        for x in range(30, 35):
            put(img, x, y, MARBLE[3] if x == 30 else MARBLE[2] if x < 33 else MARBLE[1])
    # obere Schale
    for y in range(28, 35):
        for x in range(22, 43):
            if in_ellipse(x, y, cx, 31, 10, 3.6):
                c = MARBLE[3] if y < 30 else MARBLE[2] if y < 32 else MARBLE[1]
                if in_ellipse(x, y, cx, 30.2, 8, 1.6):
                    c = WATER[3]
                put(img, x, y, c)
    add_outline(img)
    # Wasser: Strahl oben, Ueberlauf an den Seiten (nach dem Umriss, damit es leuchtet)
    for y in range(17, 30):
        for x in (31, 32):
            k = (y + f * 2) % 4
            put(img, x, y, WATER[4] if k < 2 else WATER[3])
    for (dx, dy) in [(-3, 18), (3, 18), (-4, 20), (4, 20), (-1, 16), (1, 16), (0, 15)]:
        if (dy + f) % 2 == 0:
            put(img, 32 + dx - (1 if dx < 0 else 0), dy, FOAM)
    for side in (-1, 1):
        for i in range(10):
            x = cx + side * (10 + i // 4) - (1 if side < 0 else 0)
            y = 33 + i
            if (i + f) % 3 != 0:
                put(img, x, y, WATER[4] if (i + f) % 2 else WATER[3])
        for i in range(3):
            put(img, cx + side * (11 + i), 44 + ((i + f) % 2), FOAM)
    ground_line(img, 15, 50, 60)
    return img


def pond():
    """Teich mit Seerosen 2x2: unregelmaessiges Wasser, Steinrand, Schilf, Seerosenblaetter mit Bluete."""
    img = new(64, 64)
    rnd = random.Random(9)
    for y in range(30, 61):
        for x in range(14, 51):
            wob = math.sin(x * 0.7) * 0.06 + math.cos(y * 0.9) * 0.05
            d = ((x + 0.5 - 32) / 17) ** 2 + ((y + 0.5 - 46) / 13) ** 2 + wob
            if d <= 1.0:
                if d > 0.78:
                    c = STONE[3] if (x + y) % 4 else STONE[2]
                    if y > 52:
                        c = STONE[2] if (x + y) % 3 else STONE[1]
                else:
                    c = WATER[2] if (x * 3 + y * 5) % 13 else WATER[3]
                    if d > 0.6:
                        c = WATER[1]
                put(img, x, y, c)
    # Seerosen
    for (cx, cy, fl) in [(25, 42, True), (36, 48, False), (30, 51, True), (39, 40, False), (22, 49, False)]:
        for y in range(cy - 2, cy + 3):
            for x in range(cx - 3, cx + 4):
                if in_ellipse(x, y, cx + 0.5, cy + 0.5, 3, 2) and not (x == cx + 1 and y <= cy):
                    put(img, x, y, LEAF[3] if y < cy else LEAF[2])
        if fl:
            put(img, cx, cy - 1, (255, 250, 250))
            put(img, cx - 1, cy, (250, 170, 200))
            put(img, cx + 1, cy, (250, 170, 200))
            put(img, cx, cy, (255, 220, 120))
    # Schilf hinten rechts
    for i, x in enumerate([43, 45, 46, 48]):
        h = 10 + (i * 3) % 5
        for y in range(40 - h, 41):
            put(img, x, y, LEAF[2] if y > 40 - h + 2 else LEAF[3])
        for y in range(40 - h, 40 - h + 3):
            put(img, x, y, WOOD[1])
    add_outline(img)
    return img


# ------------------------------------------------------------------ Bauten
def flagpole(f):
    """Fahnenmast 1x1: Steinsockel, weisser Mast, roter Wimpel mit goldenem Stern, der weht (4 Frames)."""
    img = new(64, 64)
    pedestal(img, 26, 38, 53, 60, GRANITE, 2)
    for y in range(6, 53):
        put(img, 31, y, (236, 236, 236))
        put(img, 32, y, (176, 176, 186))
    put(img, 31, 5, GOLD[3])
    put(img, 32, 5, GOLD[2])
    put(img, 31, 4, GOLD[2])
    flag = new(64, 64)
    RED = [(130, 30, 36), (186, 46, 50), (226, 76, 70), (246, 130, 110)]
    for x in range(33, 52):
        k = x - 33
        amp = k / 18 * 2.2
        off = amp * math.sin(k / 3.2 - f * math.pi / 2)
        top = 7 + off
        bot = 19 + off - k * 0.12
        shade = math.cos(k / 3.2 - f * math.pi / 2)
        for y in range(int(round(top)), int(round(bot))):
            c = RED[2] if shade > 0.3 else RED[1] if shade > -0.4 else RED[0]
            if y == int(round(top)) and shade > 0:
                c = RED[3]
            put(flag, x, y, c)
    # Stern (goldene Raute mit Spitzen), wandert mit der Welle
    k = 8
    off = int(round(k / 18 * 2.2 * math.sin(k / 3.2 - f * math.pi / 2)))
    for (dx, dy) in [(0, -2), (-1, -1), (0, -1), (1, -1), (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0),
                     (-1, 1), (0, 1), (1, 1), (-1, 2), (1, 2)]:
        put(flag, 41 + dx, 12 + off + dy, GOLD[2] if dy < 1 else GOLD[1])
    img.alpha_composite(flag)
    ground_line(img, 26, 38, 59)
    add_outline(img)
    return img


def pavilion():
    """Pavillon 2x2: Holzboden, weisse Saeulen, achteckiges Kupferdach mit Gruenspan und Spitze."""
    img = new(64, 64)
    COPPER = [(44, 104, 96), (64, 140, 124), (96, 176, 152), (150, 210, 186)]
    # Boden
    for y in range(52, 60):
        for x in range(13, 51):
            c = WOOD[3] if y == 52 else WOOD[2] if y < 57 else WOOD[1]
            if y > 56 and (x - 13) % 6 == 0:
                c = WOOD[0]
            put(img, x, y, c)
    for y in range(53, 60):
        put(img, 13, y, WOOD[1])
        put(img, 50, y, WOOD[0])
    # Gelaender
    for x in range(15, 49):
        put(img, x, 45, (236, 232, 222))
        if (x - 15) % 3 == 0:
            for y in range(46, 52):
                put(img, x, y, (220, 214, 200))
    # Saeulen
    for sx in (15, 25, 37, 47):
        for y in range(30, 52):
            put(img, sx, y, (246, 244, 236))
            put(img, sx + 1, y, (212, 206, 196))
    # Dach
    for y in range(14, 32):
        t = (y - 14) / 17
        half = 4 + t * 20
        for x in range(int(32 - half), int(32 + half)):
            u = (x - (32 - half)) / (2 * half)
            c = COPPER[3] if u < 0.18 else COPPER[2] if u < 0.5 else COPPER[1] if u < 0.85 else COPPER[0]
            if y >= 29:
                c = COPPER[1] if y == 29 else COPPER[0]
            if (x - 32) % 8 == 0 and y < 29:
                c = COPPER[0]
            put(img, x, y, c)
    for y in range(9, 14):
        put(img, 31, y, GOLD[2])
        put(img, 32, y, GOLD[1])
    put(img, 31, 8, GOLD[3])
    put(img, 32, 8, GOLD[2])
    ground_line(img, 13, 51, 59)
    add_outline(img)
    return img


def park():
    """Parkanlage 3x3 (Bodenbild, begehbar): Rasen, Kieswegkreuz, rundes Blumenbeet in der Mitte,
    Blumen in den Ecken, niedrige Hecke am Rand. Die beiden Baeume oben sind eigene Bilder (park_tree)."""
    img = new(64, 64)
    x0, y0, x1, y1 = 8, 12, 56, 60
    for y in range(y0, y1):
        for x in range(x0, x1):
            c = GRASS[2] if (x * 7 + y * 3) % 9 else GRASS[3]
            if (x // 4 + y // 4) % 2 == 0 and (x + y) % 2 == 0:
                c = GRASS[3]
            put(img, x, y, c)
    # Kieswege (Kreuz)
    for y in range(y0, y1):
        for x in range(x0, x1):
            on = (29 <= x <= 34) or (33 <= y <= 38)
            if on:
                c = SAND[1] if (x * 5 + y * 3) % 7 else SAND[0]
                if (x * 11 + y * 7) % 13 == 0:
                    c = SAND[3]
                if x in (29, 34) and not (33 <= y <= 38):
                    c = SAND[0]
                if y in (33, 38) and not (29 <= x <= 34):
                    c = SAND[0]
                put(img, x, y, c)
    # Rundbeet in der Mitte
    for y in range(30, 42):
        for x in range(25, 39):
            if in_ellipse(x, y, 32, 36, 6, 4.5):
                c = SOIL[1]
                if not in_ellipse(x, y, 32, 36, 4.8, 3.4):
                    c = STONE[3] if y < 36 else STONE[2]
                put(img, x, y, c)
    for (dx, dy, col) in [(-2, -1, "rot"), (2, -1, "gelb"), (0, 1, "blau"), (-3, 1, "gelb"), (3, 1, "rot"), (0, -2, "rot")]:
        pal = FLOWER_SETS[col]
        put(img, 32 + dx, 36 + dy, pal[2])
        put(img, 32 + dx, 36 + dy + 1, LEAF[2])
    # Blumen in den Ecken unten
    for (bx, by, col) in [(12, 50, "rot"), (44, 50, "gelb"), (12, 22, "blau"), (44, 22, "rot")]:
        for y in range(by, by + 6):
            for x in range(bx, bx + 8):
                if in_ellipse(x, y, bx + 4, by + 3, 4, 3):
                    put(img, x, y, LEAF[2] if (x + y) % 2 else LEAF[3])
        pal = FLOWER_SETS[col]
        for (fx, fy) in [(bx + 2, by + 2), (bx + 5, by + 1), (bx + 4, by + 4), (bx + 6, by + 3), (bx + 1, by + 4)]:
            put(img, fx, fy, pal[2])
            put(img, fx + 1, fy, pal[1])
    # niedrige Hecke links und rechts (laesst die Wege frei)
    for y in range(y0 + 1, y1 - 1):
        if 32 <= y <= 39:
            continue
        for x in (x0, x0 + 1, x1 - 2, x1 - 1):
            put(img, x, y, LEAF[2] if (x + y) % 3 else LEAF[1])
    for x in range(x0, x1):
        if 28 <= x <= 35:
            continue
        for y in (y1 - 2, y1 - 1):
            put(img, x, y, LEAF[2] if (x + y) % 3 else LEAF[1])
    add_outline(img)
    return img


def park_tree():
    """Zierbaum der Parkanlage (1 Feld): schlanker Stamm, runde, gepflegte Krone."""
    img = new(64, 64)
    for y in range(40, 59):
        for x in range(31, 34):
            put(img, x, y, WOOD[2] if x == 31 else WOOD[1])
    for (x, y) in [(30, 58), (34, 58)]:
        put(img, x, y, WOOD[1])
    blob(img, 32, 33, 9, 9, LEAF[:4], noise_seed=21)
    blob(img, 29.5, 30, 5, 4.5, LEAF[1:], noise_seed=22)
    blob(img, 34.5, 29, 4.5, 4, LEAF[2:], noise_seed=23)
    rnd = random.Random(4)
    for _ in range(6):
        x, y = rnd.randint(25, 39), rnd.randint(26, 40)
        if get_a(img, x, y):
            put(img, x, y, (236, 120, 150))
    ground_line(img, 27, 38, 59)
    add_outline(img)
    return img


# Reihenfolge der Zellen ab 60 (Data.BUILDING_CELLS)
def decor_buildings():
    return ([flowerbed("rot"), flowerbed("gelb"), flowerbed("blau"), bench(), menhir()]
            + [flagpole(f) for f in range(4)]
            + [stone_statue(), flower_tub()]
            + [fountain(f) for f in range(4)]
            + [pond(), park(), park_tree(), rose_arch(), sundial(), lantern(), pavilion(), equestrian(),
               obelisk(), bronze_statue(), street_lamp()]
            + [hologram(f) for f in range(4)])


# ------------------------------------------------------------------ Wege und Hecke (objects3.png)
def _inside(mask, x, y, half):
    lo, hi = 8 - half, 7 + half
    if lo <= x <= hi and lo <= y <= hi:
        return True
    if mask & N and lo <= x <= hi and y < lo:
        return True
    if mask & S and lo <= x <= hi and y > hi:
        return True
    if mask & W and lo <= y <= hi and x < lo:
        return True
    if mask & E and lo <= y <= hi and x > hi:
        return True
    return False


def _edge(mask, x, y, half):
    return not (_inside(mask, x - 1, y, half) and _inside(mask, x + 1, y, half)
                and _inside(mask, x, y - 1, half) and _inside(mask, x, y + 1, half))


def _round_corners(img, mask):
    for (x, y, cx, cy) in [(3, 3, 1, 1), (12, 3, -1, 1), (3, 12, 1, -1), (12, 12, -1, -1)]:
        free = ((not mask & N) if y < 8 else (not mask & S)) and ((not mask & W) if x < 8 else (not mask & E))
        if free and img.getpixel((x, y))[3]:
            put(img, x, y, (0, 0, 0, 0))


def gravel(mask):
    """Kiesweg: helles Kiesband mit Sprenkeln, Rand aus dunklerem Kies."""
    img = new(16, 16)
    rnd = random.Random(900 + mask)
    G = [(150, 132, 108), (184, 166, 136), (208, 192, 162), (232, 220, 196)]
    for y in range(16):
        for x in range(16):
            if not _inside(mask, x, y, 5):
                continue
            if _edge(mask, x, y, 5):
                c = G[0] if (x + y) % 2 else G[1]
            else:
                r = rnd.random()
                c = G[2] if r < 0.6 else G[3] if r < 0.8 else G[1]
            put(img, x, y, c)
    _round_corners(img, mask)
    return img


def bricks(mask):
    """Ziegelweg: rote Klinker im Laeuferverband, Rand aus grauen Steinen."""
    img = new(16, 16)
    for y in range(16):
        for x in range(16):
            if not _inside(mask, x, y, 5):
                continue
            if _edge(mask, x, y, 5):
                c = STONE[1] if (x + y) % 3 else STONE[2]
            else:
                row = y // 2
                off = 2 if row % 2 else 0
                if y % 2 == 0 or (x + off) % 4 == 0:
                    c = (120, 64, 48)
                else:
                    c = BRICK[2] if (x // 4 + row) % 3 else (214, 120, 80)
            put(img, x, y, c)
    _round_corners(img, mask)
    return img


def hedge(mask):
    """Hecke: dichter, gestutzter Buchsbaum (Band halbe Breite 5), oben hell, unten dunkel."""
    img = new(16, 16)
    rnd = random.Random(1300 + mask)
    for y in range(16):
        for x in range(16):
            if not _inside(mask, x, y, 5):
                continue
            # Abstand nach unten zum Rand: unten dunkler (Seite der Hecke)
            below = _inside(mask, x, y + 2, 5)
            c = LEAF[3] if rnd.random() < 0.55 else LEAF[2]
            if not below:
                c = LEAF[1] if rnd.random() < 0.7 else LEAF[0]
            elif rnd.random() < 0.12:
                c = LEAF[4]
            put(img, x, y, c)
    _round_corners(img, mask)
    add_outline(img)
    return img


ICONS_DECOR = {
    "schmuck": (["................",
                 "......1111......",
                 ".....122221.....",
                 "..111233321111..",
                 ".12221333122221.",
                 ".12333444333321.",
                 "..1233444433321.",
                 "...11234432111..",
                 "..12333443321...",
                 ".1233312213321..",
                 ".122211.112221..",
                 "..111.1551.111..",
                 "......1551......",
                 ".....166661.....",
                 "....16666661....",
                 ".....111111....."],
                {"1": (60, 30, 50), "2": (200, 60, 110), "3": (244, 120, 160), "4": (255, 222, 110),
                 "5": (60, 130, 70), "6": (184, 110, 70)}),
}
