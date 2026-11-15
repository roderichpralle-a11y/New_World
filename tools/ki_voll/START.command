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
exec python3 training/server.py --godot "$GODOT" --start --open
