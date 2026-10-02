extends Node
## Jahreszeiten: Kalender (Frühling, Sommer, Herbst, Winter), Tageslänge, Wachstum der Natur,
## Heizen im Winter, Verderb frischer Nahrung, Frost auf den Feldern, Schnee und Herbststürme.
## Alle Zahlen stehen in data/seasons.json (Listen in der Reihenfolge Frühling..Winter).
## Andere Teile des Spiels fragen nur über die Funktionen hier, z. B. Seasons.season().

signal season_changed(season: int)

enum {SPRING, SUMMER, AUTUMN, WINTER}
const KEYS := ["fruehling", "sommer", "herbst", "winter"]
const TEX := preload("res://assets/sprites/seasons.png")

var cfg: Dictionary = {}
## Spieltage, die im aktuellen Frame vergangen sind (0 bei Pause). Für Wachstum und Verderb.
var dt_days: float = 0.0
## Inseln, auf denen gerade Heizholz fehlt (World -> true). Dort frieren die Siedler.
var cold: Dictionary = {}

var _prev_time: float = -1.0
var _last_season: int = -1
var _last_day: int = -1
var _heat_acc: Dictionary = {}  # World -> angefangenes Holz
var _spoil_acc: Dictionary = {}  # Ware -> angefangene verdorbene Menge
var _spoiled: Dictionary = {}  # heute verdorben, für die Meldung am Morgen
var _icons: Dictionary = {}
var _weather: CanvasLayer
var _snow: CPUParticles2D
var _leaves: CPUParticles2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cfg = Data._load("seasons")
	_make_weather()


# ---------------------------------------------------------------- Kalender
func season_days() -> float:
	return float(cfg.get("season_days", 3.0))


func year_days() -> float:
	return season_days() * 4.0


## 0 Frühling, 1 Sommer, 2 Herbst, 3 Winter
func season(t: float = -1.0) -> int:
	if t < 0.0:
		t = Game.time_days
	return int(floor(fposmod(t, year_days()) / season_days())) % 4


func is_winter() -> bool:
	return season() == WINTER


## Jahr, beginnt bei 1
func year(t: float = -1.0) -> int:
	if t < 0.0:
		t = Game.time_days
	return int(floor(t / year_days())) + 1


## Tag innerhalb der Jahreszeit, beginnt bei 1
func day_in_season(t: float = -1.0) -> int:
	if t < 0.0:
		t = Game.time_days
	return int(floor(fposmod(t, season_days()))) + 1


## Anteil der laufenden Jahreszeit, 0..1
func season_progress() -> float:
	return fposmod(Game.time_days, season_days()) / season_days()


func season_name(s: int = -1) -> String:
	if s < 0:
		s = season()
	return cfg.get("names", ["Frühling", "Sommer", "Herbst", "Winter"])[s]


func icon(s: int = -1) -> AtlasTexture:
	if s < 0:
		s = season()
	if not _icons.has(s):
		var at := AtlasTexture.new()
		at.atlas = TEX
		at.region = Rect2(16 * s, 0, 16, 16)
		_icons[s] = at
	return _icons[s]


## Kurztext für die Leiste, z. B. "Frühling 2/3"
func short_text() -> String:
	return "%s %d/%d" % [season_name(), day_in_season(), int(season_days())]


## Was die Jahreszeit gerade bewirkt (für Hinweise im Spiel).
func effects_text(s: int = -1) -> String:
	if s < 0:
		s = season()
	match s:
		SPRING:
			return "Bäume wachsen am schnellsten, Felder werden bestellt, Tiere bekommen Junge."
		SUMMER:
			return "Lange Tage, Beeren reifen, Getreide wächst am besten. Frische Nahrung verdirbt schneller."
		AUTUMN:
			return "Pilzzeit, alles andere wächst langsamer. Keine Aussaat mehr, Stürme bremsen Schiffe, Häuser brauchen etwas Holz."
		_:
			return "Nichts wächst, kurze Tage, Schnee bremst Bauen und Laufen. Jeder Siedler braucht Holz zum Heizen und mehr Essen. Vorräte verderben nicht."


func jump_to_season(s: int) -> void:
	## Testhilfe: springt an den Morgen des ersten Tages einer Jahreszeit
	Game.time_days = floor(Game.time_days / year_days()) * year_days() + s * season_days() + 0.25
	_prev_time = Game.time_days
	_last_season = season()
	_last_day = Game.day()


func _val(key: String, s: int = -1, default: float = 1.0) -> float:
	var arr = cfg.get(key, null)
	if arr is Array and arr.size() == 4:
		return float(arr[season() if s < 0 else s])
	return default


