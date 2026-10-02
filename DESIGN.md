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
  `night_speedup`-mal (5) schneller. Nachts schlafen alle (in ihrer Hütte oder am Feuer).
- **Lager**: Lager haben Stauraum (`storage` in buildings.json: Lagerfeuer 200, Lagerhaus
  400, Großes Lager 1000, mal Forschungsbonus `storage`), jede Ware eine Größe (`size` in
  resources.json, `Data.good_size`; Boote 0 = brauchen keinen Lagerraum). Belegt ist Menge
  mal Größe. Der Spieler legt im Lager-Fenster je Ware eine Höchstmenge fest
  (`Game.store_limits`, fehlt = "frei"); diese Menge ist reserviert, freie Waren teilen sich den
  Rest. `Game.space_for(id)` sagt, wie viel noch passt; alles, was ins Lager kommt, läuft über
  `Game.add_stock`. Sammler, Bauern und Werkstätten arbeiten nicht, wenn für ihre Ware kein
  Platz ist. Eine Höchstmenge lässt sich nur so hoch setzen, wie Raum da ist
  (`Game.max_limit`). Liegt nach dem Herabsetzen mehr da, kann der Überschuss weggeworfen werden
  (`Game.discard_excess`), sonst bleibt er liegen und die Ware wächst nicht weiter. Alte
  Spielstände ohne `store_limits` laden mit allen Waren auf "frei".
  Die Funktionen nehmen schon eine Insel `w` an und lesen Vorrat und Grenzen über
  `Game._stock_of(w)` / `Game._limits_of(w)`; für getrennte Inselvorräte ändern sich nur diese
  und `storage_volume(w)`.
- **Abliefern**: Träger wählen mit `World.delivery_storage` unter allen Lagern, die höchstens
  `delivery_spread` Zellen weiter weg sind als das nächste, das mit den wenigsten
  Ablieferungen je Lagerplatz. So bleibt auch das Lagerfeuer neben einem Lagerhaus in Gebrauch.
  Abstände zählen zur nächsten Zelle des Gebäudes (`Building.dist_sq`).
- **Verloren**: Stirbt auf einer Insel der letzte Siedler, ist sie für immer verloren. Sind alle
  Inseln verloren und niemand mehr auf See, ist das Spiel vorbei (Spielstand wird gelöscht).
- Speichern: automatisch alle `autosave_seconds` Sekunden, beim Verlassen und über das Menü
  (`user://savegame.json`, im Browser in IndexedDB).

## Entwicklungsbaum und Wirtschaft (Etappe 2)

- **Forschung** (`data/techs.json`): 34 Forschungen in 6 Stufen (`_tiers`). Jede hat
  `tier`, `requires` (andere Forschungen), `cost` (Waren, beim ersten Start bezahlt),
  `points`, `effects`, optional `icon` und `soon` (sichtbar, aber noch nicht erforschbar;
  derzeit von keiner Forschung benutzt). Es läuft immer genau eine Forschung
  (`Game.research = {current, progress, done, paid}`, wird gespeichert).
- **Forscher** (Beruf, Fähigkeit `wissen`) arbeiten an Gebäuden mit `research`
  {factor, slots}: Lagerfeuer 0.5, Schreibstube 1.0, Bibliothek 1.8. Je Arbeitsgang
  `research_per_work * factor * Fähigkeit * eff("research")` Punkte, dazu
  `passive_research_per_day` ohne Forscher.
- **Effekte** werden aus allen erforschten Forschungen summiert: `Game.eff(key)` =
  1 + Summe, `Game.eff_add(key)` = Summe. Schlüssel: `gather_<rohstoff>`, `work`,
  `build`, `carry`, `walk`, `storage`, `farm_yield`, `farm_speed`, `life`, `heal`, `research`,
  ab Etappe 3 auch `weapons`, `hunt`, `tower`, `hunger` (negativ = langsamer hungrig),
  `ship_speed`, `ship_capacity`, `explore`, `birth`. Gebäude mit `effects` (Leuchtturm, Denkmal)
  zählen einmal je Art, solange eines fertig auf irgendeiner Insel steht (`Game.refresh_effects`).
