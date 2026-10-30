"""Feine Bilder von josh (2026-10-30, „Bilder fein aktuelle Fassung“): alle Gebäude, Deko, Natur, Tiere,
Symbole und Zubehör in 136 Bildpunkten je Feld (8,5 je Spielpixel) statt 64.
Quelle tools/art_v2/src/fein:
  Gebaeude_und_Schmuck/<name>.png      -> assets/sprites_hd/big/<name>.png (Bilder nebeneinander), big/index.json
  Natur_Tiere_Symbole_und_Zubehoer/... -> assets/sprites_hd/fine/<bogen>.png, Bögen wie die alten
                                          (objects, objects2, animals, cart, icons, ui, menu_icons,
                                          seasons, settler_droid, terrain_deco) in 8,5-facher Größe.
Was josh nicht geliefert hat (Schatten, Werkzeuge ...), kommt vergrößert aus dem alten vierfachen Bogen.
Die Stücke heißen wie die Regionen in scripts/autoload/data.gd (Bilder je Bewegung _0, _1 ...)."""
import json
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
SRC = os.path.join(HERE, "src", "fein")
HD = os.path.join(ROOT, "assets", "sprites_hd")
F = 8.5  # Bildpunkte je Spielpixel (136 je Feld)

# Regionen in Spielpixeln wie in scripts/autoload/data.gd: name -> (bogen, x, y, w, h)
OBJ = {
    "tree0": (0, 0, 32, 48), "tree1": (32, 0, 32, 48), "tree2": (64, 0, 32, 48), "stump": (96, 0, 32, 48),
    "sapling": (128, 0, 32, 48), "pine": (160, 0, 32, 48), "construction": (96, 48, 48, 48),
    "rock_big": (0, 96, 16, 16), "rock_small": (16, 96, 16, 16), "bush_full": (32, 96, 16, 16),
    "bush_empty": (48, 96, 16, 16), "grave": (64, 96, 16, 16),
}
OBJ.update({"campfire_%d" % i: (16 * i, 112, 16, 16) for i in range(4)})
OBJ.update({"fish_anim_%d" % i: (64 + 16 * i, 112, 16, 16) for i in range(4)})
OBJ.update({"field%d" % i: (16 * i, 128, 16, 16) for i in range(4)})
OBJ.update({"orchard%d" % i: (64 + 16 * i, 128, 16, 16) for i in range(4)})
OBJ2 = {
    "palm0": (0, 0, 32, 48), "palm1": (32, 0, 32, 48), "palm_empty": (64, 0, 32, 48), "cave": (96, 0, 32, 48),
    "mushrooms": (0, 48, 16, 16), "ore_rock": (16, 48, 16, 16), "gold_rock": (32, 48, 16, 16),
    "den": (48, 48, 16, 16), "wallow": (64, 48, 16, 16), "carcass": (80, 48, 16, 16), "arrow": (96, 48, 16, 16),
    "spice_full": (112, 48, 16, 16), "spice_empty": (128, 48, 16, 16),
}
OBJ2.update({"boat_%d" % i: (32 * i, 64, 32, 32) for i in range(2)})
for k, x in (("ship_kogge", 0), ("ship_fast", 96), ("ship_galleon", 192)):
    OBJ2.update({"%s_%d" % (k, i): (x + 48 * i, 96, 48, 48) for i in range(2)})
ANIM = {}
for k, row in (("wolf", 0), ("boar", 1), ("bear", 2), ("pirate", 3)):
    ANIM.update({"%s_%d" % (k, i): (24 * i, 24 * row, 24, 24) for i in range(5)})
