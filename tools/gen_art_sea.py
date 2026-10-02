"""Grafiken fuer Etappe 3: Seefahrt, neue Inseln und wilde Tiere.

Wird von gen_art.py aufgerufen. Erzeugt objects2.png, animals.png und haengt
Gebaeude (Werft, Wachturm, Leuchtturm, Denkmal), den Speer und neue Icons an.
"""
import math
import os
import random

from gen_art import (OUT, OUTLINE, WATER, SAND, GRASS, SOIL, WOOD, STONE, LEAF, THATCH, FIRE, PLASTER,
                    SLATE, ROOF_RED, SHINGLE, DARK, GLOW, IRON, new, put, add_outline, blob,
                    stone_wall, plaster_wall, tile_roof, door, window, ground_line, rect)

GOLD = [(150, 100, 30), (210, 160, 40), (245, 210, 80), (255, 245, 170)]
FUR_WOLF = [(70, 72, 84), (110, 112, 124), (150, 152, 162), (196, 198, 206)]
FUR_BOAR = [(66, 40, 30), (100, 64, 44), (136, 92, 62), (170, 124, 86)]
FUR_BEAR = [(54, 34, 26), (84, 54, 38), (116, 78, 52), (150, 108, 72)]
MUD = [(84, 62, 44), (110, 84, 58), (136, 106, 74)]
PALM = [(34, 96, 54), (52, 132, 62), (82, 168, 72), (128, 204, 92)]
SAIL = [(214, 206, 186), (236, 230, 214), (252, 250, 240)]


# ------------------------------------------------------------------ Natur
def palm(kind=0, nuts=True):
    img = new(32, 48)
    lean = 3 if kind == 0 else -3
    # gebogener Stamm
    for y in range(18, 45):
        t = (44 - y) / 26.0
        cx = 16 + lean * t * t
        for dx in range(-2, 2):
            x = int(round(cx + dx))
            c = WOOD[2] if dx >= 0 else WOOD[1]
            if (y + (0 if kind else 1)) % 3 == 0:
                c = WOOD[0] if dx < 0 else WOOD[1]
            put(img, x, y, c)
    top = (16 + lean, 17)
    # Wedel
    for ang, ln in [(-160, 13), (-120, 11), (-60, 11), (-20, 13), (20, 11), (160, 11), (200, 9), (-90, 7)]:
        a = math.radians(ang + kind * 8)
        for i in range(ln):
            droop = (i / ln) ** 2 * 5
            x = top[0] + math.cos(a) * i
            y = top[1] + math.sin(a) * i * 0.6 + droop
            for w in range(-1, 2):
                c = PALM[2] if w <= 0 else PALM[1]
                if i > ln - 3:
                    c = PALM[1]
                if w == -1 and i % 3 == 0:
                    c = PALM[3]
                put(img, int(round(x)), int(round(y + w * (1 if abs(math.cos(a)) > 0.5 else 0))), c)
                if abs(math.cos(a)) <= 0.5:
                    put(img, int(round(x + w)), int(round(y)), c)
    if nuts:
        for dx, dy in [(-2, 2), (1, 3), (-1, 4)]:
            put(img, top[0] + dx, top[1] + dy, (110, 70, 40))
            put(img, top[0] + dx + 1, top[1] + dy, (140, 92, 54))
            put(img, top[0] + dx, top[1] + dy + 1, (90, 56, 34))
    add_outline(img)
    return img


def cave():
    img = new(32, 48)
    blob(img, 16, 37, 15, 10.5, STONE[0:5], noise_seed=41, jag=0.08)
    blob(img, 10, 33, 6, 5, STONE[1:5], noise_seed=42)
    # Hoehleneingang
    for y in range(36, 47):
        for x in range(10, 23):
            d = ((x + 0.5 - 16) / 6.5) ** 2 + ((y + 0.5 - 47) / 10.5) ** 2
            if d <= 1.0:
                put(img, x, y, DARK if d < 0.7 else (60, 50, 56))
    # Knochen
    for x, y in [(6, 45), (7, 45), (8, 44), (25, 45), (26, 46)]:
        put(img, x, y, (236, 230, 210))
    for x, y in [(4, 30), (5, 29), (6, 29), (22, 28), (23, 28)]:
        put(img, x, y, GRASS[2])
    add_outline(img)
    return img


def mushrooms():
    img = new(16, 16)
    for (cx, cy, r, col) in [(5, 9, 3, (200, 60, 50)), (11, 10, 2.5, (210, 150, 80)), (8, 12, 2, (200, 60, 50))]:
        for y in range(int(cy), int(cy + r + 2)):
            put(img, int(cx), y, (240, 232, 214))
        for y in range(16):
            for x in range(16):
                dx = (x + 0.5 - cx) / r
                dy = (y + 0.5 - cy) / (r * 0.75)
                if dx * dx + dy * dy <= 1 and y <= cy + 0.5:
                    c = col if (x + y) % 4 else (250, 240, 230)
                    if y == int(cy):
                        c = tuple(int(v * 0.8) for v in col)
                    put(img, x, y, c)
    add_outline(img)
    return img


