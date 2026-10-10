class_name Extras
extends Node
## Ergänzungen nach josh's Ideen vom 2026-10-09 (Regeln ab Version 2):
## - Heizen mit Kohle: gibt es Kohle im Lager einer Insel, wird zuerst sie verheizt (1 Kohle heizt wie
##   `heat_coal_wood` Holz), Holz erst, wenn die Kohle alle ist (`burn_fuel`, aufgerufen von Seasons._heat).
## - Erfrieren: wer auf einer Insel ohne Brennstoff friert (Seasons.cold), sammelt Kälte. Nach einer
##   Schonzeit sinkt die Gesundheit, dann stirbt der Siedler ("freeze", "erfroren"); Kinder und Alte zuerst.
##   Palmeninseln (kein Schnee, `snow_biomes`) sind ausgenommen. Zahlen: seasons.json `freeze`.
## - Belohnung der Einführung (tutorial_reward) und die Essreihenfolge (Game.choose_food) haben
##   hier ihre Testhilfen.
## Instanz: Kind von Seasons (kein eigener Autoload), meldet sich als System bei Game an.

static var inst: Extras = null

## Siedler-ID -> gesammelte Kälte (Tage, gewichtet). Spielstand "frost".
var exposure: Dictionary = {}
var _hurt_noted: Dictionary = {}  # World -> true: "erfrieren"-Warnung für diese Kälte schon gezeigt
var _args: Dictionary = {}
var _test_deaths: Array = []


func _ready() -> void:
	inst = self
	Game.register_system(self)
	Game.state_reset.connect(func():
		exposure = {}
		_hurt_noted = {})
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)
	Game.settler_died.connect(_on_died)


## Abschnitt der Spielanleitung (hud.gd hängt ihn an).
const HELP := """[b]Kohle, Kälte und Vorräte[/b]
Im Herbst und Winter heizen die Siedler. Liegt Kohle im Lager, verbrennen sie zuerst die Kohle (1 Kohle heizt wie 2 Holz), Holz erst, wenn die Kohle alle ist. Fehlt beides, frieren sie: nach etwa einem Tag Kälte sinkt die Gesundheit, und sie können erfrieren, Kinder und Alte zuerst. Eine Meldung warnt, sobald der Brennstoff ausgeht. Auf Palmeninseln erfriert niemand.
Die Siedler essen zuerst haltbares Essen wie Brot, Räucherfisch, Kokosnüsse und Konserven, frisches Essen und rohes Getreide erst, wenn nichts Haltbares mehr da ist. Nur wer zu wenig Vitamine hat, greift trotzdem zu Obst und Beeren."""


static func help_text() -> String:
	return "\n\n" + Loc.t(HELP)


# ---------------------------------------------------------------- Kohle
## Wie viel Holz eine Kohle beim Heizen ersetzt.
static func coal_ratio() -> float:
	return maxf(0.1, float(Seasons.cfg.get("heat_coal_wood", 2.0)))


## Brennstoff einer Insel in Holz gerechnet (Holz + Kohle x coal_ratio).
static func fuel(w) -> float:
	return float(Game.amount("holz", w)) + float(Game.amount("kohle", w)) * coal_ratio()


## Heizt eine Insel: `acc` = angefangener Bedarf in Holz. Erst Kohle (ganze Stücke, je coal_ratio Holz),
## Holz nur, wenn keine Kohle mehr da ist. Gibt [Rest, warm] zurück; warm ist null, wenn nichts
## entschieden wurde (noch kein ganzes Stück fällig), sonst true (genug) oder false (es fehlt Brennstoff).
static func burn_fuel(w, acc: float) -> Array:
	var ratio := coal_ratio()
	if Game.amount("kohle", w) > 0:
		var kn := int(acc / ratio)
		if kn > 0:
			acc -= Game.take_stock("kohle", kn, w) * ratio
		if Game.amount("kohle", w) > 0:
			return [acc, true]  # es bleibt Kohle: das Holz wird nicht angerührt
	var need := int(acc)
	if need <= 0:
		return [acc, null]
	var got := Game.take_stock("holz", need, w)
	return [acc - need, got >= need]


