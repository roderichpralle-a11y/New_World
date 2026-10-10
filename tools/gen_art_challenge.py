"""Grafiken fuer "Mehr Herausforderung": Tafelmacherei, Brunnen, Gewuerzstrauch, Pirat und
neue Symbole (Tontafel, Gewuerze, Ereignis, Haendler, Feuer, Ratte).

Wird von gen_art.py (Gebaeude, Symbole) und gen_art_sea.py (objects2.png, animals.png)
aufgerufen. Alles haengt hinten an, damit die bisherigen Bilder unveraendert bleiben.
"""
from gen_art import (WOOD, STONE, LEAF, THATCH, CLAY, IRON, WATER, FIRE, new, put, add_outline, blob,
                     stone_wall, ground_line)

TABLET = [(112, 92, 76), (146, 120, 98), (176, 150, 124), (204, 182, 156)]
SPICE = [(150, 40, 30), (200, 70, 40), (236, 120, 50), (250, 180, 80)]
SKIN = [(176, 120, 84), (214, 160, 116), (236, 190, 146)]
BANDANA = [(140, 26, 30), (196, 44, 44), (236, 92, 80)]
SHIRT = [(214, 208, 196), (244, 240, 230)]
STRIPE = (54, 72, 130)
PANTS = [(52, 46, 62), (76, 68, 90)]
BOOT = (34, 26, 26)
BELT = (110, 70, 40)
BLADE = [(120, 124, 140), (190, 196, 208), (236, 240, 248)]
BRASS = (230, 180, 60)
RAT = [(70, 66, 72), (110, 104, 110), (150, 144, 148), (190, 184, 186)]


