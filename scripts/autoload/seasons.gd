extends Node
## Jahreszeiten: Kalender (Frühling, Sommer, Herbst, Winter), Tageslänge, Wachstum der Natur,
## Heizen im Winter, Verderb frischer Nahrung, Frost auf den Feldern, Schnee und Herbststürme.
## Alle Zahlen stehen in data/seasons.json (Listen in der Reihenfolge Frühling..Winter).
## Andere Teile des Spiels fragen nur über die Funktionen hier, z. B. Seasons.season().

signal season_changed(season: int)
## Die Alten haben etwas zum Klima gesagt (für andere Systeme): kind "summer" (Frühling: heißer Sommer),
## "winter_hint" (Sommer: type mild/normal/streng, mit Astronomie genau), "winter" (Herbst: genau).
signal climate_announced(kind: String, type: String)

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

## Wechselnde Winter und Sommer: Jahr (als Text) -> {"w": Wintertyp, "s": Sommertyp}, gespeichert unter
## "climate". Jedes Jahr wird zu Jahresbeginn einmal aus (Seed, Jahr) gewürfelt (_ensure_year, nur in
## _process mit Welt) und bleibt dann fest. Typen und Faktoren: seasons.json winters/summers.
var climate: Dictionary = {}
## Testhilfen --winter=, --summer=, --climate=off: feste Typen für alle Jahre ("" = würfeln)
var force_w := ""
var force_s := ""
var _cy: int = -1  # Jahr, für das _w_tab/_s_tab gelten
var _w_tab: Dictionary = {}  # Faktoren des Winters dieses Jahres (nur Zahlen und growth)
var _s_tab: Dictionary = {}  # Faktoren des Sommers dieses Jahres
var _prev_snow := 1.0  # Schnee-Faktor des letzten Winters (Tauen im Frühling)
var _events: Node = null  # Autoload Events (Angekündigte Ereignisse), falls vorhanden
var _events_looked := false
const _NONE := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cfg = Data._load("seasons")
	_make_weather()
	add_child(Extras.new())  # Kohleheizung, Erfrieren und weitere Ergänzungen (extras.gd)
	Game.register_system(self)
	Game.state_reset.connect(reset_climate)
	Game.state_save.connect(func(d: Dictionary): d["climate"] = climate.duplicate(true))
	Game.state_load.connect(_on_state_load)


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
	return cfg.get("names", [tr("Frühling"), tr("Sommer"), tr("Herbst"), tr("Winter")])[s]


func icon(s: int = -1) -> AtlasTexture:
	if s < 0:
		s = season()
	if not _icons.has(s):
		var at := AtlasTexture.new()
		at.atlas = TEX
		at.region = Rect2(16 * s, 0, 16, 16)
		_icons[s] = at
	return _icons[s]


## Kurztext für die Leiste, z. B. "Frühling 2/3" oder (title, breiter Bildschirm) "Harter Winter 2/3"
func short_text(title: bool = true) -> String:
	return "%s %d/%d" % [season_title() if title else season_name(), day_in_season(), int(season_days())]


## Was die Jahreszeit gerade bewirkt (für Hinweise im Spiel).
func effects_text(s: int = -1) -> String:
	if s < 0:
		s = season()
	match s:
		SPRING:
			return tr("Bäume wachsen am schnellsten, Felder werden bestellt, Tiere bekommen Junge.")
		SUMMER:
			if summer_type() == "heiss":  # das Verderben nennt dann climate_text (heißer Sommer)
				return tr("Lange Tage, Beeren reifen, Getreide wächst am besten.")
			return tr("Lange Tage, Beeren reifen, Getreide wächst am besten. Frische Nahrung verdirbt schneller.")
		AUTUMN:
			return tr("Pilzzeit, alles andere wächst langsamer. Keine Aussaat mehr, Stürme bremsen Schiffe, Häuser brauchen etwas Holz.")
		_:
			return tr("Nichts wächst, kurze Tage, Schnee bremst Bauen und Laufen. Jeder Siedler braucht Holz oder Kohle zum Heizen und mehr Essen. Vorräte verderben nicht.")


