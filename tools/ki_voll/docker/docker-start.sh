#!/bin/sh
# Start im Docker: beim ersten Mal die Einstellungen des Pakets in den (leeren) Ordner lauf/ legen.
set -e
mkdir -p /insel/lauf
[ -f /insel/lauf/einstellungen.json ] || cp /insel/vorlage/einstellungen.json /insel/lauf/einstellungen.json
exec python3 /insel/training/server.py --godot /opt/godot/godot
