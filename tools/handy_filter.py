#!/usr/bin/env python3
"""Schreibt die Ausschlussliste der Handy-Fassungen in export_presets.cfg neu.

Die Handy-Fassung (Presets mit dem Merkmal "handy") lädt nur die halben Bilder aus assets/sprites_hd/half/.
Jedes große Bild in big/ und fine/, zu dem es ein halbes gibt, wird dort ausgeschlossen. Bilder ohne halbe
Fassung bleiben drin. Alle Presets schließen außerdem die Testskripte (scripts/test/) aus.
Aufruf: python3 tools/handy_filter.py          schreibt die Datei
        python3 tools/handy_filter.py --check  meldet nur, ob sie aktuell ist (Rückgabewert 1, wenn nicht)
web.yml ruft das Skript vor jedem Export auf, die Liste kann also nicht mehr veralten.
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = os.path.join(ROOT, "export_presets.cfg")
BASE = ["tools/*", "scripts/test/*", "assets/sprites_hd/buildings.png", "assets/sprites_hd/sied/*",
        "assets/sprites_hd/sied_hd/*"]
HANDY = ["assets/sprites_hd/sied_pack/sied_hd/*.png"]


def handy_list():
    out = list(HANDY)
    for d in ("fine", "big"):
        for p in sorted(glob.glob(os.path.join(ROOT, "assets/sprites_hd", d, "*.png"))):
            name = os.path.basename(p)
            if os.path.exists(os.path.join(ROOT, "assets/sprites_hd/half", d, name)):
                out.append("assets/sprites_hd/%s/%s" % (d, name))
    return out


def main():
    text = open(CFG, encoding="utf-8").read()
    parts = re.split(r"(?m)^(?=\[preset\.\d+\]$)", text)
    new = []
    for part in parts:
        m = re.search(r'(?m)^custom_features="([^"]*)"$', part)
        if m and re.search(r'(?m)^exclude_filter="', part):
            items = BASE + (handy_list() if "handy" in m.group(1).split(",") else [])
            part = re.sub(r'(?m)^exclude_filter="[^"]*"$', 'exclude_filter="%s"' % ", ".join(items), part)
        new.append(part)
    result = "".join(new)
    if "--check" in sys.argv:
        if result != text:
            print("export_presets.cfg ist veraltet: python3 tools/handy_filter.py")
            return 1
        print("export_presets.cfg ist aktuell")
        return 0
    if result != text:
        open(CFG, "w", encoding="utf-8").write(result)
        print("export_presets.cfg neu geschrieben")
    else:
        print("export_presets.cfg war aktuell")
    return 0


if __name__ == "__main__":
    sys.exit(main())