def vein_rock(cols):
    img = new(16, 16)
    blob(img, 8, 9, 7, 5.6, STONE[0:5], noise_seed=23, jag=0.07)
    for x, y in [(5, 7), (6, 8), (9, 6), (10, 6), (11, 9), (7, 11), (4, 10), (10, 11)]:
        put(img, x, y, cols[1])
        put(img, x + 1, y, cols[2])
    put(img, 9, 6, cols[3])
    put(img, 5, 7, cols[3])
    add_outline(img)
    return img


def den():
    """Wolfsbau: Erdhuegel mit Loch."""
    img = new(16, 16)
    blob(img, 8, 10, 7.5, 5, [SOIL[0], SOIL[1], SOIL[2], (176, 132, 90)], noise_seed=51)
    for y in range(8, 14):
        for x in range(5, 11):
            d = ((x + 0.5 - 8) / 3) ** 2 + ((y + 0.5 - 14) / 5) ** 2
            if d <= 1:
                put(img, x, y, DARK)
    for x, y in [(2, 8), (3, 7), (13, 8), (12, 7)]:
        put(img, x, y, GRASS[2])
    put(img, 12, 13, (236, 230, 210))
    put(img, 13, 13, (236, 230, 210))
    add_outline(img)
    return img


def wallow():
    """Wildschweinsuhle: Schlammloch mit Gestruepp."""
    img = new(16, 16)
    blob(img, 8, 11, 7.5, 4, MUD, noise_seed=52)
    for x, y in [(6, 10), (7, 10), (10, 12), (11, 12), (4, 12)]:
        put(img, x, y, (150, 124, 90))
    blob(img, 4, 7, 3.5, 3, LEAF[0:4], noise_seed=53)
    blob(img, 12, 6, 3, 3, LEAF[0:4], noise_seed=54)
    add_outline(img)
    return img


def carcass():
    img = new(16, 16)
    blob(img, 8, 11, 6, 3, FUR_BOAR, noise_seed=55)
    for x in range(5, 11):
        put(img, x, 9, (220, 120, 110))
    for x, y in [(3, 13), (4, 14), (12, 13), (13, 14)]:
        put(img, x, y, FUR_BOAR[0])
    put(img, 13, 10, (236, 230, 210))
    add_outline(img)
    return img


def arrow():
    img = new(16, 16)
    for x in range(3, 13):
        put(img, x, 8, WOOD[2])
    put(img, 13, 8, IRON[3])
    put(img, 12, 7, IRON[2])
    put(img, 12, 9, IRON[2])
    for x in (3, 4):
        put(img, x, 7, (240, 240, 240))
        put(img, x, 9, (220, 70, 60))
    return img