## Text, wenn einer Insel der Brennstoff ausgeht (mit der Zeit bis zu den ersten Erfrorenen).
static func cold_text(w) -> String:
	if not can_freeze(w):
		return Loc.t("Kein Holz und keine Kohle zum Heizen: die Siedler frieren! Sie werden schneller hungrig und arbeiten langsamer.")
	var h := hours_to_first_death(w)
	if h >= 72:  # Herbst: es dauert, aber im Winter wird es ernst
		return Loc.t("Kein Holz und keine Kohle zum Heizen: die Siedler frieren! Sie werden schneller hungrig und arbeiten langsamer. Bleibt es kalt, erfrieren sie, Kinder und Alte zuerst.")
	return Loc.t("Kein Holz und keine Kohle zum Heizen: die Siedler frieren! Sie werden schneller hungrig, arbeiten langsamer und erfrieren in etwa %d Stunden, Kinder und Alte zuerst.") % h


## Text für die Wintervorhersage: geschätzter Brennstoff, mit Kohle, wenn es welche gibt.
static func need_text(wood: int) -> String:
	var coal := 0
	for w in Sea.all_worlds():
		coal += Game.amount("kohle", w)
	if coal <= 0 and not Game.is_researched("koehlerei"):
		return Loc.t("Ihr braucht etwa %d Holz zum Heizen.") % wood
	return Loc.t("Ihr braucht etwa %d Holz zum Heizen oder halb so viel Kohle. Kohle wird zuerst verbrannt (im Lager: %d).") % [wood, coal]


# ---------------------------------------------------------------- Erfrieren
static func freeze_cfg() -> Dictionary:
	var c = Seasons.cfg.get("freeze", {})
	return c if c is Dictionary else {}


## Können Siedler auf dieser Insel erfrieren? Nicht auf Inseln ohne Winter (Palmeninsel, snow_biomes 0).
static func can_freeze(w) -> bool:
	return w != null and freeze_biome(str(w.biome))


static func freeze_biome(biome: String) -> bool:
	return float(Seasons.cfg.get("snow_biomes", {}).get(biome, 1.0)) > 0.0


## Wie stark die Kälte einen Siedler trifft: Kinder und Alte (ab 80 % ihres Höchstalters) mehr.
static func weakness(s) -> float:
	var k := float(freeze_cfg().get("weak_factor", 1.5))
	if not s.is_adult() or s.age > s.max_age * 0.8:
		return k
	return 1.0


## Kälte je Tag: wie viel Brennstoff die Jahreszeit verlangt (normaler Winter 1, Herbst 0,3, Eiswinter 1,8).
static func cold_rate() -> float:
	return maxf(0.0, Seasons.heat_per_settler())


## Geschätzte Spielstunden, bis auf dieser Insel der Erste erfriert (der Schwächste, ab jetzt).
static func hours_to_first_death(w) -> int:
	var c := freeze_cfg()
	var grace := float(c.get("grace_days", 1.0))
	var dmg := float(c.get("damage_per_day", 100.0))
	var heal := float(Data.bal("heal_per_day"))
	var best := INF
	var r := cold_rate()
	if r <= 0.0:
		return 99
	for s in w.settlers:
		var k := weakness(s) * r
		var e := float(inst.exposure.get(s.id, 0.0)) if inst else 0.0
		var t := maxf(0.0, grace - e) / k
		var net := dmg * k - heal
		t += s.health / net if net > 0.0 else 99.0
		best = minf(best, t)
	return clampi(int(round(best * 24.0)), 1, 99) if best < INF else 99


func _process(_delta: float) -> void:
	var days := Seasons.dt_days
	if days <= 0.0 or Game.world == null or Game.is_over:
		return
	if _args.has("freezetest"):
		_test_keep_cold()
	var c := freeze_cfg()
	var grace := float(c.get("grace_days", 1.0))
	var dmg := float(c.get("damage_per_day", 100.0))
	var r := cold_rate()
	var seen := {}
	for w in Seasons.cold.keys():
		if not is_instance_valid(w) or not can_freeze(w) or r <= 0.0:
			continue
		for s in w.settlers.duplicate():
			seen[s.id] = true
			var k := weakness(s) * r
			var e := float(exposure.get(s.id, 0.0)) + days * k
			exposure[s.id] = e
			if e <= grace:
				continue
			s.health -= dmg * k * days
			if not _hurt_noted.has(w):
				_hurt_noted[w] = true
				Game.notify_at(w, tr("Die ersten Siedler erfrieren! Bringt sofort Holz oder Kohle ins Lager."), "abriss", "gesundheit")
				Sound.play_on("fehler", w)
			if s.health <= 0.0:
				w.kill_settler(s, tr("erfroren"), "freeze")
	# Wer wieder im Warmen ist, erholt sich
	var rec := float(c.get("recover_per_day", 2.0)) * days
	for id in exposure.keys():
		if not seen.has(id):
			exposure[id] = float(exposure[id]) - rec
			if float(exposure[id]) <= 0.0:
				exposure.erase(id)
	for w in _hurt_noted.keys():
		if not is_instance_valid(w) or not Seasons.cold.has(w):
			_hurt_noted.erase(w)


