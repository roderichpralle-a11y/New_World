#!/bin/bash
# Baut das Paket für den Mac: Insel-KI-Training.zip (Training + Spiel ohne .git, .godot und Werkzeuge).
# Aufruf: tools/ki_voll/pack.sh <Zielordner>
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$REPO/build}"
TMP="$(mktemp -d)"
P="$TMP/Insel-KI-Training"
mkdir -p "$P/training/web" "$P/spiel" "$P/lauf"
cp "$HERE/trainer.py" "$HERE/server.py" "$P/training/"
cp "$HERE/web/index.html" "$P/training/web/"
cp "$HERE/START.command" "$HERE/LIESMICH.md" "$P/"
chmod +x "$P/START.command"
python3 -c "
import json,sys
sys.path.insert(0,'$HERE')
import trainer
d={k:(0 if k in ('arbeiter','richtungen') else v) for k,v in trainer.DEFAULTS.items()}
json.dump(d,open('$P/lauf/einstellungen.json','w'),indent=1,ensure_ascii=False)"
(cd "$REPO" && git ls-files -z -- project.godot icon.png icon.png.import default_bus_layout.tres scripts data scenes assets CREDITS.md \
  | xargs -0 -I{} cp --parents {} "$P/spiel/")
mkdir -p "$OUT"
rm -f "$OUT/Insel-KI-Training.zip"
(cd "$TMP" && zip -q -r -X "$OUT/Insel-KI-Training.zip" Insel-KI-Training)
rm -rf "$TMP"
ls -la "$OUT/Insel-KI-Training.zip"
