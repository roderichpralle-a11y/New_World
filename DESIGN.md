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
  Siedler zum nächsten Lager essen (je Einheit `nutrition` Punkte, siehe „Nahrung, Vitamine“). Bei 0 sinkt die
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
  `night_speedup`-mal (5) schneller. Wann die Nacht beginnt, hängt von der Jahreszeit ab. Nachts schlafen alle (in ihrer Hütte oder am Feuer).
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
  sichtbar, die anderen laufen unsichtbar weiter. **Jede Insel hat ihr eigenes Lager**
  (`World.stock`; Lagerplatz zählt nur die Lager dieser Insel). Alle Lager-Funktionen in `Game`
  (`amount`, `add_stock`, `take_stock`, `space_for`, `can_afford`, `storage_capacity`,
  `total_food`, `eat_one`, `food_variety`) nehmen als letzten Parameter die Insel; ohne Angabe gilt
  die aktive Insel. Siedler und Gebäude geben immer ihre eigene `world` mit. Forschungskosten
  zahlt die aktive Insel, Ziele zählen `Game.amount_all` über alle Inseln. Wohnplätze, Nachwuchs und
  Schiffbrüchige zählen je Insel. Meldungen von anderen Inseln tragen den Inselnamen
  (`Game.notify_at`).
- **Schiffe** (`data/ships.json`, Logik in `Sea`): Ruderboot (Größe 1, 1 Seemann, Laderaum 40),
  Kogge (2, 2 Seeleute, 200, langsam), Schnellsegler (2, 3 Seeleute, 80, fast doppelt so schnell),
  Galeone (3, 5 Seeleute, 500). Die **Werft** (`ships: true`) baut das im Gebäudefenster gewählte
  Schiff (`Building.ship_choice`, Bauplan aus `ships.json`, `ship_wip` merkt das bezahlte
  Schiff). Fertige Schiffe entstehen als Ware (`boot`, `kogge`, ...; Größe 0, nicht im
  Lagerfenster) und `Sea._ship_tick_all` macht daraus sofort ein Schiff in `Sea.ships`:
  `{id, type, name, home, at, state: dock|load|sea, until, crew: [Siedler-IDs], cargo, route,
  leg, paused, note}`. Alte Spielstände: ihre Ware `boot` wird so zu Ruderbooten.
- **Besatzung**: Beruf **Seemann** (nach Schiffsbau; an Land angelt er). `Sea.fill_crew` nimmt
  freie Seeleute der Insel, „Seemann anheuern“ (`hire_sailor`) macht zuerst Freie zu Seeleuten.
  Ohne volle Besatzung legt kein Schiff ab; die letzten Siedler einer Insel bleiben an Land.
  Beim Ablegen verlassen Besatzung und Fahrgäste die Insel (Reise `crew`/`settlers`), beim
  Anlegen gehen sie am Hafen an Land.
- **Häfen** (`harbor: {level, berths, rate, goods?, goods_rate?}`): Werft (1 Platz klein), Anlegesteg
  (2 klein), Hafen (Navigation, 2 mittel), Großer Hafen (Seehandel, 3 groß/groß/mittel), Holzkai,
  Erzkai, Proviantkai (Seehandel, je 1 mittel, ihre Waren 3-mal so schnell). Die Zahl der Schiffe
  einer Insel ist durch ihre Liegeplätze begrenzt (`Sea.free_berth`, Heimathafen `home`);
  ohne freien Platz baut die Werft nicht. Ein Schiff der Größe 2 läuft nur Inseln mit Hafen
  (Stufe 2) an, eine Galeone nur Große Häfen; Ruderboote landen überall am Strand
  (`Sea.can_visit`). Laden kostet Zeit: Stauraum je Stunde (`Sea.load_rate`, Strand 15).
- **Fahrten**: Seekarte „Schiff hierher schicken“ (Siedler und Waren, Schiff bleibt am Ziel und lädt
  dort ab), „Neue Insel suchen“ (schnellstes freies Schiff, kommt zurück), **Routen** (Reiter
  „Schiffe“): bis 6 Halte; an jedem Halt lädt das Schiff alles ab, was dort nicht geladen wird,
  und lädt bis zur eingestellten Menge. Fahrzeit `(voyage_days_base + voyage_days_per_dist *
  Entfernung) / (eff(ship_speed) * Tempo des Schiffs) * Seasons.sail_mult()`. Liegende Schiffe
  zeigt `World.sync_ships` im Wasser vor dem Hafen. Forschung **Seehandel** (Stufe VI).
- **Seekarte** (Knopf „Inseln“, `scripts/ui/sea_panel.gd`): Reiter Inseln und Schiffe, Ansichten
  `island`, `send`, `ships`, `ship`, `stop`. Die Karte zoomt (Mausrad, zwei Finger, Knöpfe „-“ „+“
  „Alle“, 1x bis 8x um den Zeiger) und lässt sich gezoomt ziehen; ein Klick ohne Ziehen wählt
  eine Insel. Testhilfen `--panel=sea --seazoom=N --seaview=ships|ship|stop|send`, `--seatest
  --tradetest` (Hafen, Kogge auf Route).
- **Inselarten** (`data/islands.json`): `heimat` (Etappe 1, unverändert), `tropen` (Palmeninsel:
  Kokospalmen, viel Fisch, Wildschweine), `wald` (Waldinsel: Nadelwald, Pilze, Wölfe), `berg`
  (Felseninsel: Erz- und Goldadern, Bären). Insel 1–3 sind in dieser Reihenfolge, danach
  zufällig; je weiter draußen, desto mehr Tierbauten (`Sea.make_island`, endlos).
  Der Generator nimmt den Eintrag als `opts.biome` (Grasgrenze, Rohstoff-Wahrscheinlichkeiten,
  garantierter Ring um das Lager, `_dens` = Tierbauten). Jede Inselart färbt das Gras (`tint`).
- **Neue Insel besiedeln**: beim ersten Boot entsteht die World mit Lagerfeuer in der Mitte;
  die Siedler landen am Strand (`World.landing_cell`), ein Boot liegt kurz am Ufer.