func _on_died(s, cause: String) -> void:
	if s != null:
		exposure.erase(s.id)
	if cause == "freeze":
		Game.stats["frozen"] = int(Game.stats.get("frozen", 0)) + 1
		if _args.has("freezetest"):
			_test_deaths.append([s.display_name, not s.is_adult(), s.age > s.max_age * 0.8, int(s.age)])


# ---------------------------------------------------------------- Spielstand
func _on_save(d: Dictionary) -> void:
	if exposure.is_empty():
		return
	var out := {}
	for id in exposure:
		out[str(id)] = snappedf(float(exposure[id]), 0.001)
	d["frost"] = out


func _on_load(d: Dictionary, old_rules: int) -> void:
	exposure = {}
	_hurt_noted = {}
	var f = d.get("frost", null)
	if f is Dictionary:
		for k in f:
			if str(k).is_valid_int():
				exposure[int(str(k))] = float(f[k])
	if old_rules < 1:
		Game.rules_lines.append(tr("Im Herbst und Winter wird zuerst Kohle verheizt, dann Holz. Fehlt beides, können Siedler erfrieren."))
		Game.rules_lines.append(tr("Die Siedler essen zuerst haltbares Essen wie Brot und Räucherfisch, frisches erst danach (außer wenn ihnen Vitamine fehlen)."))


# ---------------------------------------------------------------- Belohnung der Einführung
## Einführung zu Ende gespielt (nicht übersprungen): 2 Siedler (ein Paar, mit niemandem verwandt) und
## eine fertige Hütte nah am Lagerfeuer. Ruft GoalCard._advance einmal auf.
static func tutorial_reward(w) -> void:
	if w == null or not is_instance_valid(w):
		return
	var cell = hut_spot(w)
	var hut_txt := Loc.t("eine fertige Hütte am Lagerfeuer")
	if cell != null:
		w.place_building("huette", cell, true)
	else:  # kein Platz: das Holz für eine Hütte
		var n := int(Data.buildings["huette"].get("cost", {}).get("holz", 16))
		Game.give_goods(w, "holz", n)
		hut_txt = Loc.t("%d Holz für eine Hütte") % n
	var got := Game.grant_reward(w, {"settlers": 2})
	Game.notify_at(w, Loc.t("Belohnung für die Einführung: %s und %s.") % [got, hut_txt], "person", "siedler")


## Freier Platz für eine Hütte, möglichst nah am Lagerfeuer, mit Platz rundherum (oder null).
static func hut_spot(w):
	return free_spot(w, "huette")


static func free_spot(w, type: String):
	var sz: Array = Data.buildings[type].size
	for rad in range(3, 16):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var c: Vector2i = w.center + Vector2i(dx, dy)
				if not w.can_place(type, c):
					continue
				# eine Zelle Abstand zu anderen Gebäuden, damit die Wege frei bleiben
				var roomy := true
				for y in range(-1, int(sz[1]) + 2):
					for x in range(-1, int(sz[0]) + 1):
						if w.building_at.has(c + Vector2i(x, y)):
							roomy = false
				if roomy:
					return c
	return null


# ---------------------------------------------------------------- Selbsttest
## --coaltest=1 Kohle vor Holz, --freezetest=1 Erfrieren (mit --season=3),
## --tutdone=1 Einführung zu Ende spielen (Belohnung), --foodorder=1 haltbares Essen zuerst.
func autotest_setup(args: Dictionary, _main) -> void:
	_args = args
	var w = Game.world
	if args.has("coaltest"):
		_coal_test(w)
	if args.has("freezetest"):
		_freeze_setup(w)
	if args.has("foodorder"):
		_food_test(w)
	if args.has("tutdone"):
		_tut_test()


