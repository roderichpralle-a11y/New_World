"""Größenverhältnisse für Version 2 (josh 2026-10-24, Weg B "Spielzeug-Maßstab").

Maßstab ist die Figur: 21 Spielpixel (etwa 1,75 m), sie bleibt immer so. In jedem Gebäudebild
wurde die Haustür im Bogen gemessen (Bogenpixel); eine Tür wird DOOR Spielpixel hoch, etwas
kleiner als die Figur (Weg B). Bilder ohne Tür bekommen den Maßstab ihres Bogens (die anderen
Bilder desselben Bogens) oder eine feste Höhe nach der Wirklichkeit in Figur-Einheiten.

Aufruf: python3 tools/art_v2/scale.py  schreibt die Vergleichstafel nach tools/preview/v2/.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build  # noqa: E402

FIG = 21.0  # Figur in Spielpixeln
DOOR = 18.0  # Tür in Spielpixeln (Weg B: 0,85 Figuren)

# Türhöhe je Bogen (Bogenpixel), gilt für Bilder ohne eigene Messung
SHEET_DOOR = {
    "gebaeude_wohnen_1": 78, "gebaeude_lager_1": 128, "gebaeude_nahrung_1": 62,
    "gebaeude_handwerk_1": 60, "gebaeude_see_1": 50, "gebaeude_wissen_1": 60,
}
# Gemessene Türen (Bogenpixel)
DOORS = {
    "hut": 77, "house_wood": 77, "house_stone": 90, "school": 80, "tenement": 75, "apartment": 62,
    "storehouse": 110, "store_big": 128,
    "mill": 55, "smokehouse": 67, "lodge": 65, "henhouse": 62, "pigsty": 62, "cowshed": 62,
    "cannery": 70, "greenhouse": 85, "bakery": 62,
    "scriptorium": 60, "scriptorium2": 60, "library": 62, "university": 52,
    "shipyard": 50,
}
# Ohne Tür: feste Höhe oder Breite in Spielpixeln (Bild samt Sockel), nach der Wirklichkeit
FIXED = {
    # Seefahrt
    "lighthouse": ("h", 84), "tower": ("h", 50), "monument": ("h", 46),
    # Zukunft (eigener Bogen)
    "ai_center": ("w", 112), "future_city": ("w", 124),
    # Schmuck
    "flowerbed_red": ("w", 18), "flowerbed_yellow": ("w", 18), "flowerbed_blue": ("w", 18),
    "bench": ("w", 20), "menhir": ("h", 24), "flagpole": ("h", 44), "statue_stone": ("h", 28),
    "flower_tub": ("h", 11), "fountain": ("w", 36), "pond": ("w", 38), "park": ("w", 54),
    "rose_arch": ("h", 27), "sundial": ("h", 15), "lantern": ("h", 26), "pavilion": ("h", 40),
    "equestrian": ("h", 42), "obelisk": ("h", 38), "statue_bronze": ("h", 32), "street_lamp": ("h", 32),
    "hologram": ("h", 28),
    # Natur: Bäume etwa 2,7 Figuren, Büsche und Felsen bis zur Hüfte
    "tree0": ("h", 58), "tree1": ("h", 58), "tree2": ("h", 58), "tree3": ("h", 64), "sapling": ("h", 22),
    "stump": ("h", 12), "rock_big": ("h", 15), "rock_small": ("h", 9), "bush_full": ("h", 13),
    "bush_empty": ("h", 13), "palm0": ("h", 60), "palm1": ("h", 60), "palm_empty": ("h", 60),
    "mushrooms": ("h", 8), "spice_full": ("h", 13), "spice_empty": ("h", 13), "ore_rock": ("h", 16),
    "gold_rock": ("h", 16), "den": ("h", 14), "wallow": ("h", 9), "cave": ("h", 34), "carcass": ("h", 9),
    # Tiere (Höhe des Laufbildes): Wolf und Eber gut halb so hoch wie die Figur, Bär zwei Drittel
    "wolf": ("h", 12), "eber": ("h", 11), "baer": ("h", 16), "pirat": ("h", 21),
    # Schiffe nach Länge (Spielzeug-Maßstab)
    "boat": ("w", 28), "ship_kogge": ("w", 52), "ship_fast": ("w", 46), "ship_galleon": ("w", 64),
}
# Gebäude, deren Grundfläche bleibt (stehen auf Felsen im Wasser)
KEEP_SIZE = {"lighthouse", "tower", "monument"}


def scale_for(name, sheet, img):
    """Spielpixel je Bogenpixel."""
    if name in FIXED:
        kind, v = FIXED[name]
        return v / (img.height if kind == "h" else img.width)
    door = DOORS.get(name, SHEET_DOOR.get(sheet))
    if door is None:
        return None
    return DOOR / door


def new_footprint(name, old, w_game):
    """Grundfläche (Felder) für ein Bild w_game Spielpixel breit: die Mauern sind etwa 70 %
    der Bildbreite (Rest Sockel mit Gras), höchstens 2 Felder mehr als bisher."""
    if name in KEEP_SIZE or old[0] == 1:
        return list(old)
    w = max(old[0], min(old[0] + 2, round(w_game * 0.70 / 16)))
    h = old[1] + (1 if w - old[0] >= 2 else 0)
    return [w, h]


def sizes():
    """name -> dict(old=(w,h), new=(w,h), fp_old, fp_new) in Spielpixeln, für alle Gebäude."""
    fp = build.footprints()
    out = {}
    for name, spec in build.BUILDINGS.items():
        img = build.building_img(name)
        w, h = build.box_for(fp.get(name, [2, 2]))
        if name in build.BOX:
            w, h = build.BOX[name]
        f_old = min(w / img.width, h / img.height, 1.0 / build.S * 4)
        s = scale_for(name, spec[0], img)
        new = (img.width * s, img.height * s)
        out[name] = {"img": img, "old": (img.width * f_old, img.height * f_old), "new": new,
                     "fp_old": fp.get(name, [2, 2]), "fp_new": new_footprint(name, fp.get(name, [2, 2]), new[0])}
    return out


def board(path, items, title, cols=4, k=3):
    """Vergleichstafel: je Bild links die Figur, daneben das Bild bisher und neu (Faktor k)."""
    fig = build.grab(build.B1, (48, 145, 172, 340), keep=0.03, feet=True)
    fig = fig.resize((max(1, round(fig.width * FIG / fig.height * k)), round(FIG * k)), Image.LANCZOS)
    cells = []
    for name, d in items:
        ow, oh = d["old"]
        nw, nh = d["new"]
        old = d["img"].resize((max(1, round(ow * k)), max(1, round(oh * k))), Image.LANCZOS)
        new = d["img"].resize((max(1, round(nw * k)), max(1, round(nh * k))), Image.LANCZOS)
        cells.append((name, d, old, new))
    pad = 12
    cw = max(fig.width * 2 + o.width + n.width + pad * 5 for _, _, o, n in cells)
    ch = max(max(o.height, n.height, fig.height) for _, _, o, n in cells) + 44
    rows = math.ceil(len(cells) / cols)
    W = min(cols, len(cells)) * cw
    im = Image.new("RGBA", (W, rows * ch + 40), (236, 230, 214, 255))
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
        big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20)
    except OSError:
        font = big = ImageFont.load_default()
    d.text((10, 8), title, fill=(60, 40, 30), font=big)
    for i, (name, dd, old, new) in enumerate(cells):
        x0 = (i % cols) * cw
        y0 = 40 + (i // cols) * ch
        base = y0 + ch - 30
        d.rectangle((x0 + 2, y0 + 2, x0 + cw - 2, y0 + ch - 2), outline=(200, 190, 170))
        x = x0 + pad
        for img, label in ((old, "bisher"), (new, "neu")):
            im.alpha_composite(fig, (x, base - fig.height))
            x += fig.width + 2
            im.alpha_composite(img, (x, base - img.height))
            d.text((x, base + 4), label, fill=(110, 90, 70), font=font)
            x += img.width + pad * 2
        fo, fn = dd["fp_old"], dd["fp_new"]
        txt = "%s  %dx%d → %dx%d Felder" % (name, fo[0], fo[1], fn[0], fn[1]) if fo != fn else "%s  %dx%d Felder" % (name, fo[0], fo[1])
        d.text((x0 + pad, y0 + 6), txt, fill=(60, 40, 30), font=font)
    im.save(path)
    print("  ", path, im.size)


GROUPS = [
    ("Wohnen und Lager", ["hut", "house_wood", "house_stone", "tenement", "apartment", "storehouse", "store_big", "school"]),
    ("Nahrung", ["mill", "bakery", "smokehouse", "henhouse", "pigsty", "cowshed", "cannery", "greenhouse", "lodge"]),
    ("Handwerk", ["sawpit", "claypit", "brickworks", "quarry", "charcoal", "mine", "smelter", "smithy", "armory",
                  "glassworks", "papermill", "printshop"]),
    ("Wissen und Zukunft", ["scriptorium", "scriptorium2", "scriptorium3", "scriptorium4", "library", "tablets",
                            "office", "radio", "automaton", "plan_automaton", "university", "lab", "ai_center",
                            "future_city"]),
    ("Seefahrt", ["shipyard", "shipyard2", "shipyard3", "jetty", "harbor", "harbor_big", "quay_wood", "quay_ore",
                  "quay_food", "tower", "lighthouse", "monument"]),
    ("Schmuck", ["flowerbed_red", "bench", "menhir", "flagpole", "statue_stone", "flower_tub", "fountain", "pond",
                 "park", "rose_arch", "sundial", "lantern", "pavilion", "equestrian", "obelisk", "statue_bronze",
                 "street_lamp", "hologram"]),
]


def nature_items():
    out = []
    for name, (sh, rect, w) in build.NATURE.items():
        img = build.grab(sh, rect, keep=0.03)
        cell = build.OBJ1.get(name) or build.OBJ2.get(name)
        f_old = min(w * build.S / img.width, (cell[3] - 1) * build.S / img.height) / build.S
        s = scale_for(name, sh, img)
        out.append((name, {"img": img, "old": (img.width * f_old, img.height * f_old),
                           "new": (img.width * s, img.height * s), "fp_old": [1, 1], "fp_new": [1, 1]}))
    for row, rects in build.ANIMAL_ROWS:
        name = ["wolf", "eber", "baer", "pirat"][row]
        img = build.grab("tiere_piraten", rects[0], keep=0.05, feet=True)
        if row == 3:
            f_old = build.FIG_H * 1.05 / img.height
        else:
            f_old = {0: 20.0, 1: 19.0, 2: 23.0}[row] / img.width
        s = scale_for(name, "", img)
        out.append((name, {"img": img, "old": (img.width * f_old, img.height * f_old),
                           "new": (img.width * s, img.height * s), "fp_old": [1, 1], "fp_new": [1, 1]}))
    return out


def main():
    os.makedirs(build.PREVIEW, exist_ok=True)
    sz = sizes()
    for i, (title, names) in enumerate(GROUPS):
        board(os.path.join(build.PREVIEW, "groesse_%d.png" % (i + 1)), [(n, sz[n]) for n in names if n in sz],
              title + ": Figur und Bild, links bisher, rechts neu", cols=3 if i != 5 else 5)
    board(os.path.join(build.PREVIEW, "groesse_7.png"), nature_items(),
          "Natur und Tiere: Figur und Bild, links bisher, rechts neu", cols=6)
    table = {n: {"neu_px": [round(d["new"][0]), round(d["new"][1])], "felder": d["fp_new"]} for n, d in sz.items()}
    json.dump(table, open(os.path.join(build.PREVIEW, "groessen.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
