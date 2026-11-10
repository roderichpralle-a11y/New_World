"""Hochregallager (josh 2026-11-10): joshs Bild tools/art_v2/src/einzeln/hochregallager_gefuellt.png
(485 x 524, Fußpunkt unten mittig, für 3 Felder Breite) in den Maßstab des Großen Lagers bringen:
8,5 Dateipixel je Spielpixel, darunter 3 Spielpixel Rand (BIG_PAD in build.py).
Bei 4 Feldern Breite (TILES = 4) wird das Bild um ein Drittel größer gerechnet.

    python3 tools/art_v2/hochregal.py   -> assets/sprites_hd/big/store_high.png + index.json
"""
import json
import math
import os

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "tools", "art_v2", "src", "einzeln", "hochregallager_gefuellt.png")
BIG = os.path.join(ROOT, "assets", "sprites_hd", "big")
NAME = "store_high"
TILES = 3          # Breite der Grundfläche, für die joshs Bild gezeichnet ist
DRAWN_FOR = 3
K = 8.5            # Dateipixel je Spielpixel (store_big: 646 / 76)
PAD = 3            # Spielpixel unter dem Bild


def main():
    img = Image.open(SRC).convert("RGBA")
    img = img.crop(img.getbbox())
    f = TILES / DRAWN_FOR
    if f != 1:
        img = img.resize((round(img.width * f), round(img.height * f)), Image.LANCZOS)
    gw = math.ceil(img.width / K)
    gh = math.ceil(img.height / K) + PAD
    # Datei genau gw*K x gh*K, damit Breite und Höhe denselben Maßstab haben (K = 8,5: gerade Spielpixelzahl)
    gw += gw % 2
    gh += gh % 2
    out = Image.new("RGBA", (int(gw * K), int(gh * K)), (0, 0, 0, 0))
    out.alpha_composite(img, ((out.width - img.width) // 2, out.height - int(PAD * K) - img.height))
    out.save(os.path.join(BIG, NAME + ".png"), optimize=True)
    ip = os.path.join(BIG, "index.json")
    index = json.load(open(ip))
    index[NAME] = [1, gw, gh]
    json.dump(index, open(ip, "w"), indent=0, sort_keys=True)
    print(NAME, out.size, index[NAME])


if __name__ == "__main__":
    main()