- **Freischalten**: Gebäude mit `requires: <forschung>` sind vorher im Bau-Menü gesperrt.
- **Werkstätten** (`production` {job, inputs, outputs, time, skill, verb, tool?, smoke?}):
  `job` ist `kueche` (Beruf Koch), `handwerk` (Handwerker) oder `stein` (Steinmetz,
  über Ziel `prod:stein`). Ein Arbeiter nimmt die Zutaten aus dem Lager, arbeitet
  `time / Tempo` Sekunden und trägt die erste Ware zum Lager (weitere direkt ins Lager).
  Gewählt wird die Werkstatt mit der knappsten Ware. Werkstätten lassen sich anhalten.
- **Ketten**: Holz → Bretter; Lehm (+Holz) → Ziegel; Holz → Kohle; Erz + Kohle → Eisen;
  Eisen + Bretter → Werkzeug; Getreide → Mehl (+Holz) → Brot; Fisch (+Holz) → Räucherfisch;
  Getreide → Eier; Obstgarten → Äpfel. Steinbruch und Mine liefern endlos Stein und Erz.
- **Schreibstube in Stufen**: Schreibstube (x1.0, 2 Forscher) → Große Schreibstube (x1.4, 3)
  → Gelehrtenstube (x1.9, 3, Forschung Gelehrsamkeit) → Akademie (x2.6, 4, Schmiedekunst),
  jeweils per `upgrade` im Infofenster und mit hohen Kosten. Ausbau-Typen haben
  `buildable: false` und `base: "schreibstube"` (zählt für Ziele wie die Grundform).
- **Wohnen**: Hütte 2 → Holzhaus 4 → Steinhaus 6. `upgrade` im Gebäude erlaubt den
  Ausbau an Ort und Stelle (wird zur Baustelle, Bewohner ziehen solange aus).
- **Abwechslung**: ab `variety_min` Nahrungssorten im Lager ist die Geburtenchance
  `variety_birth_bonus`-mal höher.
- **Bessere Häuser**: Gebäude mit `birth_bonus` (Holzhaus 1.4, Steinhaus 1.8) vervielfachen die
  Geburtenchance, wenn die Mutter dort wohnt (`Game.home_birth_bonus`). `World.assign_homes` belegt
  bessere Häuser zuerst und lässt Siedler (nicht schlafend) in ein besseres Haus umziehen, sobald dort
  Platz ist.
- **Schule** (Forschung Unterricht, Stufe III; `school` {growth, slots}): jede fertige Schule nimmt
  `slots` Kinder der Insel auf (die ältesten zuerst, `World.school_of`). Schulkinder altern
  `growth`-mal so schnell (werden also schneller erwachsen) und halten sich tagsüber an der Schule auf.
- Grafiken der neuen Gebäude liegen in `assets/sprites/buildings.png` (Zellen 64x64,
  `Data.BUILDING_CELLS`), Obstgarten-Kacheln in `objects.png` (`orchard0..3`).

## Seefahrt, neue Inseln und wilde Tiere (Etappe 3)

- **Mehrere Inseln**: Autoload `Sea` hält alle Inseln (`Sea.islands`, Meta-Daten) und für jede
  besiedelte Insel eine eigene `World` (`Sea.worlds`). Nur die aktive Insel `Game.world` ist
  sichtbar, die anderen laufen unsichtbar weiter. **Alle Inseln teilen sich die Vorräte**
  (`Game.stock`, Lagerplatz = alle Lager aller Inseln). Wohnplätze, Nachwuchs und
  Schiffbrüchige zählen je Insel. Meldungen von anderen Inseln tragen den Inselnamen
  (`Game.notify_at`).
