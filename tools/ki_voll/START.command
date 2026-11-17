#!/bin/bash
# Startet das KI-Training auf dem Mac: lädt beim ersten Mal Godot, bereitet das Spiel vor und öffnet die
# Oberfläche im Browser. Dieses Fenster offen lassen. Beenden: Fenster schließen oder Strg+C.
cd "$(dirname "$0")" || exit 1
echo "=== Insel-Siedler: KI-Training ==="

if ! command -v python3 >/dev/null 2>&1 || ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)" 2>/dev/null; then
  echo "Python 3 fehlt. Bitte einmal im Terminal eingeben:  xcode-select --install"
  echo "Danach diese Datei noch einmal starten."
  read -r -p "Eingabetaste zum Schließen ..." _
  exit 1
fi

# Alles, was beim Training entsteht, bleibt auf dem Laufwerk dieses Ordners (josh 2026-11-17): Godot und
# Python schreiben Temp-Dateien, Einstellungen und Zwischenspeicher sonst auf das Systemlaufwerk.
export INSEL_ALT_TMP="${TMPDIR:-/tmp}"
mkdir -p lauf/arbeit_start/tmp lauf/arbeit_start/daten lauf/arbeit_start/einstellungen lauf/arbeit_start/cache
export TMPDIR="$PWD/lauf/arbeit_start/tmp" TMP="$PWD/lauf/arbeit_start/tmp" TEMP="$PWD/lauf/arbeit_start/tmp"
export XDG_DATA_HOME="$PWD/lauf/arbeit_start/daten" XDG_CONFIG_HOME="$PWD/lauf/arbeit_start/einstellungen" XDG_CACHE_HOME="$PWD/lauf/arbeit_start/cache"
export PYTHONPYCACHEPREFIX="$PWD/lauf/arbeit_start/pycache"
FREI=$(df -k . | awk 'NR==2 {print int($4/1048576)}')
echo "Trainingsordner: $PWD (frei auf diesem Laufwerk: ${FREI} GB)"

GODOT_VERSION="4.7.2-stable"
if [ -z "$GODOT" ]; then
  GODOT="$PWD/godot/Godot.app/Contents/MacOS/Godot"
  if [ ! -x "$GODOT" ]; then
    echo "Lade Godot $GODOT_VERSION (einmalig, etwa 130 MB) ..."
    mkdir -p godot
    if ! curl -L --fail -o godot/godot.zip "https://github.com/godotengine/godot/releases/download/$GODOT_VERSION/Godot_v${GODOT_VERSION}_macos.universal.zip"; then
      echo "Der Download hat nicht geklappt. Bitte Godot $GODOT_VERSION für macOS von godotengine.org laden"
      echo "und Godot.app in den Ordner 'godot' neben diese Datei legen."
      read -r -p "Eingabetaste zum Schließen ..." _
      exit 1
    fi
    (cd godot && unzip -q -o godot.zip && rm godot.zip)
    xattr -dr com.apple.quarantine godot/Godot.app 2>/dev/null
  fi
fi
if [ ! -x "$GODOT" ]; then
  echo "Godot nicht gefunden: $GODOT"
  read -r -p "Eingabetaste zum Schließen ..." _
  exit 1
fi

if [ ! -d spiel/.godot/imported ]; then
  echo "Bereite das Spiel vor (einmalig, dauert ein paar Minuten) ..."
  "$GODOT" --headless --path spiel --import >/dev/null 2>&1
  "$GODOT" --headless --path spiel --import >/dev/null 2>&1
fi

echo "Starte die Oberfläche. Sie öffnet sich gleich im Browser: http://127.0.0.1:8765/"
# Der Mac soll während des Trainings nicht einschlafen (caffeinate gehört zu macOS)
if command -v caffeinate >/dev/null 2>&1; then
  exec caffeinate -i python3 training/server.py --godot "$GODOT" --open
fi
exec python3 training/server.py --godot "$GODOT" --open