- **Wilde Tiere** (`data/animals.json`, `scripts/entities/animal.gd`): Wolf, Wildschwein, Bär.
  Tierbauten sind Rohstoffquellen mit `spawns` und `den_cap` (Tiere zu Beginn). Tiere streifen
  um ihren Bau (`leash`), greifen sichtbare Siedler in `aggro` (nachts `night_aggro`) Feldern an
  und verfolgen Angreifer. Wildschweine beißen einmal und lassen dann ab. Am Lagerfeuer
  (3,5 Felder) und in Gebäuden sind Siedler sicher.
- **Tierbestand im Gleichgewicht** (`World._process_dens`, alle `animal_tick_days`):
  - *Futter*: jedes Tier hat `food` (1 satt, sinkt um `animal_hunger_per_day`). Unter 0,6 sucht es
    im Umkreis `roam` (sonst `animal_food_radius`) seines Baus eine Quelle aus `food`
    {Knotentyp: verbraucht?} und frisst 2 s; `true` nimmt eine Einheit (Beeren, Pilze, Kokos, Aas),
    `false` nicht (Wild im Wald an Bäumen). Danach ist die Quelle `animal_graze_days` für Tiere leer.
    `winter_food` gilt nur im Winter (Wildschweine: Eicheln und Wurzeln an Bäumen). Hungrige Tiere
    (unter 0,25) suchen 6 Felder weiter, haben 1,5-fachen Angriffsradius und 5 Felder mehr Leine.
    Im Winter werden sie langsamer hungrig (`animal_winter_hunger`). Bei 0 verlieren sie
    `animal_starve_per_day` ihrer Kraft je Tag und verhungern (die letzten zwei Erwachsenen einer
    Art magern nur bis 10 % ab); satte heilen.
  - *Tragfähigkeit* `World.den_capacity` = Futterquellen mit Vorrat um den Bau (ohne Aas) geteilt
    durch `food_per_animal`, höchstens `den_max`. Wer Beerensträucher aberntet oder Wald rodet,
    hat weniger Tiere.
  - *Junge*: einmal je Frühling (`Seasons.SPRING`), wenn am Bau zwei satte Erwachsene leben und der
    Bau unter seiner Tragfähigkeit ist, mit `animal_breed_chance` je Takt ein Wurf `litter`
    (höchstens Tragfähigkeit + 1). Jungtiere sind klein, haben halbe Kraft, greifen nie an, werden
    nicht gejagt und sind nach `adult_days` erwachsen. Hat ein Bau kein Paar, zieht ein Tier von
    einem Bau mit mehr als zwei Erwachsenen herüber, oder zwei einzelne Tiere finden zusammen (am
    Bau mit mehr Futter). `World._den_breed` merkt sich je Bau den Wurf dieses Frühlings.
  - *Schonung*: Jäger jagen nur Erwachsene, und nur solange mehr als `hunt_min_keep` (2)
    erwachsene Tiere dieser Art auf der Insel leben (`World.is_huntable`). Würde ein geschütztes
    Tier (eines der letzten zwei oder ein Jungtier) durch Jäger, Notwehr oder Wachturm sterben,
    entkommt es mit 20 % Kraft und flieht einen halben Tag lang in seinen Bau (`Animal._scared`).
    So stirbt keine Art mehr aus, solange noch zwei erwachsene Tiere leben.
  - *Winterruhe*: Tiere mit `hibernate` (Bär) ziehen sich im Winter in die Höhle zurück
    (unsichtbar, harmlos) und wachen im Frühling hungrig und damit angriffslustig auf.
  - Gefahr gegen Ausrottung: die letzten zwei Wölfe oder Bären bleiben immer gefährlich; Jäger
    ernten nur den Zuwachs ab. Je mehr Futter, desto mehr Tiere und desto mehr Angriffe.
- **Siedler bei Gefahr**: Jäger kämpfen, alle anderen fliehen ins nächste Haus, Lager oder
  Wachturm (`refuge_radius`) und verstecken sich, bis die Tiere weg sind, sonst ans Lagerfeuer.
  Neue Fähigkeit `jagd`. Beruf **Jäger** (braucht Waffenkunde): jagt Tiere in der Nähe, holt
  Fleisch von erlegten Tieren (`beute`, verdirbt nach `decay_days`; Wölfe und Bären fressen Aas).
  Bauten bleiben bestehen. Felle kommen beim Erlegen direkt ins Lager.
- **Wachturm** (`defense` {range, damage, interval}): schießt Pfeile auf angreifende Tiere in Reichweite.
- **Neue Waren**: Fleisch, Kokosnüsse, Pilze (Nahrung), Felle, Gold.
- **Stufe VI „Neue Welt“**: Navigation, Jagdkunst, Befestigung, Warme Kleidung, Leuchtfeuer
  (Leuchtturm: Erkunden doppelt so schnell), Goldenes Zeitalter (Denkmal: mehr Kinder, längeres
  Leben). Gold gibt es nur auf Felseninseln.
- Grafiken: `assets/sprites/objects2.png` (`Data.OBJECT2_REGIONS`: Palmen, Höhle, Pilze, Adern,
  Bauten, Beute, Pfeil, Boot), `animals.png` (Zellen 24x24, Zeile je Tier, Spalten 0–3 Laufen,
  4 Angriff), Gebäude ab Zelle 20 in `buildings.png` (Schule Zelle 25, `school()` in `gen_art.py`; Häfen und Kais ab Zelle 29), Schiffe in `objects2.png` ab y=96 (48x48, 2 Bilder). Gezeichnet von `tools/gen_art_sea.py`.

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

## Jahreszeiten

Autoload `Seasons` (`scripts/autoload/seasons.gd`), alle Zahlen in `data/seasons.json` (Listen immer
Frühling, Sommer, Herbst, Winter). Eine Jahreszeit dauert `season_days` = 3 Tage, ein Jahr 12 Tage.
Spielbeginn (Tag 1) ist Frühling; die Jahreszeit folgt nur aus `Game.time_days`, also ohne eigenen
Spielstand-Eintrag (alte Spielstände landen einfach in der passenden Jahreszeit).

