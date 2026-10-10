# Insel-Siedler – Design und Architektur

Gemütliches Aufbauspiel in Pixel-Grafik (Godot 4.7, GDScript, Compatibility-Renderer,
Web-Export ohne Threads). Spielbar im Browser auf PC und Handy.

Seit der Erweiterung „Mehr Herausforderung“ (Regeln ab Version 2) kommen dazu: wechselnde Winter und
Sommer, Inselstärken mit Gewürzen und fremden Händlern, Bedürfnisstufen der Häuser mit Fachkräften,
angekündigte Ereignisse, Forschung mit Schriften (Tontafeln, Papier, Strom), Prüfungen beim
Zeitalterwechsel mit Wertung und Aufträge mit Wahl. Überblick und Zusammenspiel: „Regeln ab Version 2“.

## Spielregeln (Etappe 1)

- Start: eine zufällige Insel aus einem Seed, Lagerfeuer und eine Hütte, zwei Siedler
  (Lena, Jonas) mit unterschiedlichen Fähigkeiten.
- **Fähigkeiten** `holz`, `stein`, `nahrung`, `bauen` (Stufe 1–10). Arbeitstempo =
  `0.6 + 0.08 * Stufe`, mal Talent (siehe „Charaktere“). Jede Arbeit bringt Erfahrung, Stufe steigt nach
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
- Fünf Spielstände (Menü und Titelbild > „Spielstände“): Platz 1 ist `savegame.json`, die anderen
  `savegame_2.json` .. `_5` (Testversion entsprechend `savegame_test_N.json`). Der aktive Platz steht in
  `user://settings.cfg` [game] `slot` (`slot_test`), Kurzinfos (Tag, Siedler, Inseln, Zeit) unter [slots].
  „Laden“ und „Neues Spiel“ in einem anderen Platz speichern erst, merken `autostart` und laden die
  Seite neu (Desktop: Neustart); main.gd überspringt dann das Titelbild. „Hier speichern“ kopiert das
  laufende Spiel in den Platz und spielt dort weiter. Testaufrufe `--panel=slots`, `--slottest=1`.