- **Werft** (`coast: true`, muss bis 2 Felder ans Wasser): Handwerker bauen Boote (Ware `boot`).
  **Seekarte** (Knopf „Inseln“, `scripts/ui/sea_panel.gd`): „Neue Insel suchen“ schickt ein Boot
  los (kommt zurück), „Siedler schicken“ verbraucht ein Boot und bringt bis zu
  `ship_base_capacity` (+ `ship_capacity`) Siedler hinüber. Mindestens einer bleibt zurück.
  Reisezeit `voyage_days_base + voyage_days_per_dist * Entfernung` geteilt durch `eff(ship_speed)`.
  Die Karte zoomt (Mausrad, zwei Finger, Knöpfe „-“ „+“ „Alle“, 1x bis 8x um den Zeiger) und
  lässt sich gezoomt ziehen; ein Klick ohne Ziehen wählt eine Insel. Testhilfe `--panel=sea --seazoom=N`.
- **Inselarten** (`data/islands.json`): `heimat` (Etappe 1, unverändert), `tropen` (Palmeninsel:
  Kokospalmen, viel Fisch, Wildschweine), `wald` (Waldinsel: Nadelwald, Pilze, Wölfe), `berg`
  (Felseninsel: Erz- und Goldadern, Bären). Insel 1–3 sind in dieser Reihenfolge, danach
  zufällig; je weiter draußen, desto mehr Tierbauten (`Sea.make_island`, endlos).
  Der Generator nimmt den Eintrag als `opts.biome` (Grasgrenze, Rohstoff-Wahrscheinlichkeiten,
  garantierter Ring um das Lager, `_dens` = Tierbauten). Jede Inselart färbt das Gras (`tint`).
- **Neue Insel besiedeln**: beim ersten Boot entsteht die World mit Lagerfeuer in der Mitte;
  die Siedler landen am Strand (`World.landing_cell`), ein Boot liegt kurz am Ufer.
- **Wilde Tiere** (`data/animals.json`, `scripts/entities/animal.gd`): Wolf, Wildschwein, Bär.
  Tierbauten sind Rohstoffquellen mit `spawns` und `den_cap`; alle `den_spawn_interval` Tage
  kommt mit `den_spawn_chance` ein Tier nach (nicht, wenn Siedler danebenstehen). Tiere streifen
  um ihren Bau (`leash`), greifen sichtbare Siedler in `aggro` (nachts `night_aggro`) Feldern an
  und verfolgen Angreifer. Wildschweine beißen einmal und lassen dann ab. Am Lagerfeuer
  (3,5 Felder) und in Gebäuden sind Siedler sicher.
- **Siedler bei Gefahr**: Jäger kämpfen, alle anderen fliehen ins nächste Haus, Lager oder
  Wachturm (`refuge_radius`) und verstecken sich, bis die Tiere weg sind, sonst ans Lagerfeuer.
  Neue Fähigkeit `jagd`. Beruf **Jäger** (braucht Waffenkunde): jagt Tiere in der Nähe, holt
  Fleisch von erlegten Tieren (`beute`, verdirbt nach `decay_days`) und räumt Bauten aus
  (gibt Felle, danach kommen keine Tiere mehr nach). Felle kommen beim Erlegen direkt ins Lager.
- **Wachturm** (`defense` {range, damage, interval}): schießt Pfeile auf Tiere in Reichweite.
- **Neue Waren**: Fleisch, Kokosnüsse, Pilze (Nahrung), Felle, Gold, Boote.
- **Stufe VI „Neue Welt“**: Navigation, Jagdkunst, Befestigung, Warme Kleidung, Leuchtfeuer
  (Leuchtturm: Erkunden doppelt so schnell), Goldenes Zeitalter (Denkmal: mehr Kinder, längeres
  Leben). Gold gibt es nur auf Felseninseln.
- Grafiken: `assets/sprites/objects2.png` (`Data.OBJECT2_REGIONS`: Palmen, Höhle, Pilze, Adern,
  Bauten, Beute, Pfeil, Boot), `animals.png` (Zellen 24x24, Zeile je Tier, Spalten 0–3 Laufen,
  4 Angriff), Gebäude ab Zelle 20 in `buildings.png` (Schule Zelle 25, `school()` in `gen_art.py`). Gezeichnet von `tools/gen_art_sea.py`.

## Feinschliff (Etappe 4)