- **Abfragen für andere Teile**: `Seasons.season()` (0–3, Konstanten `Seasons.SPRING..WINTER`),
  `is_winter()`, `year()`, `day_in_season()`, `season_name()`, `season_progress()`, Signal
  `season_changed(season)`. `Seasons.dt_days` = in diesem Frame vergangene Spieltage.
- **Anzeige**: Symbol und „Frühling 2/3“ oben in der Leiste (schmal nur das Symbol); Tippen zeigt,
  was die Jahreszeit bewirkt. Beim Wechsel eine Meldung, am letzten Herbsttag eine Wintervorwarnung
  mit dem Holzbedarf.
- **Wachstum** (`growth` je Knoten- oder Feldtyp, sonst `_default`): Faktor auf das Nachwachsen von
  Rohstoffquellen und das Reifen der Felder. Umgesetzt durch Verschieben von `regrow_at` bzw.
  `farm_time` um `dt_days * (1 - Faktor)`, das Speicherformat bleibt gleich. Winter 0 (nichts wächst),
  Herbst etwa halb so schnell, Bäume im Frühling am schnellsten, Beeren im Sommer, Pilze im Herbst.
- **Tiere vermehren sich nur im Frühling**: baut der Tier-Faden auf `Seasons.season() == Seasons.SPRING`.
- **Für andere Systeme**: `Seasons.season_mod(key)` (`mods`: `sickness`, `mood`, Standard 1.0),
  `Seasons.is_warm(world)`.
- **Heizen**: je Siedler und Tag `heat_wood_per_settler` Holz (Herbst 0,3, Winter 1) aus dem Lager.
  Fehlt Holz, frieren die Siedler der Insel (`Seasons.cold`): Hunger x`cold_hunger`, Arbeit
  x`cold_work`.

Fünf weitere Jahreszeit-Mechaniken:

1. **Tageslänge**: `night_start`/`night_end` je Jahreszeit (`Seasons.night_start()`), Sommertage lang,
   Wintertage kurz. `Game.is_night()` und das Licht der Welt richten sich danach.
2. **Feldbau-Kalender und Frost**: Getreide wird nur im Frühling und Sommer gesät (`sow_seasons`);
   zu Winterbeginn erfriert, was noch auf den Feldern wächst (`frost_kills`). Reifes Korn bleibt.
   Sträucher und Pilze verlieren zu Winterbeginn ihre Früchte (`winter_bare`).
3. **Verderb**: frische Nahrung (`perishable`) verdirbt anteilig je Tag (`spoil_per_day`, Sommer 8 %,
   Winter 0). Brot, Räucherfisch, Getreide, Kokos halten. Erlegtes verdirbt im Sommer schneller und
   hält im Winter länger (`decay`). Morgens meldet das Spiel, was verdorben ist.
4. **Schnee und Winterkälte**: im Winter Bauen x0,7 (gefrorener Boden), Laufen x0,85, Hunger x1,15;
   Fischgründe erholen sich unter Eis kaum. Schnee färbt Boden und Bäume weiß (Shader
   `assets/shaders/season.gdshader`, Materialien je Insel in `World._update_season_look`, nicht auf
   Palmeninseln: `snow_biomes`), es schneit (Partikel im Autoload).
5. **Herbststürme**: Schiffsreisen und Erkundung dauern im Herbst x1,4, im Winter x1,2, im Sommer
   x0,9 (`Seasons.sail_mult()`, gilt beim Ablegen).

Herbstlaub: Laubbäume und Büsche färben sich im Herbst orange (gleicher Shader), Laub fällt. Grafiken
der Symbole und Partikel: `tools/gen_art_seasons.py` → `assets/sprites/seasons.png`.
Test: `--season=<0..3>` startet in einer Jahreszeit, Bericht zeigt Jahreszeit und Holz.

## Charaktere der Siedler

Alle Zahlen in `data/people.json` (`Data.ppl(key)`), Logik in `scripts/entities/settler_mind.gd`
(`SettlerMind`, je Siedler `settler.mind`, gespeichert als `mind` im Siedler-Eintrag; alte
Spielstände würfeln die Werte reproduzierbar aus der Siedler-ID).

- **Eigenschaften** 1–10 (`traits`): `iq` Klugheit (Lerntempo `0.6+0.08*iq`, Forschung `0.7+0.06*iq`),
  `konst` Gesundheit (robust/kränklich: Krankheitsrisiko, Dauer und Schaden), `fleiss` (weniger
  Freizeitbedarf, Arbeit `0.9+0.022*fleiss`), `gemuet` (Grundlaune). Anzeige als Wörter ab 7,5 bzw. bis 3,5.
- **Begabungen** je Fähigkeit 0,5–1,8 (`talents`): Faktor auf jede Erfahrung (`Settler.gain_xp`).
  Kinder: `SettlerMind.inherit` mischt Eltern (`trait_inherit`) mit Zufall. Kinder starten mit Fähigkeit
  1–3 nach Begabung und lernen beim Spielen (`play_xp_per_day`), in der Schule viel mehr
  (`school_xp_per_day`), jeweils mal Begabung. Lena und Jonas haben feste Werte (`World.build_new`).
- **Vitamine** `vit` 0–100, sinken `vit_per_day`. Jede Mahlzeit gibt `vitamins` der Sorte
  (nur aus `resources.json`). Unter `vit_low` doppeltes Krankheitsrisiko,
  länger als 1 Tag unter `vit_scurvy` → Skorbut (heilt erst ab `until_vit`). Speiseplan: letzte
  `diet_memory` Sorten (`meals`) für die Laune. Schnittstelle zum Essen: `Settler._do_eat` nimmt von
  `Game.eat_food(...)` die Sorte und ruft `mind.on_meal(id, vitamins)` (siehe „Nahrung, Vitamine“).
