# Insel-Siedler – Design und Architektur

Gemütliches Aufbauspiel in Pixel-Grafik (Godot 4.7, GDScript, Compatibility-Renderer,
Web-Export ohne Threads). Spielbar im Browser auf PC und Handy.

## Spielregeln (Etappe 1)

- Start: eine zufällige Insel aus einem Seed, Lagerfeuer und eine Hütte, zwei Siedler
  (Lena, Jonas) mit unterschiedlichen Fähigkeiten.
- **Fähigkeiten** `holz`, `stein`, `nahrung`, `bauen` (Stufe 1–10). Arbeitstempo =
  `0.6 + 0.08 * Stufe`. Jede Arbeit bringt Erfahrung, Stufe steigt nach
  `skill_xp_per_level * Stufe` Punkten.
- **Berufe** (`data/jobs.json`): Frei, Holzfäller, Steinmetz, Sammler, Fischer, Bauer,
  Baumeister. Freie Siedler bauen zuerst, sammeln dann Nahrung wenn knapp, sonst das
  knappste Material. Spezialisten helfen aus, wenn ihr Rohstoff voll ist.
- **Hunger** 0–100 (100 = satt), sinkt um `hunger_per_day`. Unter `eat_below` gehen
  Siedler zum nächsten Lager essen (je Einheit `nutrition` Punkte). Bei 0 sinkt die
  Gesundheit, bei 0 Gesundheit stirbt der Siedler. Kinder essen die Hälfte.
- **Nachwuchs**: nur wenn Wohnplätze frei sind (Hütten), Nahrung ≥
  `birth_food_per_person * Bevölkerung`, ein nicht verwandtes Paar existiert (Eltern,
  Kinder, Geschwister, Großeltern ausgeschlossen, Mutter ≤ `fertile_max_age`) und die
  Mutter keine Pause (`birth_cooldown`) hat. Kinder werden mit `adult_age` Tagen
  erwachsen und erben gemischte Talente.
- **Schiffbrüchige**: Gibt es kein mögliches Paar mehr, wird gelegentlich ein neuer
  Siedler angespült (`newcomer_chance`), damit eine Familie nicht ausstirbt.
- **Alter**: Siedler sterben zwischen `old_age_min` und `old_age_max` Tagen.
- **Tag und Nacht**: ein Tag dauert `day_length` Sekunden, die Nacht läuft
  `night_speedup`-mal schneller. Nachts schlafen alle (in ihrer Hütte oder am Feuer).
- **Lager**: jede Ressource hat dieselbe Obergrenze = Summe `storage` aller Lager.
- **Verloren**: Stirbt der letzte Siedler, ist die Insel verloren (Spielstand wird gelöscht).
- Speichern: automatisch alle `autosave_seconds` Sekunden, beim Verlassen und über das Menü
  (`user://savegame.json`, im Browser in IndexedDB).

## Entwicklungsbaum und Wirtschaft (Etappe 2)

- **Forschung** (`data/techs.json`): 27 Forschungen in 5 Stufen (`_tiers`). Jede hat
  `tier`, `requires` (andere Forschungen), `cost` (Waren, beim ersten Start bezahlt),
  `points`, `effects`, optional `icon` und `soon` (sichtbar, aber erst in Etappe 3
  erforschbar: `schiffsbau`, `waffenkunde`). Es läuft immer genau eine Forschung
  (`Game.research = {current, progress, done, paid}`, wird gespeichert).
- **Forscher** (Beruf, Fähigkeit `wissen`) arbeiten an Gebäuden mit `research`
  {factor, slots}: Lagerfeuer 0.5, Schreibstube 1.0, Bibliothek 1.8. Je Arbeitsgang
  `research_per_work * factor * Fähigkeit * eff("research")` Punkte, dazu
  `passive_research_per_day` ohne Forscher.
- **Effekte** werden aus allen erforschten Forschungen summiert: `Game.eff(key)` =
  1 + Summe, `Game.eff_add(key)` = Summe. Schlüssel: `gather_<rohstoff>`, `work`,
  `build`, `carry`, `walk`, `storage`, `farm_yield`, `farm_speed`, `life`, `heal`, `research`.
- **Freischalten**: Gebäude mit `requires: <forschung>` sind vorher im Bau-Menü gesperrt.
- **Werkstätten** (`production` {job, inputs, outputs, time, skill, verb, tool?, smoke?}):
  `job` ist `kueche` (Beruf Koch), `handwerk` (Handwerker) oder `stein` (Steinmetz,
  über Ziel `prod:stein`). Ein Arbeiter nimmt die Zutaten aus dem Lager, arbeitet
  `time / Tempo` Sekunden und trägt die erste Ware zum Lager (weitere direkt ins Lager).
  Gewählt wird die Werkstatt mit der knappsten Ware. Werkstätten lassen sich anhalten.
- **Ketten**: Holz → Bretter; Lehm (+Holz) → Ziegel; Holz → Kohle; Erz + Kohle → Eisen;
  Eisen + Bretter → Werkzeug; Getreide → Mehl (+Holz) → Brot; Fisch (+Holz) → Räucherfisch;
  Getreide → Eier; Obstgarten → Äpfel. Steinbruch und Mine liefern endlos Stein und Erz.
- **Wohnen**: Hütte 2 → Holzhaus 4 → Steinhaus 6. `upgrade` im Gebäude erlaubt den
  Ausbau an Ort und Stelle (wird zur Baustelle, Bewohner ziehen solange aus).
