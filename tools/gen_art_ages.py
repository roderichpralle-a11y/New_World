"""Grafiken fuer die Zeitalter (Renaissance bis Zukunft).

Wird von gen_art.py aufgerufen: haengt Gebaeude an buildings.png an (Reihenfolge =
Data.BUILDING_CELLS ab Zelle 35) und liefert neue Symbole (ICONS_AGES).
"""
import math

from gen_art import (WOOD, STONE, PLASTER, SLATE, ROOF_RED, DARK, IRON, BRICK, GRASS, LEAF,
                     new, put, add_outline, stone_wall, brick_wall, plaster_wall, tile_roof, door,
                     window, ground_line, rect, chimney)

CONCRETE = [(96, 100, 110), (140, 144, 154), (178, 182, 190), (214, 216, 222)]
GLASS = [(40, 70, 110), (60, 110, 160), (110, 170, 214), (190, 230, 246)]
STEEL = [(54, 60, 72), (88, 96, 112), (130, 138, 156), (180, 188, 204)]
WHITE = [(170, 180, 190), (210, 218, 226), (236, 242, 246), (252, 254, 255)]
TEAL = [(20, 90, 100), (30, 140, 150), (70, 200, 200), (170, 245, 240)]
GOLD = [(150, 100, 30), (210, 160, 40), (245, 210, 80), (255, 245, 170)]
SOOT = [(50, 46, 50), (80, 76, 80), (120, 116, 120), (170, 166, 170)]
GLOWC = [(200, 70, 30), (250, 150, 50), (255, 220, 120)]


# ------------------------------------------------------------------ Bausteine
def concrete_wall(img, x0, y0, w, h, cols=CONCRETE):
    for y in range(h):
        for x in range(w):
            c = cols[2] if (x * 5 + y * 3) % 13 else cols[1]
            if y % 8 == 7:
                c = cols[1]
            if x == 0 or x == w - 1:
                c = cols[1]
            if y < 2:
                c = cols[3]
            put(img, x0 + x, y0 + y, c)