- **Krankheiten** (`illnesses`): Erkältung (langsamer), Fieber und Ruhr (`bed`: liegen zu Hause oder am
  Feuer, tödlich möglich), Skorbut. Risiko je Tag `sick_base_per_day` × Gebrechlichkeit × Kind/Alt ×
  Hunger × Vitaminmangel × draußen schlafen × `Seasons.season_mod("sickness")` × Kälte
  (`Seasons.is_warm`) × Ansteckung (Kranke im selben Haus oder bis 3 Felder) ÷ √`eff(heal)`.
  Kranke heilen ohne Krankheit nicht, verlieren `damage` je Tag; Bettruhe und Heilkunde verkürzen.
  Todesursache aus `deadly`.
- **Laune** 0–100 läuft langsam auf einen Zielwert aus Gründen (`mind.reasons`, im Infofenster): satt
  oder hungrig, Abwechslung im Speiseplan, Vitamine, Krankheit, Zuhause (kein Zuhause, schönes Haus),
  Erholung, Trauer um Tote (Familie und Partner stark, `SettlerMind.is_close`), Freude über ein Baby,
  Jahreszeit (`season_mod("mood")`), Frieren. Laune wirkt auf Arbeit (`mood_work_min..max`) und
  Geburten (`mood_birth_min..max`, kranke Mütter kaum).
- **Arbeitskraft** `mind.work_power()`: Gesundheit × Hunger × Laune × Krankheit × Vitamine × Alter
  (letzte 20 % des Lebens `work_old`) × Fleiß. Steckt in `Settler.work_factor` und in der Forschung.
- **Lebensstil** `SettlerMind.comfort()` 0–1 aus der Zahl erforschter Forschungen
  (`comfort_techs_start..full`), Stufen `comfort_stages` (Überleben, Einfaches Leben, Dorfleben,
  Wohlstand; in der Siedlerliste). Damit steigen Freizeitbedarf (`leisure_share_max` des Tages) und
  Ansprüche (Abwechslung, Zuhause, Erholung zählen stärker).
- **Freizeit**: `rest` sinkt bei Arbeit je nach Bedarf, unter 35 macht der Siedler Pause
  (`Settler._plan_leisure`: Feuer, zu Hause, Strand, mit Kindern spielen, Bibliothek/Schreibstube,
  gewichtet nach Gemüt und Klugheit), außer in einer Hungersnot (weniger als 3 Nahrung je Siedler).
- **Anzeige**: Infofenster (Charakter, Begabungen, Krankheit, Balken Vitamine/Laune/Erholung,
  Arbeitskraft, wichtigste Gründe, Eigenschaften, Fähigkeiten mit + für Begabung), Siedlerliste
  (Spalte Laune, rot bei Krankheit, Filter „Nur Kranke“, Lebensstil im Zähler).
- Test: `--chartest=1` (täglicher Bericht), `--comfort=<n>` (n Forschungen erledigt), `--sick=<n>`.

## Nahrung, Vitamine und Gleichgewicht

Ziel: eine Insel ist am Anfang schwer im Gleichgewicht zu halten, läuft aber stabil weiter, wenn sie
einmal aufgebaut ist. Dafür gilt:

- **Zwei Werte je Speise** (`resources.json`): `nutrition` = Sättigung, `vitamins` = Vitamine.
  Obst und Beeren sättigen wenig, haben aber viele Vitamine; Brot, Räucherfisch, Fleisch sättigen
  lange, haben kaum Vitamine. Rohes Getreide sättigt schlecht (10), Brot sehr gut (42).
  Abfragen: `Data.food_satiety(id)`, `Data.food_vitamins(id)`.
- **Siedler**: `hunger` (Sättigung 0–100, sinkt um `hunger_per_day` = 75). Vitamine, Speiseplan,
  Skorbut und Arbeitskraft gehören zum Charakter-Modell (`settler.mind.vit`, `mind.meals`, siehe
  „Charaktere der Siedler“). Beim Essen (`Game.eat_food(prefer_vitamins, w)`) greift ein Siedler unter
  `vitamin_target` (balance.json) zum vitaminreichsten, sonst zum sättigendsten im Lager seiner
  Insel, und meldet die Mahlzeit mit `mind.on_meal(id, Data.food_vitamins(id))`. `Game.eaten` zählt
  alles, `Game.last_eaten` ist die letzte Sorte.
- **Notessen**: ist das Lager der Insel leer (oder voll mit anderem), essen sehr hungrige Siedler
  direkt am Strauch, an Palme, Pilzkreis oder Fischgrund (`_plan_forage`).
- **Knappe Natur** (`nodes.json`): Sammeln, Fischen, Holz und Stein dauern 2–4x so lange wie
  früher, Sträucher tragen 3 Beeren und wachsen in 2,5 Tagen nach, Fischgründe 6 Fische in 1,5 Tagen.
  Ein Sammler ernährt so etwa 1,5 Erwachsene, die wilde Natur einer Startinsel etwa 15. Wer mehr
  Siedler will, braucht Felder mit Mühle und Bäckerei (ein Feld mit Brotkette ≈ 2 Erwachsene) und
  Obstgärten für Vitamine.
- **Messen**: `--jobs=sammler,fischer,...` vergibt feste Berufe (fehlende Siedler werden erzeugt),
  `--nofruit=1` entfernt Sträucher, Palmen und Pilze (Vitaminmangel testen), `--nodestat=1` zeigt
  Vorrat und Nachwachsen der Nahrungsquellen. Der Bericht zeigt je Siedler Sättigung/Vitamine/Gesundheit
  und alles Gegessene.

## Zeitalter

