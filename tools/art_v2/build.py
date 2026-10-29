"""Version 2.0.0 (josh 2026-10-24): baut assets/sprites_hd aus joshs Bildbögen (tools/art_v2/src).

Die Bögen werden nicht neu gezeichnet: jedes Bild wird freigestellt (cut.py), auf die Zellgröße
des Spiels in vierfacher Auflösung verkleinert und an die Stelle des alten Bildes im Atlas gesetzt.
Alles, wofür es noch kein neues Bild gibt, bleibt das alte Bild, nur vierfach vergrößert.
Data.hd() lädt die Atlanten und meldet Godot die alte Größe, so passen alle Regionen im Code.

Bewegungen: Laufen der Figuren (Beine), Lagerfeuer, Fahne, Springbrunnen, Hologramm, Fischgrund,
Schiffe, Leuchtturm und das Wasser entstehen hier aus den Bildern der Bögen.

Aufruf: python3 tools/art_v2/build.py   (braucht Pillow, numpy, scipy)
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cut  # noqa: E402

S = 4  # HD-Faktor
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OLD = os.path.join(ROOT, "assets", "sprites")
OUT = os.path.join(ROOT, "assets", "sprites_hd")
PREVIEW = os.path.join(ROOT, "tools", "preview", "v2")

_sheets = {}


def sheet(name):
    if name not in _sheets:
        _sheets[name] = cut.load(name)
    return _sheets[name]


# ------------------------------------------------------------------ Ausschneiden
def grab(name, rect, keep=0.05, feet=False, tol=34.0, fill=None):
    """Bild im Rechteck rect = (x0, y0, x1, y1) freistellen. keep: kleinere Teile als dieser
    Anteil am größten Teil fallen weg (Beschriftungen, Krümel). feet: Bodenschatten unter
    den Füßen abschneiden. fill: Rechtecke (x0, y0, x1, y1, dx) im Bogen, die vorher mit dem um
    dx verschobenen Ausschnitt überdeckt werden (eine fremde Figur vor einem Gebäude)."""
    img = sheet(name)
    a = np.asarray(img).copy()
    for f in fill or []:
        x0, y0, x1, y1, src_x = f
        a[y0:y1, x0:x1] = a[y0:y1, src_x:src_x + (x1 - x0)][:, ::-1]
    x0, y0, x1, y1 = rect
    sub = a[y0:y1, x0:x1]
    # Rand des Ausschnitts als Papier behandeln: Flutfüllung von den Kanten
    pad = np.pad(sub, ((3, 3), (3, 3), (0, 0)), mode="edge")
    bg = cut.bg_color(a)
    pad[:3, :] = bg
    pad[-3:, :] = bg
    pad[:, :3] = bg
    pad[:, -3:] = bg
    paper = cut.paper_mask(pad, tol=tol)[3:-3, 3:-3]
    alpha = ~paper
    alpha = ndimage.binary_opening(alpha, iterations=1)
    lab, n = ndimage.label(ndimage.binary_dilation(alpha, iterations=2))
    if n > 1:
        sizes = ndimage.sum(alpha, lab, range(1, n + 1))
        ok = [i + 1 for i, s in enumerate(sizes) if s >= sizes.max() * keep]
        alpha &= np.isin(lab, ok)
    alpha = _drop_labels(sub, alpha)
    if feet:
        alpha = _cut_feet_shadow(sub, alpha)
    rgba = np.dstack([sub, np.where(alpha, 255, 0).astype(np.uint8)])
    out = Image.fromarray(rgba, "RGBA")
    bb = out.getbbox()
    return out.crop(bb)


def _drop_labels(rgb, alpha):
    """Beschriftungen (dunkle, flache Schrift) fallen weg; ein einzelnes Bild bleibt immer."""
    lab, n = ndimage.label(ndimage.binary_dilation(alpha, iterations=3))
    if n <= 1:
        return alpha
    lum = rgb.astype(np.float32) @ np.array([0.3, 0.59, 0.11])
    sizes = ndimage.sum(alpha, lab, range(1, n + 1))
    big = int(np.argmax(sizes)) + 1
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if i + 1 == big:
            continue
        m = (lab[sl] == i + 1) & alpha[sl]
        hgt = sl[0].stop - sl[0].start
        if m.sum() and hgt < 56 and (lum[sl][m] < 90).mean() > 0.45:
            alpha[sl] &= ~m
    return alpha


def _cut_feet_shadow(rgb, alpha):
    """Unter Figuren liegt ein heller Schatten; er endet unter der letzten dunklen Zeile (Schuhe)."""
    lum = rgb.astype(np.float32) @ np.array([0.3, 0.59, 0.11])
    dark = (lum < 90) & alpha
    rows = np.where(dark.sum(axis=1) >= 3)[0]
    if len(rows) == 0:
        return alpha
    last = rows.max()
    alpha = alpha.copy()
    alpha[last + 1:] = False
    # Papier zwischen den Beinen: helle, kaum farbige Pixel, die von unten erreichbar sind
    mx = rgb.max(axis=2).astype(int)
    mn = rgb.min(axis=2).astype(int)
    paperish = (mn > 205) & (mx - mn < 30)
    lab, _ = ndimage.label(paperish & alpha)
    bottom = set(np.unique(lab[max(0, last - 2):last + 1])) - {0}
    if bottom:
        alpha &= ~np.isin(lab, list(bottom))
    # Papier zwischen den Beinen: fast weiße, eingeschlossene kleine Flächen im unteren Drittel
    h = last + 1
    white = (mn > 243) & alpha
    white[: int(h * 0.62)] = False
    lab, n = ndimage.label(white)
    if n:
        sizes = ndimage.sum(white, lab, range(1, n + 1))
        small = [i + 1 for i, s in enumerate(sizes) if s < alpha.sum() * 0.02]
        alpha &= ~np.isin(lab, small)
    # beiger Bodenschatten seitlich der Schuhe (unteres Viertel, außerhalb der dunklen Schuhe)
    r, g, b = (rgb[:, :, i].astype(int) for i in range(3))
    shadow = (lum > 175) & (r - b > 20) & (r - b < 80) & (g >= b) & (g <= r)
    boots = dark[max(0, last - 12):last + 1]
    bx = np.where(boots.any(axis=0))[0]
    if len(bx):
        out_x = np.ones(alpha.shape[1], bool)
        out_x[bx.min():bx.max() + 1] = False
        zone = np.zeros_like(alpha)
        zone[int(h * 0.75):h] = True
        alpha &= ~(shadow & zone & out_x[None, :])
    return alpha


# ------------------------------------------------------------------ Verkleinern
def scale(img, factor):
    w = max(1, round(img.width * factor))
    h = max(1, round(img.height * factor))
    return resize(img, w, h)


def resize(img, w, h):
    """Verkleinern mit vormultipliziertem Alpha, danach harte Kanten (Pixel-Look)."""
    pm = img.convert("RGBa").resize((w, h), Image.LANCZOS, reducing_gap=3.0).convert("RGBA")
    a = np.asarray(pm).copy()
    a[:, :, 3] = np.where(a[:, :, 3] >= 110, 255, 0)
    out = Image.fromarray(a, "RGBA")
    return out


def fit(img, w, h, upscale=False):
    """In ein Feld w x h (HD-Pixel) einpassen, Seitenverhältnis bleibt."""
    f = min(w / img.width, h / img.height)
    if not upscale:
        f = min(f, 1.0)
    return scale(img, f)


# ------------------------------------------------------------------ Atlanten
def old_hd(name):
    im = Image.open(os.path.join(OLD, name + ".png")).convert("RGBA")
    return im.resize((im.width * S, im.height * S), Image.NEAREST)


def clear(atlas, x, y, w, h):
    atlas.paste(Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0)), (x * S, y * S))


def put(atlas, img, x, y, w, h, bottom=4, align="bottom"):
    """Bild in die Zelle (x, y, w, h) (Spielpixel) setzen: unten mittig, Boden `bottom` Pixel
    über dem Zellrand; align="center" setzt es in die Mitte."""
    clear(atlas, x, y, w, h)
    cw, ch = w * S, h * S
    if img.width > cw or img.height > ch:
        img = fit(img, cw, ch)
    px = x * S + (cw - img.width) // 2
    if align == "center":
        py = y * S + (ch - img.height) // 2
    else:
        py = y * S + ch - bottom * S - img.height
        py = max(y * S, py)
    atlas.alpha_composite(img, (px, py))


def save(atlas, name):
    os.makedirs(OUT, exist_ok=True)
    atlas.save(os.path.join(OUT, name + ".png"), optimize=True)
    print("  ", name, atlas.size)


# ------------------------------------------------------------------ Gebäude
# Bogen, Rechteck (ohne Beschriftung) -> Bildname (Data.BUILDING_CELLS oder objects.png)
BUILDINGS = {
    # Wohnen und Schule
    "hut": ("gebaeude_wohnen_1", (48, 140, 492, 450)),
    "house_wood": ("gebaeude_wohnen_1", (542, 100, 994, 450)),
    "house_stone": ("gebaeude_wohnen_1", (1048, 100, 1501, 450)),
    "school": ("gebaeude_wohnen_1", (17, 530, 510, 932)),
    "tenement": ("gebaeude_wohnen_1", (541, 530, 994, 932)),
    "apartment": ("gebaeude_wohnen_1", (1028, 530, 1520, 932)),
    # Handwerk und Industrie
    "sawpit": ("gebaeude_handwerk_1", (21, 128, 378, 362)),
    "claypit": ("gebaeude_handwerk_1", (399, 128, 751, 362)),
    "brickworks": ("gebaeude_handwerk_1", (771, 128, 1142, 362)),
    "quarry": ("gebaeude_handwerk_1", (1160, 128, 1525, 362)),
    "charcoal": ("gebaeude_handwerk_1", (21, 425, 378, 665)),
    "mine": ("gebaeude_handwerk_1", (399, 430, 752, 665)),
    "smelter": ("gebaeude_handwerk_1", (771, 385, 1141, 665)),
    "smithy": ("gebaeude_handwerk_1", (1160, 428, 1513, 665)),
    "armory": ("gebaeude_handwerk_1", (21, 730, 378, 985)),
    "glassworks": ("gebaeude_handwerk_1", (394, 728, 752, 985)),
    "papermill": ("gebaeude_handwerk_1", (771, 740, 1145, 988)),
    "printshop": ("gebaeude_handwerk_1", (1162, 728, 1520, 985)),
    # Lager (die Figur neben den Lagern wird mit dem gespiegelten Bild links daneben überdeckt)
    "storehouse": ("gebaeude_lager_1", (417, 310, 972, 724), [(868, 540, 972, 700, 428)]),
    "store_big": ("gebaeude_lager_1", (990, 195, 1755, 724), [(1452, 540, 1540, 700, 1170)]),
    # Nahrung
    "mill": ("gebaeude_nahrung_1", (764, 55, 1070, 342)),
    "bakery": ("gebaeude_nahrung_1", (1092, 50, 1520, 342)),
    "smokehouse": ("gebaeude_nahrung_1", (16, 380, 354, 680)),
    "henhouse": ("gebaeude_nahrung_1", (373, 415, 743, 680)),
    "pigsty": ("gebaeude_nahrung_1", (764, 440, 1110, 680)),
    "cowshed": ("gebaeude_nahrung_1", (1130, 420, 1520, 680)),
    "cannery": ("gebaeude_nahrung_1", (22, 640, 541, 952)),
    "greenhouse": ("gebaeude_nahrung_1", (578, 710, 1022, 952)),
    "lodge": ("gebaeude_nahrung_1", (1062, 685, 1512, 952)),
    # Seefahrt und Schutz
    "shipyard": ("gebaeude_see_1", (30, 125, 366, 360)),
    "shipyard2": ("gebaeude_see_1", (395, 110, 750, 360)),
    "shipyard3": ("gebaeude_see_1", (780, 62, 1178, 360)),
    "jetty": ("gebaeude_see_1", (1225, 205, 1500, 360)),
    "harbor": ("gebaeude_see_1", (25, 430, 360, 655)),
    "harbor_big": ("gebaeude_see_1", (385, 405, 783, 655)),
    "quay_wood": ("gebaeude_see_1", (800, 450, 1142, 655)),
    "quay_ore": ("gebaeude_see_1", (1162, 440, 1515, 655)),
    "quay_food": ("gebaeude_see_1", (28, 730, 434, 962)),
    "tower": ("gebaeude_see_1", (505, 695, 730, 968)),
    "lighthouse": ("gebaeude_see_1", (818, 680, 1120, 978)),
    "monument": ("gebaeude_see_1", (1205, 705, 1480, 978)),
    # Wissen, Verwaltung, Zukunft
    "scriptorium": ("gebaeude_wissen_1", (30, 110, 362, 352)),
    "scriptorium2": ("gebaeude_wissen_1", (390, 105, 755, 352)),
    "scriptorium3": ("gebaeude_wissen_1", (778, 100, 1112, 352)),
    "scriptorium4": ("gebaeude_wissen_1", (1132, 38, 1515, 352)),
    "library": ("gebaeude_wissen_1", (32, 400, 415, 645)),
    "tablets": ("gebaeude_wissen_1", (452, 418, 740, 648)),
    "office": ("gebaeude_wissen_1", (800, 418, 1096, 648)),
    "radio": ("gebaeude_wissen_1", (1158, 392, 1480, 648)),
    "automaton": ("gebaeude_wissen_1", (18, 725, 394, 962)),
    "plan_automaton": ("gebaeude_wissen_1", (425, 770, 652, 962)),
    "university": ("gebaeude_wissen_1", (670, 682, 1100, 962)),
    "lab": ("gebaeude_wissen_1", (1117, 688, 1522, 962)),
    "ai_center": ("gebaeude_wissen_2", (20, 235, 748, 820)),
    "future_city": ("gebaeude_wissen_2", (780, 200, 1520, 815)),
    # Schmuck und Parks
    "flowerbed_red": ("gebaeude_schmuck_1", (415, 108, 715, 284)),
    "flowerbed_yellow": ("gebaeude_schmuck_1", (808, 108, 1100, 280)),
    "bench": ("gebaeude_schmuck_1", (42, 435, 345, 612)),
    "menhir": ("gebaeude_schmuck_1", (445, 382, 690, 616)),
    "flagpole": ("gebaeude_schmuck_1", (772, 342, 1132, 621)),
    "statue_stone": ("gebaeude_schmuck_1", (1218, 378, 1458, 653)),
    "flower_tub": ("gebaeude_schmuck_1", (64, 715, 328, 928)),
    "fountain": ("gebaeude_schmuck_1", (770, 666, 1132, 932)),
    "flowerbed_blue": ("gebaeude_schmuck_1", (1192, 723, 1491, 928)),
    "pond": ("gebaeude_schmuck_2", (44, 135, 356, 375)),
    "park": ("gebaeude_schmuck_2", (408, 58, 825, 380)),
    "rose_arch": ("gebaeude_schmuck_2", (880, 128, 1130, 380)),
    "sundial": ("gebaeude_schmuck_2", (1258, 160, 1472, 376)),
    "lantern": ("gebaeude_schmuck_2", (104, 480, 263, 714)),
    "pavilion": ("gebaeude_schmuck_2", (396, 390, 732, 715)),
    "equestrian": ("gebaeude_schmuck_2", (838, 393, 1134, 715)),
    "obelisk": ("gebaeude_schmuck_2", (1260, 393, 1493, 715)),
    "statue_bronze": ("gebaeude_schmuck_2", (256, 720, 453, 1003)),
    "street_lamp": ("gebaeude_schmuck_2", (684, 688, 844, 972)),
    "hologram": ("gebaeude_schmuck_2", (1066, 734, 1294, 976)),
}
# Eigene Größe (Spielpixel), wo die Grundfläche täuscht: der Wachturm ist schmal, aber hoch
BOX = {"tower": (24, 60)}
# Neue Zellen in buildings.png für Bilder, die es vorher nicht gab
NEW_CELLS = {"shipyard2": 92, "shipyard3": 93}


def building_cells():
    """Data.BUILDING_CELLS aus data.gd lesen (Name -> [Zelle, Frames])."""
    src = open(os.path.join(ROOT, "scripts", "autoload", "data.gd"), encoding="utf-8").read()
    start = src.index("const BUILDING_CELLS")
    body = src[start:src.index("\n}", start)]
    cells = {}
    import re
    for m in re.finditer(r'"([a-z_0-9]+)": \[(\d+), (\d+)\]', body):
        cells[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return cells


def footprints():
    """Bildname -> Grundfläche [w, h] in Feldern (aus buildings.json)."""
    b = json.load(open(os.path.join(ROOT, "data", "buildings.json"), encoding="utf-8"))
    fp = {}
    for k, v in b.items():
        if isinstance(v, dict) and "sprite" in v:
            fp.setdefault(v["sprite"], v.get("size", [2, 2]))
    fp.setdefault("shipyard2", [3, 2])
    fp.setdefault("shipyard3", [3, 2])
    return fp


def building_img(name):
    spec = BUILDINGS[name]
    fill = spec[2] if len(spec) > 2 else None
    return grab(spec[0], spec[1], keep=0.02, fill=fill)


def box_for(fp, cell_w=64, cell_h=60):
    """Größe (Spielpixel), in die ein Gebäude mit Grundfläche fp passt."""
    w = min(cell_w, fp[0] * 16 * 1.12 + 4)
    if fp[0] == 1:
        w = 20
    return w, cell_h


def gen_buildings():
    atlas = old_hd("buildings")
    # Platz für neue Zellen (Zeilen 11 und 12 gibt es schon: 512x768 = 96 Zellen)
    cells = building_cells()
    cells.update({k: (v, 1) for k, v in NEW_CELLS.items()})
    fp = footprints()
    for name, (cell, frames) in cells.items():
        if name not in BUILDINGS:
            continue
        img = building_img(name)
        w, h = box_for(fp.get(name, [2, 2]))
        if name in BOX:
            w, h = BOX[name]
        img = fit(img, int(w * S), int(h * S))
        anim = ANIMS.get(name)
        for f in range(frames):
            fr = anim(img, f, frames) if anim else img
            x, y = ((cell + f) % 8) * 64, ((cell + f) // 8) * 64
            put(atlas, fr, x, y, 64, 64, bottom=4)
    # Bäume der Parkanlage: das neue Parkbild hat seine Bäume schon, die Extra-Bäume bleiben leer
    c = cells["park_tree"][0]
    clear(atlas, (c % 8) * 64, (c // 8) * 64, 64, 64)
    save(atlas, "buildings")
    gen_big()
    return cells


BIG_PAD = 3  # Spielpixel unter dem Bild: Building setzt Bilder 4 Pixel unter den Fuß (Sockel ragt 1 Pixel vor)


def _cut_caption(img):
    """Beschriftung unter dem Bild (josh 2026-10-28: Ställe zeigten "kuhstall"): unterster Streifen,
    durch leere Zeilen vom Bild getrennt, niedrig und überwiegend dunkel -> weg."""
    a = np.asarray(img)
    rows = (a[:, :, 3] > 0).any(axis=1)
    h = len(rows)
    y = h - 1
    while y >= 0 and not rows[y]:
        y -= 1
    bottom = y
    while y >= 0 and rows[y]:
        y -= 1
    top = y + 1
    if y < 0 or bottom - top + 1 > 0.14 * h:
        return img
    band = a[top:bottom + 1]
    m = band[:, :, 3] > 0
    lum = band[:, :, :3].astype(np.float32) @ np.array([0.3, 0.59, 0.11])
    if (lum[m] < 90).mean() < 0.4:
        return img
    return img.crop((0, 0, img.width, top)).crop(img.crop((0, 0, img.width, top)).getbbox())


def gen_big():
    """Größenverhältnisse (josh 2026-10-24, Weg B, 30 % kleiner): jedes Gebäude als eigene Datei
    assets/sprites_hd/big/<name>.png in seiner gemessenen Größe (scale.py), Bilder nebeneinander.
    big/index.json: Name -> [Bilder, Breite, Höhe] je Bild in Spielpixeln (Data.BIG)."""
    import scale as sc
    out_dir = os.path.join(OUT, "big")
    os.makedirs(out_dir, exist_ok=True)
    cells = building_cells()
    index = {}
    for name, spec in BUILDINGS.items():
        img = _cut_caption(building_img(name))
        f = sc.scale_for(name, spec[0], img)
        img = scale(img, f * S)
        frames = cells.get(name, (0, 1))[1]
        if name in ("hut", "storehouse"):
            frames = 1
        w = -(-img.width // S)
        h = -(-img.height // S) + BIG_PAD
        sheet_img = Image.new("RGBA", (w * S * frames, h * S), (0, 0, 0, 0))
        anim = ANIMS.get(name)
        for fr in range(frames):
            im = anim(img, fr, frames) if anim else img
            sheet_img.alpha_composite(im, (fr * w * S + (w * S - im.width) // 2, (h - BIG_PAD) * S - im.height))
        sheet_img.save(os.path.join(out_dir, name + ".png"), optimize=True)
        index[name] = [frames, w, h]
    json.dump(index, open(os.path.join(out_dir, "index.json"), "w"), indent=0, sort_keys=True)
    print("   big", len(index))
    gen_single()


# Einzelbilder von josh (2026-10-29) im Maßstab der feinen Siedler-Bögen: Kästchen 256 = 30 Spielpixel.
SINGLE = {"bench": "bank.png", "pavilion": "pavillon.png"}
SINGLE_SCALE = 30 / 256


def gen_single():
    """Ersetzt einzelne Bilder in assets/sprites_hd/big durch joshs eigene Dateien (tools/art_v2/src/einzeln)."""
    out_dir = os.path.join(OUT, "big")
    ip = os.path.join(out_dir, "index.json")
    index = json.load(open(ip))
    for name, f in SINGLE.items():
        img = Image.open(os.path.join(ROOT, "tools", "art_v2", "src", "einzeln", f)).convert("RGBA")
        img = img.crop(img.getbbox())
        img = scale(img, SINGLE_SCALE * S)
        w = -(-img.width // S)
        h = -(-img.height // S) + BIG_PAD
        sheet_img = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
        sheet_img.alpha_composite(img, ((w * S - img.width) // 2, (h - BIG_PAD) * S - img.height))
        sheet_img.save(os.path.join(out_dir, name + ".png"), optimize=True)
        index[name] = [1, w, h]
    json.dump(index, open(ip, "w"), indent=0, sort_keys=True)
    print("   einzeln", list(SINGLE))


# ------------------------------------------------------------------ Bewegungen (Bilder je Frame)
def _arr(img):
    return np.asarray(img).astype(np.int16).copy()


def anim_flag(img, f, n):
    """Fahne weht: der blaue Stoff rechts vom Mast wird wellenförmig verschoben."""
    a = _arr(img)
    h, w = a.shape[:2]
    out = a.copy()
    cloth = (a[:, :, 2] > a[:, :, 0] + 30) | ((a[:, :, 0] > 200) & (a[:, :, 1] > 160) & (a[:, :, 2] < 120))
    xs = np.where(cloth.any(axis=0))[0]
    if len(xs) == 0:
        return img
    x0 = xs.min()
    for x in range(x0, w):
        d = int(round(math.sin((x - x0) / 9.0 - f * math.pi / 2) * 2.0 * (x - x0) / max(1, w - x0)))
        col = a[:, x].copy()
        m = cloth[:, x]
        out[:, x][m] = 0
        shifted = np.roll(col, d, axis=0)
        sm = np.roll(m, d)
        out[:, x][sm] = shifted[sm]
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def anim_sparkle(img, f, n, hue="water"):
    """Wasser glitzert: helle Wasserpixel wandern."""
    a = _arr(img)
    h, w = a.shape[:2]
    blue = (a[:, :, 2] > 150) & (a[:, :, 2] > a[:, :, 0] + 40) & (a[:, :, 3] > 0)
    yy, xx = np.mgrid[0:h, 0:w]
    wave = np.sin((xx * 0.5 + yy * 0.9) - f * math.pi / 2)
    hi = blue & (wave > 0.75)
    a[hi, :3] = np.clip(a[hi, :3] + 70, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def anim_holo(img, f, n):
    a = _arr(img)
    glow = (a[:, :, 2] > 180) & (a[:, :, 2] > a[:, :, 0] + 40)
    k = [1.0, 0.82, 1.0, 0.7][f % 4]
    a[glow, 3] = (a[glow, 3] * k).astype(np.int16)
    a[glow, :3] = np.clip(a[glow, :3] + (f % 2) * 25, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def anim_lighthouse(img, f, n):
    """Bild 1: Leuchtfeuer heller (es kreist nachts)."""
    if f == 0:
        return img
    a = _arr(img)
    lamp = (a[:, :, 0] > 200) & (a[:, :, 1] > 150) & (a[:, :, 2] < 140)
    a[lamp, :3] = np.clip(a[lamp, :3] + 60, 0, 255)
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def anim_mill(img, f, n):
    """Flügel der Windmühle drehen sich um die Nabe. Die vier Arme liegen im Bogen schräg
    (Richtungen gemessen); was sie verdecken, füllt das nächste sichtbare Pixel daneben."""
    a = np.asarray(img).copy()
    h, w = a.shape[:2]
    cx, cy = w * 0.503, h * 0.372
    arms = [(-99, -79), (106, -81), (-94, 89), (96, 89)]
    yy, xx = np.mgrid[0:h, 0:w]
    px, py = xx - cx, yy - cy
    blade = (px ** 2 + py ** 2) < (w * 0.045) ** 2
    for dx, dy in arms:
        ln = math.hypot(dx, dy)
        ux, uy = dx / ln, dy / ln
        t = px * ux + py * uy
        d = np.abs(-px * uy + py * ux)
        blade |= (t > 0) & (t < w * 0.6) & (d < w * 0.095)
    rgb = a[:, :, :3].astype(int)
    roof = (rgb[:, :, 0] > 170) & (rgb[:, :, 0] - rgb[:, :, 1] > 85) & (rgb[:, :, 2] < 100)
    blade &= (a[:, :, 3] > 0) & ~roof & (yy < h * 0.70)
    sail = np.zeros_like(a)
    sail[blade] = a[blade]
    # Füllung nur aus Dach, heller Wand oder Himmel (nicht aus den braunen Flügelrändern)
    wall = rgb.min(axis=2) > 150
    allowed = ~blade & ((a[:, :, 3] == 0) | roof | wall)
    idx = ndimage.distance_transform_edt(~allowed, return_distances=False, return_indices=True)
    rest = a.copy()
    rest[blade] = a[idx[0], idx[1]][blade]
    s_img = Image.fromarray(sail, "RGBA").rotate(-f * 90.0 / n, resample=Image.NEAREST, center=(cx, cy))
    out = Image.fromarray(rest, "RGBA")
    out.alpha_composite(s_img)
    return out


def anim_fire(img, f, n):
    """Flammen flackern: Flammenpixel werden je Bild gestreckt oder gestaucht."""
    a = np.asarray(img).copy()
    h, w = a.shape[:2]
    rgb = a[:, :, :3].astype(int)
    flame = (rgb[:, :, 0] > 200) & (rgb[:, :, 2] < 120) & (rgb[:, :, 1] > 60) & (a[:, :, 3] > 0)
    ys = np.where(flame.any(axis=1))[0]
    if len(ys) == 0:
        return img
    base = ys.max()
    k = [1.0, 0.86, 1.1, 0.93][f % 4]
    sway = [0, 1, 0, -1][f % 4]
    out = a.copy()
    out[flame] = a[flame]
    fl = np.zeros_like(a)
    fl[flame] = a[flame]
    # Flammen entfernen, dann gestreckt neu einsetzen
    out[flame & (np.arange(h)[:, None] < base - 2)] = 0
    for y in range(h):
        sy = base - (base - y) / k
        if 0 <= sy < h:
            src = fl[int(sy)]
            row = np.roll(src, int(round(sway * (base - y) / max(1, base - ys.min()))), axis=0)
            m = row[:, 3] > 0
            out[y][m] = row[m]
    return Image.fromarray(out, "RGBA")


def anim_bob(img, f, n):
    """Schiffe schaukeln: Bild 1 einen Pixel tiefer."""
    if f == 0:
        return img
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(img, (0, S // 2))
    return out


ANIMS = {
    "flagpole": anim_flag,
    "fountain": anim_sparkle,
    "hologram": anim_holo,
    "lighthouse": anim_lighthouse,
    "mill": anim_mill,
}


# ------------------------------------------------------------------ Figuren
# Bogen -> Liste (Beruf, Geschlecht, Ansicht, Rechteck). Ansicht front/side.
def _four(job, sheet_name, fm, sm, ff, sf):
    return [(job, "m", "front", sheet_name, fm), (job, "m", "side", sheet_name, sm),
            (job, "f", "front", sheet_name, ff), (job, "f", "side", sheet_name, sf)]


B1, B2 = "figuren_berufe_1", "figuren_berufe_2"
FIGURES = (
    _four("frei", B1, (48, 145, 172, 340), (210, 145, 334, 340), (48, 352, 172, 548), (214, 352, 338, 548))
    + _four("holzfaeller", B1, (408, 136, 570, 340), (596, 140, 750, 340), (412, 352, 580, 550), (594, 352, 752, 550))
    + _four("steinmetz", B1, (808, 140, 970, 340), (986, 140, 1140, 340), (808, 350, 970, 550), (988, 356, 1140, 550))
    + _four("sammler", B1, (1198, 140, 1340, 340), (1364, 140, 1502, 340), (1200, 356, 1346, 550), (1364, 356, 1510, 550))
    + _four("fischer", B1, (90, 625, 262, 820), (296, 625, 448, 820), (84, 822, 258, 1012), (286, 822, 448, 1012))
    + _four("bauer", B1, (594, 622, 764, 818), (796, 622, 954, 818), (586, 820, 760, 1012), (788, 820, 952, 1012))
    + _four("koch", B1, (1084, 600, 1249, 812), (1315, 605, 1463, 812), (1084, 813, 1249, 1012), (1315, 813, 1463, 1012))
    + _four("handwerker", B2, (146, 116, 261, 279), (286, 116, 397, 279), (146, 280, 261, 446), (284, 280, 397, 446))
    + _four("baumeister", B2, (483, 116, 595, 279), (620, 116, 725, 279), (483, 280, 595, 446), (620, 280, 725, 446))
    + _four("forscher", B2, (813, 116, 923, 279), (948, 116, 1053, 279), (813, 280, 923, 446), (947, 280, 1053, 446))
    + _four("jaeger", B2, (1145, 112, 1270, 279), (1286, 112, 1400, 279), (1138, 280, 1270, 446), (1286, 280, 1400, 446))
    + _four("verwalter", B2, (209, 593, 325, 754), (371, 593, 481, 754), (209, 755, 325, 918), (371, 755, 481, 918))
    + _four("seemann", B2, (623, 590, 762, 754), (797, 590, 925, 754), (623, 755, 762, 918), (797, 755, 925, 918))
    + _four("foerster", B2, (1059, 591, 1202, 754), (1235, 591, 1354, 754), (1059, 755, 1202, 918), (1235, 755, 1354, 918))
)
# Bezugsfigur je Bogen (ohne Hut): ihre Körperhöhe wird FIG_H Spielpixel
FIG_REF = {B1: ("frei", "m", "front"), B2: ("handwerker", "m", "front")}
FIG_H = 21.0
FIG_CELL = (24, 28)  # Zelle je Bild (Spielpixel), Füße bei y = 26
FIG_FEET = 26
# Berufe, deren Figur ihr Werkzeug schon in der Hand hält (Settler blendet dann kein zweites ein)
HOLDS_TOOL = ["holzfaeller", "steinmetz", "sammler", "fischer", "bauer", "koch", "forscher", "jaeger",
              "verwalter", "seemann", "foerster"]


def _walk_frames(img, view):
    """4 Laufbilder aus einem Standbild: 0 stehen, 1 Schritt, 2 stehen (wippt), 3 anderer Schritt.
    Die Beine (unteres Viertel) werden versetzt, der Körper wippt einen Pixel."""
    a = np.asarray(img)
    h, w = a.shape[:2]
    leg_top = int(h * 0.80)
    alpha = a[:, :, 3] > 0
    xs = np.where(alpha[leg_top:].any(axis=0))[0]
    mid = (xs.min() + xs.max()) // 2 if len(xs) else w // 2
    frames = []
    step = max(2, S // 2 + 1)
    for f in range(4):
        out = np.zeros((h + step, w, 4), dtype=np.uint8)
        body = a.copy()
        legs = np.zeros_like(a)
        legs[leg_top:] = a[leg_top:]
        body[leg_top:] = 0
        bob = step if f in (1, 3) else 0
        # Körper (wippt nach oben, wenn ein Bein gehoben ist)
        out[step - bob:step - bob + h] = np.where(body[:, :, 3:4] > 0, body, out[step - bob:step - bob + h])
        if f in (0, 2):
            out[step:step + h] = np.where(legs[:, :, 3:4] > 0, legs, out[step:step + h])
        else:
            left = legs.copy()
            right = legs.copy()
            left[:, mid:] = 0
            right[:, :mid] = 0
            lift_left = f == 1
            if view == "front":
                # ein Bein angehoben (kürzer), das andere trägt
                up = left if lift_left else right
                down = right if lift_left else left
                out[step:step + h] = np.where(down[:, :, 3:4] > 0, down, out[step:step + h])
                ys = slice(step - bob, step - bob + h)
                out[ys] = np.where(up[:, :, 3:4] > 0, up, out[ys])
            else:
                # Seitenansicht: Beine scheren vor und zurück
                sh = step if lift_left else -step
                for part, d in ((left, -sh), (right, sh)):
                    p = np.roll(part, d, axis=1)
                    out[step:step + h] = np.where(p[:, :, 3:4] > 0, p, out[step:step + h])
        frames.append(Image.fromarray(out, "RGBA"))
    return frames


def gen_figures():
    raw = {}
    for job, sex, view, sh, rect in FIGURES:
        raw[(job, sex, view)] = (sh, grab(sh, rect, keep=0.03, feet=True))
    factors = {}
    for sh, key in FIG_REF.items():
        factors[sh] = FIG_H * S / raw[key][1].height
    cw, ch = FIG_CELL
    jobs = sorted(set(k[0] for k in raw))
    for job in jobs:
        for sex in ("m", "f"):
            atlas = Image.new("RGBA", (cw * 4 * S, ch * 3 * S), (0, 0, 0, 0))
            for row, view in ((0, "front"), (1, "side"), (2, "side")):
                sh, img = raw[(job, sex, view)]
                img = scale(img, factors[sh])
                if img.width > cw * S:
                    img = fit(img, cw * S, ch * S)
                for f, fr in enumerate(_walk_frames(img, view)):
                    x = (f * cw) * S + (cw * S - fr.width) // 2
                    y = (row * ch + FIG_FEET) * S - fr.height + S // 2
                    atlas.alpha_composite(fr, (x, max(row * ch * S, y)))
            save(atlas, "fig_%s_%s" % (job, sex))
    return jobs


# ------------------------------------------------------------------ Siedler-Bögen (josh 2026-10-28)
# 42 Bögen nach dem Auftrag "Siedler-Bögen für Version 2": Kästchen 128 x 128, 8 Bilder je Zeile,
# je Bewegung 3 Zeilen (vorn, hinten, seitlich nach rechts), Schlafen 1 Zeile, Füße 8 Pixel über dem Rand.
# Verkleinert auf Kästchen von 60 Pixeln (= 30 Spielpixel bei doppelter Auflösung, Settler.SIED_*),
# damit 42 Bögen auch auf dem iPhone in den Speicher passen.
SIED_SRC = os.path.join(ROOT, "tools", "art_v2", "src", "siedler")
# Zweiter Satz sied_hd mit 120 Pixeln (= 64 Punkte je Feld wie Gebäude und Gras) für PC und Mac (josh 2026-10-28).
SIED_CELL = 60
SIED_CELL_HD = 120


def gen_settler_sheets():
    for folder, cell in (("sied", SIED_CELL), ("sied_hd", SIED_CELL_HD)):
        out_dir = os.path.join(OUT, folder)
        os.makedirs(out_dir, exist_ok=True)
        for f in sorted(os.listdir(SIED_SRC)):
            if not f.endswith(".png"):
                continue
            im = Image.open(os.path.join(SIED_SRC, f)).convert("RGBA")
            src = im.width // 8  # 8 Bilder je Zeile; Kästchen 128 (erste Bögen) oder 256 (feine Bögen, josh 2026-10-28)
            cols, rows = im.width // src, im.height // src
            out = resize(im, cols * cell, rows * cell)
            out.save(os.path.join(out_dir, f.replace("siedler_", "")), optimize=True)
        print("   Siedler-Bögen", folder, len(os.listdir(out_dir)))


# ------------------------------------------------------------------ Tiere und Piraten
ANIMAL_ROWS = [  # Zeile in animals.png, Rechtecke der 5 Bilder (4 Laufen, 1 Angriff)
    (0, [(230, 70, 415, 192), (460, 70, 640, 192), (690, 70, 875, 192), (920, 70, 1110, 192), (1165, 72, 1362, 192)]),
    (1, [(230, 200, 420, 325), (460, 200, 645, 325), (686, 200, 874, 325), (918, 200, 1110, 326), (1162, 202, 1370, 326)]),
    (2, [(218, 334, 405, 478), (442, 334, 640, 478), (666, 334, 862, 478), (886, 334, 1090, 478), (1148, 332, 1362, 478)]),
    (3, [(240, 830, 380, 996), (454, 830, 594, 996), (686, 830, 826, 996), (910, 830, 1058, 996), (1160, 828, 1362, 996)]),
]


def gen_animals():
    atlas = old_hd("animals")
    c = 24
    # Maßstab: Bär ~23 Spielpixel breit; Pirat so groß wie ein Siedler
    for row, rects in ANIMAL_ROWS:
        imgs = [grab("tiere_piraten", r, keep=0.05, feet=True) for r in rects]
        import scale as sc
        f = sc.FIXED[["wolf", "eber", "baer", "pirat"][row]][1] * S / imgs[0].height
        for col, img in enumerate(imgs):
            img = scale(img, f)
            put(atlas, img, col * c, row * c, c, c, bottom=1)
    save(atlas, "animals")


# ------------------------------------------------------------------ Symbole und Werkzeuge
def icon_cells():
    """Raster der vier Symbolbögen: Liste von (Bogen, Rechteck) in der Reihenfolge von icons.txt."""
    out = []
    # symbole_1: Kästchen mit Rahmen
    xs = [(30, 262), (279, 509), (528, 759), (777, 1009), (1027, 1259), (1276, 1507)]
    ys = [(87, 303), (321, 550), (570, 770), (788, 997)]
    for y0, y1 in ys:
        for x0, x1 in xs:
            out.append(("symbole_1", (x0 + 7, y0 + 7, x1 - 7, y1 - 50)))
    cols = [(18, 272), (272, 522), (522, 770), (770, 1020), (1020, 1270), (1270, 1525)]
    rows = {
        "symbole_2": [(80, 268), (312, 506), (540, 735), (770, 962)],
        "symbole_3": [(25, 228), (262, 494), (540, 718), (755, 952)],
        "symbole_4": [(20, 238), (276, 488), (528, 735), (785, 968)],
    }
    for sh in ("symbole_2", "symbole_3", "symbole_4"):
        for y0, y1 in rows[sh]:
            for x0, x1 in cols:
                out.append((sh, (x0, y0, x1, y1)))
    return out


LIGHT_ICONS = ["schnee", "glas"]


def gen_icons():
    names = [l.strip() for l in open(os.path.join(OLD, "icons.txt")) if l.strip()]
    atlas = old_hd("icons")
    cells = icon_cells()
    imgs = {}
    for i, name in enumerate(names):
        if i >= len(cells):
            break
        sh, rect = cells[i]
        img = grab(sh, rect, keep=0.12, tol=10.0 if name in LIGHT_ICONS else 34.0)
        imgs[name] = img
        put(atlas, fit(img, 15 * S, 15 * S, upscale=True), i * 16, 0, 16, 16, align="center")
    save(atlas, "icons")
    return imgs


TOOLS = ["axe", "pick", "basket", "rod", "hammer", "sickle", "spoon", "book", "shovel", "spear", "saber",
         "pitchfork", "club", "newspaper"]


def gen_tools(icons):
    atlas = old_hd("tools")
    src = {
        "axe": icons.get("axt"),
        "basket": icons.get("korb"),
        "hammer": grab(B2, (205, 444, 300, 530)),
        "book": grab(B2, (885, 444, 975, 532)),
        "spear": grab(B2, (1200, 448, 1335, 535), keep=0.2),
        "rod": grab(B2, (695, 912, 845, 1002)),
        "shovel": grab(B2, (1130, 912, 1255, 1003)),
        "saber": icons.get("schwert"),
        "newspaper": icons.get("zeitungen"),
    }
    for name, img in src.items():
        if img is None:
            continue
        i = TOOLS.index(name)
        put(atlas, fit(img, 15 * S, 15 * S, upscale=True), i * 16, 0, 16, 16, align="center")
    save(atlas, "tools")


# ------------------------------------------------------------------ Natur (objects.png, objects2.png)
R = "landschaft_rohstoffe"
NATURE = {  # name -> (Bogen, Rechteck, Breite in Spielpixeln)
    "tree0": (R, (18, 140, 170, 356), 30),
    "tree1": (R, (172, 140, 318, 356), 29),
    "tree2": (R, (318, 140, 478, 356), 31),
    "tree3": (R, (480, 112, 628, 356), 26),  # Fichte
    "sapling": (R, (632, 190, 736, 358), 15),
    "stump": (R, (736, 252, 868, 358), 18),
    "rock_big": (R, (890, 205, 1052, 358), 15),
    "rock_small": (R, (1056, 260, 1165, 358), 11),
    "bush_full": (R, (1190, 180, 1356, 320), 15),
    "bush_empty": (R, (1356, 180, 1516, 320), 15),
    "palm0": (R, (350, 450, 524, 688), 30),
    "palm1": (R, (520, 420, 678, 688), 29),
    "palm_empty": (R, (676, 420, 836, 688), 29),
    "mushrooms": (R, (862, 515, 1102, 648), 15),
    "spice_full": (R, (1142, 500, 1330, 644), 15),
    "spice_empty": (R, (1334, 500, 1512, 644), 15),
    "ore_rock": (R, (14, 795, 174, 962), 15),
    "gold_rock": (R, (282, 795, 434, 962), 15),
    "den": (R, (532, 792, 738, 962), 16),
    "wallow": (R, (745, 815, 1014, 968), 16),
    "cave": (R, (1020, 740, 1275, 942), 30),
    "carcass": (R, (1288, 828, 1516, 932), 16),
}
OBJ1 = {"tree0": (0, 0, 32, 48), "tree1": (32, 0, 32, 48), "tree2": (64, 0, 32, 48), "tree3": (160, 0, 32, 48),
        "stump": (96, 0, 32, 48), "sapling": (128, 0, 32, 48),
        "rock_big": (0, 96, 16, 16), "rock_small": (16, 96, 16, 16), "bush_full": (32, 96, 16, 16),
        "bush_empty": (48, 96, 16, 16)}
OBJ2 = {"palm0": (0, 0, 32, 48), "palm1": (32, 0, 32, 48), "palm_empty": (64, 0, 32, 48), "cave": (96, 0, 32, 48),
        "mushrooms": (0, 48, 16, 16), "ore_rock": (16, 48, 16, 16), "gold_rock": (32, 48, 16, 16),
        "den": (48, 48, 16, 16), "wallow": (64, 48, 16, 16), "carcass": (80, 48, 16, 16),
        "spice_full": (112, 48, 16, 16), "spice_empty": (128, 48, 16, 16)}
OB = "oberflaeche"


def _bottom_for(cell):
    """ResourceNode setzt hohe Bilder 3 Pixel, kleine 8 Pixel über den Fuß (resource_node.gd)."""
    return 3 if cell[3] > 16 else 0


def nature_img(name, cell):
    """Natur in der Größe aus scale.py (Bäume knapp 2 Figuren hoch), höchstens so groß wie die Zelle."""
    import scale as sc
    sh, rect, w = NATURE[name]
    img = grab(sh, rect, keep=0.03)
    f = sc.scale_for(name, sh, img)
    if f is None:
        return fit(img, w * S, (cell[3] - 1) * S, upscale=True)
    img = scale(img, f * S)
    return fit(img, cell[2] * S, (cell[3] - 1) * S)


# Felder (josh 2026-10-28): jede Kachel ganz mit Ackerboden gefüllt, darauf Pflanzen in drei Reihen.
# Boden und Pflanzen stammen aus den 4 Phasen "Feldfrüchte" im Bogen oberflaeche; nebeneinander
# gesetzte Felder ergeben einen durchgehenden Acker.
FIELD_SRC = [(28, 660, 118, 778), (120, 660, 220, 778), (220, 660, 322, 778), (322, 660, 432, 778)]


def _split_field(img):
    """Teilt ein Phasenbild in Pflanze (über dem Boden) und Bodenstreifen."""
    a = np.asarray(img)
    op = a[:, :, 3] > 0
    width = op.sum(axis=1)
    top = int(np.argmax(width >= 0.85 * width.max()))
    plant = img.crop((0, 0, img.width, top + 2))
    bb = plant.getbbox()
    soil = img.crop((int(img.width * 0.12), top + 6, int(img.width * 0.88), img.height - 6))
    return plant.crop(bb) if bb else plant, soil


def gen_fields(atlas):
    T = 16 * S
    parts = [_split_field(grab(OB, r, keep=0.05)) for r in FIELD_SRC]
    # Ackerboden: Farben aus dem Bodenstreifen des Bogens, als Pixelkrümel in 2er-Stufen verteilt,
    # mit drei dunkleren Furchen (unter jeder Pflanzenreihe)
    pal = parts[3][1].convert("RGB").quantize(5).convert("RGB")
    cols = sorted({c for c in pal.getdata()}, key=lambda c: sum(c))
    base, dark, light = np.array(cols[len(cols) // 2]), np.array(cols[0]), np.array(cols[-1])
    rs = np.random.RandomState(7)
    n = rs.rand(T // 2, T // 2)
    a = np.zeros((T // 2, T // 2, 3))
    a[:] = base
    a[n < 0.22] = (base + dark) / 2
    a[n < 0.07] = dark
    a[n > 0.90] = (base + light) / 2
    yy = np.arange(T // 2)[:, None]
    for fy in (10, 20, 31):
        a[(np.abs(yy - fy) < 1).repeat(T // 2, axis=1)] = dark
        a[(yy == fy - 2).repeat(T // 2, axis=1)] = (base + light) / 2
    a = np.kron(a, np.ones((2, 2, 1)))
    soil = Image.fromarray(np.dstack([a, np.full((T, T), 255)]).astype(np.uint8), "RGBA")
    ripe_h = parts[3][0].height
    f = 24.0 / ripe_h  # reifer Weizen 24 HD-Pixel hoch (6 Spielpixel)
    for i, (plant, _) in enumerate(parts):
        tile = soil.copy()
        p = scale(plant, f)
        for row, fy in enumerate((19, 39, 61)):
            xs = (10, 32, 54) if row % 2 == 0 else (21, 43)
            if i == 3:
                xs = (8, 24, 40, 56) if row % 2 == 0 else (16, 32, 48)
            for x in xs:
                px = x - p.width // 2
                py = fy + 1 - p.height
                tile.alpha_composite(p.crop((max(0, -px), max(0, -py), p.width, p.height)), (max(0, px), max(0, py)))
        atlas.paste(tile, (i * T, 128 * S))


def gen_objects(cells):
    atlas = old_hd("objects")
    for name, cell in OBJ1.items():
        put(atlas, nature_img(name, cell), *cell, bottom=_bottom_for(cell))
    # Hütte und Lagerhaus (48x48)
    for name, cell in (("hut", (0, 48, 48, 48)), ("storehouse", (48, 48, 48, 48))):
        img = fit(building_img(name), 50 * S, 44 * S)
        put(atlas, img, *cell, bottom=4)
    # Lagerfeuer (4 Bilder) aus dem Bogen Lager und Feuer, ohne die Figur
    fire = grab("gebaeude_lager_1", (28, 550, 232, 724), keep=0.02)
    fire = fit(fire, 18 * S, 14 * S, upscale=True)
    for f in range(4):
        put(atlas, anim_fire(fire, f, 4), f * 16, 112, 16, 16, bottom=1)
    # Fischgrund (4 Bilder): Wasser mit Fischen, Fische ziehen ihre Bahn
    pond = sheet(R).crop((70, 520, 290, 660)).convert("RGBA")
    pond = pond.resize((16 * S, 10 * S), Image.LANCZOS)
    for f in range(4):
        fr = Image.new("RGBA", pond.size)
        sh = (f * pond.width // 4)
        fr.paste(pond.crop((sh, 0, pond.width, pond.height)), (0, 0))
        fr.paste(pond.crop((0, 0, sh, pond.height)), (pond.width - sh, 0))
        a = np.asarray(fr).copy()
        hh, ww = a.shape[:2]
        yy, xx = np.mgrid[0:hh, 0:ww]
        d = ((xx - ww / 2) / (ww / 2)) ** 2 + ((yy - hh / 2) / (hh / 2)) ** 2
        a[:, :, 3] = np.clip((1.15 - d) * 400, 0, 220).astype(np.uint8)
        put(atlas, Image.fromarray(a, "RGBA"), 64 + f * 16, 112, 16, 16, align="center")
    # Felder (4 Wachstumsstufen) und Obstgarten (4 Stufen) aus Effekte und Wachstum
    gen_fields(atlas)
    orchard = [(472, 660, 545, 782), (545, 655, 638, 782), (638, 652, 738, 782), (738, 652, 834, 782)]
    for i, r in enumerate(orchard):
        img = grab(OB, r, keep=0.05)
        put(atlas, fit(img, 16 * S, 16 * S, upscale=True), 64 + i * 16, 128, 16, 16, bottom=0)
    save(atlas, "objects")

    atlas = old_hd("objects2")
    for name, cell in OBJ2.items():
        put(atlas, nature_img(name, cell), *cell, bottom=_bottom_for(cell))
    # Boot und Schiffe (2 Bilder: schaukeln)
    for name, cell, ic in (("boat", (0, 64, 32, 32), "boot"), ("ship_kogge", (0, 96, 48, 48), "kogge"),
                           ("ship_fast", (96, 96, 48, 48), "schnellsegler"), ("ship_galleon", (192, 96, 48, 48), "galeone")):
        img = ICONS[ic]
        w = min(cell[2] - 2, {"boat": 26, "ship_kogge": 44, "ship_fast": 40, "ship_galleon": 46}[name])
        img = fit(img, w * S, (cell[3] - 4) * S, upscale=True)
        for f in range(2):
            put(atlas, anim_bob(img, f, 2), cell[0] + f * cell[2], cell[1], cell[2], cell[3], bottom=2)
    save(atlas, "objects2")


# ------------------------------------------------------------------ Wege, Zäune, Hecken (objects3.png)
V = "landschaft_verbindungen"
CONN_ROWS = {"road": (62, 152), "dike": (182, 276), "fence": (308, 404), "gravel": (434, 530),
             "bricks": (558, 654), "hedge": (680, 776)}
CONN_COLS = [(306, 466), (497, 657), (688, 848), (879, 1039), (1070, 1230)]  # gerade, Ecke, T, Kreuz, Ende
CONN_Y = {"road": 0, "dike": 16, "fence": 48, "gravel": 64, "bricks": 80, "hedge": 96}


def _conn_tiles(kind):
    """Die fünf Formen als quadratische HD-Kacheln: gerade (N+S), Ecke (N+O), T (N+O+W), Kreuzung,
    Ende (nur S). Ausschnitt: das Quadrat in der Mitte jeder Bogen-Kachel. Gras um Wege, Zäune und
    Hecken wird durchsichtig (darunter liegt das Gras der Insel), der Deich bleibt ganz."""
    y0, y1 = CONN_ROWS[kind]
    out = []
    for x0, x1 in CONN_COLS:
        img = sheet(V).crop((x0, y0, x1, y1)).convert("RGBA")
        paper = cut.paper_mask(np.asarray(img.convert("RGB")))
        rows = np.where((~paper).sum(axis=1) > img.width * 0.6)[0]
        cols = np.where((~paper).sum(axis=0) > img.height * 0.6)[0]
        t, b = rows.min() + 4, rows.max() - 3
        cx = (cols.min() + cols.max()) // 2
        side = b - t
        img = img.crop((cx - side // 2, t, cx - side // 2 + side, b))
        if kind != "dike":
            a = np.asarray(img).copy()
            r, g, bl = (a[:, :, i].astype(int) for i in range(3))
            if kind == "hedge":
                grass = (g > r) & (r >= 70) | ((g > r) & (g > 150))
            else:
                grass = (g > r + 8) & (g > bl)
                flower = (r > 200) & (g > 200) & (bl > 170)  # weiße Blümchen im Gras
                grass |= flower & ndimage.binary_dilation(grass, iterations=3)
            a[grass, 3] = 0
            # Krümel (einzelne Grashalme) weg
            solid = a[:, :, 3] > 0
            lab, n = ndimage.label(solid)
            if n:
                sizes = ndimage.sum(solid, lab, range(1, n + 1))
                a[np.isin(lab, [i + 1 for i, z in enumerate(sizes) if z < 60]), 3] = 0
            img = Image.fromarray(a, "RGBA")
        out.append(resize(img, 16 * S, 16 * S))
    return out


def _mask_tile(shapes, m):
    """Kachel für Nachbarmaske m (N=1, O=2, S=4, W=8) aus den fünf Formen durch Drehen im Uhrzeigersinn."""
    straight, corner, tee, cross, end = shapes
    rot = lambda img, k: img.rotate(-90 * k, expand=False)
    base = {5: (straight, 0), 10: (straight, 1), 3: (corner, 0), 6: (corner, 1), 12: (corner, 2), 9: (corner, 3),
            11: (tee, 0), 7: (tee, 1), 14: (tee, 2), 13: (tee, 3), 15: (cross, 0),
            4: (end, 0), 8: (end, 1), 1: (end, 2), 2: (end, 3)}
    if m == 0:
        return end
    img, k = base[m]
    return rot(img, k)


def gen_paths(atlas=None):
    """Wege und Hecken für Version 2 (josh 2026-10-28): jedes Stück so breit wie ein Feld (nur an offenen
    Seiten 1 Spielpixel Abstand), gerade Stücke stoßen nahtlos aneinander, nur offene Enden sind rund.
    Muster selbst gezeichnet in den Farben der Bögen, nahtlos mit Feldbreite, in halben Spielpixeln.
    Ersetzt die Zeilen road, gravel, bricks und hedge in objects3 (Maske N=1, O=2, S=4, W=8)."""
    import random
    H = 32
    own = atlas is None
    if own:
        atlas = Image.open(os.path.join(OUT, "objects3.png")).convert("RGBA")

    def tex(kind):
        rnd = random.Random({"road": 11, "gravel": 12, "bricks": 13, "hedge": 14}[kind])
        img = Image.new("RGBA", (H, H))
        d = ImageDraw.Draw(img)
        px = img.load()

        def put(x, y, c):
            px[x % H, y % H] = c + (255,)
        if kind == "road":
            d.rectangle((0, 0, H, H), fill=(222, 174, 98, 255))
            for _ in range(140):
                put(rnd.randrange(H), rnd.randrange(H), rnd.choice([(232, 186, 112), (210, 160, 88), (228, 178, 104)]))
            for _ in range(10):
                x, y = rnd.randrange(H), rnd.randrange(H)
                put(x, y, (176, 146, 116)); put(x + 1, y, (196, 168, 136)); put(x + 1, y + 1, (150, 122, 96))
        elif kind == "gravel":
            d.rectangle((0, 0, H, H), fill=(126, 126, 142, 255))
            for _ in range(150):
                x, y = rnd.randrange(H), rnd.randrange(H)
                c = rnd.choice([(150, 150, 166), (168, 168, 184), (140, 140, 152), (184, 184, 190)])
                put(x, y, c); put(x + 1, y, c); put(x, y + 1, c)
                put(x + 1, y + 1, (108, 108, 122))
        elif kind == "bricks":
            mortar = (128, 70, 54)
            d.rectangle((0, 0, H, H), fill=mortar + (255,))
            for row in range(8):
                y0 = row * 4
                off = 0 if row % 2 == 0 else 4
                for b in range(4):
                    x0 = b * 8 + off
                    c = rnd.choice([(190, 112, 80), (198, 122, 88), (180, 106, 74), (186, 118, 84)])
                    for yy in range(y0, y0 + 3):
                        for xx in range(x0, x0 + 7):
                            put(xx, yy, c)
                    for xx in range(x0, x0 + 7):
                        put(xx, y0, tuple(min(255, k + 22) for k in c))
                    put(x0 + 6, y0 + 2, tuple(k - 24 for k in c))
        else:  # hedge
            d.rectangle((0, 0, H, H), fill=(18, 84, 50, 255))
            for _ in range(70):
                x, y, r = rnd.randrange(H), rnd.randrange(H), rnd.choice([2, 2, 3])
                for dy in range(-r, r + 1):
                    for dx in range(-r, r + 1):
                        if dx * dx + dy * dy <= r * r:
                            put(x + dx, y + dy, (28, 104, 58) if dy > -r + 1 else (46, 128, 62))
                put(x - 1, y - r + 1, (96, 164, 52))
            for _ in range(40):
                put(rnd.randrange(H), rnd.randrange(H), rnd.choice([(112, 178, 44), (10, 64, 44)]))
        return img

    edge_col = {"road": (178, 132, 76), "gravel": (92, 92, 106), "bricks": (112, 58, 44), "hedge": (8, 56, 38)}
    for kind in ("road", "gravel", "bricks", "hedge"):
        t = tex(kind)
        tp = t.load()
        for m in range(16):
            con = [bool(m & 1), bool(m & 2), bool(m & 4), bool(m & 8)]  # N O S W
            e, r = 2, 9
            x0 = 0 if con[3] else e
            x1 = H - 1 if con[1] else H - 1 - e
            y0 = 0 if con[0] else e
            y1 = H - 1 if con[2] else H - 1 - e
            ins = [[False] * H for _ in range(H)]
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    ok = True
                    for (open_a, open_b, cx, cy) in ((not con[0], not con[3], x0 + r, y0 + r), (not con[0], not con[1], x1 - r, y0 + r),
                                                     (not con[2], not con[3], x0 + r, y1 - r), (not con[2], not con[1], x1 - r, y1 - r)):
                        if open_a and open_b and ((x - cx) * (1 if cx > x0 + r - 1 and x < cx else 0) or True):
                            inx = (x < cx) if cx == x0 + r else (x > cx)
                            iny = (y < cy) if cy == y0 + r else (y > cy)
                            if inx and iny and (x - cx) ** 2 + (y - cy) ** 2 > r * r:
                                ok = False
                    ins[y][x] = ok
            img = Image.new("RGBA", (H, H), (0, 0, 0, 0))
            ip = img.load()
            for y in range(H):
                for x in range(H):
                    if not ins[y][x]:
                        continue
                    border = False
                    for dx, dy, side in ((0, -1, 0), (1, 0, 1), (0, 1, 2), (-1, 0, 3)):
                        nx, ny = x + dx, y + dy
                        if 0 <= nx < H and 0 <= ny < H:
                            if not ins[ny][nx]:
                                border = True
                        elif not con[side]:
                            border = True
                    ip[x, y] = (edge_col[kind] + (255,)) if border else tp[x, y]
            T = 16 * S
            clear(atlas, m * 16, CONN_Y[kind], 16, 16)
            atlas.alpha_composite(img.resize((T, T), Image.NEAREST), (m * T, CONN_Y[kind] * S))
    if own:
        save(atlas, "objects3")


def gen_fence(atlas=None):
    """Zaun für Version 2 selbst gezeichnet (josh 2026-10-28, zaun_v2.py): ersetzt die Zaunzeile in objects3."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("zaun_v2", os.path.join(ROOT, "tools", "art_v2", "zaun_v2.py"))
    z = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(z)
    own = atlas is None
    if own:
        atlas = Image.open(os.path.join(OUT, "objects3.png")).convert("RGBA")
    st = z.strip()
    T = 16 * S
    for m in range(16):
        clear(atlas, m * 16, CONN_Y["fence"], 16, 16)
        atlas.alpha_composite(st.crop((m * T, 0, m * T + T, T)), (m * T, CONN_Y["fence"] * S))
    if own:
        save(atlas, "objects3")