**Siedlerliste:** fast bildschirmfüllend mit kompakten Zeilen; Spaltenköpfe Name, Alter, Beruf, Satt sortieren (nochmal tippen dreht um), Filter für Beruf, Erwachsene/Kinder, Nur Hungrige (unter 30 % satt) und, bei mehreren Inseln, Diese Insel/Alle Inseln. Testaufruf: `--crowd=24 --panel=settlers [--sfilter=1]`.

**Schrift:** Pixelify Sans mit eigenen 5x7-Ziffern (die Originalziffern 2/5/6/8/9 waren klein kaum zu unterscheiden). Neu erzeugen mit `python3 tools/gen_font_digits.py` (liest `tools/fonts_src/`, schreibt `assets/fonts/`).

- **Ton** (Autoload `Sound`, `scripts/autoload/sound.gd`): drei Musikstücke (`tag` Heimatinsel,
  `nacht`, `insel` fremde Inseln) mit Überblendung, das Stück läuft an der alten Stelle weiter.
  Meeresrauschen mit Vögeln (Tag) oder Grillen (Nacht). Effekte über `Sound.play(name)`,
  `Sound.play_on(name, world)` (nur sichtbare Insel) und `Sound.play_at(name, world, pos)`
  (nur im Bild, leiser am Rand). Jeder Knopf klickt (Meta `silent` schaltet das ab).
  Busse `Musik` und `Effekte` stehen in `default_bus_layout.tres` (im Browser nötig: zur Laufzeit
  angelegte Busse bleiben dort stumm), Lautstärken im Menü, gespeichert in `user://settings.cfg`.
  Alle Klänge erzeugt `tools/gen_audio.py` (Ausgabe `assets/audio/`). Gebäude können mit
  `sound` einen eigenen Werkstatt-Klang haben, Tiere mit `sound` ihren Ruf.
- **Einführung und Ziele** (`data/goals.json`, `scripts/ui/goal_card.gd`): sieben Schritte mit
  Zeigerpfeil, danach feste Ziele mit Belohnungen und endlos erzeugte Ziele (Bevölkerung, Inseln,
  Geburten). Zustand `Game.goals {tut, ms}` im Spielstand; ältere Spielstände überspringen die
  Einführung und holen erreichte Ziele still nach. `Game.player_action(kind, what)` meldet
  Spieleraktionen. Statistik `kills` zählt erlegte Tiere.
- **Bauen**: mit der Maus baut ein Klick sofort (Rechtsklick oder Esc bricht ab), am Handy tippt man
  den Platz an und bestätigt mit „Hier bauen“.
- **Verschieben**: Knopf „Verschieben“ im Infofenster jedes Gebäudes (auch Baustellen, Felder und
  Lagerfeuer). Danach läuft dieselbe Platzierung wie beim Bauen (`World.start_move`, Geist mit
  `can_place(type, cell, ignore)`, eigene alte Felder gelten als frei); „Hier hinstellen“ am Handy.
  Kostenlos und sofort (`World.move_building`): Lager, Bewohner, Baufortschritt, Feldstand und
  Werkstatt bleiben; wer drinnen schläft oder sich versteckt, zieht mit; Siedler auf dem Weg zum
  alten Platz planen neu (laufende Arbeit wird zu Ende gebracht). Test: `--movetest=<Sekunden>`,
  Bildschirmfoto `--moveb=<typ>`.
- **Handy**: Karte gleitet nach dem Wischen nach, zwei Finger zoomen und schieben, größerer
  Fangradius beim Tippen, schmale Leiste mit Symbol über Text, gewählte Objekte rücken über das
  Infofenster, Vollbild-Knopf im Menü.

## Ordner