`techs.json` hat neben `_tiers` (16 Stufennamen) die Liste `_ages`: acht Zeitalter mit je zwei Stufen
(Steinzeit 1–2, Antike 3–4, Mittelalter 5–6, Renaissance 7–8, Industrialisierung 9–10, Moderne 11–12,
Informationszeitalter 13–14, Zukunft 15–16). `Data.age_of_tier(tier)`, `Data.age_name(i)`,
`Game.current_age()` = spätestes Zeitalter mit mindestens einer erforschten Sache. Beim Eintritt in ein
neues Zeitalter meldet `_finish_research` es. Im Forschungsmenü steht über jedem Zeitalter eine
Überschrift; Zeitalter jenseits des nächsten zeigen nur die Überschrift (`_age_header`).

- **Neue Waren**: Glas, Papier, Stahl, Maschinen, Strom (Größe 0), Elektronik, Konserven (Nahrung 30/8,
  verdirbt nicht). **Neue Werkstätten** (Handwerker): Glashütte, Papiermühle, Stahlwerk, Fabrik,
  Kraftwerk, Elektronikwerk, Solarpark und Fusionsreaktor (ohne Rohstoffe); Konservenfabrik (Koch).
  **Forschung**: Universität x3,5, Forschungslabor x6, KI-Zentrum x10 (je 4 Plätze). **Wohnen**:
  Mietshaus 10, Wohnblock 16. **Gewächshaus**: Farm als Gebäude (nicht `ground`), wächst ganzjährig
  (`seasons.json` growth `gewaechshaus`), der Bauer arbeitet am Eingang. **Zukunftsstadt**: Denkmal
  des letzten Zeitalters.
- **Neue Wirkungen**: `production` (Tempo aller Werkstätten, in `Settler.work_factor(..., "production")`),
  `spoil` (Kühltechnik −0,75 auf den Verderb in `Seasons._spoil`), `ai_jobs` (KI-Zentrum).
- **KI-Steuerung** (`scripts/world/ai_jobs.gd`, `AiJobs.tick(w)` alle 0,25 Tage aus `Game._process`):
  steht ein KI-Zentrum, bekommt je Insel und Runde ein freier Siedler den Beruf, der am meisten fehlt
  (Nahrung unter 6 je Siedler, Baustellen, leere Werkstätten, Holz/Stein knapp, freie Forschungsplätze);
  bei Hungersnot wird auch ein Arbeiter aus Werkstatt oder Forschung zur Nahrung geholt.
- **Grafik**: `tools/gen_art_ages.py` (Gebäude ab Zelle 35 in buildings.png, Symbole `ICONS_AGES`).
- **Test**: `--prodtest=1 --ages=1` baut nur die Gebäude der neuen Zeitalter.

## KI-Variante (Siedler denken selbst, Inselrat, Herrscher)

Eigene Ausgabe unter `/New_World/ki/` (Zweig `claude/ki-variante-oexba8`, Workflow legt ihn nach
`gh-pages/ki`). Erkennung in `Game._detect_test_build`: Webadresse mit `/ki/` (lokal `--kimode=1`) setzt
`Game.is_ki_build` und `Society.enabled`, speichert in `user://savegame_ki.json` (kopiert beim ersten Start
den normalen Spielstand) und lässt die Einführung weg. Ohne `/ki/` tut `Society` nichts, das normale
Spiel bleibt unverändert. Der letzte Stand vor der KI-Variante liegt im Zweig `version-1.0`.

### Sprachmodelle (Llama-3.2-1B für die Räte, SmolLM-135M für die Siedler)

Wunsch von josh (2026-10-04): Jeder Siedler ist ein eigenes kleines Sprachmodell, jeder Inselrat ein
größeres. Beide laufen im Browser des Spielers (kein Server, kein Schlüssel). Kann das Gerät sie nicht
laden oder will der Spieler nicht, entscheidet die Regel-KI unten wie bisher.
- `web/ki_llm.js` (im Export über `include_filter`): `window.KiLlm` startet einen Web Worker
  (Blob, Modul), der transformers.js 4.3.0 vom CDN lädt (`lib_urls`) und beide Modelle lädt
  (Modell-IDs und `dtypes` je Gerät in `data/ki_llm.json`, die Liste wird der Reihe nach probiert;
  WebGPU wenn möglich, sonst WASM). `choose`: Chatvorlage + Frage mit nummerierten Möglichkeiten,
  ein Schritt `generate` mit einem `LogitsProcessor`, der die Wahrscheinlichkeiten der Ziffern 1–9 abliest
  (`probs`, dazu `mass` = Anteil der Ziffern an allem, was das Modell schreiben wollte). `generate`: freier
  Text. Getestet in Node mit winzigen Zufallsmodellen (gleicher Code, `cfg.local_path`).
- Autoload `Llm` (`scripts/autoload/llm.gd`): Status (aus, laden, bereit, fehler), Fortschritt,
  Wahl je Gerät in `user://ki_llm.cfg` (Titelbild und Rat-Fenster fragen vor dem Download).
  `choose(role, messages, n, hint)` und `generate(...)` geben einen `Job` zurück, `await job.done`.
  `--llmmock=1` ersetzt die Modelle durch eine Attrappe (wählt nach `hint` mit Zufall), für Tests.
- **Speicher und Abstürze** (josh, iPhone 16 Pro: Llama-3.2-1B lässt Safari abstürzen): Auf Handys
  (`Llm.small_first`) denkt der Rat zuerst mit `models.rat_small` (SmolLM2-360M, sonst Qwen2.5-0.5B).
  Absturzschutz in `ki_llm.js`: vor jedem Ladeversuch steht `rolle:modell` in `localStorage.kiLlmPending`,
  gelöscht nach der ersten erfolgreichen Antwort. Steht es beim nächsten Start noch da, ist die Seite
  abgestürzt, das Modell kommt nach `kiLlmTooBig` und wird übersprungen. Geht kein Ratsmodell, denkt der
  Rat mit dem Siedlermodell (`shared`). „Llama trotzdem versuchen“ im Rat-Fenster (`Llm.retry_big`)
  vergisst die Abstürze. Der Merker steht in localStorage und IndexedDB (verlässlich auf der Platte);
  der Worker lädt erst weiter, wenn er gespeichert ist (`trying` → `go`). `crash_test.mjs` und
  `crash_idb_test.mjs` in `tools/ki_llm_test` prüfen das in Chromium.