# ---------------------------------------------------------------- Tageslänge
func night_start() -> float:
	return _val("night_start", -1, float(Data.bal("night_start")))


func night_end() -> float:
	return _val("night_end", -1, float(Data.bal("night_end")))


# ---------------------------------------------------------------- Natur
## Wachstumsfaktor einer Rohstoffquelle oder eines Felds (Typ aus nodes/buildings).
func growth(type: String) -> float:
	var g: Dictionary = cfg.get("growth", {})
	var arr = g.get(type, g.get("_default", [1, 1, 1, 1]))
	return float(arr[season()])


## Wie schnell Erlegtes verdirbt (Sommer schneller, Winter kaum).
func decay() -> float:
	return _val("decay")


func can_sow(type: String) -> bool:
	var ss: Dictionary = cfg.get("sow_seasons", {})
	if not ss.has(type):
		return true
	return season() in ss[type].map(func(x): return int(x))


# ---------------------------------------------------------------- Menschen
## Hungerfaktor eines Siedlers auf dieser Insel (Winter und Kälte zehren).
func hunger_mult(w) -> float:
	var f := _val("hunger")
	if cold.has(w):
		f *= float(cfg.get("cold_hunger", 1.5))
	return f


## Arbeitstempo auf dieser Insel (wer friert, arbeitet langsamer).
func work_mult(w) -> float:
	return float(cfg.get("cold_work", 0.75)) if cold.has(w) else 1.0


func build_mult() -> float:
	return _val("build")


func walk_mult() -> float:
	return _val("walk")


## Reisezeit-Faktor für Schiffe (Herbststürme). Gilt beim Ablegen.
func sail_mult() -> float:
	return _val("sail")


## Holzbedarf pro Siedler und Tag.
func heat_per_settler(s: int = -1) -> float:
	return _val("heat_wood_per_settler", s, 0.0)


# ---------------------------------------------------------------- Ablauf
func _process(delta: float) -> void:
	var t := Game.time_days
	dt_days = 0.0
	if _prev_time >= 0.0 and t > _prev_time and t - _prev_time < 0.5:
		dt_days = t - _prev_time
	_prev_time = t
	_update_weather()
	if Game.world == null or Game.is_over:
		return
	var s := season()
	if _last_season < 0:
		_last_season = s
		_last_day = Game.day()
		season_changed.emit(s)
	elif s != _last_season:
		_last_season = s
		_on_new_season(s)
	if Game.day() != _last_day:
		_last_day = Game.day()
		_on_new_day()
	if dt_days > 0.0:
		_heat(dt_days)
		_spoil(dt_days)


func _on_new_season(s: int) -> void:
	season_changed.emit(s)
	Game.notify("%s, Jahr %d. %s" % [season_name(s), year(), effects_text(s)], "")
	if s == WINTER:
		_frost()
	Sound.play("glocke")


func _on_new_day() -> void:
	# Bericht über verdorbene Nahrung vom Vortag
	if not _spoiled.is_empty():
		var parts := []
		for id in _spoiled:
			parts.append("%d %s" % [_spoiled[id], Data.resource_name(id)])
		Game.notify("Verdorben: %s. Räuchern und Backen macht Essen haltbar." % ", ".join(parts), "abriss")
		_spoiled = {}
	# Vorwarnung einen Tag vor dem Winter
	if season() == AUTUMN and day_in_season() == int(season_days()):
		var need := 0.0
		for w in Sea.all_worlds():
			need += w.settlers.size() * heat_per_settler(WINTER) * season_days()
		Game.notify("Morgen beginnt der Winter! Ihr braucht etwa %d Holz zum Heizen und haltbare Vorräte." % int(ceil(need)), "holz")


## Heizen: jeder Siedler braucht im Herbst etwas, im Winter viel Holz.
func _heat(days: float) -> void:
	var per := heat_per_settler()
	if per <= 0.0:
		if not cold.is_empty():
			cold.clear()
		return
	for w in Sea.all_worlds():
		if w.settlers.is_empty():
			continue
		var acc: float = float(_heat_acc.get(w, 0.0)) + per * w.settlers.size() * days
		var need := int(acc)
		if need > 0:
			var got := Game.take_stock("holz", need, w)
			acc -= need
			if got < need:
				if not cold.has(w):
					cold[w] = true
					Game.notify_at(w, "Kein Holz zum Heizen: die Siedler frieren! Sie werden schneller hungrig und arbeiten langsamer.", "holz")
					Sound.play_on("fehler", w)
			elif cold.has(w):
				cold.erase(w)
				Game.notify_at(w, "Die Öfen brennen wieder.", "holz")
		_heat_acc[w] = acc
	# Verlorene Inseln vergessen
	for w in cold.keys():
		if not is_instance_valid(w):
			cold.erase(w)