CART = {"cart_%d_%d" % (r, c): (24 * c, 24 * r, 24, 24) for r in range(6) for c in range(4)}
DROID = {"droid_%d_%d" % (r, c): (16 * c, 24 * r, 16, 24) for r in range(3) for c in range(4)}
UI = {"ui_%d" % i: (24 * i, 0, 24, 24) for i in range(4)}
MENU = {"menu_%d" % i: (20 * i, 0, 20, 20) for i in range(6)}
# Jahreszeit-Symbol: 16 x 16 oben (Seasons.icon), Teilchen 8 x 8: Schnee (64,16), Laub (72,16)
SEASONS = {"season_tree_%d" % i: (16 * i, 0, 16, 16) for i in range(4)}
SEASONS.update({"snowflake": (64, 16, 8, 8), "fall_leaf": (72, 16, 8, 8)})
DECO = {"grass_deco_%d" % i: (16 * i, 0, 16, 16) for i in range(16)}
# Nach dem Export am selben Tag auf joshs Wunsch neu gemacht, die Zip-Fassung ist älter: bleiben wie sie sind
# (sehr schnell = drei Pfeile, Inseln = Segelschiff, Verwalter = Figur mit Klemmbrett)
KEEP = {"icon_sehr_schnell", "menu_3", "menu_5"}
# Beim Zuschneiden mitgerutschte Reste (Bildpunkt-Spalten links davon werden durchsichtig): Stab neben dem Kolben
TRIM_LEFT = {"menu_1": 60}
SHEETS = {"objects": OBJ, "objects2": OBJ2, "animals": ANIM, "cart": CART, "settler_droid": DROID,
          "ui": UI, "menu_icons": MENU, "seasons": SEASONS, "terrain_deco": DECO}


def icon_regions():
    names = [l.strip() for l in open(os.path.join(ROOT, "assets", "sprites", "icons.txt")) if l.strip()]
    return {"icon_" + n: (16 * i, 0, 16, 16) for i, n in enumerate(names)}


SHEETS["icons"] = icon_regions()


def build_sheet(name, regions, src, report):
    old_img = Image.open(os.path.join(HD, name + ".png")).convert("RGBA")
    gw, gh = old_img.width // 4, old_img.height // 4
    W, H = int(gw * F), int(gh * F)
    out = old_img.resize((W, H), Image.LANCZOS)  # Ersatz für alles, was nicht geliefert wurde
    used = 0
    for pn, (x, y, w, h) in regions.items():
        p = os.path.join(src, pn + ".png")
        if not os.path.exists(p) or pn in KEEP:
            continue
        piece = Image.open(p).convert("RGBA")
        if pn in TRIM_LEFT:
            piece.paste((0, 0, 0, 0), (0, 0, TRIM_LEFT[pn], piece.height))
        X, Y = int(round(x * F)), int(round(y * F))
        out.paste((0, 0, 0, 0), (X, Y, X + int(w * F), Y + int(h * F)))
        if piece.size != (int(w * F), int(h * F)):
            # passend verkleinern, Seitenverhältnis bleibt, unten mittig
            k = min(w * F / piece.width, h * F / piece.height)
            piece = piece.resize((round(piece.width * k), round(piece.height * k)), Image.LANCZOS)
            X += (int(w * F) - piece.width) // 2
            Y += int(h * F) - piece.height
            report.append("%s/%s: auf %d x %d Spielpixel eingepasst" % (name, pn, w, h))
        out.alpha_composite(piece, (X, Y))
        used += 1
    os.makedirs(os.path.join(HD, "fine"), exist_ok=True)
    out.save(os.path.join(HD, "fine", name + ".png"), optimize=True)
    return used


def build_big(report):
    ip = os.path.join(HD, "big", "index.json")
    index = json.load(open(ip))
    src = os.path.join(SRC, "Gebaeude_und_Schmuck")
    n = 0
    for f in sorted(os.listdir(src)):
        if not f.endswith(".png"):
            continue
        name = f[:-4]
        img = Image.open(os.path.join(src, f)).convert("RGBA")
        frames = int(index.get(name, [1])[0])
        w = round(img.width / frames / F)
        h = round(img.height / F)
        if name not in index:
            report.append("big/%s: neu (%d x %d Spielpixel)" % (name, w, h))
        elif [w, h] != index[name][1:]:
            report.append("big/%s: Größe %s -> %s" % (name, index[name][1:], [w, h]))
        index[name] = [frames, w, h]
        img.save(os.path.join(HD, "big", f), optimize=True)
        n += 1
    json.dump(index, open(ip, "w"), indent=0, sort_keys=True)
    return n


def main():
    report = []
    print("big", build_big(report))
    src = os.path.join(SRC, "Natur_Tiere_Symbole_und_Zubehoer")
    known = set()
    for name, regions in SHEETS.items():
        known.update(regions)
        print(name, build_sheet(name, regions, src, report))
    rest = [f[:-4] for f in os.listdir(src) if f.endswith(".png") and f[:-4] not in known]
    if rest:
        report.append("nicht zugeordnet: " + ", ".join(sorted(rest)))
    print("\n".join(report))


if __name__ == "__main__":
    main()