- **Stückweises Einlesen** (`runGen`): Ein ONNX-Modell ohne Eingang `num_logits_to_keep` rechnet für jedes
  Wort der Anfrage Wahrscheinlichkeiten über den ganzen Wortschatz aus (Llama: 2000 Wörter × 128 000 ≈ 1 GB).
  Darum liest der Worker die Anfrage in Stücken von `chunk` (64) Wörtern mit `forward` und
  `past_key_values` ein und lässt erst den Rest `generate` machen. Gleiches Ergebnis wie am Stück
  (`chunk_test.mjs`).
- Autoload `KiMind` (`scripts/autoload/ki_mind.gd`), läuft nur wenn `Llm.active()`; dann macht
  `Society` nur noch Häuser, Pflege, Feste und Anliegen. Eine Runde geht Insel für Insel (Hauptinsel
  zuerst): ist der Rat dran (`council_days`), bekommt Llama `council_system` (Rolle, Ziel: Hauptinsel
  wachsen und forschen, andere wachsen; Jahreszeitenregeln; Prioritäten, Wünsche und feste Vorgaben
  des Herrschers; Gedächtnis) und `island_report` (Siedler mit Fähigkeiten und letzter Entscheidung,
  Gebäude mit Zellen, Vorräte und Bedarf, alle Inseln mit Lage, Rohstoffen und Bedarf, alle Schiffe mit
  Heimat und Route). Der Rat wählt nacheinander Schwerpunkt, Arbeit (Wahrscheinlichkeiten = Anteile, mal
  Prioritäten, Natur begrenzt Sammler/Fischer/Bauern, Notregel bei fast leerem Essen; `_make_orders` gibt
  jedem Siedler nach Begabung einen Auftrag), Bau (`build_options`, auch „nichts“), Forschung (nur
  Hauptinsel, `research_options`), Handel und sagt zum Schluss in einem Satz, was die Bewohner tun sollen.
  Freie Texte (Ansage, Lehren, Chat) haben `reason_tokens`/`chat_tokens` Wortstücke Platz; die Anfrage nennt
  die Grenze als halb so viele Wörter (`length_rule`). `_clean` kürzt eine
  mitten im Satz abgebrochene Antwort auf den letzten ganzen Satz (sonst „…“). Die Ansage geht nicht an
  die Siedler (sie bekommen ihren Auftrag), Lehren aber in jede Ratsanfrage.
  Danach fragt SmolLM jeden Erwachsenen (höchstens alle `settler_days`, `settler_prompt`), auf
  **Englisch**, weil SmolLM-135M fast nur Englisch kann (auf Deutsch waren die Nummern fast gleich
  wahrscheinlich, die Wahl gewürfelt): Jahreszeit, Hunger, Laune, Fähigkeiten, Inselzahlen, Auftrag des
  Rats, letzte Arbeiten; jede Möglichkeit mit kurzen Stichworten dafür (`_option_facts`: Auftrag,
  aktuelle Arbeit, wie gut er darin ist, was die Insel braucht). Möglichkeiten: Auftrag zuerst, dann
  aktueller Beruf, Lieblingsberuf, gefragte Berufe, „frei“. Die Antwort beginnt mit „My choice:“, damit
  als Nächstes die Nummer kommt. Jeder Siedler wird **zweimal** gefragt, das zweite Mal in umgekehrter
  Reihenfolge, und die Wahrscheinlichkeiten werden gemittelt (kleine Modelle nehmen gern die 1).
  **Klarheit** = höchste Wahrscheinlichkeit mal Anzahl (1 = alle gleich). Unter `undecided_clarity`
  wird nicht gewürfelt: der Siedler folgt dem Auftrag oder bleibt bei seiner Arbeit, der Rat nimmt die
  stärkste Nummer. Sonst wird nach den Wahrscheinlichkeiten mit `settler_temperature`
  (`council_temperature`) gewählt; Abweichen vom Auftrag heißt „eigene Wahl“.
  Siedler mit Befehl des Herrschers, Kranke und Seeleute werden nicht gefragt. Die Runde ist eine
  Koroutine; `epoch` bricht sie bei Neustart oder Laden ab, Pause hält sie an.
- **Handel** (`_trade`): Der Rat sieht, was anderen Inseln übrig ist und ihm fehlt, und bittet um eine
  Ware. Der Rat der anderen Insel nennt seinen Preis (eine Ware, nichts oder ablehnen), der bittende Rat
  nimmt an oder nicht. Dann fährt ein freies Schiff der gebenden Insel (sonst der eigenen; jedes Schiff
  hat seine Heimatinsel) eine Route hin und her, bis `trade_days` vorbei sind (`trades`).
- **Herrscher**: `chat(w, text)` (Llama antwortet, der Wunsch steht drei Tage im Systemtext, der Rat
  tagt bald neu), `bind(w, fokus|bau|forschung|beruf, wert, n)` feste Vorgaben (kosten Vertrauen,
  Schwerpunkt und Arbeiter gelten drei Tage, Bau und Forschung bis erledigt), `set_prio(w, key, 0..3)`.
- **Lernen**: Jede Sitzung wird als `records` mit Kennzahlen gespeichert. Bei der nächsten misst
  `_evaluate` die Veränderung je Tag (Essen, Holz, Stein, Siedler, Laune, Forschung), führt `exp` je
  Jahreszeit und Schwerpunkt und schreibt bei auffälligen Messungen eine Lehre (`_measure_lesson`).
  Alle `reflect_every` Sitzungen zieht Llama aus den letzten Entscheidungen und Folgen selbst eine Lehre
  (`_reflect`). Lehren (höchstens `lessons_max`), Erfahrung und die letzten Entscheidungen mit Folgen
  stehen in jedem Systemtext. Alles liegt im Society-Zustand der Insel (`state(w).llm`) und im Spielstand.