def boat(f):
    """Kleines Segelboot 32x32 mit Wellen (2 Frames)."""
    img = new(32, 32)
    bob = f
    # Rumpf
    for y in range(20, 26):
        w = 13 - (y - 20)
        for x in range(16 - w, 16 + w):
            c = WOOD[2] if y < 22 else WOOD[1]
            if y == 20:
                c = WOOD[3]
            if (x + y) % 5 == 0 and y > 21:
                c = WOOD[0]
            put(img, x, y + bob, c)
    # Mast und Segel
    for y in range(4, 21):
        put(img, 15, y + bob, WOOD[0])
    for y in range(5, 18):
        span = int((y - 4) * 0.75)
        for x in range(16, 17 + span):
            put(img, x, y + bob, SAIL[1] if (x + y) % 6 else SAIL[0])
        for x in range(14 - span // 2, 15):
            put(img, x, y + bob, SAIL[2] if y > 8 else SAIL[1])
    put(img, 15, 3 + bob, (220, 60, 50))
    put(img, 16, 3 + bob, (220, 60, 50))
    add_outline(img)
    # Wellen
    for x in range(2, 30, 3):
        put(img, x + f, 27, (*WATER[4], 200))
        put(img, x + 1 + f, 28, (*WATER[3], 180))
    return img


def gen_objects2():
    atlas = new(288, 144)
    for i, im in enumerate([palm(0), palm(1), palm(0, nuts=False), cave()]):
        atlas.paste(im, (i * 32, 0))
    for i, im in enumerate([mushrooms(), vein_rock(IRON[1:] + [(230, 190, 150)]),
                            vein_rock(GOLD), den(), wallow(), carcass(), arrow()]):
        atlas.paste(im, (i * 16, 48))
    # Erzader: rostrote Flecken statt Grau
    ore = vein_rock([(120, 60, 40), (170, 90, 50), (210, 130, 70), (240, 180, 120)])
    atlas.paste(ore, (16, 48))
    for f in range(2):
        atlas.paste(boat(f), (f * 32, 64))
    gen_ships(atlas)
    atlas.save(os.path.join(OUT, "objects2.png"))


# ------------------------------------------------------------------ Tiere
def quad(frame, fur, body, head, legs, tail, ears, tusks=False, snout=None, attack=False):
    """Vierbeiner von der Seite (Blick nach rechts) in einer 24x24-Zelle."""
    img = new(24, 24)
    bx, by, brx, bry = body
    hop = -1 if frame in (1, 3) else 0
    lunge = 2 if attack else 0
    # Beine (vorn/hinten im Wechsel)
    sw = [(-1, 1), (0, 0), (1, -1), (0, 0)][frame % 4] if not attack else (2, -1)
    for i, (lx, ln) in enumerate(legs):
        off = sw[0] if i % 2 == 0 else sw[1]
        for y in range(int(by + bry - 2), int(by + bry - 2 + ln)):
            put(img, int(lx + off + lunge * (i >= 2)), y + hop, fur[0] if i % 2 else fur[1])
    blob(img, bx + lunge * 0.5, by + hop, brx, bry, fur, noise_seed=61)
    # Schwanz
    for (tx, ty) in tail:
        put(img, tx, ty + hop, fur[1])
    # Kopf
    hx, hy, hr = head
    hx += lunge
    blob(img, hx, hy + hop, hr, hr * 0.85, fur[1:], noise_seed=62)
    if snout:
        sx, sy, sl, scol = snout
        for x in range(sl):
            for y in range(2):
                put(img, int(hx + sx + x), int(hy + sy + y + hop), scol if x < sl - 1 else (40, 30, 30))
    for (ex, ey) in ears:
        put(img, ex + lunge, ey + hop, fur[0])
        put(img, ex + lunge, ey + 1 + hop, fur[1])
    put(img, int(hx + hr * 0.4), int(hy - 1 + hop), (230, 220, 120) if not attack else (240, 70, 50))
    if tusks:
        put(img, int(hx + hr + 1), int(hy + 2 + hop), (250, 246, 230))
        put(img, int(hx + hr + 2), int(hy + 1 + hop), (250, 246, 230))
    if attack:
        put(img, int(hx + hr + 2), int(hy + 3 + hop), (250, 250, 250))
    add_outline(img)
    return img


def wolf(frame, attack=False):
    return quad(frame, FUR_WOLF, (10, 14, 6.5, 3.6), (17.5, 10, 3.2),
                [(6, 6), (8, 6), (13, 6), (15, 6)], [(3, 12), (2, 11), (2, 13), (1, 12)],
                [(16, 6), (18, 6)], snout=(2, 0, 3, FUR_WOLF[2]), attack=attack)


def boar(frame, attack=False):
    return quad(frame, FUR_BOAR, (10, 15, 7, 4.4), (17, 13, 3.4),
                [(6, 5), (8, 5), (13, 5), (15, 5)], [(3, 13), (2, 12)],
                [(16, 9), (15, 9)], tusks=True, snout=(2, 1, 3, (200, 140, 120)), attack=attack)


def bear(frame, attack=False):
    return quad(frame, FUR_BEAR, (10.5, 13, 8.5, 5.6), (18.5, 10, 4),
                [(5, 6), (7, 6), (14, 6), (16, 6)], [(2, 12)],
                [(16, 5), (20, 5)], snout=(3, 1, 2, FUR_BEAR[3]), attack=attack)


def gen_animals():
    atlas = new(24 * 5, 24 * 3)
    for row, fn in enumerate([wolf, boar, bear]):
        for f in range(4):
            atlas.paste(fn(f), (f * 24, row * 24))
        atlas.paste(fn(0, attack=True), (4 * 24, row * 24))
    atlas.save(os.path.join(OUT, "animals.png"))


# ------------------------------------------------------------------ Gebaeude
def shipyard():
    img = new(64, 64)
    # Helling aus Planken, die zum Wasser abfaellt
    for y in range(44, 60):
        for x in range(4, 60):
            c = WOOD[2] if (y // 3) % 2 else WOOD[1]
            if x % 9 == 0:
                c = WOOD[0]
            put(img, x, y, c)
    # Halb fertiges Boot auf dem Stapel
    for y in range(34, 46):
        w = 20 - (y - 34) * 1.3
        for x in range(int(32 - w), int(32 + w)):
            rib = (x % 5 == 0) and y < 42
            c = WOOD[3] if rib else (WOOD[2] if y < 40 else WOOD[1])
            put(img, x, y, c)
    for y in range(14, 35):
        put(img, 31, y, WOOD[0])
        put(img, 32, y, WOOD[1])
    # Kran-Gestell
    for y in range(18, 46):
        put(img, 8, y, WOOD[1])
        put(img, 9, y, WOOD[2])
        put(img, 54, y, WOOD[1])
        put(img, 55, y, WOOD[2])
    for x in range(8, 56):
        put(img, x, 18, WOOD[0])
        put(img, x, 19, WOOD[2])
    for y in range(20, 30):
        put(img, 44, y, (200, 190, 160))
    put(img, 43, 30, IRON[2])
    put(img, 44, 30, IRON[2])
    put(img, 45, 30, IRON[2])
    # Bretterstapel und Fass
    for y in range(50, 56):
        for x in range(46, 58):
            put(img, x, y, WOOD[3] if y % 2 else WOOD[2])
    ground_line(img, 4, 60)
    add_outline(img)
    return img


def tower():
    img = new(64, 64)
    # Steinsockel
    stone_wall(img, 24, 40, 16, 20)
    # Holzaufbau
    for y in range(18, 40):
        for x in range(25, 39):
            c = WOOD[2] if (x - 25) % 4 else WOOD[1]
            put(img, x, y, c)
    for i in range(22):
        put(img, 25 + i * 13 // 22, 18 + i, WOOD[0])
    # Plattform mit Zinnen
    for y in range(14, 18):
        for x in range(21, 43):
            put(img, x, y, WOOD[1] if y > 15 else WOOD[3])
    for x in range(21, 43, 4):
        for y in range(10, 14):
            put(img, x, y, WOOD[2])
            put(img, x + 1, y, WOOD[2])
    # Spitzdach
    for y in range(0, 10):
        for x in range(32 - y - 2, 32 + y + 2):
            put(img, x, y + 1, ROOF_RED[2] if x < 32 else ROOF_RED[1])
    put(img, 31, 0, (230, 190, 70))
    put(img, 32, 0, (230, 190, 70))
    # Wimpel
    for x in range(33, 38):
        put(img, x, 2 + (x - 33) // 3, (60, 110, 200))
    # Fenster mit Bogenschuetze
    window(img, 29, 22, 6, 7, lit=True)
    door(img, 29, 50, 6, 10, arch=True)
    ground_line(img, 24, 40)
    add_outline(img)
    return img


def lighthouse(f):
    img = new(64, 64)
    # Kegelfoermiger Turm, rot-weiss gestreift
    for y in range(14, 60):
        w = 6 + (y - 14) * 6 // 46
        for x in range(32 - w, 32 + w):
            band = ((y - 14) // 8) % 2
            c = (236, 232, 222) if band == 0 else ROOF_RED[2]
            if x >= 32 + w - 2:
                c = (200, 196, 186) if band == 0 else ROOF_RED[1]
            put(img, x, y, c)
    door(img, 29, 51, 6, 9, arch=True)
    window(img, 30, 34, 4, 5, lit=True)
    # Laterne
    for y in range(6, 14):
        for x in range(27, 37):
            edge = x in (27, 36)
            c = IRON[1] if edge else ((255, 236, 140) if f == 0 or (x + y) % 2 else GLOW[1])
            put(img, x, y, c)
    for x in range(25, 39):
        put(img, x, 14, IRON[1])
        put(img, x, 13, IRON[2])
    for y in range(1, 6):
        for x in range(32 - (y + 1), 32 + (y + 1)):
            put(img, x, y, SLATE[2] if x < 32 else SLATE[1])
    put(img, 31, 0, IRON[3])
    put(img, 32, 0, IRON[3])
    # Lichtstrahl
    if f == 1:
        for i in range(8):
            put(img, 37 + i, 9 - i // 3, (255, 240, 160, 180))
            put(img, 26 - i, 9 - i // 3, (255, 240, 160, 180))
    # Felsen am Fuss
    blob(img, 18, 58, 6, 3, STONE[1:5], noise_seed=71)
    blob(img, 47, 58, 5, 3, STONE[1:5], noise_seed=72)
    add_outline(img)
    return img


def monument():
    img = new(64, 64)
    # Sockel
    for i, (y0, w) in enumerate([(54, 22), (50, 18), (46, 14)]):
        for y in range(y0, y0 + 4 + (2 if i == 0 else 0)):
            for x in range(32 - w, 32 + w):
                c = STONE[3] if x < 32 + w - 2 else STONE[2]
                if y == y0:
                    c = STONE[4]
                put(img, x, y, c)
    # Goldene Figur mit erhobenem Arm (Siedler mit Fackel)
    G = GOLD
    for y in range(26, 46):
        w = 4 if y > 34 else 3
        for x in range(32 - w, 32 + w):
            put(img, x, y, G[2] if x < 32 else G[1])
    blob(img, 32, 22, 3.5, 3.8, [G[1], G[2], G[3]], noise_seed=73)
    for i in range(10):
        put(img, 35 + i // 3, 30 - i, G[2])
        put(img, 36 + i // 3, 30 - i, G[1])
    for y in range(14, 20):
        put(img, 38, y, G[0])
    for x, y in [(38, 12), (37, 11), (39, 11), (38, 10), (38, 13)]:
        put(img, x, y, FIRE[2] if y > 11 else FIRE[3])
    for x in range(26, 29):
        put(img, x, 34, G[1])
    # Inschrift-Tafel
    for y in range(51, 54):
        for x in range(25, 39):
            put(img, x, y, (90, 70, 50) if (x + y) % 3 else (120, 96, 64))
    # Blumen
    for x, y, c in [(12, 59, (250, 214, 80)), (14, 58, (236, 110, 140)), (50, 59, (150, 170, 250)), (52, 58, (250, 214, 80))]:
        put(img, x, y, c)
        put(img, x, y + 1, GRASS[1])
    add_outline(img)
    return img


def extra_buildings():
    """Reihenfolge = Data.BUILDING_CELLS ab Zelle 20."""
    return [shipyard(), tower(), lighthouse(0), lighthouse(1), monument()]


def spear():
    img = new(16, 16)
    for i in range(12):
        put(img, 2 + i, 14 - i, WOOD[2])
    for x, y in [(13, 2), (14, 1), (13, 1), (12, 2), (14, 2), (13, 3)]:
        put(img, x, y, IRON[3])
    put(img, 4, 12, (200, 60, 50))
    add_outline(img)
    return img


# ------------------------------------------------------------------ Icons
ICONS_SEA = {
    "fleisch": (["................",
                 "................",
                 "................",
                 ".......2222.....",
                 ".....22111122...",
                 "....2111111112..",
                 "...211113311112.",
                 "...211133311112.",
                 "...21111111112..",
                 "....221111122...",
                 "...44.22222.....",
                 "..444...........",
                 ".44.............",
                 "................",
                 "................",
                 "................"],
                {"1": (200, 70, 60), "2": (140, 40, 40), "3": (250, 200, 190), "4": (240, 236, 220)}),
    "felle": (["................",
               "................",
               "...1.......1....",
               "...11111111.....",
               "....222222......",
               "...12222221.....",
               "..1122332211....",
               "..1223333221....",
               "..1223333221....",
               "...12222221.....",
               "....122221......",
               "...11.11.11.....",
               "...1...1...1....",
               "................",
               "................",
               "................"],
              {"1": FUR_BOAR[1], "2": FUR_BOAR[2], "3": FUR_BOAR[3]}),
    "kokos": (["................",
               "................",
               "........4.......",
               ".......44.......",
               ".....11111......",
               "....1222221.....",
               "...122222221....",
               "...1222223221...",
               "...1222233221...",
               "...1222222221...",
               "....12222221....",
               ".....111111.....",
               "................",
               "................",
               "................",
               "................"],
              {"1": (90, 56, 34), "2": (140, 92, 54), "3": (240, 236, 220), "4": PALM[2]}),
    "pilze": (["................",
               "................",
               "....11111.......",
               "...1131111......",
               "..113111311.....",
               "..222222222.....",
               ".....44....1111.",
               ".....44...131111",
               ".....44...222222",
               ".....44.....44..",
               "....4444....44..",
               "...........4444.",
               "................",
               "................",
               "................",
               "................"],
              {"1": (200, 60, 50), "2": (150, 40, 36), "3": (250, 240, 230), "4": (240, 232, 214)}),
    "gold": (["................",
              "................",
              "................",
              "................",
              "......1111......",
              ".....133221.....",
              "....13322221....",
              "...111111111....",
              "..13322113322...",
              ".1332222133221..",
              ".1111111111111..",
              "................",
              "................",
              "................",
              "................",
              "................"],
             {"1": GOLD[0], "2": GOLD[2], "3": GOLD[3]}),
    "boot": (["................",
              ".......5........",
              ".......6........",
              ".......633......",
              ".......6333.....",
              "......46333.....",
              ".....446333.....",
              "....4446333.....",
              ".......6........",
              "..11111111111...",
              "...122222221....",
              "....1111111.....",
              "..77.77.77.77...",
              "................",
              "................",
              "................"],
             {"1": WOOD[1], "2": WOOD[2], "3": SAIL[1], "4": SAIL[2], "5": (220, 60, 50), "6": WOOD[0],
              "7": WATER[3]}),
    "kompass": (["................",
                 ".....111111.....",
                 "....12222221....",
                 "...1222322221...",
                 "..122223322221..",
                 "..122224332221..",
                 "..122244422221..",
                 "..122244422221..",
                 "..122224422221..",
                 "..122224222221..",
                 "...1222222221...",
                 "....12222221....",
                 ".....111111.....",
                 "................",
                 "................",
                 "................"],
                {"1": GOLD[0], "2": (246, 236, 210), "3": (210, 60, 50), "4": (60, 70, 100)}),
    "schild": (["................",
                "...1111111111...",
                "...1222332221...",
                "...1222332221...",
                "...1333333331...",
                "...1333333331...",
                "...1222332221...",
                "....12223221....",
                "....12223221....",
                ".....122221.....",
                "......1221......",
                ".......11.......",
                "................",
                "................",
                "................",
                "................"],
               {"1": IRON[1], "2": (60, 100, 180), "3": GOLD[2]}),
    "wolf": (["................",
              "...1........1...",
              "...11......11...",
              "...121....121...",
              "...1222222221...",
              "..122222222221..",
              "..123322223321..",
              "..122222222221..",
              "...1222222221...",
              "....12233221....",
              ".....123321.....",
              "......1441......",
              ".......11.......",
              "................",
              "................",
              "................"],
             {"1": FUR_WOLF[0], "2": FUR_WOLF[2], "3": (230, 220, 120), "4": (40, 30, 30)}),
    "eber": (["................",
              "................",
              "...11......11...",
              "...121....121...",
              "...1222222221...",
              "..122222222221..",
              "..123222222321..",
              "..122222222221..",
              ".5.1224444221.5.",
              ".55.12466421.55.",
              "....1244442.....",
              ".....11111......",
              "................",
              "................",
              "................",
              "................"],
             {"1": FUR_BOAR[0], "2": FUR_BOAR[2], "3": (230, 220, 120), "4": (200, 140, 120),
              "5": (250, 246, 230), "6": (60, 40, 40)}),
    "baer": (["................",
              "..111......111..",
              "..121......121..",
              "..1222222222221.",
              "..1222222222221.",
              ".12232222223221.",
              ".12222222222221.",
              ".12222444422221.",
              "..122244442221..",
              "...12245422221..",
              "....122222221...",
              ".....1111111....",
              "................",
              "................",
              "................",
              "................"],
             {"1": FUR_BEAR[0], "2": FUR_BEAR[2], "3": (230, 220, 120), "4": FUR_BEAR[3], "5": (30, 20, 20)}),
}


# ------------------------------------------------------------------ Schiffe und Haefen (Inselhandel)
def _hull(img, cx, y0, half_w, depth, cols, bob, taper=1.0):
    """Rumpf: oben breit, nach unten schmaler; cols = [dunkel, mittel, hell, Kante]."""
    for y in range(depth):
        w = int(half_w - y * taper)
        for x in range(cx - w, cx + w):
            c = cols[1] if y < depth - 2 else cols[0]
            if y == 0:
                c = cols[3]
            elif y == 1:
                c = cols[2]
            elif (x + y) % 7 == 0:
                c = cols[0]
            put(img, x, y0 + y + bob, c)


def _mast(img, x, y0, y1, bob):
    for y in range(y0, y1):
        put(img, x, y + bob, WOOD[0])


def _square_sail(img, x0, y0, w, h, bob, stripe=None, belly=1):
    for y in range(h):
        for x in range(w):
            c = SAIL[1] if (x + y) % 7 else SAIL[0]
            if y < 1:
                c = SAIL[2]
            if stripe and h // 3 <= y < h // 3 + 2:
                c = stripe
            dx = belly if 1 <= y < h - 1 else 0
            put(img, x0 + x + dx, y0 + y + bob, c)


def _waves(img, f, y=43):
    for x in range(1, img.width - 1, 3):
        put(img, x + f, y, (*WATER[4], 200))
        put(img, x + 1 + f, y + 1, (*WATER[3], 180))


def ship_kogge(f):
    img = new(48, 48)
    _mast(img, 24, 6, 34, f)
    _square_sail(img, 15, 9, 18, 16, f, stripe=(196, 60, 50))
    put(img, 24, 5 + f, (196, 60, 50))
    put(img, 25, 5 + f, (196, 60, 50))
    put(img, 26, 6 + f, (196, 60, 50))
    _hull(img, 24, 32, 19, 9, [WOOD[0], WOOD[1], WOOD[2], WOOD[3]], f, taper=1.4)
    # Kastelle vorn und hinten
    rect(img, 6, 28 + f, 8, 4, WOOD[2])
    rect(img, 35, 29 + f, 7, 3, WOOD[2])
    for x in range(6, 14, 2):
        put(img, x, 27 + f, WOOD[3])
    add_outline(img)
    _waves(img, f)
    return img


def ship_fast(f):
    img = new(48, 48)
    _mast(img, 19, 8, 35, f)
    _mast(img, 31, 12, 35, f)
    # Dreieckssegel
    for y in range(9, 31):
        span = int((y - 8) * 0.45)
        for x in range(20, 21 + span):
            put(img, x, y + f, SAIL[1] if (x + y) % 6 else SAIL[0])
    for y in range(13, 31):
        span = int((y - 12) * 0.5)
        for x in range(32, 33 + span):
            put(img, x, y + f, SAIL[2] if (x + y) % 5 else SAIL[1])
    for y in range(20, 31):
        span = int((y - 19) * 0.6)
        for x in range(8, 9 + span):
            put(img, x + (18 - span) // 2, y + f, SAIL[1])
    put(img, 19, 7 + f, (60, 120, 200))
    put(img, 20, 7 + f, (60, 120, 200))
    blue = [(30, 50, 90), (50, 84, 140), (80, 120, 190), (230, 230, 220)]
    _hull(img, 24, 34, 21, 6, blue, f, taper=2.6)
    add_outline(img)
    _waves(img, f)
    return img


def ship_galleon(f):
    img = new(48, 48)
    for mx, top in ((13, 6), (24, 2), (35, 7)):
        _mast(img, mx, top, 32, f)
    _square_sail(img, 7, 9, 13, 8, f)
    _square_sail(img, 7, 19, 13, 9, f)
    _square_sail(img, 17, 5, 15, 9, f, stripe=(200, 160, 40))
    _square_sail(img, 17, 16, 15, 11, f, stripe=(200, 160, 40))
    _square_sail(img, 29, 11, 12, 7, f)
    _square_sail(img, 29, 20, 12, 8, f)
    for mx, top in ((13, 6), (24, 2), (35, 7)):
        put(img, mx + 1, top + f, (196, 60, 50))
        put(img, mx + 2, top + f, (196, 60, 50))
    dark = [(50, 30, 24), (78, 48, 34), (110, 70, 46), GOLD[2]]
    _hull(img, 24, 30, 22, 11, dark, f, taper=1.2)
    # Heckkastell mit Fenstern und Goldband
    rect(img, 34, 24 + f, 10, 6, dark[1])
    for x in range(35, 43, 3):
        put(img, x, 26 + f, (250, 220, 130))
    for x in range(4, 44):
        put(img, x, 34 + f, GOLD[1])
    add_outline(img)
    _waves(img, f)
    return img


def gen_ships(atlas):
    """Zeile y=96 in objects2.png: je Schiff zwei 48x48-Bilder (schaukeln)."""
    for i, fn in enumerate([ship_kogge, ship_fast, ship_galleon]):
        for f in range(2):
            atlas.paste(fn(f), (i * 96 + f * 48, 96))


def _planks(img, x0, y0, w, h, horizontal=True):
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            k = (y - y0) if horizontal else (x - x0)
            c = WOOD[2] if (k // 3) % 2 else WOOD[3]
            if k % 3 == 2:
                c = WOOD[1]
            put(img, x, y, c)


def _posts(img, xs, y0, y1):
    for x in xs:
        for y in range(y0, y1):
            put(img, x, y, WOOD[0])
            put(img, x + 1, y, WOOD[1])


def _crate(img, x, y, s=6):
    rect(img, x, y, s, s, WOOD[2])
    for i in range(s):
        put(img, x + i, y + i, WOOD[1])
        put(img, x + i, y, WOOD[0])
        put(img, x, y + i, WOOD[0])


def _barrel(img, x, y):
    for yy in range(6):
        for xx in range(5):
            c = WOOD[2] if 0 < xx < 4 else WOOD[1]
            if yy in (1, 4):
                c = IRON[1]
            put(img, x + xx, y + yy, c)


def _crane(img, x, y_base, h, arm):
    for y in range(y_base - h, y_base):
        put(img, x, y, WOOD[0])
        put(img, x + 1, y, WOOD[1])
    for i in range(arm):
        put(img, x + 1 + i, y_base - h + i // 3, WOOD[1])
        put(img, x + 1 + i, y_base - h + 1 + i // 3, WOOD[2])
    hook_x = x + arm
    top = y_base - h + arm // 3 + 2
    for y in range(top, top + 9):
        put(img, hook_x, y, (200, 190, 160))
    put(img, hook_x - 1, top + 9, IRON[2])
    put(img, hook_x, top + 9, IRON[2])
    put(img, hook_x + 1, top + 9, IRON[2])


def _quay(img, x0, x1, top, bottom):
    stone_wall(img, x0, top, x1 - x0, bottom - top)
    for x in range(x0, x1):
        put(img, x, top, STONE[4])
        put(img, x, top + 1, STONE[3])


def jetty():
    img = new(64, 64)
    _posts(img, [20, 30, 40], 52, 62)
    _planks(img, 18, 48, 28, 6, horizontal=False)
    # Poller und Tau
    rect(img, 22, 44, 3, 4, IRON[1])
    put(img, 22, 43, IRON[2])
    put(img, 23, 43, IRON[2])
    for x, y in [(37, 45), (38, 44), (39, 44), (40, 45), (39, 46), (38, 46)]:
        put(img, x, y, (200, 180, 130))
    _crate(img, 28, 42)
    add_outline(img)
    return img


def harbor():
    img = new(64, 64)
    _quay(img, 8, 56, 42, 60)
    _planks(img, 10, 38, 44, 5)
    _crane(img, 14, 42, 26, 14)
    _crate(img, 34, 32)
    _crate(img, 41, 32)
    _crate(img, 37, 26)
    _barrel(img, 48, 32)
    # Poller
    for px in (12, 30, 50):
        rect(img, px, 39, 3, 3, IRON[1])
    ground_line(img, 8, 56)
    add_outline(img)
    return img


def harbor_big():
    img = new(64, 64)
    _quay(img, 2, 62, 40, 60)
    # Lagerhalle hinten
    stone_wall(img, 30, 16, 28, 20)
    tile_roof(img, 28, 6, 32, 11)
    door(img, 40, 25, 8, 11, arch=True)
    window(img, 33, 22, 4, 4, lit=False)
    window(img, 51, 22, 4, 4, lit=False)
    _planks(img, 4, 36, 56, 5)
    _crane(img, 6, 40, 28, 13)
    _crane(img, 24, 40, 22, 10)
    _crate(img, 12, 30)
    _barrel(img, 52, 30)
    for px in (5, 22, 40, 57):
        rect(img, px, 37, 3, 3, IRON[1])
    # Wimpel
    for y in range(4, 10):
        put(img, 58, y, WOOD[0])
    for x, y in [(59, 4), (60, 4), (61, 5), (59, 5), (60, 5), (59, 6)]:
        put(img, x, y, (60, 120, 200))
    ground_line(img, 2, 62)
    add_outline(img)
    return img


def _quay_sign(img, x, col):
    for y in range(18, 34):
        put(img, x, y, WOOD[0])
    rect(img, x + 1, 18, 7, 5, col)
    for xx in range(x + 1, x + 8):
        put(img, xx, 18, tuple(min(255, c + 40) for c in col))


def quay(kind):
    img = new(64, 64)
    _quay(img, 8, 56, 42, 60)
    _planks(img, 10, 38, 44, 5)
    _crane(img, 12, 42, 22, 11)
    if kind == "wood":
        # Stammstapel und Bretter
        for row, n in ((0, 5), (1, 4), (2, 3)):
            for i in range(n):
                cx = 30 + i * 5 + row * 2
                cy = 35 - row * 4
                blob(img, cx, cy, 2.6, 2.2, [WOOD[0], WOOD[1], WOOD[2], WOOD[3]], noise_seed=i + row * 7)
                put(img, cx, cy, THATCH[3])
        for y in range(28, 33):
            for x in range(46, 56):
                put(img, x, y, WOOD[3] if y % 2 else WOOD[2])
        _quay_sign(img, 22, (150, 100, 50))
    elif kind == "ore":
        # Schuttkegel aus Erz und Stein, Lore
        blob(img, 36, 34, 8, 5, STONE[0:5], noise_seed=3, jag=0.1)
        blob(img, 48, 35, 5, 4, [(120, 60, 40), (170, 90, 50), (210, 130, 70)], noise_seed=4, jag=0.1)
        put(img, 47, 33, GOLD[2])
        put(img, 50, 34, GOLD[3])
        rect(img, 26, 30, 7, 5, IRON[1])
        put(img, 27, 35, DARK)
        put(img, 31, 35, DARK)
        _quay_sign(img, 22, (110, 112, 130))
    else:
        # Faesser, Koerbe mit Fisch und Aepfeln
        for i, x in enumerate((28, 34, 40)):
            _barrel(img, x, 30)
        for x0, col in ((46, (200, 70, 60)), (52, (120, 170, 210))):
            rect(img, x0, 32, 5, 4, THATCH[1])
            for xx in range(x0, x0 + 5):
                put(img, xx, 31, col)
        _quay_sign(img, 22, (70, 140, 80))
    for px in (12, 34, 50):
        rect(img, px, 39, 3, 3, IRON[1])
    ground_line(img, 8, 56)
    add_outline(img)
    return img


def harbor_buildings():
    """Reihenfolge = Data.BUILDING_CELLS ab Zelle 29."""
    return [jetty(), harbor(), harbor_big(), quay("wood"), quay("ore"), quay("food")]


ICONS_TRADE = {
    "kogge": (["................",
               ".......5........",
               ".......6........",
               "....33333333....",
               "....33888833....",
               "....33333333....",
               "....33333333....",
               ".......6........",
               ".4111111111114..",
               "..12222222221...",
               "...122222221....",
               "....1111111.....",
               "..77.77.77.77...",
               "................",
               "................",
               "................"],
              {"1": WOOD[1], "2": WOOD[2], "3": SAIL[1], "4": WOOD[3], "5": (220, 60, 50), "6": WOOD[0],
               "7": WATER[3], "8": (196, 60, 50)}),
    "schnellsegler": (["................",
                       "....5...........",
                       "....6......5....",
                       "....63.....6....",
                       "....633....63...",
                       "....6333...633..",
                       "....63333..6333.",
                       "....633333.6333.",
                       "....6......6....",
                       ".1111111111111..",
                       "..12222222221...",
                       "....1111111.....",
                       "..77.77.77.77...",
                       "................",
                       "................",
                       "................"],
                      {"1": (50, 84, 140), "2": (80, 120, 190), "3": SAIL[2], "5": (60, 120, 200), "6": WOOD[0],
                       "7": WATER[3]}),
    "galeone": (["..5....5....5...",
                 "..6....6....6...",
                 ".333..3333..33..",
                 ".333..3883..33..",
                 ".333..3333..33..",
                 ".333..3333..33..",
                 "..6....6....6...",
                 ".1111111111111..",
                 ".1999999999991..",
                 "..12222222222...",
                 "..12222222221...",
                 "...111111111....",
                 "..77.77.77.77...",
                 "................",
                 "................",
                 "................"],
                {"1": (50, 30, 24), "2": (78, 48, 34), "3": SAIL[1], "5": (220, 60, 50), "6": WOOD[0],
                 "7": WATER[3], "8": GOLD[1], "9": GOLD[2]}),
    "anker": (["................",
               ".......11.......",
               "......1221......",
               ".......11.......",
               "....1111111.....",
               ".......2........",
               ".......2........",
               ".......2........",
               ".......2........",
               "..1....2....1...",
               "..12...2...21...",
               "...12..2..21....",
               "....1222221.....",
               "......111.......",
               "................",
               "................"],
              {"1": IRON[1], "2": IRON[2]}),
}