func autotest_report() -> String:
	var w = Game.world
	if w == null:
		return ""
	if _args.has("coaltest") or _args.has("freezetest") or Seasons.heat_per_settler() > 0.0:
		var ex := []
		for s in w.settlers:
			if exposure.has(s.id):
				ex.append("%s:%.2f/h%d" % [s.display_name, float(exposure[s.id]), int(s.health)])
		print("   Heizen: Kohle %d Holz %d (1 Kohle = %.1f Holz), frierend %d Inseln, erfroren %d, Kaelte %s" % [Game.amount("kohle", w), Game.amount("holz", w), coal_ratio(), Seasons.cold.size(), int(Game.stats.get("frozen", 0)), ex])
	if _args.has("freezetest"):
		print("   Erfroren der Reihe nach (Name, Kind, alt, Alter): %s" % [_test_deaths])
	if _args.has("tutdone") or _args.has("tuttest"):
		var huts: int = w.buildings.filter(func(b): return b.type == "huette" and b.complete).size()
		print("   Einfuehrung: tut=%d/%d, Siedler %d, Huetten %d" % [int(Game.goals.get("tut", 0)), Data.goals.get("tutorial", []).size(), w.settlers.size(), huts])
	return ""


static func _ok(c: bool) -> String:
	return "OK" if c else "FEHLER"


func _coal_test(w) -> void:
	var keep := {"holz": Game.amount("holz", w), "kohle": Game.amount("kohle", w)}
	w.stock["holz"] = 20
	w.stock["kohle"] = 3
	var r := burn_fuel(w, 2.5)  # 1 Kohle (= 2 Holz) fällig, 0,5 bleibt
	var c: bool = Game.amount("kohle", w) == 2 and Game.amount("holz", w) == 20 and r[1] == true and is_equal_approx(float(r[0]), 0.5)
	print("Kohle-Test %s: Bedarf 2,5 Holz: 1 Kohle verbrannt, Holz unberuehrt (Kohle %d, Holz %d, Rest %.2f)" % [_ok(c), Game.amount("kohle", w), Game.amount("holz", w), r[0]])
	r = burn_fuel(w, 1.5)  # weniger als eine Kohle fällig: warten, Holz bleibt
	c = Game.amount("kohle", w) == 2 and Game.amount("holz", w) == 20 and r[1] == true
	print("Kohle-Test %s: Bedarf 1,5: noch keine Kohle faellig, kein Holz" % _ok(c))
	r = burn_fuel(w, 7.0)  # 3 Kohle fällig, nur 2 da: 4 Holz-Anteil aus Kohle, 3 aus Holz
	c = Game.amount("kohle", w) == 0 and Game.amount("holz", w) == 17 and r[1] == true
	print("Kohle-Test %s: Bedarf 7: Kohle alle (0), dann 3 Holz (Holz %d)" % [_ok(c), Game.amount("holz", w)])
	w.stock["holz"] = 1
	r = burn_fuel(w, 3.0)
	print("Kohle-Test %s: Bedarf 3, nur 1 Holz: es fehlt Brennstoff" % _ok(Game.amount("holz", w) == 0 and r[1] == false))
	w.stock["holz"] = 20
	w.stock["kohle"] = 0
	print("Kohle-Test %s: Vorhersage ohne Kohle: %s" % [_ok(need_text(30).contains("30")), need_text(30)])
	w.stock["kohle"] = 5
	print("Kohle-Test %s: Vorhersage mit Kohle: %s" % [_ok(need_text(30).contains("5")), need_text(30)])
	print("Kohle-Test Kaelte-Text: ", cold_text(w))
	w.stock["holz"] = int(_args.get("coalwood", keep.holz))
	w.stock["kohle"] = int(_args.get("coal", 12))
	print("Kohle-Test: Lauf mit Kohle %d und Holz %d (mit --season=3 im Winter)" % [w.stock.kohle, w.stock.holz])


