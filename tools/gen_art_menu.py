#!/usr/bin/env python3
"""Bilder für die Knöpfe der Leiste unten (josh 2026-10-19: Bilder statt Text, kleinere Knöpfe).

Schreibt assets/sprites/menu_icons.png: eine Reihe Bilder je 20x20, in der Reihenfolge von NAMES
(Hud.MENU_ICONS liest dieselbe Reihenfolge). Aufruf: python3 tools/gen_art_menu.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_art import (new, put, add_outline, WOOD, STONE, THATCH, PLASTER, LEAF, SAND, WATER, IRON,
                     GLOW, ROOF_RED, SLATE)

S = 20
NAMES = ["bauen", "forschung", "siedler", "inseln", "menue", "verwalter"]
SKIN = [(196, 132, 96), (232, 176, 130), (246, 206, 164)]
PAPER = [(200, 186, 150), (236, 226, 196), (252, 246, 228)]
BLUE = [(40, 70, 130), (60, 104, 176), (100, 146, 214)]
RED = [(130, 40, 40), (180, 62, 52), (220, 100, 80)]
INK = (60, 44, 40)


def rect(img, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            put(img, x, y, c)


def bauen():
    """Kleines Haus mit Strohdach, davor ein Hammer schräg."""
    img = new(S, S)
    for y in range(3, 10):  # Dach
        half = y - 2
        for x in range(9 - half, 10 + half):
            put(img, x, y, THATCH[2] if (x + y) % 3 else THATCH[1])
    rect(img, 4, 10, 15, 17, PLASTER[1])
    rect(img, 4, 10, 15, 10, PLASTER[0])
    rect(img, 8, 13, 10, 17, WOOD[1])  # Tür
    rect(img, 12, 12, 13, 13, (120, 170, 210))  # Fenster
    # Hammer: Stiel schräg, Kopf oben rechts
    for i in range(7):
        put(img, 11 + i, 18 - i, WOOD[2])
        put(img, 12 + i, 18 - i, WOOD[1])
    rect(img, 15, 9, 19, 11, IRON[2])
    rect(img, 15, 11, 19, 11, IRON[1])
    return add_outline(img)


def forschung():
    """Offenes Buch, darüber ein leuchtender Stern."""
    img = new(S, S)
    for x in range(2, 18):  # Einband
        put(img, x, 16, WOOD[1])
        put(img, x, 15, WOOD[2])
    for x in range(3, 17):  # Seiten, zur Mitte hin abfallend
        top = 9 + abs(x - 9.5) // 3
        for y in range(int(top), 15):
            put(img, x, y, PAPER[2] if x not in (9, 10) else PAPER[0])
    for x in (4, 5, 6, 7, 12, 13, 14, 15):  # Zeilen
        put(img, x, 11, PAPER[0])
        put(img, x, 13, PAPER[0])
    # Stern
    for dx, dy in [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)]:
        put(img, 10 + dx, 4 + dy, GLOW[2] if abs(dx) + abs(dy) <= 1 else GLOW[1])
    return add_outline(img)


def _person(img, cx, top, shirt):
    rect(img, cx - 1, top, cx + 1, top, (90, 60, 40))  # Haar
    rect(img, cx - 2, top + 1, cx + 2, top + 4, SKIN[1])
    rect(img, cx - 2, top + 1, cx + 2, top + 1, (90, 60, 40))
    put(img, cx - 1, top + 3, INK)
    put(img, cx + 1, top + 3, INK)
    rect(img, cx - 3, top + 5, cx + 3, top + 10, shirt[1])
    rect(img, cx - 3, top + 5, cx - 3, top + 10, shirt[0])
    rect(img, cx + 3, top + 5, cx + 3, top + 10, shirt[0])
    rect(img, cx - 2, top + 11, cx - 1, top + 13, WOOD[0])
    rect(img, cx + 1, top + 11, cx + 2, top + 13, WOOD[0])


def siedler():
    """Zwei Siedler nebeneinander."""
    img = new(S, S)
    _person(img, 6, 3, BLUE)
    _person(img, 13, 4, RED)
    return add_outline(img)


def inseln():
    """Insel mit Palme im Wasser, daneben ein Segelboot."""
    img = new(S, S)
    for y in range(13, 19):
        for x in range(0, S):
            put(img, x, y, WATER[2] if (x + y) % 4 else WATER[3])
    for y in range(10, 15):  # Insel
        half = 7 - (14 - y)
        for x in range(8 - half, 9 + half):
            put(img, x, y, SAND[2] if y >= 12 else LEAF[3])
    for y in range(3, 11):  # Palme
        put(img, 8, y, WOOD[2])
    for dx in range(-4, 5):
        put(img, 8 + dx, 3 + abs(dx) // 2, LEAF[2])
        put(img, 8 + dx, 4 + abs(dx) // 2, LEAF[1])
    # Boot
    rect(img, 13, 15, 18, 16, WOOD[1])
    for y in range(9, 15):
        put(img, 16, y, WOOD[0])
        for x in range(13 + (14 - y) // 2, 16):
            put(img, x, y, PAPER[2])
    return add_outline(img)


def menue():
    """Zahnrad mit acht Zähnen: Einstellungen und Spielstände."""
    import math
    img = new(S, S)
    cx, cy = 9.5, 9.5
    for y in range(S):
        for x in range(S):
            dx, dy = x - cx, y - cy
            d = (dx * dx + dy * dy) ** 0.5
            a = (math.atan2(dy, dx) / (2 * math.pi) * 8 + 8.25) % 1.0
            if d <= 2.2:
                continue  # Loch
            if d <= 6.0 or (d <= 8.8 and a < 0.5):
                put(img, x, y, IRON[3] if dx + dy < -3 else (IRON[2] if dx + dy < 3 else IRON[1]))
    return add_outline(img)


def verwalter():
    """Verwalter im dunklen Rock mit Schreibbrett."""
    img = new(S, S)
    _person(img, 8, 2, SLATE)
    # Schreibbrett vor dem Körper, rechts
    rect(img, 10, 8, 16, 16, WOOD[2])
    rect(img, 11, 9, 15, 15, PAPER[2])
    rect(img, 12, 7, 14, 8, IRON[2])
    for y in (10, 12, 14):
        rect(img, 12, y, 14, y, INK)
    put(img, 11, 10, (60, 150, 70))
    put(img, 11, 12, (60, 150, 70))
    return add_outline(img)


def main():
    from PIL import Image
    sheet = Image.new("RGBA", (S * len(NAMES), S), (0, 0, 0, 0))
    for i, n in enumerate(NAMES):
        sheet.paste(globals()[n](), (i * S, 0))
    out = os.path.join(os.path.dirname(__file__), "..", "assets", "sprites", "menu_icons.png")
    sheet.save(out)
    big = sheet.resize((sheet.width * 6, sheet.height * 6), Image.NEAREST)
    os.makedirs(os.path.join(os.path.dirname(__file__), "preview"), exist_ok=True)
    big.save(os.path.join(os.path.dirname(__file__), "preview", "menu_icons.png"))
    print("menu_icons.png:", ", ".join(NAMES))


if __name__ == "__main__":
    main()