func jump_to_season(s: int) -> void:
	## Testhilfe: springt an den Morgen des ersten Tages einer Jahreszeit
	Game.time_days = floor(Game.time_days / year_days()) * year_days() + s * season_days() + 0.25
	_prev_time = Game.time_days
	_last_season = season()
	_last_day = Game.day()


func _val(key: String, s: int = -1, default: float = 1.0) -> float:
	var arr = cfg.get(key, null)
	if arr is Array and arr.size() == 4:
		var ss := season() if s < 0 else s
		return float(arr[ss]) * climate_factor(key, ss)  # Klima: Faktor des Winter- bzw. Sommertyps
	return default


# ---------------------------------------------------------------- Tageslänge
func night_start() -> float:
	return _val("night_start", -1, float(Data.bal("night_start")))


func night_end() -> float:
	return _val("night_end", -1, float(Data.bal("night_end")))


# ---------------------------------------------------------------- Natur
## Wachstumsfaktor einer Rohstoffquelle oder eines Felds (Typ aus nodes/buildings) auf Insel w.
## Jahreszeit mal Klima (growth des Winter-/Sommertyps). Ein Ereignis (Events.growth_factor, z. B.
## Dürre) ersetzt den Klimafaktor, wenn es kleiner ist (min, nicht mal: Hitze und Dürre stapeln nicht).
func growth(type: String, w = null) -> float:
	var g: Dictionary = cfg.get("growth", {})
	var arr = g.get(type, g.get("_default", [1, 1, 1, 1]))
	var s := season()
	var f := 1.0
	if s == WINTER:
		f = float(_w_tab.get("growth", _NONE).get(type, 1.0))
	elif s == SUMMER:
		f = float(_s_tab.get("growth", _NONE).get(type, 1.0))
	if _events != null:
		f = minf(f, float(_events.growth_factor(type, w)))
	return float(arr[s]) * f


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


## Allgemeiner Jahreszeit-Faktor für andere Systeme (`mods` in seasons.json), z. B.
## "sickness" (Krankheitsrisiko) oder "mood" (Laune). Unbekannte Schlüssel: 1.0.
func season_mod(key: String) -> float:
	var arr = cfg.get("mods", {}).get(key, null)
	if arr is Array and arr.size() == 4:
		var s := season()
		return float(arr[s]) * climate_factor(key, s)
	return 1.0


## Ist es auf dieser Insel warm genug? false, wenn Heizholz fehlt (gilt im Herbst und Winter).
func is_warm(w) -> bool:
	return not cold.has(w)


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
	if Game.world != null and not Game.is_over and year() != _cy:
		_ensure_year()  # neues Jahr (oder geladen): Klima würfeln, Faktoren bereitlegen
	_update_weather()
	if Game.world == null or Game.is_over:
		return
	if not _events_looked:
		_events_looked = true
		var ev := get_node_or_null("/root/" + "events".capitalize())  # Autoload Events (so bleibt tools/i18n.py wrap ruhig)
		if ev != null and ev.has_method("growth_factor"):
			_events = ev
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
	Game.notify(tr("%s, Jahr %d. %s") % [season_title(s), year(), effects_text(s)], "")
	if s == WINTER:
		_frost()
	Sound.play("glocke")
	_forecast(s)


func _on_new_day() -> void:
	# Bericht über verdorbene Nahrung vom Vortag
	if not _spoiled.is_empty():
		var parts := []
		for id in _spoiled:
			parts.append("%d %s" % [_spoiled[id], Data.resource_name(id)])
		Game.notify(tr("Verdorben: %s. Räuchern und Backen macht Essen haltbar.") % ", ".join(parts), "abriss", "lager")
		_spoiled = {}
	# Vorwarnung einen Tag vor dem Winter
	if season() == AUTUMN and day_in_season() == int(season_days()):
		var wt := winter_type()
		if wt == "normal":
			Game.notify(tr("Morgen beginnt der Winter! %s Legt auch haltbare Vorräte an.") % Extras.need_text(winter_wood_need()), "holz")
		else:
			Game.notify(tr("Morgen beginnt der Winter (%s)! %s Legt auch haltbare Vorräte an.") % [type_name("w", wt), Extras.need_text(winter_wood_need())], "holz")