## Frische Nahrung verdirbt, im Sommer schnell, im Winter gar nicht.
## Läuft je Vorrat (heute teilen sich alle Inseln einen, später hat jede Insel ihren).
func _spoil(days: float) -> void:
	var rate := _val("spoil_per_day", -1, 0.0)
	if rate <= 0.0:
		return
	var stores := []
	for w in Sea.all_worlds():
		var st: Dictionary = Game._stock_of(w)
		if not stores.any(func(x): return is_same(x[1], st)):
			stores.append([w, st])
	for pair in stores:
		var w = pair[0]
		for id in cfg.get("perishable", []):
			var key := "%s|%d" % [id, int(w.island_id)]
			var have := Game.amount(id, w)
			if have <= 0:
				_spoil_acc.erase(key)
				continue
			var acc: float = float(_spoil_acc.get(key, 0.0)) + have * rate * days
			var n := int(acc)
			if n > 0:
				acc -= n
				var lost := Game.take_stock(id, n, w)
				_spoiled[id] = int(_spoiled.get(id, 0)) + lost
			_spoil_acc[key] = acc


## Frost zu Winterbeginn: was noch auf den Feldern wächst, erfriert.
func _frost() -> void:
	var kinds: Array = cfg.get("frost_kills", [])
	for w in Sea.all_worlds():
		var n := 0
		for b in w.buildings:
			if b.complete and b.type in kinds and b.farm_state == "growing":
				b.farm_state = "fallow"
				b.refresh()
				n += 1
		# Sträucher und Pilze tragen im Winter nichts mehr
		var bare: Array = cfg.get("winter_bare", [])
		for node in w.nodes:
			if node.type in bare and node.amount > 0:
				node.amount = 0
				node.regrow_at = Game.time_days + float(node.def.get("regrow_days", 1.0))
				node.refresh()
		if n > 0:
			Game.notify_at(w, "Der Frost hat %d %s vernichtet. Sät im Frühling früh genug!" % [n, "Feld" if n == 1 else "Felder"], "weizen")


# ---------------------------------------------------------------- Wetter (Schnee, Laub)
func _make_weather() -> void:
	_weather = CanvasLayer.new()
	_weather.layer = 1
	add_child(_weather)
	_snow = _particles(Rect2(64, 16, 8, 8), Color(1, 1, 1, 0.9), 70, 22.0)
	_leaves = _particles(Rect2(72, 16, 8, 8), Color(1, 1, 1, 1), 14, 30.0)


func _particles(region: Rect2, col: Color, amount: int, fall: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var at := AtlasTexture.new()
	at.atlas = TEX
	at.region = region
	p.texture = at
	p.amount = amount
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0.3, 1)
	p.spread = 15.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = fall * 0.7
	p.initial_velocity_max = fall * 1.3
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	p.color = col
	p.emitting = false
	p.visible = false
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_weather.add_child(p)
	return p


func _update_weather() -> void:
	var on := Game.world != null and not Game.is_over
	var s := season() if on else -1
	var vs := get_viewport().get_visible_rect().size
	for p in [_snow, _leaves]:
		p.position = Vector2(vs.x * 0.5, -20)
		p.emission_rect_extents = Vector2(vs.x * 0.6, 10)
		p.lifetime = max(4.0, (vs.y + 60.0) / max(1.0, p.initial_velocity_min))
	_set_emit(_snow, s == WINTER)
	_set_emit(_leaves, s == AUTUMN)


func _set_emit(p: CPUParticles2D, on: bool) -> void:
	# Beim Ausschalten fallen die letzten Flocken noch zu Boden
	if p.emitting != on:
		p.emitting = on
		if on:
			p.visible = true


## Wie viel Schnee liegt (0..1): baut sich im Winter auf und taut im Frühling.
func snow_amount() -> float:
	var s := season()
	var p := season_progress()
	if s == WINTER:
		return clamp(p * 4.0, 0.0, 1.0)
	if s == SPRING and Game.time_days >= year_days():  # im ersten Frühling liegt kein Schnee
		return clamp(1.0 - p * 5.0, 0.0, 1.0)
	return 0.0


## Wie herbstlich das Laub ist (0..1): färbt sich im Herbst, fällt im Winter ab.
func autumn_amount() -> float:
	var s := season()
	var p := season_progress()
	if s == AUTUMN:
		return clamp(p * 2.5, 0.0, 1.0)
	if s == WINTER:
		return 1.0
	if s == SPRING and Game.time_days >= year_days():
		return clamp(1.0 - p * 4.0, 0.0, 1.0)
	return 0.0
