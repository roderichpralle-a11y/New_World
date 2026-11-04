"""Bilder vor dem Export vorbereiten (josh 2026-10-31, Prüfbericht Grafik): was das Spiel bisher beim Laden
selbst gemacht hat, steht jetzt fertig in den Dateien. Nach build.py / bilder_fein.py laufen lassen:

    python3 tools/art_v2/vorbereiten.py

1. Zierbaum der Parkanlage (park_tree) als eigenes Bild in big/: damit braucht kein Bild mehr den alten
   Gebäudeatlas buildings.png (der wird nicht mehr geladen und nicht mehr exportiert).
2. Symbolbögen icons.png (fine 136 und hd 64 je Symbol) als Raster mit 16 Symbolen je Zeile statt einer
   langen Reihe: fine/icons.png war 12648 Punkte breit, mehr als WebGL sicher zeigt (8192).
3. Halbe Größe für iPhone und iPad (half/fine, half/big): bisher wurde dort beim Laden verkleinert.
   Gleiche Regel wie früher in Data.sized_tex: nur Bilder mit mehr als 4 Punkten je Spielpixel.
Mehrfaches Ausführen ändert nichts mehr."""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
HD = os.path.join(HERE, "..", "..", "assets", "sprites_hd")
ICON_COLS = 16
MAX_TEX = 8192


def park_tree():
    ip = os.path.join(HD, "big", "index.json")
    index = json.load(open(ip))
    out = os.path.join(HD, "big", "park_tree.png")
    if "park_tree" in index and os.path.exists(out):
        return
    sheet = Image.open(os.path.join(HD, "buildings.png")).convert("RGBA")
    i = 77  # Data.BUILDING_CELLS["park_tree"], Zellen 64 Spielpixel, 4 Punkte je Spielpixel
    sheet.crop(((i % 8) * 256, (i // 8) * 256, (i % 8) * 256 + 256, (i // 8) * 256 + 256)).save(out, optimize=True)
    index["park_tree"] = [1, 64, 64]
    json.dump(index, open(ip, "w"), indent=0, sort_keys=True)
    print("   park_tree -> big/park_tree.png")


# Größer als gemessen (josh): Name -> [Faktor, Höhe in Spielpixeln danach]. Wachturm 1,5-mal so hoch (2026-10-31).
GROW = {"tower": [1.5, 53]}
F = 8.5  # Bildpunkte je Spielpixel in big/


def grow():
    ip = os.path.join(HD, "big", "index.json")
    index = json.load(open(ip))
    for name, (k, target_h) in GROW.items():
        if name not in index or int(index[name][2]) >= target_h:
            continue
        p = os.path.join(HD, "big", name + ".png")
        img = Image.open(p).convert("RGBA")
        body = img.crop(img.getbbox())
        body = body.resize((round(body.width * k), round(body.height * k)), Image.LANCZOS)
        w, h = -(-body.width // F), -(-body.height // F)
        w, h = int(w), int(h)
        out = Image.new("RGBA", (int(w * F), int(h * F)), (0, 0, 0, 0))
        out.alpha_composite(body, ((out.width - body.width) // 2, out.height - body.height))
        out.save(p, optimize=True)
        print("   %s: %s -> %s Spielpixel" % (name, index[name][1:], [w, h]))
        index[name] = [1, w, h]
    json.dump(index, open(ip, "w"), indent=0, sort_keys=True)


def icon_grid(path, cell):
    img = Image.open(path).convert("RGBA")
    if img.height != cell:
        return  # schon ein Raster
    n = img.width // cell
    rows = -(-n // ICON_COLS)
    out = Image.new("RGBA", (ICON_COLS * cell, rows * cell), (0, 0, 0, 0))
    for k in range(n):
        out.paste(img.crop((k * cell, 0, k * cell + cell, cell)), ((k % ICON_COLS) * cell, (k // ICON_COLS) * cell))
    out.save(path, optimize=True)
    print("   %s: %d x %d -> %d x %d" % (os.path.relpath(path, HD), img.width, img.height, out.width, out.height))


def _half(src, dst, game_w, game_h):
    img = Image.open(src).convert("RGBA")
    k = MAX_TEX / max(img.width, img.height)
    if k < 1.0:
        img = img.resize((int(img.width * k), int(img.height * k)), Image.LANCZOS)
    if img.width <= game_w * 4:
        return False
    w, h = max(game_w, img.width // 2), max(game_h, img.height // 2)
    if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
        return True
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.resize((w, h), Image.BICUBIC).save(dst, optimize=True)
    return True


def halves():
    n = 0
    sizes = {}  # half/sizes.json: Spielgröße der feinen Bögen, damit das Spiel das große Bild gar nicht erst lädt
    fine = os.path.join(HD, "fine")
    for f in sorted(os.listdir(fine)):
        if f.endswith(".png"):
            im = Image.open(os.path.join(fine, f))
            gw, gh = im.width * 16 // 136, im.height * 16 // 136
            sizes["fine/" + f] = [gw, gh]
            n += _half(os.path.join(fine, f), os.path.join(HD, "half", "fine", f), gw, gh)
    json.dump(sizes, open(os.path.join(HD, "half", "sizes.json"), "w"), indent=0, sort_keys=True)
    index = json.load(open(os.path.join(HD, "big", "index.json")))
    for name, (frames, w, h) in index.items():
        p = os.path.join(HD, "big", name + ".png")
        if os.path.exists(p):
            n += _half(p, os.path.join(HD, "half", "big", name + ".png"), int(frames) * int(w), int(h))
    print("   halbe Größe: %d Bilder in half/" % n)


if __name__ == "__main__":
    park_tree()
    grow()
    icon_grid(os.path.join(HD, "fine", "icons.png"), 136)
    icon_grid(os.path.join(HD, "icons.png"), 64)
    halves()