## Heizen: jeder Siedler braucht im Herbst etwas, im Winter viel Holz (Kohle zuerst, Extras.burn_fuel).
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
		var res := Extras.burn_fuel(w, acc)  # zuerst Kohle, dann Holz
		acc = float(res[0])
		if res[1] != null:
			if res[1] == false:
				if not cold.has(w):
					cold[w] = true
					Game.notify_at(w, Extras.cold_text(w), "holz")
					Sound.play_on("fehler", w)
			elif cold.has(w):
				cold.erase(w)
				Game.notify_at(w, tr("Die Öfen brennen wieder."), "holz")
		_heat_acc[w] = acc
	# Verlorene Inseln vergessen
	for w in cold.keys():
		if not is_instance_valid(w):
			cold.erase(w)


## Anteil, der von dieser Ware heute pro Tag verdirbt (0 für haltbare Ware und im Winter).
func spoil_rate(id: String) -> float:
	if not id in cfg.get("perishable", []):
		return 0.0
	return _val("spoil_per_day", -1, 0.0) * maxf(0.0, Game.eff("spoil"))


## Frische Nahrung verdirbt, im Sommer schnell, im Winter gar nicht.
## Läuft je Vorrat (heute teilen sich alle Inseln einen, später hat jede Insel ihren).
func _spoil(days: float) -> void:
	var rate := _val("spoil_per_day", -1, 0.0) * maxf(0.0, Game.eff("spoil"))  # Kuehltechnik
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
			Game.notify_at(w, tr("Der Frost hat %d %s vernichtet. Sät im Frühling früh genug!") % [n, tr("Feld") if n == 1 else tr("Felder")], "weizen")


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
	if s == WINTER and not _snow.emitting:
		# Milder Winter: weniger Flocken, Eiswinter mehr
		var want := int(70.0 * clampf(climate_factor("snow", WINTER), 0.3, 2.0))
		if _snow.amount != want:
			_snow.amount = want
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
		# Klima: milder Winter halb so viel Schnee, harter Winter und Eiswinter schneller weiß
		var f := climate_factor("snow", WINTER)
		return clamp(p * 4.0 * maxf(1.0, f), 0.0, 1.0) * minf(1.0, f)
	if s == SPRING and Game.time_days >= year_days():  # im ersten Frühling liegt kein Schnee
		return clamp(1.0 - p * 5.0, 0.0, 1.0) * minf(1.0, _prev_snow)
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


# ---------------------------------------------------------------- Klima (wechselnde Winter und Sommer)
## Wintertyp des Jahres y (Standard: dieses Jahr): "mild", "normal", "hart" oder "bitter" (Eiswinter).
## Steht schon ab Frühling fest (gewürfelt zu Jahresbeginn), auch wenn die Siedler ihn noch nicht kennen.
func winter_type(y: int = -1) -> String:
	if y < 0:
		y = year()
	var e = climate.get(str(y))
	return str(e.get("w", "normal")) if e is Dictionary else "normal"


## Sommertyp des Jahres y (Standard: dieses Jahr): "normal" oder "heiss".
func summer_type(y: int = -1) -> String:
	if y < 0:
		y = year()
	var e = climate.get(str(y))
	return str(e.get("s", "normal")) if e is Dictionary else "normal"


## Faktor des Klimas auf einen Jahreszeit-Wert (Schlüssel wie in seasons.json, z. B. "hunger",
## "heat_wood_per_settler", "sickness", "snow", "ill_ruhr"). Nur Winter und Sommer, sonst 1.
func climate_factor(key: String, s: int = -1) -> float:
	if s < 0:
		s = season()
	if s == WINTER:
		return float(_w_tab.get(key, 1.0))
	if s == SUMMER:
		return float(_s_tab.get(key, 1.0))
	return 1.0


## Eintrag eines Typs aus seasons.json (kind "w" = winters, "s" = summers).
func type_def(kind: String, t: String) -> Dictionary:
	return cfg.get("winters" if kind == "w" else "summers", {}).get(t, {})


func type_name(kind: String, t: String) -> String:
	return str(type_def(kind, t).get("name", t))


## Name der Jahreszeit mit Klima, z. B. "Harter Winter" oder "Heißer Sommer" (sonst season_name).
func season_title(s: int = -1) -> String:
	if s < 0:
		s = season()
	if s == WINTER and winter_type() != "normal":
		return type_name("w", winter_type())
	if s == SUMMER and summer_type() != "normal":
		return type_name("s", summer_type())
	return season_name(s)