# ------------------------------------------------------------------ Gebaeude
def _tablet(img, x0, y0, w=4, h=5, tone=1):
    """Kleine Tontafel mit Keilschrift-Strichen."""
    for y in range(h):
        for x in range(w):
            c = TABLET[tone + 1] if x == 0 or y == 0 else TABLET[tone]
            put(img, x0 + x, y0 + y, c)
    for y in range(1, h - 1, 2):
        put(img, x0 + 1 + (y // 2) % 2, y0 + y, TABLET[0])
        if w > 3:
            put(img, x0 + w - 2, y0 + y, TABLET[0])


def tablet_works():
    """Tafelmacherei (2x2): Trockengestell mit Tontafeln unter einem Strohdach, Lehmhaufen."""
    img = new(64, 64)
    # Pfosten des Gestells
    for x0 in (10, 40):
        for y in range(22, 60):
            put(img, x0, y, WOOD[1])
            put(img, x0 + 1, y, WOOD[2])
    # Strohdach (leicht schraeg)
    for y in range(14, 24):
        inset = (23 - y) // 3
        for x in range(6 + inset, 47 - inset):
            c = THATCH[2] if (x + y) % 4 else THATCH[1]
            if y >= 22:
                c = THATCH[0]
            if y == 14 + 0 and x % 3 == 0:
                c = THATCH[3]
            put(img, x, y, c)
    # Drei Regalbretter mit Tafeln
    for i, sy in enumerate((32, 42, 52)):
        for x in range(10, 42):
            put(img, x, sy, WOOD[2])
            put(img, x, sy + 1, WOOD[0])
        for k, tx in enumerate(range(13, 39, 6)):
            if (i + k) % 5 == 4:
                continue  # Luecke im Regal
            _tablet(img, tx, sy - 6, 4, 6, 1 if (i + k) % 2 else 2)
    # Arbeitstisch mit nassen Tafeln
    for x in range(44, 60):
        put(img, x, 46, WOOD[3])
        put(img, x, 47, WOOD[1])
    for x0 in (45, 58):
        for y in range(48, 60):
            put(img, x0, y, WOOD[0])
    _tablet(img, 47, 42, 4, 4, 0)
    _tablet(img, 53, 42, 4, 4, 1)
    # Lehmhaufen vorne rechts
    blob(img, 52, 56, 8, 4.5, [CLAY[0], CLAY[1], CLAY[2], (230, 176, 120)], noise_seed=77)
    ground_line(img, 6, 62)
    add_outline(img)
    return img


def well():
    """Brunnen (1x1): runder Steinbrunnen mit Holzdach, Kurbel und Eimer."""
    img = new(64, 64)
    # Brunnenring: Steinwand mit ovalem Rand oben
    stone_wall(img, 23, 46, 18, 13)
    for x in range(22, 42):
        dx = (x + 0.5 - 32) / 10
        for y in range(42, 49):
            dy = (y + 0.5 - 45.5) / 3.5
            if dx * dx + dy * dy <= 1:
                put(img, x, y, STONE[3] if dy < 0 else STONE[2])
    for x in range(25, 39):
        dx = (x + 0.5 - 32) / 7
        for y in range(43, 48):
            dy = (y + 0.5 - 45.5) / 2.2
            if dx * dx + dy * dy <= 1:
                put(img, x, y, WATER[0] if dy < 0 else WATER[1])
    # Pfosten
    for x0 in (22, 40):
        for y in range(24, 50):
            put(img, x0, y, WOOD[1])
            put(img, x0 + 1, y, WOOD[2])
    # Kurbelwelle mit Seil und Eimer
    for x in range(22, 42):
        put(img, x, 30, WOOD[0])
    put(img, 42, 30, WOOD[2])
    put(img, 43, 31, WOOD[2])
    put(img, 43, 32, WOOD[1])
    for y in range(31, 37):
        put(img, 31, y, (200, 186, 150))
    for y in range(37, 42):
        for x in range(29, 34):
            put(img, x, y, WOOD[2] if x not in (29, 33) else WOOD[1])
    for x in range(29, 34):
        put(img, x, 38, IRON[1])
    # Satteldach
    for y in range(14, 26):
        half = (y - 14) + 3
        for x in range(32 - half, 32 + half):
            c = WOOD[2] if (x - 32) % 4 else WOOD[1]
            if x < 32:
                c = WOOD[3] if (x - 32) % 4 else WOOD[2]
            put(img, x, y, c)
    for x in range(17, 47):
        put(img, x, 26, WOOD[0])
    ground_line(img, 22, 42)
    add_outline(img)
    return img


def challenge_buildings():
    """Zellen 51 (Tafelmacherei) und 52 (Brunnen) in buildings.png."""
    return [tablet_works(), well()]


# ------------------------------------------------------------------ Natur
def spice_bush(full=True):
    """Gewuerzstrauch (16x16): dunkles Laub, voll mit roten und orangen Schoten."""
    img = new(16, 16)
    blob(img, 8, 9.5, 6.5, 5.5, [(24, 70, 46), LEAF[1], LEAF[2], LEAF[3]], noise_seed=91, jag=0.15)
    blob(img, 9.5, 6.5, 3.5, 3, LEAF[1:4], noise_seed=92)
    # Stamm
    put(img, 8, 14, WOOD[1])
    put(img, 8, 15, WOOD[0])
    if full:
        for x, y, c in [(4, 8, 1), (7, 6, 2), (11, 8, 1), (6, 11, 2), (10, 12, 1), (12, 5, 2), (3, 11, 3)]:
            put(img, x, y, SPICE[c])
            put(img, x, y + 1, SPICE[c - 1])
            put(img, x + 1, y, SPICE[3] if c > 1 else SPICE[2])
    add_outline(img)
    return img


# ------------------------------------------------------------------ Pirat
def pirate(frame, attack=False):
    """Pirat von der Seite (Blick nach rechts) in einer 24x24-Zelle: Kopftuch, Bart,
    gestreiftes Hemd, Saebel. Spalten 0-3 Laufen, 4 Angriff (Saebelhieb nach vorn)."""
    img = new(24, 24)
    hop = -1 if frame in (1, 3) else 0
    lean = 1 if attack else 0
    sw = [(-1, 1), (0, 0), (1, -1), (0, 0)][frame % 4] if not attack else (-1, 2)
    # Beine: hinten dunkler, vorn heller, Stiefel unten
    for i, base in enumerate((10, 12)):
        off = sw[i]
        for y in range(16, 22):
            yy = y + (hop if y < 20 else 0)
            col = BOOT if y >= 20 else PANTS[i]
            put(img, base + off, yy, col)
            put(img, base + off + 1, yy, col)
        put(img, base + off + 2, 21, BOOT)
    # Rumpf: gestreiftes Hemd, Guertel
    for y in range(10, 16):
        for x in range(9, 15):
            c = SHIRT[1] if x > 10 else SHIRT[0]
            if y in (11, 13):
                c = STRIPE
            if y == 15:
                c = BELT
            put(img, x + lean, y + hop, c)
    put(img, 12 + lean, 15 + hop, BRASS)
    # Kopf mit Bart und Auge
    for y in range(4, 10):
        for x in range(10, 15):
            put(img, x + lean, y + hop, SKIN[1] if x < 14 else SKIN[2])
    put(img, 15 + lean, 7 + hop, SKIN[1])  # Nase
    for x in range(11, 15):
        put(img, x + lean, 9 + hop, (60, 36, 26))
    put(img, 14 + lean, 8 + hop, (60, 36, 26))
    put(img, 10 + lean, 8 + hop, (60, 36, 26))
    put(img, 13 + lean, 6 + hop, (30, 20, 24))
    # Kopftuch mit Knoten hinten
    for x in range(9, 15):
        put(img, x + lean, 3 + hop, BANDANA[1])
        put(img, x + lean, 4 + hop, BANDANA[2] if x % 2 else BANDANA[1])
    put(img, 10 + lean, 5 + hop, BANDANA[1])
    put(img, 8 + lean, 5 + hop, BANDANA[0])
    put(img, 7 + lean, 6 + hop, BANDANA[0])
    put(img, 8 + lean, 7 + hop, BANDANA[1])
    # Arm und Saebel
    if attack:
        for x in range(13, 18):
            put(img, x + lean, 11 + hop, SHIRT[0] if x < 16 else SKIN[1])
        put(img, 18 + lean, 10 + hop, BRASS)
        put(img, 18 + lean, 12 + hop, BRASS)
        for x in range(19, 22):
            put(img, x, 11 + hop, BLADE[1])
            put(img, x, 10 + hop, BLADE[2] if x < 21 else BLADE[0])
        put(img, 22, 10 + hop, BLADE[0])
    else:
        for y in range(10, 14):
            put(img, 13 + lean, y + hop, SHIRT[0])
            put(img, 14 + lean, y + hop, SHIRT[0] if y < 13 else SKIN[1])
        put(img, 15, 13 + hop, SKIN[1])
        put(img, 15, 12 + hop, BRASS)
        put(img, 16, 13 + hop, BRASS)
        # gebogene Klinge schraeg nach oben
        for (x, y) in [(16, 11), (17, 10), (17, 9), (18, 8), (18, 7), (19, 6)]:
            put(img, x, y + hop, BLADE[1])
            put(img, x + 1, y + hop, BLADE[2] if y > 6 else BLADE[0])
    add_outline(img)
    return img


# ------------------------------------------------------------------ Symbole
ICONS_CHALLENGE = {
    "tontafel": (["................",
                  "................",
                  "..222222222.....",
                  "..2333333331....",
                  "..23.1.11.31....",
                  "..233333333.1...",
                  "..23.11.1.31.1..",
                  "..233333333.1...",
                  "..23.1.11.31.1..",
                  "..2333333331.1..",
                  "..23.11.1.31.1..",
                  "..2333333331.1..",
                  "..1111111111.1..",
                  "....1.1.1.1.1...",
                  "................",
                  "................"],
                 {"1": TABLET[0], "2": TABLET[3], "3": TABLET[2]}),
    "gewuerze": (["................",
                  "........4.......",
                  ".....43334......",
                  "....4322234.....",
                  "...432121234....",
                  "...555555555....",
                  "...566666665....",
                  "...566666665..7.",
                  "..56666666665778",
                  "..5666666666578.",
                  "..566666666657..",
                  "..566666666665..",
                  "...5666666665...",
                  "....55555555....",
                  "................",
                  "................"],
                 {"1": SPICE[0], "2": SPICE[1], "3": SPICE[2], "4": SPICE[3], "5": (140, 104, 64),
                  "6": (214, 186, 136), "7": (200, 40, 36), "8": (60, 130, 60)}),
    "ereignis": (["................",
                  ".......11.......",
                  "......1221......",
                  "......1221......",
                  ".....122221.....",
                  ".....123321.....",
                  "....12233221....",
                  "....12233221....",
                  "...1222332221...",
                  "...1222332221...",
                  "..122222222221..",
                  "..122223322221..",
                  ".12222233222221.",
                  ".11111111111111.",
                  "................",
                  "................"],
                 {"1": (150, 100, 20), "2": (250, 206, 60), "3": (50, 34, 30)}),
    "haendler": (["................",
                  "......1..1......",
                  ".......11.......",
                  "......2222......",
                  ".......33.......",
                  ".....122221.....",
                  "....12222221....",
                  "...1222222221...",
                  "...1224422221...",
                  "..122244222221..",
                  "..122222255521..",
                  "..12222225665...",
                  "...1222255665...",
                  "....11115665....",
                  ".........55.....",
                  "................"],
                 {"1": (100, 64, 40), "2": (160, 112, 66), "3": (200, 186, 150), "4": (200, 150, 96),
                  "5": (150, 100, 30), "6": (250, 214, 90)}),
    "feuer": (["................",
               ".......1........",
               "......11........",
               "......121...1...",
               ".....1221..11...",
               "....12221.121...",
               "....122211221...",
               "...1223221221...",
               "...12233322221..",
               "..1223343332221.",
               "..1233444433321.",
               "..1234444443321.",
               "..1233444443321.",
               "...12334443321..",
               "....111111111...",
               "................"],
              {"1": FIRE[0], "2": FIRE[1], "3": FIRE[2], "4": FIRE[3]}),
    "ratte": (["................",
               "................",
               "................",
               "................",
               "..........11....",
               ".......1112211..",
               ".....111222225..",
               "....12222222223.",
               "...122222222222.",
               "...122222222221.",
               "..6.11111111111.",
               ".6...1.1...1.1..",
               ".6..............",
               "..66............",
               "................",
               "................"],
              {"1": RAT[1], "2": RAT[2], "3": (230, 150, 160), "5": (20, 16, 20), "6": (214, 140, 150)}),
}