- Rat-Fenster mit Sprachmodellen: Schwerpunkt, Satz des Rats, „Mit dem Rat sprechen“, „Feste
  Vorgaben“, „Prioritäten“, Aufträge und eigene Entscheidungen, Lehren. „KI beobachten“ zeigt Status
  und Rechenzeit, die letzte Sitzung mit Wahrscheinlichkeiten, jeden Siedler mit Auftrag und Wahl,
  das Gedächtnis und die letzte Anfrage an jedes Modell im Wortlaut.
  Zeilen zum Siedler springen nur bei echtem Klick oder Tipp (`_jump_on_tap`); vorher schloss das
  Mausrad über einer Siedlerzeile das Fenster. Beim Scrollen und beim Lesen der Anfrage baut sich die
  Ansicht nicht neu auf, die Scrollposition bleibt.
- **KI-Bericht (vorübergehend zur Kontrolle)**: `KiMind.trace` hält jede Anfrage an ein Modell fest
  (Möglichkeiten, Wahrscheinlichkeiten A/B, Klarheit, Nummernanteil, Entscheidung und Regel, Antworttexte,
  volle Anfrage für die letzten 150), nur im Speicher. „KI-Bericht herunterladen“ im Menü und in
  „KI beobachten“ lädt `report_text()` als Textdatei herunter (Zusammenfassung, Gedächtnis je Insel,
  Verlauf). Test: `--kireport=pfad`; Mausrad-Test: `--panel=ki --wheeltest=1 --shot=...`.

### Regel-KI (ohne Sprachmodelle)

Autoload `Society` (`scripts/autoload/society.gd`), alle Zahlen in `data/society.json`:
- **Denken** (`_think`, alle `think_days` je Insel): `situation(w)` sammelt Lage (Essen je Kopf,
  Heizholz bis zum Frühling, Baustellen, Raubtiere, Felder ...). `desired_jobs` rechnet, wie viele
  Arbeiter jeder Beruf bräuchte (ein Sammler ernährt `gatherer_feeds` Esser), `job_slots` gewichtet mit
  der Strategie und passt auf die verfügbaren Siedler an (Seeleute, Kranke im Bett und vom Herrscher
  Bestimmte zählen nicht). Offene Plätze füllt, wer frei ist oder aus einem überbesetzten Beruf kommt,
  nach `preference` (Begabung, Können, Gewohnheit, Absprache des Hauses, Lieblingsberuf). Höchstens
  `max_changes_per_think` Wechsel, jeder Siedler höchstens alle `change_cooldown_days`. `thoughts[id]`
  ist der Gedanke im Infofenster. Das KI-Zentrum (`AiJobs`) ist in dieser Variante aus.
- **Häuser** (`_make_households`): Bewohner eines Hauses (`home_id`, ohne Haus „Am Lagerfeuer“) mit
  einem Sprecher (bleibt, solange er dort wohnt). Die Häuser teilen sich die Bereiche `DOMAINS` nach
  Bedarf und Begabung, das gibt Vorrang bei der Berufswahl. Kranke im Bett heilen schneller, wenn
  jemand im Haus sie pflegt (`care_heal_bonus`).
- **Inselrat** (`_council`, alle `council_days`): jeder Sprecher stimmt nach `opinion` (Lage aus
  `situation_scores` plus eigene Sicht: Hunger im Haus, enges Haus, Klugheit, Fleiß, Gemüt, Gesundheit)
  für eine Strategie aus `strategies`. Gleichstand behält die alte. Eine neue Mehrheit wird ein Anliegen.
- **Anliegen** (`requests`, `add_request`, je Insel und Art nur eines, danach Pause): `strategie`, `bau`
  (große Bauten über `small_build_cost`; kleine baut der Rat selbst, `_plan_buildings` und `find_spot`),
  `forschung` (Insel mit den meisten Siedlern, `choose_research` nach Strategie), `fest`, `freizeit`,
  `ueberstunden`, `hilfe` (eine reiche Insel schickt ein freies Schiff mit Essen oder Holz). Antwort über
  `answer(id, "ja"|"nein")`; nach `request_days` entscheidet der Rat bei Strategie, Bau, Forschung und
  Überstunden selbst, sonst sinkt das Vertrauen leicht.
- **Herrscher**: Vertrauen je Insel 0–100 (`trust`), wirkt auf Laune und Überzeugungskraft.
  `start_debate(w, strategie)` → `argue("lage"|"gemeinwohl"|"fest"|"freizeit")`: jedes Argument gibt je
  Sprecher Kraft (Lage nur, wenn sie wirklich dafür spricht, mal Klugheit; Gemeinwohl mal Gemüt;
  Versprechen für alle) mal Vertrauen; überzeugt ist, wessen Kraft seinen Widerstand (Abstand seiner
  Lieblingsstrategie) erreicht. Mehrheit = neue Strategie, Versprechen werden eingelöst. `command`
  setzt durch (Vertrauen −12, zwei Tage schlechte Laune). `order_job` (Beruf im Infofenster) gilt einen Tag.
- **Wirkungen**: `Society.work_mult(w)` in `Settler.work_factor` (Fest, Freizeit, Überstunden),
  `Society.mood_reasons(s)` in `SettlerMind._update_mood`, `Society.on_attack` aus `Settler.take_damage`.
- **Beobachten**: `decide(w, text)` schreibt jede Entscheidung (Berufswechsel mit Bedarf, Stimmen im Rat,
  Bauten, Anliegen) ins Protokoll `dlog` je Insel (40 Einträge, gespeichert). Im Rat-Fenster zeigt
  „KI beobachten“ die Lage, Bedarf je Beruf (gebraucht/besetzt), den nächsten Bau, die Gedanken aller
  Siedler (antippen springt hin) und das Protokoll. Bildschirmfoto `--panel=ki`.
- **Oberfläche**: Knopf „Rat (n)“ und `scripts/ui/council_panel.gd` (Inselreiter, Strategie, Vertrauen,
  Anliegen als Karten, Abstimmung, Häuser, Chronik, Diskussion). Spielanleitung beginnt mit `HELP_KI`.