def gen_objects3():
    atlas = old_hd("objects3")
    for kind in CONN_ROWS:
        shapes = _conn_tiles(kind)
        for m in range(16):
            put(atlas, _mask_tile(shapes, m), m * 16, CONN_Y[kind], 16, 16, align="center")
    gen_fence(atlas)
    gen_paths(atlas)
    for name, x, r in (("plant_mark", 0, (688, 805, 848, 885)), ("clear_mark", 16, (688, 905, 848, 990))):
        img = sheet(V).crop(r).convert("RGBA")
        paper = cut.paper_mask(np.asarray(img.convert("RGB")))
        a = np.asarray(img).copy()
        a[:, :, 3] = np.where(paper, 0, 255)
        img = Image.fromarray(a, "RGBA")
        img = img.crop(img.getbbox())
        put(atlas, fit(img, 16 * S, 16 * S, upscale=True), x, 32, 16, 16, align="center")
    save(atlas, "objects3")


# ------------------------------------------------------------------ Gelände (terrain.png)
BODEN = "landschaft_boden"


def _seamless(img):
    """Nahtlos kachelbar: Überblenden mit der um die halbe Größe verschobenen Kopie."""
    a = np.asarray(img).astype(np.float32)
    h, w = a.shape[:2]
    b = np.roll(np.roll(a, h // 2, axis=0), w // 2, axis=1)
    yy, xx = np.mgrid[0:h, 0:w]
    wx = 1 - np.abs((xx + 0.5) / w * 2 - 1)
    wy = 1 - np.abs((yy + 0.5) / h * 2 - 1)
    m = np.clip(np.minimum(wx, wy) * 3.0, 0, 1)[:, :, None]
    out = a * m + b * (1 - m)
    return Image.fromarray(out.astype(np.uint8), img.mode)


def _texture(rect, out=16 * S, src_px=None):
    """Bodenstück aus dem Bogen, auf die Kachelgröße gebracht (gleicher Maßstab wie Gebäude)."""
    img = sheet(BODEN).crop(rect).convert("RGBA")
    return _seamless(img.resize((out, out), Image.LANCZOS))


def _noise(seed, n=16):
    rnd = np.random.RandomState(seed)
    g = rnd.rand(5, 5)
    g[-1, :] = g[0, :]
    g[:, -1] = g[:, 0]
    z = ndimage.zoom(g, n * 2 / 4.0, order=3)[: n * 2, : n * 2]
    return z


# Böden (josh 2026-10-26): Gras einfarbig im Grün der Gebäudesockel, Grasbüschel und Blumen halb so groß
# wie im Bogen und unregelmäßig verstreut; Strand nur sandfarben mit vereinzelten Steinen und Kieseln.
GRASS_GREEN = (126, 176, 52)  # Median des Grases an den Hausrändern (Hütte, Holzhaus)
SAND_COLOR = (246, 224, 162)
DECAL_SCALE = 0.286  # halb so groß wie bisher (bisher 112 Bogenpixel auf 64 HD-Pixel)


def _decals(rect, base, min_d=55, min_px=12, max_px=900):
    """Einzelteile (Büschel, Blumen, Steine) aus einem Bodenstück des Bogens: alles, was sich deutlich
    von der Grundfarbe abhebt, als freigestelltes Bild in halber Größe."""
    a = np.asarray(sheet(BODEN).crop(rect).convert("RGB")).astype(int)
    d = np.sqrt(((a - np.array(base)) ** 2).sum(axis=2))
    m = ndimage.binary_closing(d > min_d, iterations=1)
    lab, n = ndimage.label(m)
    out = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        part = lab[sl] == i + 1
        if not (min_px <= part.sum() <= max_px):
            continue
        rgba = np.dstack([a[sl], np.where(part, 255, 0)]).astype(np.uint8)
        img = Image.fromarray(rgba, "RGBA")
        img = scale(img, DECAL_SCALE * S / 2.0 * 2.0)
        if img.getbbox():
            out.append(img.crop(img.getbbox()))
    return out


def _scatter(tile, decals, rnd, n, margin=3):
    """n Teile zufällig auf die Kachel setzen, ohne über den Rand zu ragen (Kacheln bleiben nahtlos)."""
    for _ in range(n):
        dc = decals[rnd.randrange(len(decals))]
        if dc.width + 2 * margin >= tile.width or dc.height + 2 * margin >= tile.height:
            continue
        x = rnd.randint(margin, tile.width - dc.width - margin)
        y = rnd.randint(margin, tile.height - dc.height - margin)
        tile.alpha_composite(dc, (x, y))
    return tile


def gen_terrain():
    import random
    atlas = old_hd("terrain")
    T = 16 * S
    rnd = random.Random(2026)
    tufts = _decals((24, 190, 240, 445), (119, 179, 55))
    flowers = [t for t in tufts if np.asarray(t)[:, :, :3].min(axis=2).mean() > 150]
    grass_bits = [t for t in tufts if t not in flowers]
    stones = _decals((1040, 190, 1262, 445), (253, 231, 171), min_d=45)
    plain_g = Image.new("RGBA", (T, T), (*GRASS_GREEN, 255))
    plain_s = Image.new("RGBA", (T, T), (*SAND_COLOR, 255))
    deep = sheet(BODEN).crop((24, 568, 240, 846)).convert("RGBA")
    deep = _seamless(deep.resize((T * 2, T * 2), Image.LANCZOS))
    for f in range(4):
        d = f * T // 8
        atlas.paste(deep.crop((d, d // 2, d + T, d // 2 + T)), (f * T, 0))
    n = 32
    noise_s = (_noise(101, n // 2) - 0.5) * 0.36
    noise_g = (_noise(202, n // 2) - 0.5) * 0.36
    u = (np.arange(n) + 0.5) / n
    U, Vv = np.meshgrid(u, u)
    wet = np.array([214, 190, 132, 255], np.uint8)
    foam = np.array([235, 248, 255, 210], np.uint8)
    g_edge = np.array([int(c * 0.82) for c in GRASS_GREEN] + [255], np.uint8)
    for m in range(16):
        tl, tr, bl, br = [(1.0 if m & b else 0.0) for b in (1, 2, 4, 8)]
        cv = (tl * (1 - U) + tr * U) * (1 - Vv) + (bl * (1 - U) + br * U) * Vv
        for kind, row in (("sand", 1), ("grass", 2)):
            v = cv + (noise_s if kind == "sand" else noise_g)
            v = np.kron(v, np.ones((T // n, T // n)))
            out = np.zeros((T, T, 4), np.uint8)
            inside = v > 0.5
            if kind == "sand":
                out[inside] = (*SAND_COLOR, 255)
                out[(v > 0.40) & ~inside] = wet
                # Schaum malt seit 2026-10-28 der Wasser-Shader (Wellenkante, die an- und zurückläuft)
            else:
                out[inside] = (*GRASS_GREEN, 255)
                out[(v > 0.5) & (v < 0.545)] = g_edge
            atlas.paste(Image.fromarray(out, "RGBA"), (m * T, row * T))
    # Zeile 3: Sand 0..3 mit einzelnen Steinen, Gras 4..15 mit Büscheln und Blumen (World._paint_tile)
    for v in range(4):
        t = _scatter(plain_s.copy(), stones, rnd, 1 + (v == 3))
        atlas.paste(t, (v * T, 3 * T))
    # Gras 4..15: glatt; Grasbüschel und Blumen liegen seit 2026-10-28 als feine eigene Ebene darüber
    # (terrain_deco.png, gen_grass_deco), weich gefiltert statt in den Bodenkacheln
    for v in range(12):
        atlas.paste(plain_g.copy(), ((4 + v) * T, 3 * T))
    save(atlas, "terrain")
    gen_season_ground()
    gen_grass_texture()
    gen_dikes()
    gen_grass_deco()


def _blade(d, x, y, length, lean, col):
    """Ein Grashalm, 1 HD-Pixel breit, leicht gebogen."""
    px, py = x, y
    for i in range(1, length + 1):
        t = i / length
        nx = x + lean * t * t
        ny = y - i
        d.line((round(px), round(py), round(nx), round(ny)), fill=col)
        px, py = nx, ny


def gen_grass_deco():
    """terrain_deco.png (josh 2026-10-28): Grasbüschel und Blumen halb so groß wie vorher und feiner
    gezeichnet: Pixel von einem halben Spielpixel (doppelte Auflösung wie die Siedler), 16 Kacheln mit
    1 bis 3 Teilen, sonst durchsichtig. Farben aus dem Gras der Bögen (dunkel, mittel, hell)."""
    import random
    T = 16 * S
    H = T // 2  # Zeichenraster: halbe Spielpixel
    rnd = random.Random(1028)
    dark, mid, light, tip = (38, 92, 34, 255), (72, 140, 44, 255), (112, 178, 58, 255), (160, 206, 84, 255)
    petals = [(250, 250, 244), (250, 214, 74), (236, 132, 170), (150, 170, 240), (246, 246, 246)]
    atlas = Image.new("RGBA", (16 * T, T), (0, 0, 0, 0))
    for v in range(16):
        tile = Image.new("RGBA", (H, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(tile)
        n = rnd.choice([1, 1, 2, 2, 3])
        for _ in range(n):
            x, y = rnd.randint(4, H - 5), rnd.randint(9, H - 2)
            if rnd.random() < 0.3:
                # Blume: Stiel, vier Blütenblätter, gelbe Mitte
                h = rnd.randint(3, 5)
                d.line((x, y, x, y - h), fill=mid)
                d.point((x + 1, y - 1), fill=light)
                c = petals[rnd.randrange(len(petals))]
                shade = tuple(int(k * 0.8) for k in c) + (255,)
                cy = y - h - 1
                for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    d.point((x + dx, cy + dy), fill=c + (255,))
                d.point((x + 1, cy + 1), fill=shade)
                d.point((x, cy), fill=(250, 200, 60, 255))
            else:
                # Büschel: 4 bis 7 Halme, hinten dunkel, vorne hell, 4 bis 8 halbe Spielpixel hoch
                k = rnd.randint(4, 7)
                for b in range(k):
                    bx = x + rnd.randint(-2, 2)
                    col = dark if b < k // 3 else (mid if b < 2 * k // 3 else light)
                    ln = rnd.randint(4, 8)
                    _blade(d, bx, y, ln, rnd.uniform(-2.5, 2.5), col)
                    if col == light and rnd.random() < 0.5:
                        d.point((bx, y - ln + 1), fill=tip)
                d.line((x - 2, y, x + 2, y), fill=dark)
        atlas.paste(tile.resize((T, T), Image.NEAREST), (v * T, 0))
    atlas.save(os.path.join(OUT, "terrain_deco.png"))
    print("   terrain_deco", atlas.size)


def gen_grass_texture():
    """terrain_grasstex.png (josh 2026-10-28, zweite Fassung „feiner“): Gras der ganzen Insel in voller
    HD-Auflösung (1 Bildpixel = Viertel-Spielpixel): weiche Grünflecken mit Raster-Übergängen, dünne Halme,
    die nach oben heller werden, und Blumen mit fünf Blütenblättern. Ein nahtloses Feld aus 8x8 Kacheln
    (World legt Kachel (x mod 8, y mod 8) auf volle Grasfelder). Gezeichnet von gras_fein.py; die alten
    Büschel und Blumen (terrain_deco) zeigt World nicht mehr."""
    import subprocess
    subprocess.run([sys.executable, "-I", os.path.join(ROOT, "tools", "art_v2", "gras_fein.py"),
                    os.path.join(OUT, "terrain_grasstex.png")], check=True)
    print("   terrain_grasstex (fein)")


def gen_dikes():
    """dike_tiles.png (josh 2026-10-28): Deich als durchgehender Damm. Grasrücken überall, Steinböschung nur
    an den Seiten zum Wasser. Kachel für Maske m: Wasser im N=1, O=2, S=4, W=8 und schräg NO=16, SO=32,
    SW=64, NW=128 (nur zählt, wenn beide Nachbarn daneben kein Wasser sind: Innenecke). Spalte m & 15,
    Zeile m >> 4, je 16x16 Spielpixel. Die Steine laufen mit der Kachelbreite durch, so passen
    Nachbarkacheln ohne Fuge aneinander. Gezeichnet in halben Spielpixeln."""
    import random
    H = 32  # halbe Spielpixel je Kachel
    B = 11  # Breite der Böschung (halbe Spielpixel)
    grass, gdark, glight = (126, 176, 52), (96, 150, 42), (150, 196, 66)
    st_dark, st_mid, st_light, st_hi = (74, 76, 86), (128, 130, 140), (160, 162, 172), (196, 198, 206)
    wet = (60, 74, 86)

    rnd = random.Random(1510)
    # Steinband: H breit (nahtlos), B tief; Zeile 0 = Rasenkante, Zeile B-1 = Wasserkante
    band = Image.new("RGBA", (H, B), (92, 94, 104, 255))
    bd = ImageDraw.Draw(band)
    x = 0
    rows = [(0, 6), (5, 6)]
    for ri, (y0, h) in enumerate(rows):
        x = -rnd.randint(0, 3) - ri * 2
        while x < H:
            w = rnd.randint(6, 9)
            tone = rnd.choice([(128, 130, 140), (140, 140, 148), (118, 122, 134), (150, 146, 140)])
            lit = tuple(min(255, c + 30) for c in tone)
            shade = tuple(c - 26 for c in tone)
            for dx in (0, H, -H):  # nahtlos über den Rand; runde Feldsteine wie im Bogen
                x0, x1, y1 = x + dx + 1, x + dx + w - 1, y0 + h - 1
                bd.rectangle((x0, y0 + 1, x1, y1), fill=tone + (255,))
                bd.line((x0, y1, x1, y1), fill=shade + (255,))
                bd.line((x1, y0 + 1, x1, y1), fill=shade + (255,))
                bd.line((x0 + 1, y0 + 1, x1 - 1, y0 + 1), fill=lit + (255,))
                bd.point((x0 + 1, y0 + 2), fill=st_hi + (255,))
                for cx, cy in ((x0, y0 + 1), (x1, y0 + 1), (x0, y1), (x1, y1)):
                    bd.point((cx, cy), fill=st_dark + (255,))
            x += w
    bp = band.load()
    for xx in range(H):
        bp[xx, B - 1] = wet + (255,)
        if xx % 5 == 0:
            bp[xx, B - 2] = wet + (255,)
    # Grasrücken (nahtlos): Grundgrün mit kurzen Halmen
    crown = Image.new("RGBA", (H, H), grass + (255,))
    cp = crown.load()
    for _ in range(46):
        x, y = rnd.randrange(H), rnd.randrange(H)
        for k in range(rnd.randint(1, 3)):
            cp[x % H, (y - k) % H] = (gdark if k == 0 else glight) + (255,)
    # überhängende Grashalme an der Rasenkante der Böschung
    lip = [rnd.random() < 0.45 for _ in range(H)]

    def side(img, rot):
        """Böschung an eine Seite: rot 0 = Norden (Band oben, Wasserkante außen), im Uhrzeigersinn."""
        b = band.transpose(Image.FLIP_TOP_BOTTOM)  # Wasserkante oben (außen)
        layer = Image.new("RGBA", (H, H), (0, 0, 0, 0))
        layer.paste(b, (0, 0))
        lp = layer.load()
        for xx in range(H):
            if lip[xx]:
                lp[xx, B - 1] = gdark + (255,)
        layer = layer.rotate(-90 * rot, expand=False)
        img.alpha_composite(layer)

    def corner(img, k):
        """Innenecke k (0 NO, 1 SO, 2 SW, 3 NW): Viertelkreis aus Steinen."""
        layer = Image.new("RGBA", (H, H), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        r = B
        d.pieslice((H - r, -r, H + r, r), 90, 180, fill=st_dark + (255,))
        for (cx, cy, w) in ((H - 4, 2, 4), (H - 8, 1, 3), (H - 3, 6, 3), (H - 7, 5, 3)):
            d.rectangle((cx, cy, cx + w - 1, cy + 2), fill=st_mid + (255,))
            d.point((cx, cy), fill=st_light + (255,))
        d.arc((H - r, -r, H + r, r), 90, 180, fill=gdark + (255,))
        for xx in range(H - 2, H):
            layer.putpixel((xx, 0), wet + (255,))
        img.alpha_composite(layer.rotate(-90 * k, expand=False))

    T = 16 * S
    atlas = Image.new("RGBA", (16 * T, 16 * T), (0, 0, 0, 0))
    for m in range(256):
        img = crown.copy()
        for i in range(4):
            if m & (1 << i):
                side(img, i)
        for k in range(4):
            if m & (16 << k):
                corner(img, k)
        atlas.paste(img.resize((T, T), Image.NEAREST), ((m & 15) * T, (m >> 4) * T))
    atlas.save(os.path.join(OUT, "dike_tiles.png"))
    print("   dike_tiles", atlas.size)


def gen_season_ground():
    """terrain_season.png: Zeilen 0..7 Schnee als ein nahtloses Feld aus 8x8 Kacheln (World legt Kachel
    (x mod 8, y mod 8), so laufen die Schneewehen über die Kachelgrenzen), Zeile 8 Laub (8 Kacheln).
    World legt beides als eigene Ebenen über Gras und Sand und blendet sie mit der Jahreszeit ein."""
    import random
    T = 16 * S
    N = 8
    rnd = random.Random(77)
    atlas = Image.new("RGBA", (N * T, (N + 1) * T), (0, 0, 0, 0))
    # periodisches Rauschen: Zufall im Frequenzraum tiefpassgefiltert, dadurch an den Rändern nahtlos
    W = N * T // 2
    rs = np.random.RandomState(31)
    fy = np.fft.fftfreq(W)[:, None]
    fx = np.fft.fftfreq(W)[None, :]
    r = np.sqrt(fx ** 2 + fy ** 2)
    spec = np.fft.fft2(rs.randn(W, W)) * np.exp(-(r / 0.018) ** 2)
    f = np.real(np.fft.ifft2(spec))
    spec2 = np.fft.fft2(rs.randn(W, W)) * np.exp(-(r / 0.06) ** 2)
    f = f / f.std() + 0.35 * np.real(np.fft.ifft2(spec2)) / np.real(np.fft.ifft2(spec2)).std()
    f = np.kron(f, np.ones((2, 2)))  # 2-Pixel-Stufen wie die übrige Pixelgrafik
    # josh 2026-10-28: 70 % weniger Schnee am Boden. Die Schwelle liegt so, dass nur noch 30 % der früheren
    # Fläche (f > 0.1) bedeckt sind; die Wehen bleiben dieselben, nur kleiner.
    t0 = float(np.quantile(f, 1.0 - 0.3 * (f > 0.1).mean()))
    a = np.zeros(f.shape + (4,), np.uint8)
    a[f > t0] = (226, 236, 250, 255)
    a[f > t0 + 0.25] = (246, 250, 255, 255)
    a[(f > t0) & (f < t0 + 0.1)] = (200, 216, 240, 255)
    atlas.paste(Image.fromarray(a, "RGBA"), (0, 0))
    for v in range(N):
        # Laub: drei bis sieben kleine Blätter in Herbstfarben
        leaf = Image.new("RGBA", (T, T), (0, 0, 0, 0))
        d = ImageDraw.Draw(leaf)
        cols = [(214, 104, 38), (232, 156, 46), (178, 64, 34), (150, 92, 44), (240, 188, 70)]
        for _ in range(rnd.randint(3, 7)):
            x, y = rnd.randint(4, T - 10), rnd.randint(4, T - 8)
            c = cols[rnd.randrange(len(cols))]
            dark = tuple(int(k * 0.7) for k in c)
            w, h = rnd.choice([(6, 4), (4, 6), (6, 6), (8, 4)])
            d.ellipse((x, y, x + w, y + h), fill=c + (255,))
            d.line((x, y + h // 2, x + w, y + h // 2), fill=dark + (255,))
        atlas.paste(leaf, (v * T, N * T))
    atlas.save(os.path.join(OUT, "terrain_season.png"))
    print("   terrain_season", atlas.size, "Schnee %.0f %%" % (100 * (f > t0).mean()))



# ------------------------------------------------------------------ Oberfläche
def _nine(src, corner_src, cell=24 * S, corner=6 * S):
    """Neun-Teile-Bild (Ecken fest, Kanten und Mitte gestreckt) in eine HD-Zelle."""
    w, h = src.size
    c = corner_src
    out = Image.new("RGBA", (cell, cell))
    parts = {
        (0, 0): (0, 0, c, c), (1, 0): (c, 0, w - c, c), (2, 0): (w - c, 0, w, c),
        (0, 1): (0, c, c, h - c), (1, 1): (c, c, w - c, h - c), (2, 1): (w - c, c, w, h - c),
        (0, 2): (0, h - c, c, h), (1, 2): (c, h - c, w - c, h), (2, 2): (w - c, h - c, w, h),
    }
    sizes = [corner, cell - 2 * corner, corner]
    offs = [0, corner, cell - corner]
    for (i, j), box in parts.items():
        piece = src.crop(box).resize((sizes[i], sizes[j]), Image.LANCZOS)
        out.alpha_composite(piece, (offs[i], offs[j]))
    return out


def gen_ui():
    atlas = old_hd("ui")
    # Fensterrahmen: untere Hälfte des Rahmens (ohne Titelleiste mit Kreuz) oben und unten gespiegelt
    frame = grab(OB, (24, 60, 412, 370), keep=0.2)
    fw, fh = frame.size
    low = frame.crop((0, fh // 2, fw, fh))
    panel = Image.new("RGBA", (fw, low.height * 2))
    panel.alpha_composite(low.transpose(Image.FLIP_TOP_BOTTOM), (0, 0))
    panel.alpha_composite(low, (0, low.height))
    nine = _nine(panel, 34)
    # Mitte des Fensters einfarbig (gestreckt würde die Papierstruktur zu Flecken)
    a = np.asarray(nine).copy()
    c0, c1 = 6 * S, 18 * S
    a[c0:c1, c0:c1, :3] = np.median(a[c0:c1, c0:c1, :3].reshape(-1, 3), axis=0).astype(np.uint8)
    put(atlas, Image.fromarray(a, "RGBA"), 0, 0, 24, 24, align="center")
    # Knöpfe: normal, hover, gedrückt; die Mitte ohne Schrift (Streifen links neben dem Wort)
    for i, r in enumerate([(432, 64, 676, 170), (698, 64, 970, 172), (989, 64, 1238, 176)]):
        b = grab(OB, r, keep=0.2)
        bw, bh = b.size
        clean = b.copy()
        strip = b.crop((24, 0, 44, bh))
        for x in range(24, bw - 24, 20):
            clean.paste(strip, (x, 0))
        put(atlas, _nine(clean, 20), 24 * (i + 1), 0, 24, 24, align="center")
    save(atlas, "ui")
    # Knöpfe der Leiste unten (je 20x20): das Bild in der Mitte der Holzknöpfe
    menu = old_hd("menu_icons")
    xs = [(38, 150), (165, 278), (292, 405), (418, 532), (546, 660), (673, 787)]
    for i, (x0, x1) in enumerate(xs):
        img = sheet(OB).crop((x0 + 15, 413, x1 - 15, 492)).convert("RGBA")
        a = np.asarray(img).copy()
        # Holzhintergrund des Knopfes weg: braune, matte Farben, die vom Rand aus erreichbar sind
        r, g, b = (a[:, :, i].astype(int) for i in range(3))
        wood = (r > g) & (g >= b - 5) & (r - b > 25) & (r < 215) & (r - b < 120)
        if i == 2:  # Siedler: braune Haare, nur die Farbe der Ecke zählt als Holz
            wood = np.abs(a[:, :, :3].astype(int) - a[3, 3, :3].astype(int)).sum(axis=2) < 60
        lab, _ = ndimage.label(wood)
        edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
        a[np.isin(lab, list(edge)), 3] = 0
        img = Image.fromarray(a, "RGBA")
        img = img.crop(img.getbbox())
        put(menu, fit(img, 20 * S, 20 * S, upscale=True), i * 20, 0, 20, 20, align="center")
    save(menu, "menu_icons")
    # Jahreszeiten (16x16 je Zeit) und Teilchen (Schnee, Blatt, je 8x8)
    seasons = old_hd("seasons")
    for i, r in enumerate([(24, 842, 124, 968), (126, 842, 230, 968), (230, 842, 334, 968), (334, 842, 448, 968)]):
        put(seasons, fit(grab(OB, r, keep=0.05), 16 * S, 16 * S, upscale=True), i * 16, 0, 16, 16, align="center")
    put(seasons, fit(grab(OB, (494, 868, 552, 930)), 8 * S, 8 * S, upscale=True), 64, 16, 8, 8, align="center")
    put(seasons, fit(grab(OB, (664, 870, 716, 932)), 8 * S, 8 * S, upscale=True), 72, 16, 8, 8, align="center")
    save(seasons, "seasons")


def gen_app_icon():
    img = grab(OB, (1288, 680, 1514, 908), keep=0.2)
    img = img.resize((128, 128), Image.LANCZOS)
    img.save(os.path.join(ROOT, "icon.png"))


ICONS = {}


def main():
    os.makedirs(OUT, exist_ok=True)
    print("Symbole")
    ICONS.update(gen_icons())
    gen_tools(ICONS)
    print("Gebäude")
    cells = gen_buildings()
    print("Natur")
    gen_objects(cells)
    gen_objects3()
    print("Gelände")
    gen_terrain()
    print("Figuren")
    gen_figures()
    gen_settler_sheets()
    print("Tiere")
    gen_animals()
    print("Oberfläche")
    gen_ui()
    gen_app_icon()
    # Unveränderte Atlanten (Karre, Droide, Berufskleidung) vierfach vergrößert, damit sie bei
    # weichem Filter so scharf bleiben wie bisher
    for n in ("cart", "settler_droid"):
        save(old_hd(n), n)


if __name__ == "__main__":
    main()