func _freeze_setup(w) -> void:
	print("Erfrier-Test: Palmeninsel erfriert %s, Heimat %s, Waldinsel %s" % [freeze_biome("tropen"), freeze_biome("heimat"), freeze_biome("wald")])
	# Ein Kind und eine alte Siedlerin dazu, damit man die Reihenfolge sieht
	var adults: Array = w.settlers.filter(func(s): return s.is_adult())
	var mom = adults.filter(func(s): return s.sex == "f")
	var dad = adults.filter(func(s): return s.sex == "m")
	if not mom.is_empty() and not dad.is_empty():
		var kid = w.spawn_child(mom[0], dad[0])
		kid.age = 1.0
	var more := Game.spawn_immigrants(w, 2)
	if not more.is_empty():
		more[0].age = more[0].max_age * 0.85
	for s in w.settlers:
		s.hunger = 100.0
	_test_keep_cold()
	print("Erfrier-Test: %d Siedler, kein Brennstoff, Jahreszeit %s, Brennstoff/Tag je Siedler %.2f, Text: %s" % [w.settlers.size(), Seasons.season_name(), Seasons.heat_per_settler(), cold_text(w)])


## Erfrier-Test: Lager ohne Holz und Kohle halten, alle satt (es soll nur die Kälte wirken).
func _test_keep_cold() -> void:
	var w = Game.world
	w.stock["holz"] = 0
	w.stock["kohle"] = 0
	for s in w.settlers:
		s.hunger = maxf(s.hunger, 60.0)


func _food_test(w) -> void:
	var keep: Dictionary = w.stock.duplicate()
	var s = w.settlers[0]
	var set_food := func(d: Dictionary):
		for id in Data.food_ids():
			w.stock[id] = int(d.get(id, 0))
	s.hunger = 40.0
	s.mind.vit = 90.0
	set_food.call({"beeren": 30, "aepfel": 30, "brot": 2})
	print("Essen-Test %s: Brot vor Beeren und Aepfeln (%s)" % [_ok(Game.choose_food(s, w) == "brot"), Game.last_eaten])
	set_food.call({"beeren": 30, "aepfel": 30, "brot": 0, "raeucherfisch": 3})
	print("Essen-Test %s: Raeucherfisch vor Obst (%s)" % [_ok(Game.choose_food(s, w) == "raeucherfisch"), Game.last_eaten])
	set_food.call({"beeren": 30, "aepfel": 30})
	print("Essen-Test %s: kein Haltbares, dann frisches Essen (%s)" % [_ok(Game.choose_food(s, w) in ["beeren", "aepfel"]), Game.last_eaten])
	set_food.call({"beeren": 30, "fisch": 5, "weizen": 50, "kokos": 4})
	print("Essen-Test %s: Kokos vor Beeren, Fisch und Getreide (%s)" % [_ok(Game.choose_food(s, w) == "kokos"), Game.last_eaten])
	set_food.call({"beeren": 30, "weizen": 50})
	print("Essen-Test %s: Getreide ist Rohware fuer die Muehle, kein haltbares Essen (%s)" % [_ok(Game.choose_food(s, w) == "beeren"), Game.last_eaten])
	set_food.call({"weizen": 50})
	print("Essen-Test %s: nur Getreide da, dann Getreide (%s)" % [_ok(Game.choose_food(s, w) == "weizen"), Game.last_eaten])
	s.mind.vit = 20.0
	set_food.call({"aepfel": 30, "brot": 30})
	print("Essen-Test %s: wenig Vitamine (20): Aepfel trotz Brot (%s)" % [_ok(Game.choose_food(s, w) == "aepfel"), Game.last_eaten])
	s.mind.vit = 90.0
	w.stock = keep


func _tut_test() -> void:
	var w = Game.world
	var n: int = Data.goals.get("tutorial", []).size()
	var before := [w.settlers.size(), w.buildings.filter(func(b): return b.type == "huette").size()]
	print("Einfuehrungs-Test: vorher Siedler %d, Huetten %d, Platz fuer Huette %s" % [before[0], before[1], hut_spot(w)])
	Game.goals.tut = n - 1  # letzter Schritt: Tempo
	var ts := Engine.time_scale
	Game.set_speed(3)
	Engine.time_scale = ts
	await get_tree().create_timer(2.0, true, false, true).timeout
	var after := [w.settlers.size(), w.buildings.filter(func(b): return b.type == "huette").size()]
	var c: bool = after[0] == before[0] + 2 and after[1] == before[1] + 1
	print("Einfuehrungs-Test %s: nachher Siedler %d (+%d), Huetten %d (+%d), tut=%d/%d" % [_ok(c), after[0], after[0] - before[0], after[1], after[1] - before[1], int(Game.goals.tut), n])
	for s in w.settlers.slice(before[0]):
		var home = w.building_by_id(s.home_id)
		print("   neu: %s (%s), Zuhause %s" % [s.display_name, s.sex, home.type if home else "-"])