- Export und Import je Platz: „Exportieren“ lädt den Platz als JSON-Datei herunter
  (`JavaScriptBridge.download_buffer`, Desktop FileDialog). „Importieren“ prüft die Datei
  (`Game.import_slot`: Version 1..SAVE_VERSION, `time_days`) und schreibt sie in den Platz. Im Browser
  öffnet nur eine echte Nutzergeste die Dateiauswahl (iPhone): `button_down` setzt in JS einen
  Capture-Listener auf `pointerup`/`touchend`, der das `<input type=file>` anklickt.

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
  Entfernung) / (eff(ship_speed) * Tempo des Schiffs) * Seasons.sail_mult()`.
  **Fahrtart** (josh: „Bei den Routen kann es auch einmal Routen geben, also hin und zurück“): unter den
  Halten „Fahrt: Immer wieder | Einmal hin und zurück“ (`sea_panel._route_mode_row`). Einmal: Start ist der
  erste Halt, an dem das Schiff lädt (der, den es als Nächstes anläuft); es fährt alle anderen Halte an,
  kommt zum Start zurück, lädt dort alles ab (lädt nichts mehr) und ist wieder frei: Route angehalten
  (`idle_ships` zählt es), die Halte bleiben, „Route starten“ fährt sie noch einmal; Meldung „Die … ist
  zurück in …“. Anzeige „Noch 2 Halte, dann ist das Schiff wieder frei.“. Ein übersprungener Halt (Hafen zu
  klein) zählt mit. Spielstand im Schiff (optional): `once` (bool), `once_left` (Halte, die noch kommen,
  -1 = nicht begonnen), `once_from` (Starthalt); alte Routen ohne `once` fahren immer wieder. Code:
  `Sea.set_route_once`, `is_once`, `once_stops_left`, `_once_stop` (in `_route_step`), `_once_finish`
  (nach dem Laden), `_once_skip`. Halte hinzufügen oder entfernen und das Umstellen beginnen die
  Zählung neu. Test `--fixture=sea.json --oncetest=1` (`RouteTest`, Sea meldet sich dafür mit
  `Game.register_system` an): Halte 0 → 1 → 0, Ladung je Strecke, frei danach, Speichern mitten auf der
  Fahrt, alte Route fährt weiter, neu starten, umstellen („Einmal-Route OK/FEHLER“); `--oncetest=shot
  --panel=sea --seaview=ship` fürs Bildschirmfoto. Liegende Schiffe
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

**Sprache (Englisch/Deutsch):** Der Quelltext bleibt deutsch, Englisch ist die Standardsprache. `data/i18n/en.json` ordnet jedem deutschen Text (Schlüssel) den englischen zu. Im Code stehen Anzeigetexte in `tr("...")` (in statischen Funktionen `Loc.t("...")`); Texte aus `data/*.json` (Felder name, desc, text, hint, verb ... siehe `Data.TEXT_KEYS`) übersetzt Data beim Laden. `scripts/autoload/loc.gd` lädt die Sprache aus `user://settings.cfg` ([game] language, Standard "en"), die Wahl steht im Menü und auf dem Startbild und startet das Spiel nach dem Speichern neu. Gespeicherte Insel- und Schiffsnamen zeigt `Loc.name_of` in der gewählten Sprache. Werkzeug: `python3 tools/i18n.py wrap` packt neue deutsche Texte im Code in tr(), `missing` listet Texte ohne Übersetzung (data/i18n/missing.json), `check` prüft Platzhalter. Neue Texte also immer auch in en.json eintragen. Testaufruf: `--langcheck=1` meldet sichtbare deutsche Texte im englischen Spiel.

**Versionsnummer:** steht in `project.godot` unter `application/config/version`. Die ersten beiden Stellen (1.0) zählt man dort von Hand hoch; die letzte setzt der Web-Build selbst auf die Zahl der Stände des Zweigs (`git rev-list --count --first-parent HEAD`), jeder Build von main zählt also eins weiter. Das Menü und der Titelbildschirm zeigen sie unten an, die Testversion mit dem Zusatz „(Testversion)“.

**Siedlerliste:** fast bildschirmfüllend mit kompakten Zeilen; Spaltenköpfe Name, Alter, Beruf, Satt sortieren (nochmal tippen dreht um), Filter für Beruf, Erwachsene/Kinder, Nur Hungrige (unter 30 % satt) und, bei mehreren Inseln, Diese Insel/Alle Inseln. Testaufruf: `--crowd=24 --panel=settlers [--sfilter=1]`. Spalte Auslastung: `Settler.busy_percent()` = eigene Arbeit / (eigene Arbeit + anderes + nichts zu tun) der Tageszeit eines Erwachsenen, gleiche Einteilung wie die Statistik der KI-Version (`_stat_kind`: job, other, idle, needs zählt nicht), hier als gleitender Wert, der mit `BUSY_DAYS` (1 Tag) verblasst; wird beim Berufswechsel geleert und gespeichert.

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
- **Einführung und Ziele** (`data/goals.json`, `scripts/ui/goal_card.gd`): neun Schritte mit
  Zeigerpfeil, danach feste Ziele mit Belohnungen und endlos erzeugte Ziele (Bevölkerung, Inseln,
  Geburten). Zustand `Game.goals {tut, ms}` im Spielstand; ältere Spielstände überspringen die
  Einführung und holen erreichte Ziele still nach. `Game.player_action(kind, what)` meldet
  Spieleraktionen. Statistik `kills` zählt erlegte Tiere. Das X auf der Zielkarte blendet das
  aktuelle Ziel aus (`goals.hide` = Ziel-ID), das nächste erscheint wieder. `goals.tv` = 2 markiert die
  Einführung mit neun Schritten; Spielstände ohne `tv` rechnen ihren Schritt aus der alten
  Siebener-Einführung um (`apply_save_header`). Prüfart `job`: Siedler mit Beruf `what`, alle Inseln.
  Wer die Einführung zu Ende spielt (nicht überspringt), bekommt 2 Siedler und eine fertige Hütte
  (siehe „Kohle, Erfrieren und weitere Ergänzungen“).
- **Nahrung in der Oberleiste**: Zahl der Nahrungsgüter und dahinter `Game.food_days()`, für wie viele
  Tage die Nahrung der angezeigten Insel reicht: Summe aus Menge mal Sättigung, geteilt durch die
  Siedler (Kinder zählen voll) und den Tagesbedarf `hunger_per_day` mit Jahreszeit und Kälte. Rot
  unter einem Tag; schmale Bildschirme zeigen „3T“.
- **Meldungen**: `Game.notify(text, icon, cat)` hat eine Art aus `Game.NOTIFY_CATS` (ohne Angabe nach
  dem Symbol über `NOTIFY_ICON_CAT`). Menü > „Meldungen“ schaltet jede Art und die Zielkarte ab;
  gespeichert in `user://settings.cfg` Abschnitt `[notify]`, gilt für alle Spielstände.
  Abgeschaltete Arten erreichen das Signal `notified` gar nicht. Neue Meldungsarten (etwa der KI)
  als neuen Eintrag in `NOTIFY_CATS` anlegen und beim Aufruf als `cat` angeben.
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
- **Heizen**: je Siedler und Tag `heat_wood_per_settler` Holz (Herbst 0,3, Winter 1) aus dem Lager,
  Kohle zuerst (1 Kohle = `heat_coal_wood` Holz, siehe „Kohle, Erfrieren und weitere Ergänzungen“).
  Fehlt beides, frieren die Siedler der Insel (`Seasons.cold`): Hunger x`cold_hunger`, Arbeit
  x`cold_work`, nach einer Schonzeit erfrieren sie.

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

### Wechselnde Winter und Sommer (Herausforderung)

Jedes Jahr hat einen **Wintertyp** (`mild` Milder Winter, `normal`, `hart` Harter Winter, `bitter` Eiswinter)
und einen **Sommertyp** (`normal`, `heiss` Heißer Sommer). Regelzeile für alte Spielstände: „Winter und Sommer
sind jedes Jahr anders. Im Herbst sagen die Alten voraus, wie hart der Winter wird.“

- **Würfeln**: zu Jahresbeginn (Frühlingsanfang) einmal, nur in `Seasons._process` mit Welt
  (`_ensure_year`), deterministisch aus `hash("<seed>:<jahr>:klima")` (`Seasons.roll_year`). Gewichte in
  `seasons.json` `climate_odds` (es gilt die Zeile mit dem größten `from_year` <= Jahr):
  Jahr 1 mild 50 / normal 50 (nie heiß), Jahr 2 mild 30 / normal 55 / hart 15, heiß 15 %, Jahr 3 25/50/20/Eis 5,
  heiß 20 %, Jahr 4–7 20/45/25/10, heiß 25 %, ab Jahr 8 15/40/30/15, heiß 30 %. `climate_no_repeat`: auf einen
  Eiswinter folgt höchstens ein harter Winter. Das Ergebnis wird gespeichert (spätere Änderungen der Gewichte
  ändern keinen schon angekündigten Winter).
- **Wirkung**: `seasons.json` `winters`/`summers` je Typ: Faktoren auf die Werte dieser Jahreszeit (gleiche
  Schlüssel wie die Listen: `heat_wood_per_settler`, `hunger`, `build`, `walk`, `sail`, `spoil_per_day`,
  `decay`; aus `mods`: `sickness`, `mood`; dazu `snow`, `growth` {Typ: Faktor}, `ill_<krankheit>`; fehlt =
  1). `Seasons._val`, `season_mod`, `growth` und `snow_amount` rechnen den Faktor ein, damit wirkt er auf
  Heizen, Hunger, Nahrung-Tage, Bauen, Laufen, Schiffe, Verderb, Krankheit, Laune und Nachwachsen.
  Ergebnis im Winter (mild / normal / hart / Eis): Heizholz je Siedler und Tag 0,6 / 1 / 1,4 / 1,8, Hunger
  1,09 / 1,15 / 1,22 / 1,29, Krankheit 1,6 / 2 / 2,3 / 2,6, Bauen 0,84 / 0,7 / 0,6 / 0,53, Fischgründe
  0,6 / 0,35 / 0,14 / 0; Palmen ebenso. Heißer Sommer: Verderb 12 % statt 8 %, Aas x1,25, Krankheit 1,0
  statt 0,8, Laune −3, Felder und Beeren x0,8, Obstgarten x0,85, Pilze x0,6, Ruhr doppelt so häufig
  (`SettlerMind._pick_illness`). Gewächshaus und Bäume bleiben gleich. Die Faktoren des laufenden Jahres liegen
  zwischengespeichert in `_w_tab`/`_s_tab` (eine Nachschlage-Operation je Abfrage).
- **Vorhersage** (ehrlich, nie falsch; Meldungsart `lager`, Symbol `sonne`/`schnee`): Frühlingsanfang: ein
  heißer Sommer wird angekündigt. Sommeranfang: grobe Vorhersage („Die Alten erwarten einen milden /
  gewöhnlichen / strengen Winter“, streng = hart oder Eiswinter; `winter_hints`). Herbstanfang: genauer Typ,
  Wirkung und geschätztes Heizholz aller Inseln (`Seasons.winter_wood_need()`). Letzter Herbsttag: die alte
  Wintervorwarnung, mit Typ. Forschung **Astronomie** (Wirkung `forecast`) nennt den genauen Typ schon im
  Sommer. Signal `Seasons.climate_announced(kind, type)` (`summer`, `winter_hint`, `winter`).
- **Anzeige**: `Seasons.season_title()` („Harter Winter“, sonst der Jahreszeit-Name) in Meldungen, im
  Laune-Grund und ab 900 Pixel Breite in der Leiste. **Klima-Symbol** (`scripts/ui/climate_badge.gd`,
  `Seasons.badge()`) rechts neben der Jahreszeit, auch auf dem Handy: Sonne auf Rot (heißer Sommer, ab der
  Ankündigung bis Sommerende), Schneeflocke auf Grün (mild), Blau (hart bzw. grob „streng“) oder Dunkelblau
  (Eiswinter), sobald der Winter bekannt ist. Antippen der Jahreszeit zeigt zusätzlich
  `Seasons.climate_text()`. Schmale Bildschirme (< 480): Leiste enger, Tag ohne Uhrzeit.
- **Für andere Systeme**: `Seasons.winter_type(y = dieses Jahr)` und `Seasons.summer_type(y)` (steht ab
  Frühling fest, auch wenn noch nicht angekündigt), `winter_forecast()` (was die Siedler wissen: "", Typ
  oder "streng"), `climate_factor(key)`, `Seasons.climate` (alle Jahre, z. B. für eine Wertung). `growth(type,
  w)` fragt `Events.growth_factor(type, w)` (Dürre, siehe Angekündigte Ereignisse) und nimmt das Kleinere aus
  Klima- und Ereignisfaktor (Faktor auf den Jahreszeitwert; Hitze und Dürre stapeln nicht).
- **Spielstand**: `climate` = {"<jahr>": {"w": Typ, "s": Typ}} über `Game.state_save`/`state_load`, alle Jahre.
  Alter Spielstand ohne `climate`: das laufende Jahr ist ein Schonjahr (normal/normal), gewürfelt wird ab dem
  nächsten Jahr. Unbekannte Typen werden beim Laden zu `normal`. Neues Spiel: `state_reset` leert alles.
- **Testhilfen**: `--winter=mild|normal|hart|bitter` und `--summer=normal|heiss` legen den Typ für alle
  Jahre fest (nach `--season`), `--climate=off` macht alle Jahre gewöhnlich (vergleichbare Läufe),
  `--climatetest=1` druckt die Verteilung über 200 Seeds x 20 Jahre, die Werte je Typ, alle Vorhersagen
  und Antipp-Texte, Astronomie, Speichern/Laden und den alten Spielstand. `--climatetap=1` tippt kurz vor dem
  Bildschirmfoto die Jahreszeit an (`=2`: Vorhersage der Jahreszeit) und meldet die Breite der Leiste. Der
  20-Sekunden-Bericht zeigt Klima, Heizholz und das Symbol.

## Kohle, Erfrieren und weitere Ergänzungen (Herausforderung)

josh, 2026-10-09: Kohle heizt zuerst, Siedler können erfrieren, haltbares Essen zuerst, Belohnung für die Einführung, keine Balken mehr im Siedler-Infofenster. Code in
`scripts/autoload/extras.gd` (`Extras`, kein eigener Autoload: Seasons hängt ihn in `_ready` als Kind an,
er meldet sich als System bei Game an).

- **Kohle heizt zuerst** (`Extras.burn_fuel`, aufgerufen von `Seasons._heat`): der Heizbedarf wird in Holz
  gerechnet (`heat_wood_per_settler`). Liegt Kohle im Lager der Insel, brennt zuerst sie: je ganze
  `heat_coal_wood` (2) Holz Bedarf eine Kohle. Holz brennt erst, wenn keine Kohle mehr da ist. 2 ist
  derselbe Wert wie in der Köhlerei (4 Holz → 2 Kohle): Kohle spart also kein Holz, braucht aber nur
  halb so viel Lagerplatz. Achtung: Kohle für Schmelzofen, Glashütte und Stahlwerk wird im Winter mit
  verheizt. `Extras.fuel(w)` = Holz + Kohle x 2. Vorhersage im Herbst, Antippen der Jahreszeit und
  Wintervorwarnung nennen mit Kohle (oder nach der Forschung Köhlerei) „etwa N Holz oder halb so viel
  Kohle; Kohle wird zuerst verbrannt (im Lager: K)“ (`Extras.need_text`). Der Bot rechnet die Kohle in
  seine Holzreserve ein (`heat_reserve` minus Kohle x 2, Notfall-Holzfäller nach `Extras.fuel`).
- **Erfrieren** (seasons.json `freeze`): solange eine Insel friert (`Seasons.cold`, kein Holz und keine
  Kohle), sammelt jeder Siedler dort Kälte (`Extras.exposure`, Spielstand `frost` {Siedler-ID: Wert}),
  je Tag so viel, wie die Jahreszeit Brennstoff verlangt (normaler Winter 1, Herbst 0,3, Eiswinter 1,8),
  Kinder und Alte (ab 80 % des Höchstalters) x`weak_factor` 1,5. Über `grace_days` (1) sinkt die
  Gesundheit um `damage_per_day` (100) x denselben Faktor; das normale Heilen (40 am Tag, wenn satt)
  läuft weiter. Bei 0 stirbt der Siedler (`World.kill_settler(s, "erfroren", "freeze")`,
  `stats.frozen`). Im Warmen sinkt die Kälte um `recover_per_day` (2). Normaler Winter ohne jeden
  Brennstoff: Kinder und Alte sterben nach etwa 1,6 Tagen, Erwachsene nach etwa 2,7; Eiswinter
  schneller. Inseln ohne Schnee (`snow_biomes` 0, Palmeninsel) sind ausgenommen.
  Meldungen: sobald der Brennstoff ausgeht „Kein Holz und keine Kohle … erfrieren in etwa N Stunden,
  Kinder und Alte zuerst“ (`Extras.cold_text`, Schätzung für den Schwächsten; über 72 Stunden ohne
  Zahl), sobald die Gesundheit des Ersten sinkt einmal „Die ersten Siedler erfrieren!“ (Art
  `gesundheit`), dann je Toter „… ist erfroren.“ Laune-Grund „Friert (kein Holz, keine Kohle)“.
- **Haltbares Essen zuerst**: siehe „Nahrung, Vitamine und Gleichgewicht“ (`Game.durable_first`).
- **Belohnung für die Einführung** (`Extras.tutorial_reward`, aus `GoalCard._advance`, wenn der letzte
  Schritt erfüllt ist; nicht beim Überspringen und nicht beim stillen Nachholen alter Spielstände): eine
  fertige Hütte auf dem ersten freien Platz um das Lagerfeuer (Ring für Ring, eine Zelle Abstand zu
  anderen Gebäuden; ohne Platz 16 Holz) und 2 Einwanderer über `Game.grant_reward(w, {"settlers": 2})`
  (eine Frau und ein Mann, mit niemandem verwandt). Meldung „Belohnung für die Einführung: 2 Einwanderer
  und eine fertige Hütte am Lagerfeuer.“
- **Siedler-Infofenster ohne Balken**: Sättigung, Gesundheit, Vitamine, Laune, Erholung, Eigenschaften und
  Fähigkeiten haben keine Balken mehr; Eigenschaften und Fähigkeiten stehen als eine Textzeile
  („Bauen 3 · Nahrung 4+ · …“, `Hud._info_text`). Die Werte selbst gibt es weiter (Siedlerliste, Laune-Gründe).
- **Alte Spielstände**: zwei Zeilen im Fenster „Neue Regeln“ (Kohle/Erfrieren, haltbares Essen).
- **Messung mit dem Bot** (3 Seeds 11/22/33, `--autotest=820 --noevents=1 --winter=normal`, je zwei Läufe
  vorher und nachher, dazu ein Gegenversuch ohne die Essensreihenfolge): kein Skorbut, keine
  Erfrorenen, keine Hungertoten, Vitamine im Schnitt gleich (88). Die Essensreihenfolge kostet etwas:
  verdorben je Lauf 184 statt 161 (+14 %), höchstens 26,5 statt 29,8 Siedler, Steinzeit-Prüfung im
  Schnitt Tag 24,0 statt 22,2 (3 von 6 Läufen erst in Jahr 3, vorher 0 von 6). Ohne sie (nur Kohle,
  Erfrieren, Bot) lagen die Werte wie vorher (159 verdorben, 29 Siedler, Tag 22,7). Der Bot friert je
  Lauf 0–2 Mal kurz (wie vorher), die Schonzeit reicht immer. Ein erster Versuch, bei dem Getreide als
  haltbares Essen galt, ließ die Siedler das Korn roh essen (Brot fast nie) und wurde verworfen; ohne die
  Vitamin-Ausnahme aßen die Siedler im `--schooltest` nur Brot und bekamen Skorbut (3 Fälle).
- **Testhilfen**: `--coaltest=1` (Kohle vor Holz, Texte; mit `--season=3` ein Winter mit `--coal=N
  --coalwood=N`), `--freezetest=1` (mit `--season=3 --winter=normal`: ein Kind und eine Alte dazu, das
  Lager bleibt ohne Brennstoff; Bericht mit Kälte und Gesundheit je Siedler, Reihenfolge der Toten),
  `--foodorder=1` (Essensreihenfolge), `--tutdone=1` (letzter Einführungsschritt: 2 Siedler, Hütte).

## Inselstärken, Gewürze und fremde Händler (Herausforderung)

Jede Inselart kann etwas besonders gut, Palmeninseln haben Gewürze, und an Häfen kommen fremde Händler, die
gegen Gold handeln. Regelzeile für alte Spielstände: „Jede Inselart hat Stärken. Palmeninseln haben
Gewürze. Händler kommen an Häfen und handeln gegen Gold.“

- **Inselstärken** (buildings.json `biome_bonus` = {Inselart: Faktor}): Felseninsel Erzmine x2, Steinbruch
  und Stahlwerk x1,5; Waldinsel Sägegrube, Köhlerei, Papiermühle x1,5; Palmeninsel Räucherei,
  Konservenfabrik, Solarpark x1,5; Heimatinsel keine. Der Faktor teilt die Zeit eines Arbeitsgangs
  (`Building.biome_factor()` in `Settler._plan_production` und `_do_take_inputs`); Wege, Pausen und
  Rohstoffe bleiben gleich, darum ist der Gewinn im Spiel kleiner als der Faktor.
  Anzeige: Bauliste „Inselstärke: hier x1,5 so schnell“ (grün) bzw. „Schneller auf: Felseninsel x1,5“,
  dieselbe Zeile im Infofenster des Gebäudes, Seekarte „Stärken:“ mit Gebäudesymbolen, islands.json-`desc`
  nennt sie. Helfer: `IslandTraits` (`scripts/world/island_traits.gd`): `factor`, `strengths`,
  `good_biomes`, `bonus_text`, `times` (x1,5 mit deutschem Komma).
- **Gewürze**: Rohstoffquelle `gewuerzstrauch` nur auf Palmeninseln, 8 Stück je Insel aus islands.json
  `extra` = [[Typ, Anzahl, Abstand von, bis, nur auf Gras]]. `IslandGen._place_extra` setzt sie in einem
  eigenen Durchgang mit eigenem Zufall (`hash([seed, "extra"])`), alle anderen Rohstoffe bleiben für jeden
  Seed gleich. Sammler (`jobs.json` targets) pflücken sie nur, solange die Insel genug Essen hat, dann
  aber zuerst (`IslandTraits.gather_order`: Essen >= 10 je Siedler). Wachstum je Jahreszeit in
  seasons.json. Alter Spielstand: `IslandTraits.patch_spice` setzt beim Laden die Sträucher einer
  Palmeninsel, die noch keinen hat, auf ihre Plätze (nur freie Felder, nicht neben Gebäude) und meldet
  „Auf … wachsen jetzt 8 Gewürzsträucher.“; sobald einer steht, passiert nichts mehr.
- **Fremde Händler** (Autoload `Merchant`, `scripts/autoload/merchant.gd`, Werte in `data/merchant.json`):
  sobald eine besiedelte Insel einen fertigen Hafen hat (`Sea.harbor_level >= 1`, die Werft zählt), kommt
  der erste Händler `first_after_days` (2) Tage später. Einen Tag vorher (`announce_days`) wählt er die
  Insel (nur mit Hafen und Siedlern, ohne angekündigte Piraten `Events.busy(w)`, Gewicht
  (1 + Hafenstufe) x Siedler) und meldet sich (Meldungsart `ereignis`, Symbol `haendler`). Er liegt
  `stay_days` (1) im Hafen, als eingefärbte Kogge vor dem Ufer (`add_ship`, Farbe `ship_tint`), und kommt
  `interval` (4–6) Tage nach der Abfahrt wieder. Kann keine Insel ihn aufnehmen, verschiebt er sich um
  `postpone_days`. Geht die angekündigte Insel bis zur Ankunft nicht mehr (z. B. Piraten angekündigt),
  wählt er eine andere und kündigt sich dort wieder einen Tag vorher an. Seehandel (Wirkung `trade` in techs.json): Abstand x0,7 und ein Verkaufslos mehr.
- **Lose**: 4 Verkaufs- und 3 Ankaufslose (dazu je 2 einfache, siehe unten), jedes 1–3-mal (`lot_times`). Losgröße für 6–14 Gold
  (`lot_gold`, resources.json `price`), billige Waren in Fünferschritten. Er verkauft zu x1,0–1,25
  (aufgerundet) und kauft zu x0,5–0,65 (abgerundet, mindestens 1 Gold). Angebot je Zeitalter (`sells`:
  Ware → ab Zeitalter); Gewürze bietet er immer an, solange keine Palmeninsel besiedelt ist, sonst in der
  Hälfte der Besuche. Ankauf aus `buys`, Gewürze zuerst, dann Waren, die die Insel hat.
  **Einfache Waren** (josh: „Gehandelt werden können auch einfache Güter wie Holz“): zusätzlich je Besuch
  `basic_sell_lots` (2) Verkaufs- und `basic_buy_lots` (2) Ankaufslose aus `basic` (Holz, Stein, Lehm,
  Getreide, Bretter, Ziegel ab Steinzeit, Kohle ab Antike; Ware → ab Zeitalter), Losgröße für
  `basic_lot_gold` (3–6) Gold in Fünferschritten (z. B. 30–60 Holz, 10–25 Bretter), gleiche Preisspannen.
  Eigener Zufall (`hash([seed, Besuch, "haendler_einfach"])`), eine Ware nie zugleich im Ver- und Ankauf,
  beim Ankauf zuerst Waren, die die Insel in der Menge hat. Die seltenen Lose bleiben vollständig (4 + 3),
  Ziegel und die einfachen Waren stehen dafür nicht mehr in `sells`/`buys`. `Merchant.is_basic(id)`. Zufall
  `hash([seed, Besuch, ...])`: gleicher Spielstand, gleiche Lose. Gold und Waren gehören immer der Insel,
  an der er liegt; `buy_block`/`sell_block` liefern den Grund, warum es nicht geht („zu wenig Gold“,
  „kein Platz im Lager“, „ausverkauft“, „nur 3 im Lager“ …). Jeder Handel zählt `stats.trades` und sendet
  `Game.player_action("trade", Ware)`.
- **Handelsfenster** (`scripts/ui/trade_panel.gd`, in `hud._panels()`): Name, Insel und Restzeit, Gold
  dieser Insel, Hinweis auf Gold anderer Inseln, Zeilen „Er verkauft“ / „Er kauft“ mit Symbol, Menge,
  „noch 2x“ bzw. Grund, Preis und 36 px hohem Knopf (auf 360 px Breite passend). Geöffnet über den
  **Händler-Knopf** oben (`scripts/ui/top_alerts.gd`, hud.top_alerts: breit links neben der
  Geschwindigkeit, schmal darunter; gold = liegt im Hafen, blass = angekündigt), das Infofenster eines
  Hafens oder der Werft und die Seekarte (Inselansicht: „Händler hier“ mit „Handeln“). Die Hilfe hat
  einen eigenen Absatz (`TradePanel.HELP`).
- **Spielstand**: oben `merchant` = {next, plan, island, until, seq, name_i, sells, buys} (Lose als
  [{id, n, gold, left}]). Alter Spielstand ohne `merchant`: erster Besuch `rules_day` + 2, falls schon ein
  Hafen steht, sonst 2 Tage nach dem ersten Hafen. Neues Spiel: `state_reset` leert alles.
- **Testhilfen**: `--tradetest2=1` (Werft, Waren und 40 Gold; prüft Lose, gleiche Lose bei gleichem Seed,
  Kauf, Verkauf, Gründe, Schiff, Speichern/Laden, Seehandel, alten Spielstand, Abfahrt, Ankündigung und den
  zweiten Besuch, druckt „Handel OK/FEHLER“; `=shot` legt nur den Händler hin), `--basictrade=1`
  (einfache Waren: Anzahl Lose, Losgrößen, 40 Besuche, Kohle erst ab Antike, Kauf, Verkauf, Speichern;
  druckt „Einfache Waren OK/FEHLER“), `--spicetest=1`
  (Generator, 20 Seeds, Kolonie, Reihenfolge der Sammler, alter Spielstand, Ernte über 2 Tage),
  `--biometest=1` (Tabelle, Arbeitszeit, Planung des Siedlers; je ein Tag Heimat/Felsen/Heimat nur zur
  Info), `--merchant=off` (keine Händler, für vergleichbare Läufe), `--goisland=N` (vor den Tests auf
  Insel N wechseln, dazu `--goplace=steinbruch,…` fertige Gebäude dort), `--panel=trade` (Handelsfenster
  fürs Bildschirmfoto).
  Der 20-Sekunden-Bericht zeigt Händler (Zustand, Insel, Tag, Lose, Handel) und Gewürze je Insel.

## Charaktere der Siedler

Alle Zahlen in `data/people.json` (`Data.ppl(key)`), Logik in `scripts/entities/settler_mind.gd`
(`SettlerMind`, je Siedler `settler.mind`, gespeichert als `mind` im Siedler-Eintrag; alte
Spielstände würfeln die Werte reproduzierbar aus der Siedler-ID).

- **Eigenschaften** 1–10 (`traits`): `iq` Klugheit (Lerntempo `0.6+0.08*iq`, Forschung `0.7+0.06*iq`),
  `konst` Gesundheit (robust/kränklich: Krankheitsrisiko, Dauer und Schaden), `fleiss` (weniger
  Freizeitbedarf, Arbeit `0.9+0.022*fleiss`), `gemuet` (Grundlaune). Anzeige als Wörter ab 7,5 bzw. bis 3,5.
- **Begabungen** je Fähigkeit 0,5–1,8 (`talents`). Ab `talent_show` (1,3) heißt sie **Talent** (Stern im Spiel).
  Seit josh 2026-10-10 stärker: Arbeitstempo mal `SettlerMind.talent_work` = 1 + `talent_work_bonus` (0,5) je Punkt
  über 1 (1,3 → +15 %, 1,5 → +25 %, 1,8 → +40 %; steckt in `Settler.skill_factor`, also in jeder Arbeit und in der
  Forschung), Schwächen unter 1 bremsen nicht. Erfahrung mal `talent_learn` = 1 + `talent_learn_bonus` (2,0) je Punkt
  über 1 (1,8 → 2,6-fach statt 1,8-fach), unter 1 wie bisher die Begabung selbst (`Settler.gain_xp`). Die KI
  (`AiJobs`) und der Test-Bot wählen nach `skill_factor`, also mit Talent.
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
- **Anzeige der Talente** (`scripts/ui/talent_info.gd`, Stern im Code gezeichnet, weil die Schrift kein ★ hat):
  Infofenster je Talent eine Zeile „Talent: Bauen (+40 % schneller, lernt +160 % schneller)“ mit Stern, sonst
  „Talent: keins“; Berufsknöpfe mit Stern, wenn die Fähigkeit des Berufs ein Talent ist (Tooltip mit Bonus).
  Siedlerliste: Spalte „Talent“ (z. B. „Holz +25 %“, ein Talent je Zeile, höchstens zwei Zeilen, bei mehr „…“; nur breit, sortierbar), Stern im Berufsmenü, Bonus im Tooltip
  am Namen. Meldung beim Erwachsenwerden nennt die Talente mit Bonus.
- **Anzeige**: Infofenster (Charakter, Begabungen, Krankheit, Laune mit Arbeitskraft, wichtigste
  Gründe, Eigenschaften und Fähigkeiten mit + für Begabung als Text; seit josh 2026-10-09 ohne Balken
  für Sättigung, Gesundheit, Vitamine, Laune, Erholung, Eigenschaften und Fähigkeiten), Siedlerliste
  (Spalte Laune, rot bei Krankheit, Filter „Nur Kranke“, Lebensstil im Zähler).
- Test: `--chartest=1` (täglicher Bericht), `--comfort=<n>` (n Forschungen erledigt), `--sick=<n>`,
  `--talenttest=1` (Tempo- und Lernbonus, Texte, Sterne im Infofenster und in der Siedlerliste, Spalte nur bei
  breitem Fenster; druckt „Talente OK/FEHLER“), `--select=1 --infoscroll=2000` (Bildschirmfoto der Berufswahl).

## Nahrung, Vitamine und Gleichgewicht

Ziel: eine Insel ist am Anfang schwer im Gleichgewicht zu halten, läuft aber stabil weiter, wenn sie
einmal aufgebaut ist. Dafür gilt:

- **Zwei Werte je Speise** (`resources.json`): `nutrition` = Sättigung, `vitamins` = Vitamine.
  Obst und Beeren sättigen wenig, haben aber viele Vitamine; Brot, Räucherfisch, Fleisch sättigen
  lange, haben kaum Vitamine. Rohes Getreide sättigt schlecht (10), Brot sehr gut (84).
  Abfragen: `Data.food_satiety(id)`, `Data.food_vitamins(id)`.
- **Siedler**: `hunger` (Sättigung 0–100, sinkt um `hunger_per_day` = 75). Vitamine, Speiseplan,
  Skorbut und Arbeitskraft gehören zum Charakter-Modell (`settler.mind.vit`, `mind.meals`, siehe
  „Charaktere der Siedler“). Beim Essen wählt `Game.choose_food(settler, w)` die Speise aus dem Lager seiner Insel (Kopf
  der Schleife in `Settler._do_eat`, sie hört bei `eat_until - 4` auf). Wertung je Sorte: gedeckter
  Sättigungsbedarf (bis `eat_until`), abzüglich `eat_waste_weight` (0.6) für Sättigung, die über den
  Bedarf hinausgeht; dazu gedeckter Vitaminbedarf (bis `vitamin_target`, doppelt bei Mangel unter
  `vit_low`); Abwechslung gegenüber `mind.meals`; Bonus für Verderbliches (`Seasons.spoil_rate(id)`);
  Bonus für große Vorräte; Abzug, wenn eine fertige Werkstatt die Ware als Zutat braucht (Weizen,
  Fisch). **Haltbares zuerst** (josh 2026-10-09, `Game.durable_first`): hat der Siedler genug Vitamine
  (mindestens `vitamin_target`), wählt er nur unter haltbarem Essen (nicht in seasons.json `perishable`,
  ohne Rohware einer Werkstatt wie Getreide: Brot, Räucherfisch, Kokos, Konserven), das andere erst, wenn
  nichts Haltbares mehr da ist. Wer Vitamine braucht, wählt aus allem. Innerhalb der Gruppe gilt die
  Wertung oben. `Game.eat_food(prefer_vitamins, w)` bleibt als einfache Wahl (Sättigendstes oder
  Vitaminreichstes) für andere Aufrufer. Die Mahlzeit meldet `mind.on_meal(id, Data.food_vitamins(id))`.
  `Game.eaten` zählt alles, `Game.last_eaten` ist die letzte Sorte. Test: `--foodtest=1`.
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

## Bedürfnisstufen der Bewohner (Herausforderung)

Häuser haben eine **Stufe** (buildings.json `level`): Hütte 1 Siedler, Holzhaus 2 Dorfbewohner, Steinhaus 3
Bürger, Mietshaus 4 Städter, Wohnblock 5 Großstädter. Ausbau Hütte → Holzhaus → Steinhaus → Mietshaus →
Wohnblock (`upgrade`, Forschung wie bisher). Kinder-Bonus (`birth_bonus`) Holzhaus 1,4, Steinhaus 1,8,
Mietshaus 1,8, Wohnblock 2,0. Regelzeile für alte Spielstände: „Häuser haben Bedürfnisse. Nur zufriedene
Häuser stellen Fachkräfte für höhere Werkstätten (z. B. Schmiede ab Holzhaus-Stufe).“

- **Bedürfnisse** (`data/levels.json`, `levels[k-1]` = Stufe k; jede Stufe braucht zusätzlich alles der
  Stufen darunter): 1 Nahrung, Wärme (nur Anzeige); 2 Abwechslung (3 Nahrungssorten im Lager), Möbel
  (0,15 Bretter je Verbraucher und Tag); 3 Zubereitetes Essen (Vorrat Brot/Räucherfisch/Eier/Konserven von
  0,5 je Verbraucher), Hausrat (0,06 Werkzeug), Schule (fertiges Gebäude mit `school`); 4 Glas 0,08,
  Papier 0,08, Gewürze 0,05; 5 Strom 0,4, Elektronik 0,04. Arten (`kind`): `good` (Verbrauch), `stock`
  (nur Vorrat), `variety`, `building` (`flag`), `food`, `warm`.
- **Rechnung** (`HouseNeeds`, `scripts/autoload/house_needs.gd`): je Insel alle `tick_days` (0,1 Tag,
  nur mit Welt, nicht bei Spielende oder Pause). Verbraucher der Gruppe k = Bewohner fertiger Häuser ab
  Stufe k (Erwachsene 1, Kinder `child_weight` 0,5). Waren werden über einen Bruchteil-Zähler (`acc`)
  ganzzahlig mit `Game.take_stock` verbraucht; Erfüllung = bekommen / gewollt, was fehlt, bleibt nicht
  als Schuld stehen. Jede Erfüllung wird geglättet (`tau_days` 0,5). Zufriedenheit der Stufe k =
  Mittel aller Bedürfnisse der Stufen 2..k. `ok(k)` mit Hysterese: an ab `on` 0,7, aus unter `off` 0,55.
  Ein Haus der Stufe L **zählt als** die höchste Stufe k <= L, bei der `ok(2)` bis `ok(k)` alle gelten
  (streng: ein Steinhaus ohne Möbel zählt als Stufe 1, auch wenn Stufe 3 im Mittel reichen würde), sonst
  als Stufe 1. `HouseNeeds.level_ok(w, k)` ist ebenso streng. Das Infofenster sagt „Zählt nur als
  Hausstufe 1 (Siedler), es fehlt: Möbel (Bretter) ...“. Bedürfnisse mit Ware heißen in der Anzeige
  „Möbel (Bretter)“, „Hausrat (Werkzeug)“ (`HouseNeeds.need_label`); Hausstufen heißen immer „Hausstufe“,
  „Stufe“ bleibt den Forschungsstufen.
  Wechsel melden sich (Meldungsart `siedler`, Symbol `haus`), nur wenn es Häuser dieser Stufe gibt.
- **Fachkräfte-Pool**: Werkstätten und Forschungsplätze haben `worker_level` (Standard 1): Stufe 2
  Schmelze, Schmiede, Werft, Bibliothek, Schreibstube 3 und 4; 3 Glashütte, Papiermühle, Universität,
  Stahlwerk, Konservenfabrik; 4 Fabrik, Kraftwerk, Elektronikwerk, Labor; 5 Solarpark, Fusionsreaktor,
  KI-Zentrum. Fachkräfte(k) = Erwachsene in Häusern, die als Stufe >= k zählen; belegt(k) = Siedler in
  fertigen Gebäuden mit `worker_level` >= k. Einen Platz der Stufe L darf ein Siedler nur nehmen, wenn
  für alle k = 2..L belegt(k) < Fachkräfte(k) (ohne ihn selbst). Eine Stelle: `World.pool_allows(b, sid)`
  (→ `HouseNeeds.pool_allows`), abgefragt in `World.find_workshop`, `World.find_research_place`, beim
  Weiterforschen in `Settler._do_research` und in `AiJobs`. Wer schon arbeitet, hört nach dem
  laufenden Arbeitsgang auf, wenn der Pool kleiner wird. Abgewiesene melden sich je Insel und Stufe
  höchstens alle `turned_note_days` (3 Tage). Schalter `balance.json` `worker_levels` (false: keine Sperre).
- **Weitere Wirkungen**: Kinder-Bonus des Hauses und Laune „Wohnt schön“ nur, wenn das Haus als seine
  volle Stufe zählt (`HouseNeeds.full_level`); Laune „Bedürfnisse erfüllt“ +2 x Stufe x (0,5 + Charakter)
  bzw. „Bedürfnisse fehlen: …“ −(3 + 2 x Stufe) für Bewohner ab Stufe 2 (nur gemerkte Werte). Ausbau eines
  Hauses ab Stufe 2 erst, wenn es voll zufrieden ist (`World.upgrade_building`, Knopf gesperrt).
  `World.assign_homes` setzt Siedler zuerst in die höchsten Häuser. Nachwuchs rechnet je Insel mit deren
  eigenem Essen und eigener Abwechslung.
- **Anzeige** (`scripts/ui/needs_info.gd`, je eine Zeile in hud.gd): Haus: „Hausstufe 5: Großstädter“,
  rote Zeile „Zählt nur als Stufe …“, Balken Zufriedenheit (grün/rot), je Stufe die Bedürfnisse mit Wert
  (grün ab 0,7, gelb ab 0,4, sonst rot). Werkstatt/Forschung ab Stufe 2: „Arbeiter ab Stufe …“,
  „Fachkräfte Stufe k: belegt / vorhanden“ und ein roter Hinweis, wenn Plätze frei bleiben. Ausbau:
  gesperrter Knopf mit Grund. Siedler: „Zuhause: Wohnblock · Bürger“ (Stufe, als die das Haus zählt).
  Bauliste: Stufe und neue Bedürfnisse bzw. Arbeiterstufe.
- **Für andere Systeme**: `HouseNeeds.effective_level(b)`, `full_level(b)`, `count_level(w, k)` (Häuser,
  die als Stufe >= k zählen), `level_ok(w, k)`, `level_sat(w, k)`, `level_name(k)`, `pool(w, k)` →
  [belegt, Fachkräfte], `turned_away`.
- **Spielstand**: oben `needs` = {"<insel-id>": {sat: {Bedürfnis: 0..1}, ok: {"2".."5": bool}, acc:
  {Ware: Rest}, grace: time_days}}. Alter Spielstand (oder Insel ohne Eintrag): alles zufrieden, `ok` an
  und einen Tag Schonfrist (`grace_days`), in der keine Stufe abfällt.
- **Testhilfen**: `--needstest=1` (alles erforscht, alle Häuser und Fachgebäude, 36 Siedler; vier
  Abschnitte: alles da, ohne Waren, auch ohne zubereitetes Essen, wieder alles; prüft Pool, Kinder-Bonus,
  Laune, Ausbau, Speichern/Laden und alten Spielstand, druckt „Bedürfnis-Test OK/FEHLER“).
  `--needstest=shot|drop` baut dasselbe und hält alle Waren bzw. alle außer den Bedürfnis-Waren vorrätig
  (für Bildschirmfotos). `--needsscroll=N` rollt das Infofenster nach `--selectb` um N Pixel.
  `--workerlevels=0` schaltet die Sperre ab. Der 20-Sekunden-Bericht zeigt je Insel Zufriedenheit,
  Häuser, Fachkräfte und Abgewiesene.

## Angekündigte Ereignisse (Herausforderung)

Ab dem zweiten Jahr trifft jede Insel ab und zu ein Ereignis, das sich vorher ankündigt: Dürre, Ratten,
Brand, Seuche, Sturmflut und ab dem Mittelalter Piraten. Wer vorbereitet ist (Forschung, Gebäude, Vorräte),
kommt gut durch; wer eine Dürre, Seuche oder einen Piratenüberfall ohne Tote übersteht, bekommt einen
Einwanderer. Regelzeile für alte Spielstände: „Ab dem zweiten Jahr kündigen sich Ereignisse an: Dürre,
Ratten, Brand, Seuche, Sturmflut und ab dem Mittelalter Piraten. Wer sie gut übersteht, bekommt Einwanderer.“

- **Zeitplan** (Autoload `Events`, `scripts/autoload/events.gd`, Werte in `data/events.json`): frühestens ab
  Spieltag `start_day` (13 = erster Tag von Jahr 2), nie während der Einführung (`Game.goals.tut` kleiner
  als die Zahl der Einführungsziele). Je besiedelter Insel höchstens ein Ereignis; das nächste frühestens
  `interval` (8–16) Tage nach dem Ende des letzten, dazu zufällig eine Jahreszeit früher, gleich oder später
  (`season_jitter` 1, mindestens `min_gap` 5 Tage; im Mittel bleibt es bei 12 Tagen). So wandern Ereignisse
  durch das Jahr (vorher kamen sie Jahr für Jahr in derselben Jahreszeit). Neue oder geladene Inseln
  haben `grace_days` (8) Schonzeit. Wer während der Vorwarnung stirbt, zählt nicht als Toter des Ereignisses.
  Zwischen zwei Ankündigungen auf allen Inseln mindestens `global_gap` (3) Tage. Ab `min_settlers` (6)
  Siedlern (Seuche und Piraten 8). Ankündigung `lead` (1–2) Tage vorher, Eintritt tagsüber (`strike_tod`
  0,3–0,55). Die Art wird nach der Jahreszeit beim Eintritt gewürfelt (`weights` Frühling, Sommer, Herbst,
  Winter; heißer Sommer x2 für Dürre und Brand; keine Seuche im harten oder strengen Winter), nie zweimal
  dieselbe Art hintereinander, nur Arten, die auf der Insel etwas treffen (`eligible`). Passt keine, wird
  `retry_days` später neu gewürfelt. Zufall `hash([seed, Insel, Nummer, "ereignis"])`.
  Stärke = clamp(0,5 + 0,1 x (Jahr − 2) + Siedler / 30, 0,5, 2,5).
- **Arten**:
  - **Dürre** (Sommer): bis zum Ende des Sommers (mindestens 1,5 Tage) wachsen Feld, Obstgarten, Beeren und
    Pilze mit 0,4 (mit Bewässerung 0,7). `Seasons.growth` nimmt das Kleinere aus Klima und Ereignis (kein
    Produkt: ein heißer Sommer mit Dürre ergibt 0,4). Nur mit fertigem Feld oder Obstgarten.
  - **Ratten**: fressen clamp(0,15 + 0,08 x Stärke, 0,15, 0,35) von Getreide, Mehl, Obst, Beeren, Pilzen,
    Kokos, Fisch, Eiern und Brot (`goods`; Konserven, Tontafeln, Papier nie), mit Großem Lager die Hälfte.
    Ab 30 solcher Waren.
  - **Brand**: 1 + ⌊Stärke / 1,25⌋ Gebäude (das erste zufällig, dann die nächsten) werden **beschädigt**,
    nicht abgerissen: wieder Baustelle, einfache Baustoffe (`basic_goods`) bleiben zu 70 % (`keep`), andere
    ganz, Bauarbeit von vorn, Bewohner und Arbeiter ziehen aus (`Events.damage_building`). Baumeister bauen
    mit der normalen Baustellen-Logik wieder auf. Kein Gebäude schützt davor (den Brunnen gibt es nicht
    mehr, siehe „Entfernte Gebäude und Forschungen“); der Rat lautet, Holz, Bretter und Stein bereitzuhalten.
    Nie: Lager, Häfen und Ufergebäude (`coast`), Gebäude mit Wirkung (`effects`), Felder, Lagerfeuer.
  - **Seuche** (2 Tage): Krankheitsrisiko x(1 + (m − 1) / Heilkunst) mit m = clamp(2 + 0,6 x Stärke, 2,5, 4)
    (`SettlerMind`, Heilkunde und Impfung über die Wirkung `heal`); 70 % der neuen Krankheiten sind die
    Seuchen-Krankheit (Fieber oder Ruhr, bei der Ankündigung genannt); ein Siedler erkrankt sofort.
  - **Sturmflut** (Herbst, Winter): Felder und Obstgärten bis 2 Felder vom Wasser verlieren ihre Ernte
    (brach), 1 + ⌊Stärke / 1,25⌋ Gebäude am Ufer werden beschädigt (Baustoffe 80 %). Deichbau (Wirkung
    `flood`) verhindert alles. Häfen, Werften und Ufergebäude bleiben heil.
  - **Piraten** (ab Zeitalter 2, mit Hafen oder Werft): clamp(2 + Siedler / 10 + (Zeitalter − 2), 2, 7)
    Piraten (`Raider`, `scripts/entities/raider.gd`, Unterklasse von `Animal`, Werte in events.json
    `raider`, Grafik Zeile 3 in animals.png) landen etwa 12 Felder vom Lager am Strand, ihr Schiff (rot
    gefärbte Kogge) liegt davor. Sie gehen zum nächsten Lager, plündern dort 4 Sekunden und gehen zurück;
    die Beute (je Pirat 6 + 4 x Stärke aus `loot`: Gold, Werkzeug, Eisen …) nehmen sie erst beim Ablegen aus
    dem Lager. Nach einem halben Tag gehen alle zurück, nach 0,8 Tagen sind sie fort. Sie greifen Siedler in
    3 Feldern an; Jäger und Wachtürme bekämpfen sie wie wilde Tiere. Vertriebene zählen `stats.pirates`,
    nicht als Jagd (kein Fleisch, keine Felle, nicht in `stats.kills`); wurde mindestens die Hälfte
    vertrieben, lassen sie je Vertriebenem 1 Gold zurück. Der Händler meidet die Insel (`Events.busy`).
- **Ende**: Meldungen bei Ankündigung (Ton `warnung`, was passiert, was hilft und ob es schon da ist:
  „Hilft: Bewässerung (noch nicht erforscht).“), Eintritt (Ton `glocke`) und Ende (Meldungsart `ereignis`).
  Ohne Tote nach Dürre, Seuche oder Piraten (`reward`): `stats.events_survived` + 1 und ein Einwanderer, ohne
  freien Wohnplatz Waren je Zeitalter (`reward_goods`) über `Game.grant_reward`. `stats.events` zählt alle.
- **Anzeige**: Ereignis-Knopf (`scripts/ui/event_chip.gd`) in `hud.top_alerts`: Symbol der Art, gelb =
  angekündigt, rot = läuft; breit dazu „Dürre in 30 Std.“ bzw. „Seuche noch 20 Std.“ und „+1“ für weitere
  Inseln, schmal nur das Symbol. Antippen zeigt alle Ereignisse mit Insel, Zeit und Gegenmittel. Liegen
  die Knöpfe unter der Geschwindigkeit, rücken die Meldungen darunter. Infofenster eines Piraten: Kraft,
  was er tut, seine Beute.
- **Für andere Systeme**: `Events.busy(w)` (Piraten angekündigt oder da), `growth_factor(type, w)`,
  `sickness_factor(w)`, `epidemic_illness(w)`, `event_of(w)`, `chip()`, `describe_all()`,
  `damage_building(w, b, keep)`, `near_water(w, c, size, r)`; Signal `changed`.
- **Spielstand**: oben `events` = {islands: {"<insel-id>": {next, last, ev}}, last, seq}; `ev` = {type, at,
  strike, end, power, deaths, struck, ill?, count?, left?, kills?, loot?, landing?}. Piraten selbst werden
  nie gespeichert (`World.serialize` lässt `Raider` aus); nach dem Laden landen die übrigen (`left`) neu.
  Alter Spielstand: jede Insel `grace_days` Schonzeit ab dem Laden.
- **Testhilfen**: `--eventtest=<duerre|ratten|brand|seuche|sturmflut|piraten|all>` (Ankündigung 0,05 Tage
  vorher, prüft die Wirkung, Gegenmittel, Belohnung, bei Piraten Speichern/Laden, Beute erst beim Ablegen
  und Abwehr mit Wachturm und Jägern; druckt „Ereignis-Test … OK/FEHLER“), `--eventsched=1` (sechs Jahre
  Zeitplan im Zeitraffer: erster Tag, Abstände, keine Art zweimal, Jahreszeit), `--noevents=1` (keine
  Ereignisse, für vergleichbare Läufe), `--skiptut=1` (Einführung überspringen, damit Bot-Läufe Ereignisse
  sehen). Bildschirmfotos: `--eventshot=<art>[:now]` (angekündigt bzw. eingetreten), `--eventtap=1`
  (Knopf kurz vor dem Bild antippen), `--selectraider=1` (`--raiderwait=N` Sekunden) wählt einen Piraten.
  Der 20-Sekunden-Bericht zeigt je Insel das Ereignis bzw. den nächsten Termin.

## Zeitalter

`techs.json` hat neben `_tiers` (16 Stufennamen) die Liste `_ages`: acht Zeitalter mit je zwei Stufen
(Steinzeit 1–2, Antike 3–4, Mittelalter 5–6, Renaissance 7–8, Industrialisierung 9–10, Moderne 11–12,
Informationszeitalter 13–14, Zukunft 15–16). `Data.age_of_tier(tier)`, `Data.age_name(i)`,
`Game.current_age()` = Zahl der bestandenen Prüfungen (`Exams.passed`, siehe „Prüfungen beim
Zeitalterwechsel und Wertung“); das neue Zeitalter meldet `Exams.pass_exam`. Im Forschungsmenü steht über jedem Zeitalter eine
Überschrift; Zeitalter jenseits des nächsten zeigen nur die Überschrift (`_age_header`).
`_ages[i].writing` nennt die Schreibwaren, die Forscher in diesem Zeitalter verbrauchen (siehe
„Forschung braucht Schriften“).

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

## Forschung braucht Schriften

Teil der Regeln ab Version 2 (siehe unten). Forscher verbrauchen ab der Antike Schreibwaren, und
Forschungen kosten mehr.

- **Verbrauch**: je 100 gutgeschriebene Forschungspunkte (Punkte mal `eff("research")`) die Mengen aus
  `techs.json` `_ages[i].writing`: Steinzeit nichts, Antike 10 Tontafeln, Mittelalter 4 Tontafeln,
  Renaissance 2,5 Papier, Industrialisierung 1,5 Papier, Moderne 1 Papier + 2 Strom,
  Informationszeitalter 2 Strom + 0,15 Elektronik, Zukunft 1,5 Strom + 0,1 Elektronik. Je Forschung ist das
  fest `ceil(Punkte × Rate / 100)`, z. B. Heilkunde 300 Punkte = 30 Tontafeln, Papier 3900 Punkte = 156
  Tontafeln. Genommen wird aus dem Lager der Insel des Forschers (Forschung ist gemeinsam, Lager je Insel:
  eine Kolonie mit eigener Schreibstube braucht eigene Tafeln oder ein Schiff, das sie bringt).
- **Rückfall**: eine Ware zählt nur, wenn ein Gebäude, das sie herstellt, schon freigeschaltet ist
  (`Game.is_unlocked`); lässt sich keine Ware des Zeitalters herstellen, gilt die Liste des Zeitalters davor
  (wiederholt). So brauchen Antike-Forschungen vor der Töpferei nichts, die Forschung Papier noch Tontafeln,
  Elektrizität nur Papier und Computer nur Strom. Es zählt, was freigeschaltet ist, nicht was gebaut ist:
  nach Papier brauchen Forschungen Papier, auch wenn noch keine Papiermühle steht (die Meldung sagt dann
  „Baue: Papiermühle“). Das Ergebnis je Forschung wird zwischengespeichert (`Writing.goods_for`) und in
  `Game._recompute_effects` geleert.
- **Fehlt etwas**: liegt von einer Ware keine ganze Einheit im Lager, bringt der Arbeitsgang nur
  `balance.writing_missing_factor` (0,2) der Punkte und verbraucht nichts. Meldung (Art Forschung) höchstens
  einmal am Tag je Insel mit dem Gebäude, das fehlt („Baue: Tafelmacherei“) oder nichts liefert („Prüfe:
  ...“); der Forscher zeigt „Forscht langsam, es fehlen Tontafeln“. Passive Forschung
  (`passive_research_per_day`) und Punkte aus Belohnungen (`Game.add_research` direkt) bleiben frei.
- **Code**: Autoload `Writing` (`scripts/autoload/writing.gd`). `Settler._do_research` ruft
  `world.use_writing(Writing.goods_for(t), pts * eff)` (→ `Writing.consume`) und multipliziert die Punkte
  mit dem Ergebnis. Bruchteile sammeln sich in `World.writing_debt` (nicht gespeichert: beim Laden geht
  höchstens eine Einheit je Ware verloren). `stats.writing_used` zählt alle verbrauchten Einheiten (mit
  `stats.get(k, 0)` lesen).
- **Tafelmacherei** (Wissen, nach Töpferei, Holz 12 + Stein 6): ein Handwerker formt Lehm 2 → Tontafeln 3
  (4 s), gemessen etwa 15–25 Tafeln am Tag; eine Lehmgrube mit einem Steinmetz reicht dafür.
- **Kosten und Punkte**: Kosten Stufe 1 wie bisher, Stufe 2 ×1,5 (aufgerundet), ab Stufe 3 ×2; Gold und
  Felle bleiben gleich, Backkunst und Tierhaltung kosten weiter Mehl bzw. Weizen. Punkte Stufe 1–4 wie bisher,
  5–6 ×1,25, 7 ×1,5, 8 ×1,4, ab 9 ×1,25 (ab Stufe 5 auf 50 gerundet; Stufe 7 braucht jetzt mehr als
  Stufe 6). Die Zahlen stehen direkt in `techs.json` (`research_cost_factor` bleibt 1).
  Ausnahme Eisenkette (Balance-Runde 2026-10-09): Bergbau 500 → 420, Eisenverhüttung 600 → 500,
  Schmiedekunst 650 → 550 Punkte (je etwa −15 %, zusammen 280 Punkte weniger). Grund: Schmiede und
  Werkzeug sind der letzte Schritt zur Antike-Prüfung (10 Werkzeug); mit 3 Forschern lag der Weg
  rechnerisch bei Jahr 7, so bei etwa Jahr 6 (mit 5 Forschern Jahr 4–5).
- **Oberfläche**: jede Forschungszeile „Beim Forschen: 24 Tontafeln“ (Rest für diese Forschung, auch bei
  gesperrten, in `_row_height` mitgezählt); Kopf des Forschungsfensters „Noch nötig: 63 Tontafeln (Lager: 0)“
  und rot „Es fehlen Tontafeln: Forschung nur 20 %. Baue: Tafelmacherei.“; Zeitalter-Überschrift
  „Forscher brauchen: Tontafeln“; Infofenster eines Forschungsgebäudes „Verbraucht beim Forschen:
  Tontafeln (Lager: N)“ (rot, wenn etwas fehlt; in der Steinzeit „Ab der Antike brauchen Forscher
  Tontafeln.“).
- **Alte Spielstände**: nichts zu übernehmen. Bezahlte Forschungen kosten nichts nach, der Fortschritt bleibt
  in Punkten (der Prozentwert sinkt, wo die Punkte gestiegen sind). Läuft gerade eine Forschung ab der
  Antike ohne Tafeln, forscht sie mit 20 %, bis eine Tafelmacherei liefert. Zeile im Fenster „Neue Regeln“.
- **Test**: `--writingtest=1`: prüft zuerst die Rückfall-Regel für elf Forschungsstände und
  `World.use_writing` direkt, dann Stufe 1–4 erforscht außer Schmiedekunst, Schreibstube, Lehmgrube,
  Tafelmacherei und Steinhaus fertig, 2 Forscher, Handwerker, Steinmetz, 0 Tontafeln; Tagesbericht
  „Schrifttest Tag ...“ mit Punkten am Tag, Tafeln hergestellt/verbraucht und langsamen Arbeitsgängen
  (gemessen: erst etwa 35–40 Punkte am Tag, mit Tafeln 100–135). `--writingtest=2`: ohne Tafelmacherei,
  bleibt bei etwa 20 Punkten am Tag. `--build=1 --research=1`: sobald eine bezahlte Forschung Tontafeln
  braucht, baut der Bot Tafelmacherei und Lehmgrube, teilt Steinmetz und Handwerker ein (nur bei genug
  Essen) und hält beide an, wenn genug auf Vorrat ist (Antike direkt: `--comfort=12`). Bildschirmfoto:
  `--panel=research --researchscroll=<forschung>`. Der 20-Sekunden-Bericht hat eine Zeile „Schriften: ...“.

## Prüfungen beim Zeitalterwechsel und Wertung

Teil der Regeln ab Version 2. Ein neues Zeitalter beginnt erst nach einer Prüfung; jede bestandene Prüfung
bringt ein Fest, Einwanderer und Waren. Dazu eine Wertung mit Rekorden (Menü > Wertung).

- **Sperre**: eine Forschung ist nur möglich, wenn ihr Zeitalter (`Data.age_of_tier(tier)`) höchstens
  `Exams.passed` ist; sonst hat sie den Zustand `exam` (`Game.tech_state`, Reihenfolge done/soon/current/
  locked/exam/available). `Game.current_age()` = `Exams.passed` (0 = Steinzeit). So lassen sich auch
  Forschungen mit Voraussetzungen aus früheren Zeitaltern (Handkarren, Glasmacherei, Papier, Uhrwerk) nicht
  vorziehen. `Game.start_research` meldet „Erst die Prüfung für das Zeitalter X bestehen.“
- **Prüfungen** in `techs.json` `_ages[i].exam` (i = 0..6; Prüfung i öffnet Zeitalter i+1, die Zukunft hat
  keine): `{checks: [...], fest_days, reward: {Ware: Menge, "settlers": n}}`. Bedingungen wie bei den Zielen
  (`GoalChecks`), dazu neu `age_techs` {age, n} (erforschte Forschungen dieses Zeitalters), `houses` {what, n}
  (dieses Haus oder ein besseres über `upgrade` oder die Hausstufe `level`, siehe Bedürfnisstufen), `no_starve_days` {n} (Tage
  seit dem letzten Hungertod, `stats.starve_day`), `food` {n}, `variety` mit `all` (alle Inseln), `tech`
  {what}, `exams` {n}. Waren werden auf allen Inseln gezählt und nicht verbraucht. Unbekannte Gebäude-IDs
  zählen 0 und erscheinen lesbar („Mietshaus“). Werte (zum Nachjustieren nach josh's Spieltest):
  - Steinzeit → Antike: 8 Steinzeit-Forschungen, 6 Siedler, 1 Holzhaus (oder besser), 3 Sorten Nahrung;
    2 Einwanderer, 10 Bretter, 10 Ziegel, 10 Tontafeln.
  - Antike → Mittelalter: 8 Antike-Forschungen, 12 Siedler, 1 Steinhaus, 20 Brot, 10 Werkzeug, 12 Tage ohne
    Hungertod; 2 Einwanderer, 10 Werkzeug, 6 Eisen.
  - Mittelalter → Renaissance: 8 Forschungen, 20 Siedler, 2 besiedelte Inseln, 1 Wachturm, 20 Werkzeug;
    2 Einwanderer, 20 Ziegel, 12 Kohle.
  - Renaissance → Industrialisierung: 6 Forschungen, 28 Siedler, 3 Inseln, 1 Universität, 20 Glas, 20 Papier;
    3 Einwanderer, 20 Eisen, 20 Kohle.
  - Industrialisierung → Moderne: 5 Forschungen, 36 Siedler, 1 Mietshaus, 20 Stahl, 6 Maschinen,
    20 Konserven; 3 Einwanderer, 12 Stahl, 4 Maschinen.
  - Moderne → Informationszeitalter: 6 Forschungen, 45 Siedler, 1 Wohnblock, 1 Kraftwerk, 1 Gewächshaus;
    3 Einwanderer, 16 Glas, 40 Strom.
  - Informationszeitalter → Zukunft: 4 Forschungen, 55 Siedler, 4 Inseln, 1 Forschungslabor, 30 Elektronik;
    3 Einwanderer, 20 Elektronik, 10 Gold.
- **Bestehen** geschieht von selbst: `Exams` prüft alle 0,25 Tage (und gleich nach einer fertigen Forschung),
  nur wenn das Spiel läuft (nicht auf dem Titelbild, nicht bei Pause). Dann: nächstes Zeitalter, Meldung
  „Prüfung bestanden! Ein neues Zeitalter beginnt: ...“ (früher in `_finish_research`), Sound `stufe`, Fest
  (`fest_days` = 1 Tag, Laune „Feiert das neue Zeitalter“ +`people.json fest_mood` = 15, „Fest!“ über den
  Siedlern), Belohnung über `Game.grant_reward` auf die besiedelte Insel mit den meisten freien Wohnplätzen
  (Einwanderer zuerst als Paar, mit niemandem verwandt; Waren auf dieselbe Insel).
- **Fest-Video**: Beim Fest geht mitten im Bild ein kleines Video auf (`FestVideo`, `scripts/ui/fest_video.gd`,
  Signal `Exams.fest_started(Anlass)`): 5,5 Sekunden Pixelbühne (96 Pixel hoch, 100..180 breit, ganzzahlig
  vergrößert, Handy 360 px: x3, PC 960x540: x4) mit Nachthimmel und Meer, Wimpelkette und drei Laternen,
  6 Siedlern aus den Spiel-Sprites, die um ein flackerndes Lagerfeuer tanzen (Funken, Arme hoch, kleine
  Sprünge), 8 Feuerwerksraketen, Konfetti und einem roten Banner „Fest!“ mit dem Anlass („Ein neues
  Zeitalter: Antike“). Alles wird im Code gezeichnet, ohne neue Bilddateien; jedes Bild hängt nur von der
  Zeit ab. Es läuft in Echtzeit (auch bei Tempo 3 oder Pause gleich lang), das Spiel läuft darunter weiter
  (kein Anhalten, damit es nicht mit anderen Fenstern um das Tempo streitet). Sound `stufe`. Tippen oder
  Klicken (auch Esc, Leertaste, Enter) überspringt, danach schließt es sich selbst. Ein neues Fest ersetzt
  ein laufendes Video. In Selbsttests erscheint es nur mit `--festvideo=1` oder `--panel=fest`.
- **Anzeige**: im Forschungsfenster unter der Überschrift des nächsten Zeitalters ein Kasten mit jeder
  Bedingung (Haken und grün, wenn erfüllt, sonst blasses Symbol und rote Zahl) und der Belohnung
  (`ExamView`, alle 0,5 s aufgefrischt); Forschungen dieses Zeitalters zeigen „Prüfung“ (Tippen nennt, was
  fehlt); der Kopf sagt „Alles erforscht, was jetzt geht. Bestehe die Prüfung ...“, wenn nichts anderes mehr
  geht. Die Zielkarte zeigt die Prüfung vor den Zielen, sobald sie das Weiterforschen aufhält (die
  Forschungen des Zeitalters reichen schon oder nichts anderes ist mehr zu erforschen; `Exams.blocking`),
  mit „Es fehlt noch: ...“ als Erklärung. Dieses Pseudo-Ziel (`exam_<i>`) bringt nie ein Ziel weiter.
- **Wertung** (`Exams.score_parts`, nimmt nie ab): 10 je Höchstbevölkerung, 50 je besiedelte Insel (auch
  verlorene, mit Heimat), 10 je entdeckte Insel, 15 je Forschung, 250 je Prüfung, 25 je erreichtes Ziel
  (`goals.ms`), 60 je Jahr ohne Hungertod (`stats.good_years`), 40 je Auftrag (`stats.quests`, Teil D),
  500 für eine gebaute Zukunftsstadt (`stats.future_city`). Menü > Wertung (neben Spielstände) zeigt die
  Punkte und die Rekorde; das Spielende-Fenster zeigt „Wertung: N Punkte“ und „Neuer Rekord: ...“.
- **Rekorde** in `user://settings.cfg` Abschnitt `[records]` (Testversion `[records_test]`), für alle
  Spielstände des Geräts: `score`, `max_pop`, `best_streak` (längste Zeit ohne Hungertod in Tagen), `days`
  (längstes Spiel), `age_1` .. `age_7` (frühester Spieltag, an dem das Zeitalter erreicht wurde; nur aus
  echten Prüfungen). Aktualisiert jeden Morgen, bei jeder Prüfung und am Spielende.
- **Spielstand**: Schlüssel `exams` = `{passed, days, fest_until, year, y_starved, beaten}` (`days[i]` =
  `time_days`, als Prüfung i bestanden wurde, -1 = übernommen; `beaten` = in diesem Spiel gebrochene Rekorde).
  Neue `stats`: `good_years`, `best_streak`, `future_city` (mit `stats.get(k, 0)` lesen).
  `Exams.sync()` in `Game._recompute_effects` zieht `passed` auf das späteste erforschte Zeitalter nach
  (Testhilfen, die Forschungen direkt eintragen).
- **Alte Spielstände**: ohne `exams` gilt als bestanden, was erforscht, bezahlt oder gerade in Arbeit ist
  (nichts Bezahltes wird gesperrt), die Tage sind -1 (keine Zeitalter-Rekorde). Jahre ohne Hungertod zählen ab
  dem Laden. Zeile im Fenster „Neue Regeln“.
- **Code**: Autoload `Exams` (`scripts/autoload/exams.gd`), Bedingungen `GoalChecks`
  (`scripts/ui/goal_checks.gd`, auch von `GoalCard` benutzt, für Aufträge erweiterbar), Oberfläche `ExamView`
  (`scripts/ui/exam_view.gd`).
- **Test**: `--examtest=N`: prüft Daten, unbekannte IDs, Haus-Stufen, Sperre und Speichern, besteht N Prüfungen
  sofort, erfüllt dann alle Bedingungen der Prüfung N bis auf ein Gebäude, reicht es nach 40 s nach und
  zeigt, dass sie von selbst besteht (mit Fest-Laune). Der Bericht hat eine Zeile „Pruefungen: ...“.
  `--build=1 --research=1`: der Forschungs-Bot überspringt eine Prüfung, wenn keine andere Forschung bezahlbar
  ist, aber eine des nächsten Zeitalters (wie früher der Sprung); `--strictexam` schaltet das ab.
  Bildschirmfotos: `--panel=research --examscroll=1`, `--examhint=1` (Zielkarte aufgeklappt),
  `--panel=score` (`--scorescroll=1`), `--gameovershot=1`.
  Fest-Video: `--festvideo=1` (besteht eine echte Prüfung: Video offen mit Anlass und Sound, im Bild, schließt
  nach 5,5 s selbst, Spiel läuft weiter, Überspringen per Klick, Fingertipp und Taste, ohne Testschalter kein
  Video; Ausgabe `FESTVIDEO ...` und am Ende `FESTVIDEO OK`), Bildschirmfoto `--panel=fest --festframe=2.4`
  (Standbild zu dieser Sekunde).

## Aufträge mit Wahl

Teil der Regeln ab Version 2. Nach der Einführung bietet das Auftragsbrett drei Aufträge an; der Spieler
sucht sich einen aus. Belohnungen sind Waren, Forschungspunkte, Einwanderer, dauerhafte Segen oder Baupläne.

- **Ablauf**: Die Ziele (Meilensteine) bleiben die Zeile „Ziel“ der Zielkarte (bzw. die Prüfung, wenn sie
  das Weiterforschen aufhält); darunter steht die Zeile „Auftrag“. Tippen auf die Zeile oder „Wählen (3)“ /
  „Details“ öffnet das Fenster „Aufträge“ (auch Menü > Aufträge, falls die Zielkarte aus ist). Nur ein
  Auftrag läuft zur Zeit, jeder hat eine Frist. Angebote gelten 1 Tag (`offer_days`), danach kommen nach
  `cooldown` (0,5 Tage) neue; ebenso nach Erfüllen, Scheitern oder Aufgeben. „Andere Aufträge“ bringt sofort
  drei neue, danach erst wieder nach `reroll_days` (1 Tag). Scheitern, Aufgeben und Neu-Würfeln kosten
  nichts. Ein Angebot, das schon erfüllt ist, fällt weg. Das Brett öffnet 0,25 Tage nach der Einführung
  (alte Spielstände gleich nach dem Laden). Zufall aus `hash([seed, seq, "auftrag"])`: gleicher Spielstand,
  gleiche Angebote.
- **Vorlagen** (`goals.json` `quests.templates`, Gewicht `w` 1–3 bestimmt die Belohnung, `days` die Frist
  nach dem Annehmen; A = Zeitalter, P = Siedler auch auf See, R = Forschungspunkte je Tag, gemessen über
  den letzten Tag, mindestens 4):
  - `vorrat_essen` (w1, 4 T.): beste herstellbare Speise (Brot, Räucherfisch, Konserven, Eier, sonst die
    sättigendste), Lager aller Inseln = jetzt + round5(max(15, 1,5·P)).
  - `vorrat_ware` (w1, 4 T.): herstellbares Material, + round5(clamp(4·P / Preis, 8, 100)).
  - `winterholz` (w1, bis Winterbeginn): Holz + P·3 (× Winterhärte, so wie die Siedler sie kennen
    (`Seasons.winter_forecast`, unbekannt = normal, „streng“ = hart): mild 0,75, normal 1, hart 1,5, bitter 2), weniger Kohle im Lager × `heat_coal_wood` (sie heizt zuerst), nur Frühling/Sommer mit mindestens 3 Tagen bis zum Winter.
  - `bauen` (w1, 4 T.; w2, 6 T. bei mehr als 60 Baukosten): ein freigeschaltetes Gebäude, das es noch nicht
    gibt (keine Denkmäler); sonst `bauen_mehr`: noch eins des größten Wohnhauses.
  - `wohnen` (w1, 5 T.): Wohnplätze + max(4, 0,25·P). `wachsen` (w2, 6 T.): Siedler + max(2, 0,15·P).
  - `forschen` (w2, 6 T.): eine wählbare Forschung (nie hinter einer Prüfung), bezahlt oder bezahlbar,
    mit höchstens 0,7·R·6 Restpunkten.
  - `jagd` (w1, 4 T., erst mit Jäger): min(3 + A, erlegbare Tiere), je Art bleiben `hunt_min_keep`.
  - `winter` (w2, bei hartem/bittrem Winter w3; bis zum Frühling): kein Hungertod; nur an Herbsttag 1–2.
    Scheitert beim ersten Hungertod (`stats.starved`), gelingt, wenn die Frist erreicht ist.
  - `liefern` (w2, 5 T.): ab 2 besiedelten Inseln und einem Schiff: Menge auf Insel Y (`stock_at`).
  - `geburten` (w1, 5 T.): 2 + P/8. `entdecken` (w2, 4 T., mit Schiff): eine neue Insel.
    `abwechslung` (w1, 3 T.): eine Sorte Nahrung mehr auf der besten Insel.
  Lager-Ziele höchstens `stock_space` (0,7) des freien Platzes, sonst (unter 8) keine Vorlage.
  „Herstellbar“: ein fertiges Gebäude stellt es her oder erntet es, eine Rohstoffquelle auf einer
  besiedelten Insel liefert es für einen freigeschalteten Beruf, oder Jäger jagen (Fleisch, Felle).
- **Belohnungen**: jedes Angebot eine; die drei Angebote haben verschiedene Vorlagen und möglichst
  verschiedene Arten, das leichteste bekommt Waren, höchstens eins einen Segen.
  - Waren **passend zur Lage** (josh: „Die Mengen der Belohnungen von Quests sollten an die Situation in
    Form von Menge und Art angepasst werden“; `QuestRewards`, `scripts/autoload/quest_rewards.gd`, Werte in
    `goals.json` `quests.adapt`). Art aus dem Bedarf (`QuestRewards.needs`), Gewicht in Klammern:
    Essen für weniger als 2 Tage (6, haltbarste Speise: Räucherfisch, ab Antike Brot, ab Industrie
    Konserven), Sommer/Herbst Essen bis Winterende (Herbst 5, Sommer 3,5), Brennstoff bis Winterende nach
    Wintervorhersage (Herbst/Winter 5, Sommer 3; Kohle im Lager zählt doppelt mit, ist die Köhlerei frei
    oder Kohle da, gibt es Kohle statt Holz, halbe Menge, Grund „zum Heizen im Winter“), Schreibwaren der laufenden Forschung (3), Bedürfnisse
    der Hausstufen, die es gibt (3; Bretter, Werkzeug, Brot, Glas, Papier, Gewürze ...), nächste Prüfung:
    Lagerwaren und Baukosten der verlangten Häuser/Gebäude, sobald baubar oder die Forschung wählbar ist
    (3), Kosten der drei günstigsten wählbaren Forschungen (2), Baustoffe unter 30 + 3 je Siedler (1).
    Punkte = Gewicht x Fehlbedarf in Gold / Budget (0,5–1,5); Zufall unter allen ab 60 % des Besten.
    Nie die Ware, die der Auftrag selbst verlangt, keine Ware doppelt in einer Runde, nie Waren, von denen
    genug da ist (`plenty`: ein Viertel des Lagers aller Inseln und mindestens 40 + 4 je Siedler).
    Ohne Bedarf: `goods_by_age` (Gewürze ab Renaissance) bis zum Zeitalter, nur Brauchbares (`usable`:
    Nahrung, Baukosten oder Rohstoff freigeschalteter Gebäude, Kosten naher Forschungen, Hausbedürfnisse,
    Schreibwaren); ist von allem genug da, gibt es Forschungspunkte statt Waren.
    Menge: Budget `goods_budget` (25) · w · (1 + A) Gold · Siedler-Faktor clamp(P / 8, 0,5, 2) / `price`;
    bei bekanntem Fehlbedarf 1,5-mal der Fehlbedarf, mindestens 30 % und höchstens 100 % des Budgets;
    höchstens `goods_space` (0,4) der Lagerkapazität und 60 % des freien Platzes aller Inseln für diese
    Ware, mindestens 3 (passt nichts, nimmt es das Dringendste trotzdem; der Rest wartet auf Platz).
    Beispiele (2 Siedler, Steinzeit): Hunger 16 Räucherfisch, Herbst mit knappem Essen 12 Räucherfisch,
    Herbst ohne Holz 35 Holz (Gewicht 3: 110). Anzeige mit Grund: „15 Bretter (für die Bewohner)“
    (`reward.why`: hunger, winter, heizen, schrift, haeuser, pruefung, forschung, bauen; im Spielstand
    optional, unbekannte fallen weg). Auf die sichtbare Insel, Überlauf auf andere (`Game.grant_reward`).
    Fällt eine andere Belohnung aus (Segen voll, Gebäude schon frei), wird die Ersatzware erst bei der
    Auszahlung gewählt.
  - Forschungspunkte: max(20·w, w·R). Direkt auf die laufende Forschung (`Game.add_research(p, false)`,
    also ohne Schreibwaren aus Teil E), was übrig ist oder ohne laufende Forschung in `rp_bank`; die Bank
    geht an die nächste gestartete Forschung (Meldung „Gesparte Forschungspunkte ...“).
  - Einwanderer (ab w2, nur wenn auf den Inseln so viele Wohnplätze frei sind und das Essen für 2 Tage
    reicht, `QuestRewards.settlers_ok`): 1 (w2) oder 2 (w3), Begabung beim Angebot gewählt (`talents`, Jagd erst mit
    Jäger), Begabung 1,5–1,8, Stufe 4 + A/2, Hunger 80, über `Game.grant_reward` (wer nicht landen kann,
    wird zu Brettern).
  - Segen (ab w2, dauerhaft, `boons` mit Obergrenze `cap`): Fischfang/Holzfällen/Steinabbau/Beerensammeln
    +15 % (bis 45 %), Ernte/Forschung/Lagerplatz/Bautempo/Werkstätten/Nachwuchs +10 % (bis 30 %),
    Heilung +25 % (bis 75 %), Lauftempo +5 % (bis 15 %), Tragen +1 (bis 3), Hunger −5 % (bis −15 %).
    Volle Segen werden nicht mehr angeboten (sonst Waren statt dessen). `Game._recompute_effects` rechnet
    sie über `Quests.add_boons(effects)` ein.
  - Bauplan (ab w2): ein baubares Gebäude ohne Hafen, Schiffe oder Wirkung, dessen Forschung schon wählbar
    ist (Voraussetzungen erforscht, Zeitalter erreicht, also nie an einer Prüfung vorbei), mit
    beschaffbaren Bau- und Betriebswaren. `Game.is_unlocked` fragt `Quests.has_plan`; die Bauliste zeigt
    „Bauplan aus einem Auftrag.“. Nie für die laufende Forschung und nie für die Forschung, die ein Auftrag
    „Erforsche X“ selbst verlangt (`plan_choices(exclude_tech)`). Ist das Gebäude bis zur Auszahlung
    schon frei, gibt es Waren.
- **Oberfläche**: Zielkarte (`GoalCard`, Zeile aus `QuestView.goal_row`): Symbol, „Auftrag“, Knopf,
  Text, Balken mit „wert/ziel“ und Restzeit („4 T. 14 Std.“). Das X blendet nur das Ziel aus, der Auftrag
  bleibt. Fenster „Aufträge“ (`hud._quest_panel`, in `_panels()`): drei Kästen mit Text, Frist, Belohnung
  und „Annehmen“, darunter „Andere Aufträge“; beim laufenden Auftrag Fortschritt, Restzeit und „Aufgeben“
  (zweimal tippen); unten „Segen und Baupläne“ und die Zählung. Meldungsart `ziel` („Aufträge“).
- **Spielstand**: Schlüssel `quests` = `{offers, active, next, offers_until, reroll_at, plans, boons,
  rp_bank, rp_marks, seq, stats, last}`; ein Auftrag ist `{tpl, w, days, until, accepted, check: {type, what,
  n, base, island, max}, survive, reward: {kind, what|key|talent, n|v}}`. Texte werden nicht gespeichert
  (`Quests.text_of` baut sie aus der Vorlage, die Sprache stimmt also). Zähler (Tiere, Geburten, Inseln,
  Hungertote) haben `base` = Wert beim Annehmen. Beim Laden fallen unbekannte Vorlagen, Waren, Gebäude,
  Forschungen und Segen weg, Zahlen werden umgewandelt, Segen auf die Obergrenze gekürzt.
  `stats.quests` (erledigt, 40 Punkte in der Wertung) und `stats.quests_failed`.
- **Alte Spielstände**: ohne `quests` öffnet das Brett gleich nach dem Laden, auch mitten in der Einführung
  (dann steht die Auftragszeile unter dem Einführungsschritt). Zeile im Fenster „Neue Regeln“.
- **Bedingungen**: `GoalChecks` (gemeinsam mit Zielen und Prüfungen) kann dafür neu `base`, `stock_at`
  {what, island}, `variety` mit `max` (beste Insel) und `starved`.
- **Code**: Autoload `Quests` (`scripts/autoload/quests.gd`, tickt alle 0,05 Tage, nur wenn das Spiel
  läuft), Oberfläche `QuestView` (`scripts/ui/quest_view.gd`). Die Winterhärte kommt aus
  `Quests.winter_type()` (Vorhersage aus den wechselnden Wintern; so verrät die Holzmenge nichts Geheimes).
- **Test**: `--questtest=N`: Generator (40 Runden, Regeln), jede Belohnungsart direkt (Waren, Forschung mit
  Bank, Einwanderer mit Begabung, Segen bis zur Obergrenze, Bauplan), Speichern/Laden mit unbekannten IDs,
  alter Spielstand, danach im laufenden Spiel Angebot N annehmen und erfüllen, einen Auftrag scheitern
  lassen, einen aufgeben, „Andere Aufträge“, Winter ohne und mit Hungertod, Ablauf der Angebote.
  `--questreward=goods|research|settlers|boon|plan` erzwingt die Belohnung, `--questfast=1` jede Frist 0,3
  Tage, `--questauto=1` überspringt die Einführung und nimmt jedes erste Angebot an (z. B. mit
  `--build=1 --research=1`). `--questadapt=1` (`QuestRewardsTest`): Belohnung je Lage (Hunger, Herbst mit
  knappem Essen, Herbst ohne Holz, mit Köhlerei Kohle statt Holz und Kohle im Lager deckt den Bedarf, Überfluss, Schreibwaren, Prüfung, Hausstufe 2, Mengen nach Siedlern,
  Zeitalter und Platz, Einwanderer nur mit Dach, 30 Angebotsrunden ohne doppelte Ware, Spielstand),
  druckt „Belohnung angepasst OK/FEHLER“; `--questadapt=shot --questshot=offers --panel=quests` zeigt
  eine Belohnung mit Grund. Der 20-Sekunden-Bericht hat eine Zeile „Auftraege: ...“. Bildschirmfotos:
  `--questshot=offers|active|card` (mit `--panel=quests` das Fenster), `--panel=build --cat=nahrung` zeigt
  den Bauplan.

## Regeln ab Version 2 (Herausforderung)

Grundgerüst für die Erweiterung „Mehr Herausforderung“ (Bedürfnisse, Schriften, Klima, Ereignisse,
Aufträge, Prüfungen, Händler). josh: „Die neuen Regeln greifen ab dem Laden“, alte Spielstände laden also
weiter und bekommen die neuen Regeln ab dem Ladezeitpunkt.

| Teil | Abschnitt | Autoload | Spielstand | Daten |
|---|---|---|---|---|
| H | Wechselnde Winter und Sommer (unter Jahreszeiten) | `Seasons` | `climate` | `seasons.json` |
| G | Inselstärken, Gewürze und fremde Händler | `Merchant` | `merchant` | `merchant.json`, `islands.json`, `buildings.json` `biome_bonus` |
| B | Bedürfnisstufen der Bewohner | `HouseNeeds` | `needs` | `levels.json`, `buildings.json` `level`/`worker_level` |
| C | Angekündigte Ereignisse | `Events` | `events` | `events.json` |
| E | Forschung braucht Schriften | `Writing` | – | `techs.json` `_ages[i].writing` |
| J | Prüfungen beim Zeitalterwechsel und Wertung | `Exams` | `exams` | `techs.json` `_ages[i].exam` |
| D | Aufträge mit Wahl | `Quests` | `quests` | `goals.json` `quests` |

Reihenfolge der Autoloads in `project.godot`: Seasons, Writing, Exams, Quests, HouseNeeds, Merchant, Events
(alle nach Game und Sea). Ein alter Spielstand zeigt im Fenster „Neue Regeln“ je Teil genau eine Zeile.

**Zusammenspiel der Teile**:
- Klima → Aufträge: Winterholz und das Gewicht des Winter-Auftrags folgen der Wintervorhersage
  (`Quests.winter_type()` aus `Seasons.winter_forecast()`).
- Kohle → Aufträge: Kohle im Lager zählt beim Winterholz-Auftrag und bei der Belohnung „zum Heizen im
  Winter“ als Brennstoff mit (`Extras.fuel`, 1 Kohle = `heat_coal_wood` Holz); ist die Köhlerei frei,
  ist die Heiz-Belohnung Kohle statt Holz. Kohle verkauft der Händler ab der Antike als einfache Ware.
- Kälte → Klima: wie schnell Siedler ohne Brennstoff auskühlen, folgt dem Heizbedarf der Jahreszeit
  (`Extras.cold_rate` = `Seasons.heat_per_settler()`), im Eiswinter also 1,8-mal so schnell.
- Klima → Ereignisse: Hitze verdoppelt Dürre und Brand, keine Seuche im harten Winter; `Seasons.growth`
  nimmt das Kleinere aus Klima und Dürre (`Events.growth_factor`).
- Prüfungen → alle: `Game.current_age()` = bestandene Prüfungen (Piraten ab Mittelalter, Händlerwaren,
  Auftragsbelohnungen, Baupläne nur bis zum erreichten Zeitalter, Forschungsaufträge nie hinter einer Prüfung).
- Hausstufen → Prüfungen: `houses` zählt über die Ausbaukette und `level` (Mietshaus, Wohnblock).
- Fachkräfte-Pool und Schriften wirken beide beim Forschen: `World.find_research_place` und die Fortsetzung
  in `Settler._do_research` fragen `pool_allows`, die Punkte kosten Schreibwaren aus dem Lager der Insel.
  Tafelmacherei und Lehmgrube sind Stufe 1. Hausbedürfnisse (Papier ab Stufe 4) und Forscher teilen sich
  das Lager.
- Ereignisse → Händler: der Händler meidet Inseln mit angekündigten Piraten (`Events.busy`). Ratten fressen
  keine Tontafeln und kein Papier.
- Aufträge → Wertung: 40 Punkte je erledigtem Auftrag (`stats.quests`); Segen und Baupläne laufen über
  `Game._recompute_effects` bzw. `Game.is_unlocked` (Baupläne zählen damit auch für die Schreibwaren).
- Oberleiste: Klima-Symbol neben der Jahreszeit; Händler- und Ereignisknopf in `hud.top_alerts`
  (`TopAlerts`, rechts neben dem Tempo, auf schmalen Bildschirmen darunter).
- Selbsttest `--integtest=1` (`scripts/autoload/integration_test.gd`) prüft diese Verbindungen
  („Zusammenspiel OK/FEHLER“).

- **Regelstand**: `Game.RULES` (= 1). Der Spielstand bekommt die Schlüssel `rules` (int) und `rules_day`
  (float, `time_days`, ab dem die Regeln für diesen Spielstand gelten). `SAVE_VERSION` bleibt 3: eine alte,
  im Browser zwischengespeicherte Version lehnt unbekannte Versionen ab und würde den Spielstand löschen.
  Speichert so eine alte Version erneut, fehlen die neuen Schlüssel wieder; jede Übernahme muss also
  wiederholbar sein. Damit dabei nichts verloren geht, legt `Game.save_game` (`_store_backup`) eine Kopie
  aller neuen Schlüssel (alles außer `OLD_SAVE_KEYS`), der Forschung (`done`, `paid`, `progress`,
  `current`) und je Insel der Gebäude und Waren, die alte Versionen nicht kennen (`V2_BUILDINGS`
  Tafelmacherei; `V2_GOODS` Tontafeln, Gewürze), unter `islands[0]["v2"]` ab; alte Versionen
  geben die Inseldaten unverändert weiter. Fehlt beim Laden `rules`, aber `v2` ist da
  (`_merge_backup`), kommt alles zurück: Prüfungen, Aufträge, Segen, Klima, Ereignisse, Händler,
  Forschungen (Vereinigung), Gebäude an ihrem Platz, wenn er frei ist (`_restore_backup_world`), und
  Waren, die dort fehlen. Bekannte Grenze: Gewürzsträucher (Palmeninsel) erzeugen in der alten Version
  Fehlermeldungen, bleiben aber im Spielstand. Alter Spielstand: `rules` fehlt (= 0), `rules_day` = Ladezeitpunkt. `Game.rules_old`
  ist der Regelstand des geladenen Spielstands; `rules_day` steht schon fest, wenn `state_load` kommt.
- **Systeme**: Autoloads melden sich in `_ready` mit `Game.register_system(self)` an (`Game.systems`).
  Signale in `Game`:
  - `state_reset()` am Ende von `reset_state` (neues Spiel; die neue Welt entsteht erst danach),
  - `state_save(data: Dictionary)` in `save_game` kurz vor dem Schreiben: eigene Schlüssel oben in
    `data` eintragen (nicht in `research` oder `goals`, die baut `apply_save_header` neu),
  - `state_load(data: Dictionary, old_rules: int)` aus `Game.after_load(data)`, das main.gd direkt nach
    `Sea.build_from_save` aufruft (alle Welten existieren). Danach gilt `rules = RULES`.
  JSON liefert Zahlen als float und Schlüssel als Text: immer mit `int()`/`str()` umwandeln.
- **Selbsttest der Systeme**: main.gd ruft für jedes angemeldete System `autotest_setup(args, main)`
  (nach den normalen Testvorbereitungen, vor der Schleife; darf `await` benutzen) und bei jedem
  20-Sekunden-Bericht `autotest_report()` (Text oder „“). So bekommen neue Systeme eigene Testschalter,
  ohne main.gd zu ändern. Systeme ticken über `Game.time_days`, nie über `Game.set_speed()`.
- **Meldungen beim Laden**: `Game.queue_note(text, icon, cat)` merkt sich Meldungen, solange das Spiel noch
  nicht sichtbar läuft (Laden, Titelbild: dort würden sie unter dem Titelbild verschwinden).
  `Game.flush_notes()` zeigt sie: in `main._on_continue` (nach dem Fenster „Neue Regeln“),
  `_on_new_game` und im Selbsttest; danach wirkt `queue_note` wie `notify`.
- **Fenster „Neue Regeln“**: Jedes System hängt in seinem `state_load`-Handler bei `old_rules < 1` ein bis
  zwei Zeilen in einfachem Deutsch (mit `tr()`) an `Game.rules_lines` an. Bei einem alten Spielstand ist
  `Game.rules_due` gesetzt; sobald das Spiel weiterläuft (nicht auf dem Titelbild), zeigt
  `Hud.show_rules_dialog(lines, on_close, pause)` die Zeilen einmal an, das Spiel steht so lange
  („Verstanden“). Wird vorher gespeichert, liegen die Zeilen als `rules_due` im Spielstand und kommen beim
  nächsten Laden wieder (in der dann gewählten Sprache: `Loc.name_of`). Ohne Zeilen erscheint kein Fenster. Der Selbsttest gibt stattdessen
  `NEUE REGELN (...)` und die Zeilen aus (`Game.rules_seen()`).
- **Statistik**: `stats.starved` (Hungertote) und `stats.starve_day` (`time_days` des letzten Hungertods,
  alte Spielstände: `rules_day`), immer mit `stats.get(k, 0)` lesen. `World.kill_settler(s, reason, cause)`
  bekommt neben dem Anzeigetext einen Schlüssel: `starve` (verhungert), `sick`, `old`, `killed`.
  Signal `Game.settler_died(settler, cause)`.
- **Belohnungen** (für Ereignisse, Aufträge, Prüfungen):
  - `Game.grant_reward(w, reward, opts = {}) -> String`: `reward` = {Waren-ID: Menge, "settlers": n}.
    Waren kommen auf Insel `w`, was dort keinen Platz hat, auf andere Inseln mit Platz („30 Bretter
    (10 davon auf Möweninsel)“). Der Rest geht nicht verloren, sondern wartet (`Game.reward_wait`,
    Spielstand `reward_wait`) und kommt ins Lager, sobald Platz ist (alle 0,25 Tage geprüft, es bleibt
    aber immer `wait_free_share` (15 %) des Lagers frei, damit die Ernte Platz hat); die Meldung sagt
    „(20 warten auf Platz im Lager)“, beim Einlagern „Wartende Waren sind jetzt im Lager: ...“. Einwanderer über `spawn_immigrants` (mit `opts`), wer nicht landen kann, wird zu
    10 Brettern. Liefert eine kurze Zusammenfassung („2 Einwanderer, 10 Bretter“); melden muss der Aufrufer.
  - `Game.spawn_immigrants(w, n, opts = {}) -> Array`: Erwachsene über `World.spawn_newcomer(sex, opts)`,
    abwechselnd Frau und Mann, zuerst das auf der Insel seltenere Geschlecht, mit niemandem verwandt.
    Kann niemand auf `w` landen: besiedelte Insel mit den meisten freien Wohnplätzen
    (`Game.immigrant_world(exclude)`), sonst 10 Bretter je Person (`opts.convert = false` schaltet das ab).
    `opts`: `talent` (Fähigkeit), `talent_val` (Begabung, Standard 1,5 bis `talent_max`), `skill`
    (Stufe darin, Standard 4 + Zeitalter/2, höchstens 7), `hunger` (Standard 80).
  - `Game.give_goods(w, id, n) -> [untergebracht, davon auf anderen Inseln]`.
- **Meldungsart** `ereignis` („Ereignisse und Händler“); Symbole `ereignis`, `haendler`, `feuer`, `ratte`
  gehören ohne Angabe zu dieser Art.
- **Preise**: jede Ware in `resources.json` hat `price` (Gold je Einheit, für Händler und Belohnungen);
  Schiffe und Strom haben keinen.
- **Neue Inhalte, vorerst nur Daten und Grafik** (die Regeln dazu bauen die einzelnen Erweiterungen):
  Waren `tontafel` (Tontafeln) und `gewuerze` (Gewürze, kein Essen); Rohstoffquelle `gewuerzstrauch`
  (2 Gewürze, wächst in 4 Tagen nach; auf Palmeninseln, siehe Inselstärken); Gebäude `tafelmacherei` (Wissen, nach
  Töpferei, Lehm 2 → Tontafeln 3 über die normale Werkstatt-Logik); Forschung `deichbau` (Stufe 4, Wirkung
  `flood`). Den Brunnen und Brunnenbau gab es auch, sie sind wieder entfernt (siehe unten).
- **Grafik**: `tools/gen_art_challenge.py` (von `gen_art.py` und `gen_art_sea.py` aufgerufen, hängt nur
  hinten an): buildings.png Zelle 51 `tablets` (Tafelmacherei), Zelle 52 bleibt leer (war der Brunnen); Symbole `tontafel`,
  `gewuerze`, `ereignis`, `haendler`, `feuer`, `ratte`; objects2.png `spice_full`/`spice_empty`
  (x 112/128, y 48); animals.png Zeile 3 (Höhe jetzt 96) mit dem Piraten (`Data.ANIMAL_ROWS`, kein Eintrag
  in animals.json; `Data.animal_tex("pirat", frame)`).
- **Alte Spielstände prüfen**: Mit dem Stand vor der Erweiterung (Commit 5851837) in einem eigenen
  `XDG_DATA_HOME` je Lauf `--build=1 --research=1` (2 Jahre), `--seatest=1`, `--schooltest=1` und
  `--prodtest=1 --ages=1` laufen lassen und `savegame.json` aufheben. Neue Version:
  `--fixture=<datei> --autotest=60` (einmal `NEUE REGELN`, kein SCRIPT ERROR), danach `--keep`
  (keine zweite Ausgabe).
- **Testhilfen**: `--seed=N` (feste Insel für neue Spiele), `--fixture=<pfad>` (Spielstand vor dem Laden in
  den aktiven Platz kopieren, weiter wie `--keep`), `--rulesdialog=1` (Bildschirmfoto des Fensters, ohne
  alten Spielstand mit Beispielzeilen), `--place=wachturm,tafelmacherei` (fertige Gebäude hinstellen),
  `--panel=build --cat=wissen --buildscroll=tafelmacherei` (Bauliste bis zum Gebäude rollen), `--rewardtest=1`
  (Belohnung mit Einwanderern, Lagerüberlauf und ein Hungertod).
- **Entfernte Gebäude und Forschungen** (josh, Oktober 2026: „Lass den Brunnen weg. Entferne ihn aus dem
  Code.“): Den Brunnen (`brunnen`) und die Forschung Brunnenbau (`brunnenbau`) gibt es nicht mehr, auch
  nicht im Bot, in Ereignissen, Aufträgen oder der Grafik. `scripts/autoload/retired.gd` (`Retired`, kein
  Autoload) kennt ihre alten Kosten (`BUILDINGS`, `TECHS`) und räumt alte Spielstände auf:
  `Retired.strip_save` (aus `Game.apply_save_header`, nach `_merge_backup`, vor dem Aufbau der Inseln)
  nimmt Brunnen aus den Inseldaten (auch Version 1 mit `world`) und aus der Sicherung für ältere Versionen
  (`_v2_restore`, damit dort keine Brunnen mehr zurückkommen) und Brunnenbau aus `done`, `paid`,
  `progress` und `current` (war es die laufende Forschung, ist keine gewählt). Zurück kommt je Insel das
  Baumaterial: ein fertiger Brunnen 10 Stein und 4 Holz, eine Baustelle das schon gelieferte Material,
  dazu die bezahlten Kosten von Brunnenbau (15 Stein, 15 Holz) auf die Heimatinsel; jedes Gebäude (ID)
  zählt einmal. `Retired.give_back` (aus `Game.after_load`, nach `state_load`) gibt es über
  `Game.grant_reward`: erst ins Lager der Insel, so weit Platz ist, dann auf andere Inseln, der Rest wartet
  auf Platz (`reward_wait`); nichts geht verloren. Einmal kommt die Meldung „Brunnen gibt es nicht mehr:
  3 Brunnen sind abgebaut. Baumaterial zurück: 41 Stein, 25 Holz.“ Danach steht im Spielstand nichts mehr
  davon, beim nächsten Laden passiert nichts. Test: `--fixture=<alter Stand mit Brunnen>
  --retiredtest=n:3,stein:41,holz:25` (erwartete Zahl und Summe aller Inseln; druckt „Entfernt OK/FEHLER“).

## Testversion

Pushes auf den Zweig `claude/entwicklungsbaum-x33t1h` landen unter `/New_World/test/`, main unter `/`
(Workflow mit `destination_dir` und `keep_files`). Die Testversion speichert in
`user://savegame_test.json` und kopiert beim ersten Start den normalen Spielstand
(`Game._detect_test_build`, lokal `--testbuild`). Der Titel zeigt „Testversion“.
Der Umbau „Mehr Herausforderung“ (Zweig `claude/project-thread-m73c7d`) landet unter `/New_World/neu/`
mit eigenem Spielstand `user://savegame_neu.json` (lokal `--neubuild`). Beim ersten Start kopiert sie das
Spiel, das im normalen Spiel gerade aktiv ist (`settings.cfg` [game] `slot`, sonst Platz 1). `Game.build_tag` ist „test“
oder „neu“; danach heißen der Spielstand-Platz (`slot_<tag>`) und die Rekorde (`records_<tag>`).

## Ordner

| Pfad | Inhalt |
|---|---|
| `data/*.json` | Alle Spielwerte (Ressourcen, Rohstoffquellen, Gebäude, Berufe, Balance, Namen) |
| `scripts/autoload/data.gd` | Lädt JSON, Sprite-Regionen (`OBJECT_REGIONS`), Icons |
| `scripts/autoload/game.gd` | Zeit, Vorräte, Nachwuchs, Abstammung, Forschung und Effekte, Speichern/Laden |
| `scripts/autoload/writing.gd` | Forschung braucht Schriften (Schreibwaren je Zeitalter) |
| `scripts/autoload/exams.gd` | Prüfungen beim Zeitalterwechsel, Fest, Wertung und Rekorde |
| `scripts/autoload/quests.gd` | Aufträge mit Wahl (Brett, Belohnungen, Segen, Baupläne) |
| `scripts/autoload/integration_test.gd` | Selbsttest `--integtest=1`: Zusammenspiel der Erweiterungen |
| `scripts/autoload/seasons.gd` | Jahreszeiten: Kalender, Wachstum, Heizen, Verderb, Frost, Schnee, Klima (wechselnde Winter und Sommer) |
| `scripts/autoload/house_needs.gd` | Bedürfnisstufen der Häuser, Fachkräfte-Pool (`data/levels.json`) |
| `scripts/autoload/merchant.gd`, `merchant_test.gd` | Fremde Händler (`data/merchant.json`) und ihre Selbsttests |
| `scripts/autoload/events.gd`, `events_test.gd` | Angekündigte Ereignisse (`data/events.json`) und ihre Selbsttests |
| `scripts/autoload/sea.gd` | Inseln, Welten je Insel, Schiffsreisen, Inselwechsel |
| `scripts/world/island_gen.gd` | Inselgenerator (Seed → Gelände + Rohstoffe) |
| `scripts/world/island_traits.gd` | Inselstärken (`biome_bonus`) und Gewürzsträucher |
| `scripts/autoload/extras.gd` | Kohleheizung, Erfrieren, Belohnung der Einführung und ihre Selbsttests (Kind von Seasons) |
| `scripts/world/world.gd` | Tilemaps, Wegfindung (AStarGrid2D), Entitäten, Bauen, Effekte, Tag/Nacht |
| `scripts/world/game_camera.gd` | Ziehen, Zoom (Mausrad, zwei Finger), Tippen |
| `scripts/entities/*.gd` | `Settler` (KI), `SettlerMind` (Charakter), `Building`, `ResNode`, `Animal`, `Raider` (Pirat) |
| `scripts/ui/hud.gd`, `ui_theme.gd`, `sea_panel.gd` | Oberfläche im Code gebaut, Pixel-Theme, Seekarte |
| `scripts/ui/goal_card.gd`, `goal_checks.gd` | Zielkarte oben links; gemeinsame Prüfung von Zielen, Prüfungen und Aufträgen |
| `scripts/ui/exam_view.gd`, `quest_view.gd` | Prüfungskasten und Fenster „Wertung“; Auftragszeile und Fenster „Aufträge“ |
| `scripts/ui/climate_badge.gd` | Klima-Symbol neben der Jahreszeit |
| `scripts/ui/needs_info.gd` | Anzeige der Bedürfnisstufen im Infofenster und in der Bauliste |
| `scripts/ui/trade_panel.gd`, `top_alerts.gd` | Handelsfenster der Händler, Hinweis-Knöpfe oben rechts |
| `scripts/ui/event_chip.gd` | Ereignis-Knopf oben rechts (angekündigte Ereignisse) |
| `tools/gen_art.py`, `gen_art_sea.py` | Erzeugen alle Grafiken in `assets/sprites/` (Pillow) |

## Koordinaten

- Logik-Raster = Eckpunkte des Geländes. Zelle `(x,y)` liegt bei Weltposition `(x*16, y*16)`.
- Gelände wird im **Dual-Grid** gezeichnet: Kachel `(x,y)` liegt zwischen den Eckpunkten
  `(x..x+1, y..y+1)` und wählt aus 16 Eckmasken (Bit 1 oben links, 2 oben rechts,
  4 unten links, 8 unten rechts). Drei Ebenen: Wasser (animiert), Sand, Gras.
- Gebäude: `cell` = obere linke Zelle, Größe aus `size`. Eingang = Zelle mittig unter
  der Grundfläche. `ground`-Gebäude (Felder) sind begehbar, alle anderen blockieren.

## Datenformate

- **resources.json**: `{id: {name, icon, category: "material"|"food", nutrition?, vitamins?, size, order, price?}}`.
  Alles mit `category: food` wird gegessen.
- **nodes.json**: Rohstoffquellen. `yield`, `capacity`, `work_time`, `skill`, `terrain`
  (`grass`, `land`, `shore_water`), `solid`, `regrow_days`, `on_empty` (`regrow`|`remove`),
  `sprites` {full: [...], empty, low, growing}.
- **buildings.json**: `size`, `sprite`, `buildable`, `cost`, `work`, optional `housing`,
  `storage`, `light`, `ground`, `farm` {yield, amount, grow_days, sow_time, harvest_time}.
- **jobs.json**: `skill`, `tool` (Sprite in tools.png), `targets` (Knotentypen oder
  `farm`/`construction`), optional `requires` (Forschung).
- **islands.json**: Inselarten, siehe Etappe 3 (dazu `extra`, siehe Inselstärken). **merchant.json**: fremde
  Händler, siehe dort; buildings.json `biome_bonus`. **events.json**: angekündigte Ereignisse, siehe dort. **animals.json**: `hp`, `damage`, `speed`,
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
  Siedler und Tiere werden gespeichert. Seit den neuen Regeln außerdem `rules`, `rules_day`, `rules_due`
  (siehe „Regeln ab Version 2“) und die Schlüssel der einzelnen Systeme (über `Game.state_save`).

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
godot --headless --fixed-fps 60 -- --autotest=25 --scale=10 --seed=11 --tutdone=1  # Einführung beenden: 2 Siedler, Hütte
godot --headless --fixed-fps 60 -- --autotest=100 --scale=10 --seed=11 --season=3 --coaltest=1  # Kohle vor Holz
godot --headless --fixed-fps 60 -- --autotest=200 --scale=10 --seed=11 --season=3 --winter=normal --freezetest=1  # Erfrieren
godot --headless --fixed-fps 60 -- --autotest=5 --scale=10 --foodorder=1  # Essensreihenfolge
godot --headless -- --autotest=150 --scale=10 --schooltest=1  # Steinhaus und Schule: Geburten, Schulkinder
godot --headless -- --autotest=130 --scale=10 --seed=7 --needstest=1  # Bedürfnisstufen und Fachkräfte
godot --headless -- --autotest=160 --scale=10 --seed=7 --tradetest2=1  # fremde Händler (auch --spicetest, --biometest)
godot --headless -- --autotest=200 --scale=10 --seed=7 --eventtest=all  # angekündigte Ereignisse (auch --eventsched=1)
godot --headless -- --autotest=230 --scale=10 --build=1   # ein ganzes Jahr, Bericht mit Jahreszeit und Holz
godot --headless -- --autotest=300 --scale=10 --seatest=1  # Werft, drei Inseln entdecken und besiedeln
godot --headless --fixed-fps 60 -- --autotest=60 --scale=10 --fixture=alt.json  # alten Spielstand weiterspielen
godot --headless --fixed-fps 60 -- --autotest=10 --scale=10 --fixture=wells.json --retiredtest=n:3,stein:41,holz:25  # Brunnen entfernt
godot --headless --fixed-fps 60 -- --autotest=200 --scale=10 --writingtest=1  # Forschung braucht Tontafeln
godot --headless --fixed-fps 60 -- --autotest=100 --scale=10 --examtest=0  # Prüfung beim Zeitalterwechsel
godot --headless --fixed-fps 60 -- --autotest=120 --scale=10 --questtest=1  # Aufträge mit Wahl
godot --headless --fixed-fps 60 -- --autotest=10 --scale=10 --seed=7 --questadapt=1  # Belohnungen passend zur Lage
godot --headless --fixed-fps 60 -- --autotest=60 --scale=10 --seed=7 --integtest=1  # Zusammenspiel der Erweiterungen
godot --headless --fixed-fps 60 -- --autotest=20 --scale=10 --talenttest=1  # Talente: Bonus, Sterne, Spalte (Spalte nur mit Fenster)
godot --headless --fixed-fps 60 -- --autotest=40 --scale=10 --fixture=sea.json --oncetest=1  # Einmal-Route hin und zurück
godot --headless --fixed-fps 60 -- --autotest=30 --scale=10 --seed=7 --basictrade=1  # Händler mit einfachen Waren
godot --headless --fixed-fps 60 -- --autotest=820 --scale=10 --seed=11 --bot=1 --noevents=1 --winter=normal  # Spiel-Bot v2, 4 Jahre
#   --fixed-fps 60 vor "--" rechnet so schnell wie moeglich (gleicher Spielverlauf); --seed=N feste Insel
#   dazu --wildlife=1: Tierbestand je Insel und Bau; --weak=1: ohne Waffenkunde (Tiere gefährlicher), Bildschirmfoto: --island=<id>, --panel=sea
# Bildschirmfoto-Optionen: --panel=research|build|stock|fest (--festframe=<s>), --selectb=<typ>, --look=1
godot --headless --fixed-fps 60 -- --autotest=25 --scale=10 --festvideo=1  # Fest-Video
xvfb-run godot --rendering-driver opengl3 -- --autotest=20 --shot=/tmp/bild.png
godot --headless --export-release "Web" build/web/index.html
```

**Spiel-Bot v2 (`--bot=1`, `scripts/world/bot.gd`)** misst die Balance: er spielt wie ein aufmerksamer
Spieler und nur über die öffentliche Spiellogik (Baustellen mit `place_building`, Berufe mit `set_job`,
Forschung mit `start_research`, `Quests.accept`, Werkstätten an/aus, Hoechstmengen im Lager mit
`Game.set_limit`). Er bekommt keine Waren geschenkt und erzwingt keine Prüfung. Die alten Bots
`--build=1`/`--research=1` bleiben unverändert; `--bot=1` ersetzt sie (nicht zusammen benutzen).
- Einführung: drückt „Überspringen“ auf der Zielkarte, damit Aufträge und Ereignisse kommen.
- Forschung: erst ein Auftrag mit Forschung, dann Steinzeit (Schrift … Mühlenbau), dann Antike
  (Backkunst zuerst); nur Bezahlbares, Heizholz bleibt liegen. Überspringt eine Forschung, die eine
  Ware braucht, die der gewünschten Forschung fehlt.
- Bauen (Wunschliste): Lager bei über 85 % zuerst (ab dem ersten Lager), Auftragsgebäude, bis zur
  Steinzeit-Prüfung das Holzhaus (Bretter dafür liegen schon vor der Zimmerei bereit), Obstgärten und
  Felder (je 1 + Siedler/4, Felder nur, solange kein Getreideberg liegt), Bäckerei und Mühle (Mühle
  erst nach der Prüfung, eine zweite bei Getreideberg), Räucherei, Schreibstube, Wohnplätze, Sägegrube, Lehmgrube und Tafelmacherei,
  Lager, Ziegelei, Steinhaus, Steinbruch, Schule …
  Wohnplätze nur, wenn die Nahrung reicht und die Siedlung nicht über das hinauswächst, was der letzte
  Winter satt gemacht hat (plus ein Viertel, mindestens 20; nach knappem Winter kein Wachstum).
- Berufe: Baumeister bei Baustellen, Forscher, Sammler/Fischer/Bauern nach einem Regler auf
  Nahrung-Tage (Ziel je Jahreszeit, im Herbst Wintervorrat) und nur so viele, wie Quellen da sind,
  Holzfäller nach Heizholz-Vorhersage (`Seasons.winter_forecast()`), Werkstätten nach Zielmengen.
- Aufträge: nimmt das beste Angebot an (Gebäude, Vorräte, Forschung; keine Schiffe/Häfen).
Ausgabe: alle 20 s `BOT (Tag ..)`, `BOT Berufe soll ..` und `BOT Nahrungskette ..` (Getreide/Mehl/Brot,
Lagerplatz, größte Waren, Werkstätten), je Jahr `BOT Jahr N zu Ende ..`, bei jeder bestandenen Prüfung
`BOT: Pruefung N bestanden (Tag x). Bedingungen zuerst erfuellt: ..` (wann jede Bedingung zuerst
erfüllt war) und am Ende eine Zeile `ERGEBNIS: Tag .. | Siedler .. | Pruefungen .. [Zeitalter Tag ..
(Jahr ..)] | Forschungen .. (Steinzeit, Antike, spaeter) | Hungertote .. (Jahr 1-2: ..) | Tote .. |
Tontafeln verbraucht .. | Auftraege erledigt, gescheitert | Ereignisse ueberstanden x von y | Wertung`.
Abnahme (3 Seeds 11/22/33, `--autotest=820 --noevents=1 --winter=normal`): Steinzeit-Prüfung in Jahr 2
(vor Tag 25), mindestens 3 Antike-Forschungen, Tontafeln verbraucht, keine Hungertoten in Jahr 1–2.
Läufe sind nicht ganz gleich (Zufall je Siedler): die Prüfung streut etwa zwischen Tag 19 und 25.
Stand Balance-Runde 2026-10-09 (Seeds 11/22/33, 820 s je mit und ohne Ereignisse, dazu Seed 11 über
8 Jahre): Steinzeit-Prüfung Tag 21–28 (Jahr 2–3), keine Hungertoten, Ereignisse alle überstanden; die
Antike-Prüfung schafft der Bot in 8 Jahren nicht, weil er nie Werkzeug herstellt (Köhlerei erst spät,
Mine nicht immer platzierbar, nur 3–4 Forscher, Forschung oft ohne Bezahlbares). Die Antike-Prüfung ist
damit vom Bot nicht messbar; die Punkte der Eisenkette sind von Hand gerechnet. Derselbe Seed streut
um bis zu 5 Tage (Seed 11 ohne Ereignisse: Tag 21 und Tag 26 bei gleichen Steinzeit-Daten); eine
Kürzung der Steinzeit-Stufe-2-Punkte um 15 % brachte keinen messbaren Unterschied und wurde verworfen.

Bei jedem Push auf `main` baut GitHub Actions die Web-Version und legt sie auf den
Branch `gh-pages` (GitHub Pages).

**Neueste Version laden:** Godots Service Worker (PWA) liefert beim Neuladen zuerst die alte Version
aus dem Cache; sein Signal `pwa_update_available` kommt dabei nicht an. Darum schreibt der Build
`version.txt` (gleiche Nummer wie im Spiel). Das HUD holt die Datei beim Start und alle 10 Minuten
ohne Cache (`_watch_updates`). Ist sie neuer, erscheint ein Fenster „Neue Version“ mit „Jetzt laden“ und
„Später“ (auch auf dem Titelbild, josh 2026-10-08: geladen wird nur von Hand), und der Menüknopf heißt
„Neue Version laden!“. Test: `--panel=update --shot=...`. `Game.load_newest_version()` speichert,
sperrt weiteres Speichern, löscht nur die Caches `Insel-Siedler-sw-cache-*` (die KI-Modelle liegen in
anderen Caches), meldet den Service Worker ab, holt index.html/js/pck neu und lädt mit `?v=` neu.