## Was die Siedler über diesen Winter wissen: "" (Frühling: noch nichts), "rough" (Sommer: grob) oder
## "exact" (ab Herbst; mit Astronomie, Wirkung forecast, schon im Sommer).
func winter_known() -> String:
	match season():
		SPRING:
			return ""
		SUMMER:
			return "exact" if Game.eff_add("forecast") > 0.0 else "rough"
	return "exact"


## Der Winter, so wie die Siedler ihn gerade kennen: "" (unbekannt), der Typ, oder grob "mild",
## "normal", "streng" (hart oder Eiswinter).
func winter_forecast() -> String:
	var k := winter_known()
	if k == "":
		return ""
	var t := winter_type()
	if k == "rough" and not cfg.get("winter_hints", {}).has(t):
		return "streng"
	return t


## Geschätztes Heizholz für den Winter dieses Jahres, alle Inseln zusammen.
func winter_wood_need() -> int:
	var need := 0.0
	for w in Sea.all_worlds():
		need += w.settlers.size() * heat_per_settler(WINTER) * season_days()
	return int(ceil(need))


## Klima-Symbol für die Oberleiste: {} (nichts) oder {"kind": "w"/"s", "type": Typ oder "streng"}.
## Heißer Sommer ab der Vorhersage im Frühling bis Sommerende, danach der Winter, sobald er bekannt ist.
func badge() -> Dictionary:
	var s := season()
	var st := summer_type()
	if (s == SPRING or s == SUMMER) and st != "normal":
		return {"kind": "s", "type": st}
	var wf := winter_forecast()
	if wf != "" and wf != "normal":
		return {"kind": "w", "type": wf}
	return {}


## Klima-Text zum Antippen der Jahreszeit (leer oder mit Leerzeichen vorne).
func climate_text() -> String:
	var parts := []
	var s := season()
	var st := summer_type()
	if st != "normal" and (s == SPRING or s == SUMMER):
		var d := type_def("s", st)
		if s == SPRING:
			parts.append("%s %s" % [d.get("text", ""), d.get("desc", "")])
		else:
			parts.append(str(d.get("desc", "")))  # der Name steht schon im Titel der Jahreszeit
	var wf := winter_forecast()
	if s == SUMMER:
		parts.append(_winter_hint_text())
	elif s == AUTUMN:
		var d := type_def("w", wf)
		parts.append("%s %s" % [d.get("text", ""), Extras.need_text(winter_wood_need())])
		if wf != "normal":
			parts.append(str(d.get("desc", "")))
	elif s == WINTER and wf != "normal":
		parts.append(str(type_def("w", wf).get("desc", "")))  # der Name steht schon im Titel
	return "" if parts.is_empty() else " " + " ".join(parts)


## Sommer: grobe Vorhersage der Alten (mit Astronomie der genaue Typ samt Wirkung).
func _winter_hint_text() -> String:
	var wf := winter_forecast()
	if winter_known() == "exact":
		var d := type_def("w", wf)
		var t := str(d.get("text", ""))
		return t if wf == "normal" else "%s %s" % [t, d.get("desc", "")]
	return str(cfg.get("winter_hints", {}).get(wf, {}).get("text", ""))


## Vorhersagen zu Beginn einer Jahreszeit (ehrlich, nie falsch). Meldungsart "lager".
func _forecast(s: int) -> void:
	match s:
		SPRING:
			var st := summer_type()
			if st != "normal":
				var d := type_def("s", st)
				Game.notify("%s %s" % [d.get("text", ""), d.get("desc", "")], "sonne", "lager")
				climate_announced.emit("summer", st)
		SUMMER:
			Game.notify(_winter_hint_text(), "schnee", "lager")
			climate_announced.emit("winter_hint", winter_forecast())
		AUTUMN:
			var wt := winter_type()
			var d := type_def("w", wt)
			var msg := "%s %s" % [d.get("text", ""), Extras.need_text(winter_wood_need())]
			if wt != "normal":
				msg += " " + str(d.get("desc", ""))
			Game.notify(msg, "schnee", "lager")
			climate_announced.emit("winter", wt)