- **Abwechslung**: ab `variety_min` Nahrungssorten im Lager ist die Geburtenchance
  `variety_birth_bonus`-mal höher.
- Grafiken der neuen Gebäude liegen in `assets/sprites/buildings.png` (Zellen 64x64,
  `Data.BUILDING_CELLS`), Obstgarten-Kacheln in `objects.png` (`orchard0..3`).
- Für Etappe 3: `schiffsbau` und `waffenkunde` stehen am Ende des Baums mit `soon: true`.
  Werft und Wachturm als Gebäude mit `requires` anlegen und `soon` entfernen.

## Ordner

| Pfad | Inhalt |
|---|---|
| `data/*.json` | Alle Spielwerte (Ressourcen, Rohstoffquellen, Gebäude, Berufe, Balance, Namen) |
| `scripts/autoload/data.gd` | Lädt JSON, Sprite-Regionen (`OBJECT_REGIONS`), Icons |
| `scripts/autoload/game.gd` | Zeit, Vorräte, Nachwuchs, Abstammung, Forschung und Effekte, Speichern/Laden |
| `scripts/world/island_gen.gd` | Inselgenerator (Seed → Gelände + Rohstoffe) |
| `scripts/world/world.gd` | Tilemaps, Wegfindung (AStarGrid2D), Entitäten, Bauen, Effekte, Tag/Nacht |
| `scripts/world/game_camera.gd` | Ziehen, Zoom (Mausrad, zwei Finger), Tippen |
| `scripts/entities/*.gd` | `Settler` (KI), `Building`, `ResNode` |
| `scripts/ui/hud.gd`, `ui_theme.gd` | Oberfläche im Code gebaut, Pixel-Theme |
| `tools/gen_art.py` | Erzeugt alle Grafiken in `assets/sprites/` (Pillow) |

## Koordinaten

- Logik-Raster = Eckpunkte des Geländes. Zelle `(x,y)` liegt bei Weltposition `(x*16, y*16)`.
- Gelände wird im **Dual-Grid** gezeichnet: Kachel `(x,y)` liegt zwischen den Eckpunkten
  `(x..x+1, y..y+1)` und wählt aus 16 Eckmasken (Bit 1 oben links, 2 oben rechts,
  4 unten links, 8 unten rechts). Drei Ebenen: Wasser (animiert), Sand, Gras.
- Gebäude: `cell` = obere linke Zelle, Größe aus `size`. Eingang = Zelle mittig unter
  der Grundfläche. `ground`-Gebäude (Felder) sind begehbar, alle anderen blockieren.

## Datenformate

- **resources.json**: `{id: {name, icon, category: "material"|"food", nutrition?, order}}`.
  Alles mit `category: food` wird gegessen.
- **nodes.json**: Rohstoffquellen. `yield`, `capacity`, `work_time`, `skill`, `terrain`
  (`grass`, `land`, `shore_water`), `solid`, `regrow_days`, `on_empty` (`regrow`|`remove`),
  `sprites` {full: [...], empty, low, growing}.
- **buildings.json**: `size`, `sprite`, `buildable`, `cost`, `work`, optional `housing`,
  `storage`, `light`, `ground`, `farm` {yield, amount, grow_days, sow_time, harvest_time}.
- **jobs.json**: `skill`, `tool` (Sprite in tools.png), `targets` (Knotentypen oder
  `farm`/`construction`).
- **balance.json**: alle Zahlen für Zeit, Hunger, Nachwuchs, Lager, Karte.
- **Spielstand**: `{version, seed, time_days, stock, next_id, stats, lineage,
  world: {nodes: [[type,x,y,amount,regrow_at,variant]], buildings: [...], settlers: [...], graves}}`.
  Das Gelände wird aus dem Seed neu erzeugt, nur Rohstoffe/Gebäude/Siedler werden gespeichert.

## Erweitern (spätere Etappen)

- Neue Ressource: Eintrag in `resources.json` und Icon in `tools/gen_art.py` (`ICONS`).
- Neue Rohstoffquelle: Eintrag in `nodes.json`, Sprite-Region in `Data.OBJECT_REGIONS`,
  Platzierung in `IslandGen._place_nodes`.
- Neues Gebäude: Eintrag in `buildings.json` (mit `category` und optional `requires`)
  plus Sprite in `tools/gen_art.py` (`gen_buildings2`, Reihenfolge = `Data.BUILDING_CELLS`).
- Neue Forschung: Eintrag in `techs.json`; neue Effekt-Schlüssel dort auswerten, wo sie wirken.
- Weitere Inseln: `IslandGen.generate(seed, size, opts)` ist rein datenbasiert;
  `World` hält derzeit genau eine Insel.

## Testen

```
godot --headless -- --autotest=120 --scale=10 --build=1     # Simulation mit Bericht
godot --headless -- --autotest=400 --scale=10 --build=1 --research=1   # forscht automatisch
godot --headless -- --autotest=60 --scale=10 --prodtest=1  # alle Werkstätten, alles erforscht
# Bildschirmfoto-Optionen: --panel=research|build|stock, --selectb=<typ>, --look=1
xvfb-run godot --rendering-driver opengl3 -- --autotest=20 --shot=/tmp/bild.png
godot --headless --export-release "Web" build/web/index.html
```

Bei jedem Push auf `main` baut GitHub Actions die Web-Version und legt sie auf den
Branch `gh-pages` (GitHub Pages).