def glass_window(img, x0, y0, w, h, cols=GLASS):
    for y in range(h):
        for x in range(w):
            edge = x in (0, w - 1) or y in (0, h - 1)
            c = STEEL[1] if edge else (cols[3] if (x - y) % 7 == 0 else cols[2] if y < h // 2 else cols[1])
            put(img, x0 + x, y0 + y, c)


def flat_roof(img, x0, y0, w, h, cols=CONCRETE):
    for y in range(h):
        for x in range(w):
            put(img, x0 + x, y0 + y, cols[3] if y == 0 else cols[0] if y == h - 1 else cols[1])


def smokestack(img, x0, y_top, y_bot, w=5, cols=BRICK, smoke=True):
    for y in range(y_top, y_bot):
        for x in range(w):
            c = cols[2] if x < w - 2 else cols[0]
            if (y - y_top) % 6 == 0:
                c = cols[0]
            put(img, x0 + x, y, c)
    for x in range(-1, w + 1):
        put(img, x0 + x, y_top, cols[2] if x < w else cols[0])
    if smoke:
        for i, (dx, dy, r) in enumerate([(1, -3, 2), (3, -7, 2.5), (6, -10, 2), (9, -12, 1.5)]):
            cx, cy = x0 + w // 2 + dx, y_top + dy
            for y in range(int(cy - r), int(cy + r) + 1):
                for x in range(int(cx - r), int(cx + r) + 1):
                    if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and y >= 0:
                        put(img, x, y, SOOT[3] if (x + y) % 3 else SOOT[2])


def dome(img, cx, cy, r, cols=WHITE, ribs=False):
    for y in range(cy - r, cy + 1):
        for x in range(cx - r, cx + r + 1):
            d = (x - cx) ** 2 + ((y - cy) * 1.15) ** 2
            if d <= r * r:
                shade = (x - cx + (y - cy) * 0.6) / max(1, r)
                c = cols[3] if shade < -0.5 else cols[2] if shade < 0.2 else cols[1]
                if ribs and (x - cx) % 5 == 0:
                    c = cols[0]
                put(img, x, y, c)


def solar_panel(img, x0, y0, w=10, h=7):
    for y in range(h):
        for x in range(w):
            c = (40, 60, 120) if (x % 3 and y % 3) else (150, 170, 210)
            if y == 0:
                c = (180, 200, 230)
            put(img, x0 + x + (h - y) // 2, y0 + y, c)
    for y in range(h, h + 3):
        put(img, x0 + w // 2, y0 + y, STEEL[1])


def sign(img, x0, y0, w, h, bg, fg_pts):
    rect(img, x0, y0, w, h, bg)
    for (x, y, c) in fg_pts:
        put(img, x0 + x, y0 + y, c)


def crate_stack(img, x0, y0, cols=WOOD):
    for (dx, dy) in [(0, 4), (6, 4), (3, 0)]:
        for y in range(5):
            for x in range(6):
                c = cols[2] if 0 < x < 5 and 0 < y < 4 else cols[1]
                put(img, x0 + dx + x, y0 + dy + y, c)


def fence(img, x0, x1, y0, cols=STEEL):
    for x in range(x0, x1):
        put(img, x, y0, cols[2])
        if x % 3 == 0:
            for y in range(y0, y0 + 5):
                put(img, x, y, cols[1])


# ------------------------------------------------------------------ Gebaeude
def glassworks():
    """Glashuette: Backsteinhalle mit kegelfoermigem Ofen und gluehendem Fenster."""
    img = new(64, 64)
    brick_wall(img, 4, 34, 36, 26)
    tile_roof(img, 2, 18, 40, 18, SLATE)
    door(img, 16, 46, 9, 14)
    window(img, 7, 40, 6, 6)
    # Kegelofen
    for y in range(10, 60):
        half = 6 + (y - 10) * 10 // 50
        for x in range(50 - half, 50 + half):
            c = BRICK[2] if x < 50 else BRICK[1]
            if (y // 3 + x // 4) % 5 == 0:
                c = BRICK[0]
            put(img, x, y, c)
    for y in range(48, 56):
        for x in range(46, 54):
            put(img, x, y, GLOWC[2] if 47 < x < 52 and y > 49 else GLOWC[1] if y > 48 else GLOWC[0])
    smokestack(img, 47, 6, 12, 6, BRICK)
    # Glasflaschen
    for i, c in enumerate([GLASS[2], (90, 170, 110), GLASS[3]]):
        bx = 28 + i * 4
        for y in range(52, 59):
            put(img, bx, y, c)
            put(img, bx + 1, y, c)
        put(img, bx, 50, c)
        put(img, bx, 51, c)
    ground_line(img, 2, 62)
    add_outline(img)
    return img


def papermill():
    """Papiermuehle: Fachwerkhaus mit Wasserrad und Papierboegen auf der Leine."""
    img = new(64, 64)
    plaster_wall(img, 6, 32, 40, 28)
    tile_roof(img, 4, 12, 44, 22, ROOF_RED)
    door(img, 20, 46, 8, 14)
    window(img, 10, 38, 6, 6)
    window(img, 34, 38, 6, 6)
    # Wasserrad rechts
    cx, cy, r = 52, 44, 11
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            d = math.hypot(x - cx, y - cy)
            if r - 2 <= d <= r:
                put(img, x, y, WOOD[1])
            elif d < r - 2:
                a = math.atan2(y - cy, x - cx)
                if abs(math.sin(a * 4)) < 0.25:
                    put(img, x, y, WOOD[2])
    rect(img, 44, 55, 20, 5, (60, 120, 190))
    for x in range(44, 64, 3):
        put(img, x, 55, (200, 236, 250))
    # Papierboegen auf der Leine
    for x in range(8, 44):
        put(img, x, 28, WOOD[0])
    for bx in (10, 18, 26, 34):
        rect(img, bx, 29, 6, 5, (250, 248, 238))
        put(img, bx + 5, 33, (210, 206, 196))
    ground_line(img, 4, 62)
    add_outline(img)
    return img


def university():
    """Universitaet: Steinbau mit Saeulen, Kuppel mit Fernrohr und Fahnen."""
    img = new(64, 64)
    stone_wall(img, 2, 32, 60, 28, [STONE[1], STONE[2], STONE[3], STONE[4], STONE[4]])
    tile_roof(img, 2, 22, 60, 12, SLATE, overhang=1)
    dome(img, 32, 22, 12, [GLASS[0], (80, 130, 120), (110, 170, 150), (160, 210, 190)], ribs=True)
    for y in range(4, 11):
        put(img, 32, y, IRON[2])
    for x in range(32, 40):
        put(img, x, 8 - (x - 32) // 3, IRON[1])
    # Saeulen
    for sx in range(8, 58, 8):
        for y in range(36, 58):
            put(img, sx, y, STONE[4])
            put(img, sx + 1, y, STONE[3])
    door(img, 28, 44, 8, 16, arch=True)
    for wx in (11, 19, 39, 47):
        window(img, wx, 40, 5, 9)
    # Fahnen
    for fx, col in ((4, (60, 80, 170)), (58, (170, 50, 50))):
        for y in range(8, 32):
            put(img, fx, y, IRON[1])
        rect(img, fx + 1, 8, 5, 4, col)
    rect(img, 22, 59, 20, 1, STONE[1])
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def steelworks():
    """Stahlwerk: Hochofen, zwei Schlote und gluehender Abstich."""
    img = new(64, 64)
    brick_wall(img, 2, 30, 34, 30)
    flat_roof(img, 2, 27, 34, 4, SOOT)
    for wx in (6, 16, 26):
        window(img, wx, 36, 5, 8)
    door(img, 13, 48, 10, 12)
    # Hochofen
    for y in range(16, 60):
        half = 8 if y > 26 else 6
        for x in range(48 - half, 48 + half):
            c = STEEL[2] if x < 48 else STEEL[1]
            if y % 7 == 0:
                c = STEEL[0]
            put(img, x, y, c)
    for y in range(50, 58):
        for x in range(42, 54):
            put(img, x, y, GLOWC[2] if y > 53 else GLOWC[1])
    for x in range(36, 42):
        put(img, x, 57, GLOWC[1])
        put(img, x, 58, GLOWC[0])
    smokestack(img, 8, 6, 28, 5, SOOT)
    smokestack(img, 22, 10, 28, 5, SOOT)
    smokestack(img, 46, 6, 17, 5, BRICK)
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def factory():
    """Fabrik: Saegezahndach, Schlot mit Rauch, Zahnrad-Schild."""
    img = new(64, 64)
    brick_wall(img, 2, 30, 60, 30)
    # Saegezahndach mit Oberlichtern
    for i in range(5):
        x0 = 2 + i * 12
        for y in range(18, 31):
            for x in range(x0, x0 + 12):
                if x - x0 < (y - 18):
                    put(img, x, y, SLATE[2] if x - x0 < 6 else SLATE[1])
                elif x - x0 >= 11:
                    put(img, x, y, GLASS[2] if y > 20 else GLASS[3])
    for wx in range(6, 58, 10):
        window(img, wx, 38, 6, 8)
    door(img, 26, 46, 12, 14)
    smokestack(img, 54, 2, 30, 6, BRICK)
    # Zahnrad
    cx, cy = 32, 26
    for y in range(cy - 4, cy + 5):
        for x in range(cx - 4, cx + 5):
            d = math.hypot(x - cx, y - cy)
            a = math.atan2(y - cy, x - cx)
            if d <= 3 + (1 if math.cos(a * 6) > 0.3 else 0) and d >= 1.5:
                put(img, x, y, IRON[3])
    crate_stack(img, 44, 50)
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def cannery():
    """Konservenfabrik: Backsteinhaus, Dosenstapel, Fisch-Schild."""
    img = new(64, 64)
    brick_wall(img, 4, 32, 46, 28)
    tile_roof(img, 2, 16, 50, 18, SLATE)
    door(img, 22, 46, 9, 14)
    window(img, 9, 38, 7, 7)
    window(img, 38, 38, 7, 7)
    chimney(img, 40, 10, 10, IRON)
    # Dosenstapel
    for row, n in ((0, 3), (1, 2)):
        for i in range(n):
            x0 = 52 + i * 4 + row * 2
            y0 = 54 - row * 5
            for y in range(5):
                for x in range(3):
                    c = IRON[3] if y == 0 else (200, 60, 50) if y in (2, 3) else IRON[2]
                    put(img, x0 + x, y0 + y, c)
    sign(img, 20, 26, 14, 6, (240, 230, 200),
         [(3, 3, (80, 130, 180)), (4, 2, (80, 130, 180)), (5, 3, (80, 130, 180)), (6, 3, (80, 130, 180)),
          (7, 2, (80, 130, 180)), (8, 3, (80, 130, 180)), (9, 4, (80, 130, 180)), (9, 2, (80, 130, 180))])
    ground_line(img, 2, 62)
    add_outline(img)
    return img


def tenement():
    """Mietshaus: drei Stockwerke Backstein, viele Fenster, Schornsteine."""
    img = new(64, 64)
    brick_wall(img, 6, 14, 52, 46)
    tile_roof(img, 4, 2, 56, 14, SLATE, overhang=2)
    chimney(img, 14, 0, 6)
    chimney(img, 46, 0, 6)
    for row in range(3):
        for col in range(5):
            if row == 2 and col == 2:
                continue
            window(img, 10 + col * 10, 18 + row * 13, 6, 8, lit=(row + col) % 2 == 0)
    door(img, 28, 46, 8, 14, arch=True)
    for x in range(6, 58):
        put(img, x, 30, STONE[3])
        put(img, x, 43, STONE[3])
    ground_line(img, 4, 60)
    add_outline(img)
    return img


def powerplant():
    """Kraftwerk: Betonhalle, Kuehlturm mit Dampf, Strommast mit Leitungen."""
    img = new(64, 64)
    concrete_wall(img, 2, 36, 34, 24)
    flat_roof(img, 2, 33, 34, 4)
    for wx in (6, 16, 26):
        glass_window(img, wx, 40, 6, 6)
    door(img, 14, 50, 9, 10)
    # Kuehlturm (Hyperbel)
    for y in range(12, 60):
        t = (y - 36) / 24.0
        half = int(9 + 4 * t * t)
        for x in range(50 - half, 50 + half):
            c = CONCRETE[3] if x < 50 - half // 3 else CONCRETE[2] if x < 50 + half // 3 else CONCRETE[1]
            put(img, x, y, c)
    for (cx, cy, r) in [(50, 9, 6), (46, 4, 4), (55, 3, 4)]:
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and y >= 0:
                    put(img, x, y, WHITE[3] if (x + y) % 4 else WHITE[2])
    # Blitz-Schild
    for (x, y) in [(20, 22), (19, 23), (18, 24), (19, 24), (20, 24), (19, 25), (18, 26), (17, 27)]:
        put(img, x, y, (250, 220, 60))
    for y in range(29, 34):
        put(img, 19, y, STEEL[1])
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def greenhouse():
    """Gewaechshaus: Glasdach auf Stahlrahmen, gruene Pflanzen und Aepfel innen."""
    img = new(64, 64)
    for y in range(22, 60):
        for x in range(4, 60):
            roof = y < 34
            inside = GLASS[3] if (x + y) % 5 == 0 else (200, 236, 230)
            c = inside if roof else (170, 220, 200)
            if x % 8 == 4 or y == 34 or y == 59:
                c = STEEL[2]
            put(img, x, y, c)
    for y in range(12, 34):
        span = (y - 12) * 28 // 22
        for x in range(32 - span, 32 + span):
            c = (210, 240, 236) if (x - y) % 6 else GLASS[3]
            if x % 8 == 4:
                c = STEEL[2]
            put(img, x, y, c)
    # Pflanzen
    for px in range(8, 58, 7):
        for y in range(46, 58):
            for x in range(px, px + 5):
                if (x - px - 2) ** 2 + (y - 50) ** 2 < 10:
                    put(img, x, y, LEAF[3] if (x + y) % 3 else LEAF[2])
        put(img, px + 1, 48, (210, 50, 50))
        put(img, px + 3, 51, (230, 70, 60))
    ground_line(img, 2, 62)
    add_outline(img)
    return img


def apartment():
    """Wohnblock: Betonhochhaus mit Glasfenstern und Balkonen."""
    img = new(64, 64)
    concrete_wall(img, 10, 4, 44, 56, [(150, 140, 130), (190, 180, 168), (216, 208, 196), (236, 230, 220)])
    flat_roof(img, 9, 2, 46, 3)
    for row in range(6):
        for col in range(4):
            glass_window(img, 14 + col * 10, 7 + row * 8, 6, 5)
        for x in range(12, 52):
            put(img, x, 12 + row * 8, (120, 110, 100))
    rect(img, 27, 50, 10, 10, GLASS[1])
    for y in range(50, 60):
        put(img, 32, y, STEEL[2])
    # Baeume davor
    for tx in (4, 58):
        for y in range(46, 56):
            for x in range(tx - 4, tx + 4):
                if (x - tx) ** 2 + (y - 50) ** 2 < 14:
                    put(img, x, y, LEAF[3] if (x + y) % 3 else LEAF[2])
        for y in range(54, 60):
            put(img, tx, y, WOOD[1])
    ground_line(img, 2, 62)
    add_outline(img)
    return img


def electronics():
    """Elektronikwerk: flache weisse Halle, Reinraum-Fenster, Chip-Schild."""
    img = new(64, 64)
    concrete_wall(img, 2, 30, 60, 30, WHITE)
    flat_roof(img, 2, 27, 60, 4, STEEL)
    for wx in range(6, 58, 12):
        glass_window(img, wx, 36, 9, 7, [TEAL[0], TEAL[1], TEAL[2], TEAL[3]])
    door(img, 28, 48, 9, 12)
    # Chip-Schild auf dem Dach
    rect(img, 24, 14, 16, 12, (40, 50, 60))
    rect(img, 27, 17, 10, 6, (60, 160, 120))
    for i in range(4):
        put(img, 26 + i * 4, 13, GOLD[2])
        put(img, 26 + i * 4, 26, GOLD[2])
        put(img, 23, 16 + i * 3, GOLD[2])
        put(img, 40, 16 + i * 3, GOLD[2])
    for y in range(27, 30):
        put(img, 28, y, STEEL[1])
        put(img, 36, y, STEEL[1])
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def solarpark():
    """Solarpark: Reihen von Solarpaneelen auf der Wiese, Wechselrichter-Haeuschen."""
    img = new(64, 64)
    for row in range(3):
        for col in range(4):
            solar_panel(img, 2 + col * 15, 24 + row * 12, 11, 7)
    rect(img, 50, 54, 10, 6, CONCRETE[2])
    rect(img, 50, 53, 10, 1, CONCRETE[3])
    for (x, y) in [(55, 55), (54, 56), (55, 57), (56, 56)]:
        put(img, x, y, (250, 210, 60))
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def lab():
    """Forschungslabor: Glasbau mit Antenne und Satellitenschuessel."""
    img = new(64, 64)
    concrete_wall(img, 4, 28, 56, 32, WHITE)
    for wx in range(8, 56, 8):
        glass_window(img, wx, 32, 6, 22)
    flat_roof(img, 3, 25, 58, 4, STEEL)
    door(img, 28, 48, 8, 12)
    # Antenne
    for y in range(2, 25):
        put(img, 14, y, STEEL[2])
    for i in range(4):
        for x in range(12 - i, 17 + i):
            put(img, x, 6 + i * 5, STEEL[1])
    put(img, 14, 1, (250, 60, 60))
    # Schuessel
    for y in range(10, 22):
        for x in range(38, 56):
            if (x - 47) ** 2 / 81.0 + (y - 12) ** 2 / 36.0 <= 1 and y >= 12:
                put(img, x, y, WHITE[2] if x < 47 else WHITE[1])
    for y in range(18, 25):
        put(img, 47, y, STEEL[1])
    ground_line(img, 2, 62)
    add_outline(img)
    return img


def ai_center():
    """KI-Zentrum: weisse Kuppel mit leuchtendem Band und Servertuermen."""
    img = new(64, 64)
    rect(img, 4, 44, 56, 16, WHITE[2])
    rect(img, 4, 44, 56, 2, WHITE[3])
    dome(img, 32, 44, 26, WHITE)
    for x in range(8, 57):
        y = 36 + int(3 * math.sin((x - 8) / 7.0))
        put(img, x, y, TEAL[3])
        put(img, x, y + 1, TEAL[2])
    # Auge
    for y in range(24, 33):
        for x in range(26, 39):
            d = ((x - 32) / 6.5) ** 2 + ((y - 28) / 4.0) ** 2
            if d <= 1:
                put(img, x, y, TEAL[2] if d > 0.35 else TEAL[3] if d > 0.1 else (255, 255, 255))
    door(img, 28, 50, 8, 10, arch=True)
    for sx in (8, 50):
        rect(img, sx, 48, 6, 11, STEEL[1])
        for y in range(50, 58, 2):
            put(img, sx + 2, y, TEAL[3])
            put(img, sx + 4, y, (120, 250, 140))
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def fusion():
    """Fusionsreaktor: Torus mit blauem Plasma in einer Halle."""
    img = new(64, 64)
    concrete_wall(img, 2, 34, 60, 26, STEEL)
    flat_roof(img, 2, 31, 60, 4, CONCRETE)
    cx, cy = 32, 30
    for y in range(8, 52):
        for x in range(6, 58):
            d = ((x - cx) / 24.0) ** 2 + ((y - cy) / 14.0) ** 2
            if 0.45 <= d <= 1:
                c = WHITE[2] if y < cy else WHITE[1]
                if abs(d - 0.72) < 0.08:
                    c = (120, 200, 255) if (x + y) % 3 else (220, 250, 255)
                put(img, x, y, c)
    for y in range(22, 38):
        for x in range(20, 44):
            if ((x - cx) / 10.0) ** 2 + ((y - cy) / 6.0) ** 2 <= 1:
                put(img, x, y, (60, 120, 220) if (x - y) % 4 else (180, 230, 255))
    door(img, 28, 50, 8, 10)
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def future_city():
    """Zukunftsstadt: schlanke weisse Tuerme, Glas, gruene Daecher und eine Rakete."""
    img = new(64, 64)
    towers = [(4, 26, 10), (16, 10, 10), (30, 18, 10), (44, 6, 9)]
    for (x0, top, w) in towers:
        for y in range(top, 60):
            for x in range(x0, x0 + w):
                c = WHITE[2] if x < x0 + w - 3 else WHITE[1]
                if (y - top) % 5 == 2 and x0 < x < x0 + w - 1:
                    c = GLASS[2] if (x + y) % 4 else TEAL[3]
                put(img, x, y, c)
        for x in range(x0, x0 + w):
            put(img, x, top - 1, LEAF[3])
            put(img, x, top - 2, LEAF[2] if x % 2 else LEAF[3])
    # Rakete
    for y in range(4, 46):
        for x in range(56, 61):
            put(img, x, y, WHITE[3] if x < 59 else WHITE[1])
    for y in range(0, 5):
        for x in range(58 - (y + 1) // 2, 59 + (y + 1) // 2):
            put(img, x, y, (220, 60, 60))
    for (x, y) in [(55, 42), (55, 43), (55, 44), (61, 42), (61, 43), (61, 44)]:
        put(img, x, y, (220, 60, 60))
    # Schwebebahn
    for x in range(2, 56):
        put(img, x, 36, STEEL[2])
    rect(img, 22, 32, 10, 4, TEAL[2])
    ground_line(img, 0, 64)
    add_outline(img)
    return img


def age_buildings():
    """Reihenfolge = Data.BUILDING_CELLS ab Zelle 35."""
    return [glassworks(), papermill(), university(), steelworks(), factory(), cannery(), tenement(),
            powerplant(), greenhouse(), apartment(), electronics(), solarpark(), lab(), ai_center(),
            fusion(), future_city()]


# ------------------------------------------------------------------ Symbole
class _Grid:
    def __init__(self):
        self.g = [["." for _ in range(16)] for _ in range(16)]

    def set(self, x, y, ch):
        if 0 <= x < 16 and 0 <= y < 16:
            self.g[y][x] = ch

    def rect(self, x0, y0, w, h, ch):
        for y in range(y0, y0 + h):
            for x in range(x0, x0 + w):
                self.set(x, y, ch)

    def circle(self, cx, cy, r, ch, ring=None):
        for y in range(16):
            for x in range(16):
                d = math.hypot(x - cx, y - cy)
                if ring is not None and d <= r and d >= r - ring:
                    self.set(x, y, ch)
                elif ring is None and d <= r:
                    self.set(x, y, ch)

    def line(self, x0, y0, x1, y1, ch):
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            self.set(round(x0 + (x1 - x0) * i / n), round(y0 + (y1 - y0) * i / n), ch)

    def rows(self):
        return ["".join(r) for r in self.g]


def _icon_glas():
    g = _Grid()
    g.rect(4, 3, 8, 11, "1")
    g.rect(5, 4, 6, 9, "2")
    g.line(6, 5, 6, 11, "3")
    g.line(9, 5, 7, 8, "3")
    return g.rows(), {"1": STEEL[1], "2": GLASS[2], "3": GLASS[3]}


def _icon_papier():
    g = _Grid()
    g.rect(3, 2, 10, 12, "1")
    for y in (4, 6, 8, 10):
        g.line(5, y, 10, y, "2")
    g.line(12, 2, 12, 13, "3")
    return g.rows(), {"1": (250, 246, 232), "2": (150, 150, 170), "3": (200, 196, 180)}


def _icon_stahl():
    g = _Grid()
    for i, y in enumerate((9, 5)):
        g.rect(2 + i * 2, y, 11, 4, "1")
        g.line(2 + i * 2, y, 12 + i * 2, y, "2")
        g.line(2 + i * 2, y + 3, 12 + i * 2, y + 3, "3")
    return g.rows(), {"1": STEEL[2], "2": STEEL[3], "3": STEEL[0]}


def _icon_maschinen():
    g = _Grid()
    g.circle(7.5, 7.5, 6, "1")
    for a in range(8):
        ang = a * math.pi / 4
        g.set(round(7.5 + 7 * math.cos(ang)), round(7.5 + 7 * math.sin(ang)), "1")
    g.circle(7.5, 7.5, 2.2, ".")
    g.circle(7.5, 7.5, 5, "2", ring=1)
    return g.rows(), {"1": IRON[2], "2": IRON[3]}


def _icon_konserven():
    g = _Grid()
    g.rect(4, 3, 8, 11, "1")
    g.rect(4, 6, 8, 5, "2")
    g.line(4, 3, 11, 3, "3")
    g.line(6, 8, 9, 8, "4")
    return g.rows(), {"1": IRON[2], "2": (200, 60, 50), "3": IRON[3], "4": (250, 230, 200)}


def _icon_strom():
    g = _Grid()
    pts = [(9, 1), (8, 2), (7, 3), (6, 4), (5, 5), (4, 6), (4, 7), (5, 7), (6, 7), (7, 7), (8, 7), (7, 8),
           (6, 9), (5, 10), (4, 11), (3, 12), (4, 12), (5, 11), (6, 11), (7, 10), (8, 9), (9, 8), (10, 7),
           (11, 6), (10, 6), (9, 6), (8, 6), (7, 6), (8, 5), (9, 4), (10, 3), (10, 2), (10, 1)]
    for (x, y) in pts:
        g.set(x, y, "1")
    g.set(9, 2, "2")
    g.set(8, 3, "2")
    return g.rows(), {"1": (250, 210, 50), "2": (255, 250, 200)}


def _icon_elektronik():
    g = _Grid()
    g.rect(4, 4, 8, 8, "1")
    g.rect(6, 6, 4, 4, "2")
    for i in range(4):
        g.set(5 + i * 2, 2, "3")
        g.set(5 + i * 2, 3, "3")
        g.set(5 + i * 2, 12, "3")
        g.set(5 + i * 2, 13, "3")
        g.set(2, 5 + i * 2, "3")
        g.set(3, 5 + i * 2, "3")
        g.set(12, 5 + i * 2, "3")
        g.set(13, 5 + i * 2, "3")
    return g.rows(), {"1": (40, 50, 60), "2": (60, 170, 120), "3": GOLD[2]}


def _icon_uhr():
    g = _Grid()
    g.circle(7.5, 7.5, 6.5, "1")
    g.circle(7.5, 7.5, 5.5, "2")
    g.line(8, 8, 8, 3, "3")
    g.line(8, 8, 11, 8, "3")
    return g.rows(), {"1": GOLD[1], "2": (250, 246, 232), "3": DARK}


def _icon_fernrohr():
    g = _Grid()
    for i in range(10):
        g.rect(2 + i, 10 - i, 3, 2, "1" if i < 6 else "2")
    g.line(6, 10, 3, 14, "3")
    g.line(6, 10, 9, 14, "3")
    return g.rows(), {"1": GOLD[2], "2": GOLD[1], "3": WOOD[1]}


def _icon_dampf():
    g = _Grid()
    g.rect(2, 9, 12, 5, "1")
    g.rect(3, 6, 3, 4, "1")
    g.circle(4, 13, 2, "2")
    g.circle(11, 13, 2, "2")
    for (x, y) in [(4, 4), (5, 3), (4, 2), (6, 1), (7, 2)]:
        g.set(x, y, "3")
    return g.rows(), {"1": STEEL[1], "2": DARK, "3": WHITE[2]}


def _icon_zug():
    g = _Grid()
    g.rect(1, 6, 9, 6, "1")
    g.rect(9, 4, 5, 8, "2")
    g.rect(10, 5, 3, 2, "3")
    g.rect(2, 3, 2, 3, "1")
    for x in (3, 7, 11):
        g.circle(x, 12.5, 1.6, "4")
    g.line(0, 15, 15, 15, "5")
    return g.rows(), {"1": (60, 90, 70), "2": (190, 60, 50), "3": GLASS[3], "4": DARK, "5": WOOD[1]}


def _icon_spritze():
    g = _Grid()
    for i in range(8):
        g.rect(3 + i, 11 - i, 2, 2, "1")
    g.line(11, 3, 14, 0, "2")
    g.line(2, 13, 0, 15, "3")
    g.rect(5, 9, 3, 1, "4")
    return g.rows(), {"1": WHITE[2], "2": STEEL[2], "3": STEEL[1], "4": (200, 60, 60)}


def _icon_schnee():
    g = _Grid()
    for (dx, dy) in [(1, 0), (0, 1), (1, 1), (1, -1)]:
        g.line(7 - 6 * dx, 7 - 6 * dy, 7 + 6 * dx, 7 + 6 * dy, "1")
    g.circle(7, 7, 1.5, "2")
    return g.rows(), {"1": (140, 200, 240), "2": (230, 248, 255)}


def _icon_motor():
    g = _Grid()
    g.rect(3, 5, 10, 8, "1")
    g.rect(5, 2, 2, 3, "2")
    g.rect(9, 2, 2, 3, "2")
    g.rect(1, 7, 2, 4, "2")
    g.rect(13, 7, 2, 4, "2")
    g.line(5, 8, 10, 8, "3")
    g.line(5, 10, 10, 10, "3")
    return g.rows(), {"1": (180, 50, 40), "2": STEEL[1], "3": DARK}


def _icon_computer():
    g = _Grid()
    g.rect(2, 2, 12, 9, "1")
    g.rect(3, 3, 10, 7, "2")
    g.line(4, 5, 8, 5, "3")
    g.line(4, 7, 10, 7, "3")
    g.rect(6, 11, 4, 2, "1")
    g.rect(3, 13, 10, 2, "4")
    return g.rows(), {"1": STEEL[1], "2": (30, 60, 90), "3": (120, 240, 160), "4": WHITE[1]}


def _icon_netz():
    g = _Grid()
    g.circle(7.5, 7.5, 6.5, "1", ring=1)
    g.line(1, 7, 14, 7, "1")
    g.line(7, 1, 7, 14, "1")
    for y in range(16):
        for x in range(16):
            d = math.hypot((x - 7.5) * 2.2, y - 7.5)
            if 6 <= d <= 7:
                g.set(x, y, "1")
    g.circle(7.5, 7.5, 5.5, "2")
    g.circle(7.5, 7.5, 6.5, "1", ring=1)
    g.line(1, 7, 14, 7, "1")
    g.line(7, 1, 7, 14, "1")
    return g.rows(), {"1": TEAL[1], "2": (90, 150, 230)}


def _icon_dna():
    g = _Grid()
    for y in range(16):
        a = y / 15.0 * 2 * math.pi
        x1 = 7.5 + 4 * math.sin(a)
        x2 = 7.5 - 4 * math.sin(a)
        g.set(round(x1), y, "1")
        g.set(round(x2), y, "2")
        if y % 3 == 0:
            g.line(round(min(x1, x2)) + 1, y, round(max(x1, x2)) - 1, y, "3")
    return g.rows(), {"1": (80, 140, 230), "2": (220, 80, 120), "3": WHITE[1]}


def _icon_ki():
    g = _Grid()
    g.circle(7.5, 8, 6.5, "1")
    g.circle(7.5, 8, 5, "2")
    for (x, y) in [(5, 6), (10, 6), (7, 9), (5, 11), (10, 11), (8, 4)]:
        g.set(x, y, "3")
    g.line(5, 6, 7, 9, "4")
    g.line(10, 6, 7, 9, "4")
    g.line(7, 9, 5, 11, "4")
    g.line(7, 9, 10, 11, "4")
    return g.rows(), {"1": TEAL[1], "2": (20, 40, 60), "3": TEAL[3], "4": TEAL[2]}


def _icon_roboter():
    g = _Grid()
    g.rect(4, 3, 8, 6, "1")
    g.set(6, 5, "2")
    g.set(9, 5, "2")
    g.line(7, 1, 7, 2, "3")
    g.set(7, 0, "4")
    g.rect(3, 9, 10, 5, "3")
    g.rect(1, 10, 2, 3, "1")
    g.rect(13, 10, 2, 3, "1")
    g.line(6, 7, 9, 7, "2")
    return g.rows(), {"1": WHITE[2], "2": TEAL[3], "3": STEEL[2], "4": (250, 60, 60)}


def _icon_atom():
    g = _Grid()
    for k in range(3):
        a0 = k * math.pi / 3
        for t in range(64):
            th = t / 64.0 * 2 * math.pi
            x = 6.5 * math.cos(th)
            y = 2.5 * math.sin(th)
            g.set(round(7.5 + x * math.cos(a0) - y * math.sin(a0)), round(7.5 + x * math.sin(a0) + y * math.cos(a0)), "1")
    g.circle(7.5, 7.5, 1.6, "2")
    return g.rows(), {"1": (100, 180, 250), "2": (250, 120, 60)}


def _icon_zeitalter():
    g = _Grid()
    g.rect(6, 1, 4, 1, "1")
    g.rect(6, 14, 4, 1, "1")
    for y in range(2, 14):
        half = abs(7.5 - y) * 0.7 + 0.5
        g.line(round(8 - half), y, round(7 + half), y, "2" if y < 8 else "3")
    g.line(7, 7, 8, 8, "3")
    return g.rows(), {"1": WOOD[1], "2": GLASS[3], "3": (230, 200, 120)}


ICONS_AGES = {
    "glas": _icon_glas(), "papier": _icon_papier(), "stahl": _icon_stahl(), "maschinen": _icon_maschinen(),
    "konserven": _icon_konserven(), "strom": _icon_strom(), "elektronik": _icon_elektronik(),
    "uhr": _icon_uhr(), "fernrohr": _icon_fernrohr(), "dampf": _icon_dampf(), "zug": _icon_zug(),
    "spritze": _icon_spritze(), "schnee": _icon_schnee(), "motor": _icon_motor(), "computer": _icon_computer(),
    "netz": _icon_netz(), "dna": _icon_dna(), "ki": _icon_ki(), "roboter": _icon_roboter(), "atom": _icon_atom(),
    "zeitalter": _icon_zeitalter(),
}