- **Spielstand**: `society` {isl, requests, next_req, orders, welcomed}; fehlt er, startet alles neu.
- **Test**: `--kimode=1 --kitest=1 [--kiauto=ja|nein|rede|befehl] [--crowd=10]`, Bildschirmfoto
  `--panel=rat` bzw. `--panel=debatte`.

## Testversion

Pushes auf den Zweig `claude/entwicklungsbaum-x33t1h` landen unter `/New_World/test/`, main unter `/`
(Workflow mit `destination_dir` und `keep_files`). Die Testversion speichert in
`user://savegame_test.json` und kopiert beim ersten Start den normalen Spielstand
(`Game._detect_test_build`, lokal `--testbuild`). Der Titel zeigt „Testversion“.

## Ordner

| Pfad | Inhalt |
|---|---|
| `data/*.json` | Alle Spielwerte (Ressourcen, Rohstoffquellen, Gebäude, Berufe, Balance, Namen) |
| `scripts/autoload/data.gd` | Lädt JSON, Sprite-Regionen (`OBJECT_REGIONS`), Icons |
| `scripts/autoload/game.gd` | Zeit, Vorräte, Nachwuchs, Abstammung, Forschung und Effekte, Speichern/Laden |
| `scripts/autoload/seasons.gd` | Jahreszeiten: Kalender, Wachstum, Heizen, Verderb, Frost, Schnee |
| `scripts/autoload/sea.gd` | Inseln, Welten je Insel, Schiffsreisen, Inselwechsel |
| `scripts/autoload/society.gd` | KI-Variante: Siedler denken selbst, Häuser, Inselrat, Anliegen an den Herrscher |
| `scripts/autoload/llm.gd`, `web/ki_llm.js` | KI-Variante: Sprachmodelle im Browser (Worker, transformers.js), Attrappe für Tests |
| `scripts/autoload/ki_mind.gd` | KI-Variante: Inselräte (Llama) und Siedler (SmolLM) entscheiden, Handel, Chat, Vorgaben, Lernen |
| `scripts/world/island_gen.gd` | Inselgenerator (Seed → Gelände + Rohstoffe) |
| `scripts/world/world.gd` | Tilemaps, Wegfindung (AStarGrid2D), Entitäten, Bauen, Effekte, Tag/Nacht |
| `scripts/world/game_camera.gd` | Ziehen, Zoom (Mausrad, zwei Finger), Tippen |
| `scripts/entities/*.gd` | `Settler` (KI), `SettlerMind` (Charakter), `Building`, `ResNode`, `Animal` |
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

- **resources.json**: `{id: {name, icon, category: "material"|"food", nutrition?, vitamins?, size, order}}`.
  Alles mit `category: food` wird gegessen.
- **nodes.json**: Rohstoffquellen. `yield`, `capacity`, `work_time`, `skill`, `terrain`
  (`grass`, `land`, `shore_water`), `solid`, `regrow_days`, `on_empty` (`regrow`|`remove`),
  `sprites` {full: [...], empty, low, growing}.
- **buildings.json**: `size`, `sprite`, `buildable`, `cost`, `work`, optional `housing`,
  `storage`, `light`, `ground`, `farm` {yield, amount, grow_days, sow_time, harvest_time}.
- **jobs.json**: `skill`, `tool` (Sprite in tools.png), `targets` (Knotentypen oder
  `farm`/`construction`), optional `requires` (Forschung).
- **islands.json**: Inselarten, siehe Etappe 3. **animals.json**: `hp`, `damage`, `speed`,
  `aggro`, `night_aggro`, `attack_time`, `meat`, `felle`, `leash`, `row` (Zeile in animals.png),
  `plural`, `plural_dat`, `food`, `winter_food`, `food_name`, `food_per_animal`, `roam`, `litter`,
  `den_max`, `adult_days`, `hibernate`.
- **balance.json**: alle Zahlen für Zeit, Hunger, Nachwuchs, Lager, Karte. `work_pace` (0.65 seit josh's Spieltest am 2026-10-03) bremst jede Arbeit (Sammeln, Fällen, Abbau, Felder, Bau, Werkstätten, Forschung) gegenüber dem Verbrauch; Laufen, Essen, Heizen und die Uhr bleiben gleich.
- **Spielstand** (Version 3): `{version, seed, time_days, next_id, stats, lineage, research,
  islands: [{id, name, biome, seed, size, pos, state, found_day, dens, world?}], active, voyages}`
  mit `world: {stock, nodes: [[type,x,y,amount,regrow_at,variant]], buildings: [...], settlers: [...],
  graves, animals: [[type,x,y,hp,home_x,home_y,age,food]], den_breed}`. Ohne `den_breed` (älterer
  Spielstand) kehren ausgeräumte Baue zurück und jeder Bau wird einmalig auf `den_cap` Tiere aufgefüllt. Version 1 (nur `world`) wird beim Laden als
  Heimatinsel übernommen. Version 1 und 2 hatten ein gemeinsames `stock`: das bekommt beim Laden
  die Heimatinsel. Das Gelände wird aus dem Seed neu erzeugt, nur Rohstoffe, Gebäude,
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
godot --headless -- --autotest=230 --scale=10 --build=1   # ein ganzes Jahr, Bericht mit Jahreszeit und Holz
godot --headless -- --autotest=300 --scale=10 --seatest=1  # Werft, drei Inseln entdecken und besiedeln
#   dazu --wildlife=1: Tierbestand je Insel und Bau; --weak=1: ohne Waffenkunde (Tiere gefährlicher), Bildschirmfoto: --island=<id>, --panel=sea
# Bildschirmfoto-Optionen: --panel=research|build|stock, --selectb=<typ>, --look=1
xvfb-run godot --rendering-driver opengl3 -- --autotest=20 --shot=/tmp/bild.png
godot --headless --export-release "Web" build/web/index.html
```

Bei jedem Push auf `main` baut GitHub Actions die Web-Version und legt sie auf den
Branch `gh-pages` (GitHub Pages).