| Pfad | Inhalt |
|---|---|
| `data/*.json` | Alle Spielwerte (Ressourcen, Rohstoffquellen, Gebäude, Berufe, Balance, Namen) |
| `scripts/autoload/data.gd` | Lädt JSON, Sprite-Regionen (`OBJECT_REGIONS`), Icons |
| `scripts/autoload/game.gd` | Zeit, Vorräte, Nachwuchs, Abstammung, Forschung und Effekte, Speichern/Laden |
| `scripts/autoload/sea.gd` | Inseln, Welten je Insel, Schiffsreisen, Inselwechsel |
| `scripts/world/island_gen.gd` | Inselgenerator (Seed → Gelände + Rohstoffe) |
| `scripts/world/world.gd` | Tilemaps, Wegfindung (AStarGrid2D), Entitäten, Bauen, Effekte, Tag/Nacht |
| `scripts/world/game_camera.gd` | Ziehen, Zoom (Mausrad, zwei Finger), Tippen |
| `scripts/entities/*.gd` | `Settler` (KI), `Building`, `ResNode`, `Animal` |
| `scripts/ui/hud.gd`, `ui_theme.gd`, `sea_panel.gd` | Oberfläche im Code gebaut, Pixel-Theme, Seekarte |
| `tools/gen_art.py`, `gen_art_sea.py` | Erzeugen alle Grafiken in `assets/sprites/` (Pillow) |

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
  `farm`/`construction`), optional `requires` (Forschung).
- **islands.json**: Inselarten, siehe Etappe 3. **animals.json**: `hp`, `damage`, `speed`,
  `aggro`, `night_aggro`, `attack_time`, `meat`, `felle`, `leash`, `row` (Zeile in animals.png).
- **balance.json**: alle Zahlen für Zeit, Hunger, Nachwuchs, Lager, Karte.
- **Spielstand** (Version 2): `{version, seed, time_days, stock, next_id, stats, lineage, research,
  islands: [{id, name, biome, seed, size, pos, state, found_day, dens, world?}], active, voyages}`
  mit `world: {nodes: [[type,x,y,amount,regrow_at,variant]], buildings: [...], settlers: [...],
  graves, animals: [[type,x,y,hp,home_x,home_y]]}`. Version 1 (nur `world`) wird beim Laden als
  Heimatinsel übernommen. Das Gelände wird aus dem Seed neu erzeugt, nur Rohstoffe, Gebäude,
  Siedler und Tiere werden gespeichert.

## Erweitern (spätere Etappen)

- Neue Ressource: Eintrag in `resources.json` und Icon in `tools/gen_art.py` (`ICONS`).
- Neue Rohstoffquelle: Eintrag in `nodes.json`, Sprite-Region in `Data.OBJECT_REGIONS`,
  Platzierung in `IslandGen._place_nodes`.
- Neues Gebäude: Eintrag in `buildings.json` (mit `category` und optional `requires`)
  plus Sprite in `tools/gen_art.py` (`gen_buildings2`, Reihenfolge = `Data.BUILDING_CELLS`).
- Neue Forschung: Eintrag in `techs.json`; neue Effekt-Schlüssel dort auswerten, wo sie wirken.
- Neue Inselart: Eintrag in `islands.json` und in `Sea.make_island` in die Auswahl nehmen.
- Neues Tier: Eintrag in `animals.json`, Zeile in `gen_art_sea.gen_animals`, Bau in `nodes.json`
  mit `spawns`.

## Testen

```
godot --headless -- --autotest=120 --scale=10 --build=1     # Simulation mit Bericht
godot --headless -- --autotest=400 --scale=10 --build=1 --research=1   # forscht automatisch
godot --headless -- --autotest=60 --scale=10 --prodtest=1  # alle Werkstätten, alles erforscht
godot --headless -- --autotest=120 --scale=10 --tuttest=1  # spielt die Einführung durch
godot --headless -- --autotest=150 --scale=10 --schooltest=1  # Steinhaus und Schule: Geburten, Schulkinder
godot --headless -- --autotest=300 --scale=10 --seatest=1  # Werft, drei Inseln entdecken und besiedeln
#   dazu --weak=1: ohne Waffenkunde (Tiere gefährlicher), Bildschirmfoto: --island=<id>, --panel=sea
# Bildschirmfoto-Optionen: --panel=research|build|stock, --selectb=<typ>, --look=1
xvfb-run godot --rendering-driver opengl3 -- --autotest=20 --shot=/tmp/bild.png
godot --headless --export-release "Web" build/web/index.html
```

Bei jedem Push auf `main` baut GitHub Actions die Web-Version und legt sie auf den
Branch `gh-pages` (GitHub Pages).