## Würfelt Winter und Sommer eines Jahres, nur aus (Seed, Jahr) und dem Winter des Vorjahres
## (climate_no_repeat: kein Eiswinter nach einem Eiswinter). Gewichte: climate_odds.
func roll_year(seed_v: int, y: int, prev_w: String = "normal") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:klima" % [seed_v, y])
	var row := _odds_row(y)
	var w := _pick(rng, row.get("winter", {}))
	var s := _pick(rng, row.get("summer", {}))
	var nr: Dictionary = cfg.get("climate_no_repeat", {})
	if nr.has(w) and prev_w == w:
		w = str(nr[w])
	if not cfg.get("winters", {}).has(w):
		w = "normal"
	if not cfg.get("summers", {}).has(s):
		s = "normal"
	return {"w": w, "s": s}


func _odds_row(y: int) -> Dictionary:
	var best: Dictionary = {}
	var best_y := -1
	for r in cfg.get("climate_odds", []):
		var fy := int(r.get("from_year", 1))
		if fy <= y and fy > best_y:
			best_y = fy
			best = r
	return best


func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	var last := "normal"
	for k in weights:
		if float(weights[k]) > 0.0:
			total += float(weights[k])
			last = str(k)
	if total <= 0.0:
		return "normal"
	var x := rng.randf() * total
	for k in weights:
		var wt := float(weights[k])
		if wt <= 0.0:
			continue
		x -= wt
		if x < 0.0:
			return str(k)
	return last


## Klima für das laufende Jahr festlegen (würfeln, wenn es noch fehlt) und die Faktoren bereitlegen.
func _ensure_year() -> void:
	var y := year()
	var key := str(y)
	if not climate.has(key):
		climate[key] = roll_year(Game.seed_value, y, winter_type(y - 1))
	if force_w != "":
		climate[key]["w"] = force_w
	if force_s != "":
		climate[key]["s"] = force_s
	_cy = y
	_w_tab = _factors(type_def("w", winter_type(y)))
	_s_tab = _factors(type_def("s", summer_type(y)))
	_prev_snow = float(type_def("w", winter_type(y - 1)).get("snow", 1.0))


## Nur die Faktoren eines Typs (Zahlen und growth), damit climate_factor nie Text liefert.
func _factors(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if d[k] is float or d[k] is int:
			out[k] = float(d[k])
		elif k == "growth" and d[k] is Dictionary:
			out[k] = d[k]
	return out


## Neues Spiel: kein Klima vom vorigen Spiel übernehmen.
func reset_climate() -> void:
	climate = {}
	_cy = -1
	_w_tab = {}
	_s_tab = {}
	_prev_snow = 1.0


## Spielstand geladen (Game.state_load): Klima lesen. Alter Spielstand ohne "climate": dieses Jahr
## bleibt gewöhnlich (Schonjahr, kein unangekündigter harter Winter), gewürfelt wird ab dem nächsten.
func _on_state_load(data: Dictionary, old_rules: int) -> void:
	climate = {}
	var c = data.get("climate", null)
	if c is Dictionary:
		for k in c:
			var e = c[k]
			if not (e is Dictionary) or not str(k).is_valid_int():
				continue
			var w := str(e.get("w", "normal"))
			var s := str(e.get("s", "normal"))
			climate[str(int(str(k)))] = {"w": w if cfg.get("winters", {}).has(w) else "normal",
				"s": s if cfg.get("summers", {}).has(s) else "normal"}
	if not climate.has(str(year())) and not (c is Dictionary):
		climate[str(year())] = {"w": "normal", "s": "normal"}
	_cy = -1
	if old_rules < 1:
		Game.rules_lines.append(tr("Winter und Sommer sind jedes Jahr anders. Im Herbst sagen die Alten voraus, wie hart der Winter wird."))


# ---------------------------------------------------------------- Selbsttest (Klima)
## Testhilfen (Game.systems): --winter=mild|normal|hart|bitter und --summer=normal|heiss legen den Typ
## für alle Jahre fest (nach --season), --climate=off macht alle Jahre gewöhnlich, --climatetest=1
## prüft Würfeln, Faktoren, Vorhersagen, Speichern und alte Spielstände.
func autotest_setup(args: Dictionary, _main) -> void:
	if str(args.get("climate", "")) == "off":
		force_w = "normal"
		force_s = "normal"
	if args.has("winter"):
		force_w = str(args.winter) if cfg.get("winters", {}).has(str(args.winter)) else ""
		print("Klima-Test: Winter fest auf '", force_w, "'")
	if args.has("summer"):
		force_s = str(args.summer) if cfg.get("summers", {}).has(str(args.summer)) else ""
		print("Klima-Test: Sommer fest auf '", force_s, "'")
	if force_w != "" or force_s != "":
		_cy = -1
		_ensure_year()
	if args.has("climatetest"):
		_climate_test()
	if args.has("climatetap"):
		# Bildschirmfoto-Hilfe: kurz vor Ende die Jahreszeit antippen (1) bzw. die Vorhersage zeigen (2)
		var secs := float(args.get("autotest", "20"))
		get_tree().create_timer(maxf(0.5, secs - 2.0), true, false, true).timeout.connect(func(): _test_tap(_main, str(args.climatetap)))


func _test_tap(main, mode: String) -> void:
	var sc: Control = main.hud._season_icon.get_parent()
	if mode == "2":
		_forecast(season())
	else:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		sc.gui_input.emit(ev)
	var vs: Vector2 = sc.get_viewport().get_visible_rect().size
	var bar: Control = sc.get_parent().get_parent()
	for c in sc.get_children():
		if c is ClimateBadge:
			var r: Rect2 = c.get_global_rect()
			print("Klima-Test Oberleiste: Leiste bis x=%d, Bild %dx%d, Symbol sichtbar=%s bei x=%d..%d (im Bild=%s), Jahreszeit-Text sichtbar=%s" % [bar.get_global_rect().end.x, vs.x, vs.y,
				c.is_visible_in_tree(), r.position.x, r.end.x, r.end.x <= vs.x, main.hud._season_label.visible])


func autotest_report() -> String:
	var b := badge()
	print("   Klima Jahr %d: Winter=%s Sommer=%s | %s | Heizholz/Siedler(Winter) %.2f, Hunger x%.2f, Bauen x%.2f, Krank x%.2f, Fischgrund %.2f | Symbol %s/%s | %s" % [year(),
		winter_type(), summer_type(), season_title(), heat_per_settler(WINTER), _val("hunger"), build_mult(), season_mod("sickness"),
		growth("fischgrund"), b.get("kind", "-"), b.get("type", "-"), climate.keys()])
	return ""


func _climate_test() -> void:
	var types_w: Array = cfg.get("winters", {}).keys()
	# 1) Verteilung: 200 Seeds x Jahre 1-20, der Reihe nach mit Wiederholungsregel
	var counts := {}  # Zeile -> {typ: n}
	var bitter_twice := 0
	var det_ok := true
	for sd in 200:
		var prev := "normal"
		for y in range(1, 21):
			var r := roll_year(sd * 7919 + 13, y, prev)
			if r != roll_year(sd * 7919 + 13, y, prev):
				det_ok = false
			if r.w == "bitter" and prev == "bitter":
				bitter_twice += 1
			var row := "J%d" % int(_odds_row(y).get("from_year", 1))
			if not counts.has(row):
				counts[row] = {"n": 0}
			counts[row].n += 1
			counts[row][r.w] = int(counts[row].get(r.w, 0)) + 1
			counts[row]["s_" + r.s] = int(counts[row].get("s_" + r.s, 0)) + 1
			prev = r.w
	for row in counts:
		var c: Dictionary = counts[row]
		var parts := []
		for k in c:
			if k != "n":
				parts.append("%s %.0f%%" % [k, 100.0 * float(c[k]) / float(c.n)])
		print("Klima-Test Verteilung ab %s (%d Jahre): %s" % [row, c.n, ", ".join(parts)])
	print("Klima-Test: deterministisch=", det_ok, " Eiswinter nach Eiswinter=", bitter_twice)
	# 2) Faktoren je Typ: echte Getter im Winter bzw. Sommer
	var keep_t := Game.time_days
	var keep_c := climate.duplicate(true)
	var keep_fw := force_w
	var keep_fs := force_s
	force_w = ""
	force_s = ""
	var y := year()
	var winter_t := (float(y - 1) * year_days()) + 3.0 * season_days() + 1.5
	var summer_t := (float(y - 1) * year_days()) + season_days() + 1.5
	for t in types_w:
		climate[str(y)] = {"w": t, "s": "normal"}
		_ensure_year()
		Game.time_days = winter_t
		print("Klima-Test Winter %-7s Titel '%s': Heizholz %.2f, Hunger %.2f, Krank %.2f, Bauen %.2f, Laufen %.2f, Segeln %.2f, Fischgrund %.3f, Palme %.2f, Laune %.3f, Schnee(Ende) %.2f" % [t,
			season_title(), heat_per_settler(), _val("hunger"), season_mod("sickness"), build_mult(), walk_mult(), sail_mult(),
			growth("fischgrund"), growth("palme"), season_mod("mood"), clampf(4.0 * maxf(1.0, climate_factor("snow")), 0.0, 1.0) * minf(1.0, climate_factor("snow"))])
		Game.time_days = keep_t
	for t in cfg.get("summers", {}).keys():
		climate[str(y)] = {"w": "normal", "s": t}
		_ensure_year()
		Game.time_days = summer_t
		var ills := {}
		for k in Data.ppl("illnesses"):
			ills[k] = float(Data.ppl("illnesses")[k].get("weight", 0)) * climate_factor("ill_" + k)
		print("Klima-Test Sommer %-6s Titel '%s': Verderb %.3f, Aas %.2f, Krank %.2f, Laune %.3f, Feld %.2f, Busch %.2f, Obstgarten %.2f, Pilze %.2f, Gewaechshaus %.2f, Krankheiten %s" % [t,
			season_title(), _val("spoil_per_day", -1, 0.0), decay(), season_mod("sickness"), season_mod("mood"),
			growth("feld"), growth("busch"), growth("obstgarten"), growth("pilzkreis"), growth("gewaechshaus"), ills])
		Game.time_days = keep_t
	# 3) Vorhersagen: Frühling, Sommer (grob, mit Astronomie genau), Herbst (genau + Holz), Symbol, Antippen
	for t in types_w:
		climate[str(y)] = {"w": t, "s": "heiss" if t == "hart" else "normal"}
		_ensure_year()
		for s in [SPRING, SUMMER, AUTUMN, WINTER]:
			Game.time_days = (float(y - 1) * year_days()) + s * season_days() + 0.3
			print("Klima-Test Vorhersage Winter=%s %s: Symbol %s, kennt '%s'" % [t, season_name(s), badge(), winter_forecast()])
			print("      Antippen:", climate_text())
			_forecast(s)
		Game.time_days = keep_t
	var keep_done: Array = Game.research.done.duplicate()
	if not "astronomie" in Game.research.done:
		Game.research.done.append("astronomie")
	Game._recompute_effects()
	climate[str(y)] = {"w": "bitter", "s": "normal"}
	_ensure_year()
	Game.time_days = (float(y - 1) * year_days()) + season_days() + 0.3
	print("Klima-Test mit Astronomie (forecast=%.0f) im Sommer: kennt '%s'" % [Game.eff_add("forecast"), winter_forecast()])
	_forecast(SUMMER)
	Game.research.done = keep_done
	Game._recompute_effects()
	Game.time_days = keep_t
	# 4) Speichern und Laden, alter Spielstand (Schonjahr und Regelzeile)
	climate = keep_c
	force_w = keep_fw
	force_s = keep_fs
	_cy = -1
	_ensure_year()
	var d := {}
	Game.state_save.emit(d)
	var back = JSON.parse_string(JSON.stringify(d))
	var keep_lines: Array = Game.rules_lines.duplicate()
	_on_state_load(back, 1)
	print("Klima-Test Speichern/Laden: gespeichert ", d.get("climate"), " gleich=", climate == keep_c, " Regelzeilen +", Game.rules_lines.size() - keep_lines.size())
	_on_state_load({}, 0)
	_ensure_year()
	print("Klima-Test alter Spielstand: ", climate, " Jahr ", year(), " Winter ", winter_type(), " Regelzeile: ", Game.rules_lines.slice(keep_lines.size()))
	Game.rules_lines = keep_lines
	_on_state_load(back, 1)
	_ensure_year()
	# 5) Ereignis-Faktor (Dürre aus C): min statt mal
	print("Klima-Test Events-Autoload vorhanden: ", _events != null)
