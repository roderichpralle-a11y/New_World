extends Node
## Fremde Händler (Regeln ab Version 2, "Herausforderung": Inselstärken, Gewürze und fremde Händler).
##
## Sobald auf einer besiedelten Insel ein fertiger Hafen steht (die Werft zählt mit), kommt
## `first_after_days` später der erste Händler, angekündigt `announce_days` vorher (Meldungsart
## "ereignis", Symbol "haendler"). Er liegt `stay_days` lang im Hafen einer Insel mit Hafen (lieber
## große Häfen und viele Siedler; Inseln mit angekündigtem Ereignis, Events.busy(w), überspringt er)
## und kommt `interval` Tage nach der Abfahrt wieder. Seehandel (Wirkung "trade"): Abstand x0,7 und
## ein Los mehr. Alles steht in data/merchant.json.
##
## Gehandelt wird in festen Losen mit dem Lager der Insel, an der er liegt (Gold dieser Insel):
## `sell_lots` Lose, die er verkauft, und `buy_lots`, die er kauft, jedes 1-3-mal. Losgröße: Waren für
## 6-14 Gold (resources.json price), bei billigen Waren in Fünferschritten. Er verkauft zum Preis x1,0-1,25
## (aufgerundet) und kauft zu x0,5-0,65 (abgerundet, mindestens 1 Gold). Was er anbietet, hängt vom
## Zeitalter ab ("sells": Ware -> ab Zeitalter); Gewürze bietet er immer an, solange keine Palmeninsel
## besiedelt ist, sonst jedes zweite Mal. Gewürze kauft er immer, wenn es eine Palmeninsel gibt. Die Lose
## entstehen aus Hash(Seed, Besuchsnummer) und stehen im Spielstand.
##
## Spielstand: oben "merchant" = {next, plan, island, until, seq, name_i, sells, buys}
## (Game.state_save/state_load). Alter Spielstand: erster Besuch rules_day + first_after_days.

signal changed  # angekündigt, angekommen, abgefahren oder gehandelt

var cfg: Dictionary = {}
var enabled := true  # Testhilfe --merchant=off
## next: time_days der nächsten Ankunft (-1 = noch keiner geplant), plan: angekündigte Insel (-1 keine),
## island: Insel, an der er liegt (-1 keine), until: Abfahrt, seq: Nummer des Besuchs, name_i: Name,
## sells / buys: Lose [{id, n, gold, left}] (sells: er verkauft n Waren für gold; buys: er kauft n Waren
## und zahlt gold; left: wie oft noch).
var state: Dictionary = {}
var _next_tick := 0.0


func _ready() -> void:
	cfg = Data._load("merchant")
	state = _fresh()
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


func _fresh() -> Dictionary:
	return {"next": -1.0, "plan": -1, "island": -1, "until": 0.0, "seq": 0, "name_i": 0, "sells": [], "buys": []}


func _c(key: String, default):
	return cfg.get(key, default)


# ---------------------------------------------------------------- Abfragen
func present() -> bool:
	return int(state.island) >= 0 and world() != null


## Liegt der Händler gerade bei dieser Insel?
func at(island_id: int) -> bool:
	return int(state.island) == island_id and present()


## Insel (World), an der der Händler liegt, sonst null.
func world():
	return _valid(int(state.island))


## Insel, für die er angekündigt ist, sonst null.
func planned_world():
	return _valid(int(state.plan))


func _valid(id: int):
	if id < 0:
		return null
	var w = Sea.worlds.get(id)
	if w == null or not is_instance_valid(w) or Sea.meta(id).get("state", "") != "settled":
		return null
	return w


func merchant_name() -> String:
	var names: Array = cfg.get("names", [])
	if names.is_empty():
		return tr("Händler")
	return str(names[int(state.name_i) % names.size()])


func hours_left() -> int:
	return maxi(0, int(ceil((float(state.until) - Game.time_days) * 24.0)))


func hours_until() -> int:
	return maxi(0, int(ceil((float(state.next) - Game.time_days) * 24.0)))


## Darf der Händler diese Insel anlaufen? Besiedelt, mit Siedlern, mit fertigem Hafen (Werft zählt)
## und ohne angekündigtes Ereignis (falls es Ereignisse gibt).
func eligible(w) -> bool:
	if w == null or not is_instance_valid(w) or w.settlers.is_empty():
		return false
	if Sea.meta(int(w.island_id)).get("state", "") != "settled":
		return false
	return Sea.harbor_level(w) >= 1 and not _busy(w)


func _busy(w) -> bool:
	var ev = get_node_or_null("/root/" + "events".capitalize())  # Autoload Events aus C, falls vorhanden
	return ev != null and ev.has_method("busy") and bool(ev.busy(w))


func has_harbor() -> bool:
	for w in Sea.all_worlds():
		if Sea.harbor_level(w) >= 1 and not w.settlers.is_empty():
			return true
	return false


## Kurzer Zustand für Anzeigen ("" = kein Hafen, noch nichts geplant).
func status_text() -> String:
	if present():
		return tr("%s liegt in %s, noch %d Std.") % [merchant_name(), Sea.island_name(world()), hours_left()]
	var pw = planned_world()
	if pw != null:
		return tr("Ein Händler kommt in %d Std. nach %s.") % [hours_until(), Sea.island_name(pw)]
	if float(state.next) >= 0.0:
		var d := float(state.next) - Game.time_days
		return tr("Der nächste Händler kommt in etwa %d Tagen.") % maxi(1, roundi(d))
	return tr("Händler kommen, sobald eine Insel einen Hafen hat (auch die Werft zählt).")


# ---------------------------------------------------------------- Ablauf
func _process(_delta: float) -> void:
	if not enabled or Game.world == null or Game.is_over or Game.speed <= 0:
		return
	if Game.time_days < _next_tick:
		return
	_next_tick = Game.time_days + 0.02
	tick()


func tick() -> void:
	var t := Game.time_days
	if int(state.island) >= 0:
		if world() == null:
			_leave(false)  # Insel verloren
		elif t >= float(state.until):
			_leave(true)
		return
	if float(state.next) < 0.0:
		if has_harbor():
			state.next = t + float(_c("first_after_days", 2.0))
			changed.emit()
		return
	var lead := float(_c("announce_days", 1.0))
	if int(state.plan) < 0 and t >= float(state.next) - lead:
		var w = _pick()
		if w == null:
			if not has_harbor():
				state.next = -1.0  # kein Hafen mehr: neu planen, sobald wieder einer steht
			else:
				state.next = t + lead + float(_c("postpone_days", 0.5))
			changed.emit()
			return
		state.plan = int(w.island_id)
		Game.notify(tr("In %d Stunden legt ein fremder Händler in %s an. Er handelt gegen Gold aus dem Lager dieser Insel.") % [hours_until(), Sea.island_name(w)], "haendler", "ereignis")
		Sound.play("glocke")
		changed.emit()
		return
	if t >= float(state.next):
		var w = planned_world()
		if not eligible(w):
			# Geplante Insel geht nicht mehr (z. B. Piraten angekündigt): eine andere, aber wieder mit
			# Ankündigung einen Tag vorher
			w = _pick()
			if w != null:
				state.plan = int(w.island_id)
				state.next = t + lead
				Game.notify(tr("Der fremde Händler fährt stattdessen nach %s und legt dort in %d Stunden an.") % [Sea.island_name(w), hours_until()], "haendler", "ereignis")
				changed.emit()
				return
		if w == null:
			if int(state.plan) >= 0:
				Game.notify(tr("Der fremde Händler verspätet sich: Kein Hafen kann ihn gerade aufnehmen."), "haendler", "ereignis")
			state.plan = -1
			state.next = t + lead + float(_c("postpone_days", 0.5)) if has_harbor() else -1.0
			changed.emit()
			return
		arrive(w)


## Händler legt jetzt an Insel w an (auch Testhilfe).
func arrive(w) -> void:
	state.island = int(w.island_id)
	state.plan = -1
	state.until = Game.time_days + float(_c("stay_days", 1.0))
	make_lots(w)
	w.sync_ships()
	Game.notify(tr("%s hat in %s angelegt und bleibt %d Stunden. Oben auf das Händler-Symbol tippen, um zu handeln.") % [merchant_name(), Sea.island_name(w), hours_left()], "haendler", "ereignis")
	Sound.play_on("entdeckt", w)
	changed.emit()


func _leave(say: bool) -> void:
	var w = world()
	var who := merchant_name()
	state.island = -1
	state.plan = -1
	state.sells = []
	state.buys = []
	state.seq = int(state.seq) + 1
	state.next = Game.time_days + next_interval(int(state.seq))
	if w != null:
		w.sync_ships()
		if say:
			Game.notify(tr("%s ist weitergesegelt. Der nächste Händler kommt in ein paar Tagen.") % who, "haendler", "ereignis")
	changed.emit()


## Tage bis zum nächsten Besuch nach Abfahrt Nummer seq (Seehandel: x0,7).
func next_interval(seq: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed_value, seq, "haendler_zeit"])
	var iv: Array = _c("interval", [4.0, 6.0])
	var d := rng.randf_range(float(iv[0]), float(iv[1]))
	if Game.eff_add("trade") > 0.0:
		d *= float(_c("trade_interval", 0.7))
	return d


## Zielinsel: unter den Inseln mit Hafen zufällig, gewichtet nach Hafenstufe und Siedlern.
func _pick():
	var cands := []
	var total := 0.0
	for w in Sea.all_worlds():
		if eligible(w):
			var wt := float(1 + Sea.harbor_level(w)) * maxf(1.0, float(w.settlers.size()))
			cands.append([w, wt])
			total += wt
	if cands.is_empty():
		return null
	cands.sort_custom(func(a, b): return int(a[0].island_id) < int(b[0].island_id))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed_value, int(state.seq), "haendler_ort"])
	var r := rng.randf() * total
	for c in cands:
		r -= float(c[1])
		if r <= 0.0:
			return c[0]
	return cands[-1][0]


# ---------------------------------------------------------------- Lose
func tradeable(id: String) -> bool:
	var d: Dictionary = Data.resources.get(id, {})
	return not d.is_empty() and id != "gold" and float(d.get("price", 0.0)) > 0.0 and int(d.get("size", 1)) > 0 \
		and d.get("category", "") != "ship"


func _tropen_settled() -> bool:
	for m in Sea.settled_islands():
		if m.get("biome", "") == "tropen":
			return true
	return false


func _lot_n(id: String, rng: RandomNumberGenerator) -> int:
	var price := float(Data.resources[id].price)
	var lg: Array = _c("lot_gold", [6, 14])
	var n := roundi(rng.randf_range(float(lg[0]), float(lg[1])) / price)
	if price < 0.5:
		n = maxi(5, roundi(n / 5.0) * 5)
	return maxi(1, n)


func _times(rng: RandomNumberGenerator) -> int:
	var lt: Array = _c("lot_times", [1, 3])
	return rng.randi_range(int(lt[0]), int(lt[1]))


## Lose für Besuch Nummer state.seq an Insel w (immer gleich für Seed und Besuch).
func make_lots(w) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.seed_value, int(state.seq), "haendler"])
	var names: Array = cfg.get("names", [])
	state.name_i = rng.randi() % maxi(1, names.size())
	var age := maxi(2, Game.current_age())
	var tropen := _tropen_settled()
	# Er verkauft: Waren seines Zeitalters, Gewürze immer ohne Palmeninsel, sonst jedes zweite Mal
	var pool := []
	var sells: Dictionary = cfg.get("sells", {})
	for id in sells:
		if tradeable(str(id)) and int(sells[id]) <= age:
			pool.append(str(id))
	_shuffle(pool, rng)
	var spice := pool.has("gewuerze") and (not tropen or rng.randf() < float(_c("spice_offer_chance", 0.5)))
	pool.erase("gewuerze")
	if spice:
		pool.push_front("gewuerze")
	var n_sell := int(_c("sell_lots", 4)) + (int(_c("trade_extra_lots", 1)) if Game.eff_add("trade") > 0.0 else 0)
	var out := []
	var mk: Array = _c("sell_markup", [1.0, 1.25])
	for id in pool.slice(0, n_sell):
		var n := _lot_n(id, rng)
		var gold := ceili(n * float(Data.resources[id].price) * rng.randf_range(float(mk[0]), float(mk[1])))
		out.append({"id": id, "n": n, "gold": maxi(1, gold), "left": _times(rng)})
	state.sells = out
	# Er kauft: Gewürze zuerst (gibt es eine Palmeninsel), dann Waren, die die Insel hat, dann der Rest
	var taken := out.map(func(l): return l.id)
	var bpool := []
	for id in cfg.get("buys", []):
		if tradeable(str(id)) and (not str(id) in taken or str(id) == "gewuerze"):
			bpool.append(str(id))
	_shuffle(bpool, rng)
	var br: Array = _c("buy_rate", [0.5, 0.65])
	var want_spice := tropen or Game.amount("gewuerze", w) > 0
	var first := []
	var have := []
	var rest := []
	for id in bpool:
		var n := _lot_n(id, rng)
		var gold := maxi(1, floori(n * float(Data.resources[id].price) * rng.randf_range(float(br[0]), float(br[1]))))
		var lot := {"id": id, "n": n, "gold": gold, "left": _times(rng)}
		if id == "gewuerze" and want_spice:
			first.append(lot)
		elif Game.amount(id, w) >= n:
			have.append(lot)
		else:
			rest.append(lot)
	state.buys = (first + have + rest).slice(0, int(_c("buy_lots", 3)))


func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var x = a[i]
		a[i] = a[j]
		a[j] = x


# ---------------------------------------------------------------- Handeln
## Warum Los i (er verkauft) gerade nicht geht ("" = geht).
func buy_block(i: int) -> String:
	var w = world()
	if w == null:
		return tr("Der Händler ist weitergesegelt.")
	if i < 0 or i >= state.sells.size():
		return tr("ausverkauft")
	var l: Dictionary = state.sells[i]
	if int(l.left) <= 0:
		return tr("ausverkauft")
	if Game.amount("gold", w) < int(l.gold):
		return tr("zu wenig Gold")
	if Game.space_for(str(l.id), w) < int(l.n):
		return tr("kein Platz im Lager")
	return ""


## Kauft Los i vom Händler (Gold der Insel, an der er liegt). Liefert "" oder den Grund.
func buy(i: int) -> String:
	var why := buy_block(i)
	if why != "":
		return why
	var w = world()
	var l: Dictionary = state.sells[i]
	Game.take_stock("gold", int(l.gold), w)
	Game.add_stock(str(l.id), int(l.n), w)
	l.left = int(l.left) - 1
	_traded(str(l.id))
	return ""


## Warum Los i (er kauft) gerade nicht geht ("" = geht).
func sell_block(i: int) -> String:
	var w = world()
	if w == null:
		return tr("Der Händler ist weitergesegelt.")
	if i < 0 or i >= state.buys.size():
		return tr("genug gekauft")
	var l: Dictionary = state.buys[i]
	if int(l.left) <= 0:
		return tr("genug gekauft")
	var have := Game.amount(str(l.id), w)
	if have < int(l.n):
		return tr("nur %d im Lager") % have
	if Game.space_for("gold", w) < int(l.gold):
		return tr("kein Platz für Gold")
	return ""


## Verkauft Los i an den Händler. Liefert "" oder den Grund.
func sell(i: int) -> String:
	var why := sell_block(i)
	if why != "":
		return why
	var w = world()
	var l: Dictionary = state.buys[i]
	Game.take_stock(str(l.id), int(l.n), w)
	Game.add_stock("gold", int(l.gold), w)
	l.left = int(l.left) - 1
	_traded(str(l.id))
	return ""


func _traded(id: String) -> void:
	Game.stats["trades"] = int(Game.stats.get("trades", 0)) + 1
	Game.player_action.emit("trade", id)
	Sound.play("fertig")
	changed.emit()


## Gold auf den anderen Inseln (für den Hinweis im Handelsfenster): [[Inselname, Gold], ...].
func gold_elsewhere(w) -> Array:
	var out := []
	for o in Sea.all_worlds():
		if o != w and Game.amount("gold", o) > 0:
			out.append([Sea.island_name(o), Game.amount("gold", o)])
	return out


# ---------------------------------------------------------------- Bild
## World.sync_ships: das Schiff des Händlers (getönte Kogge) liegt vor dem Hafen.
func add_ship(w, taken: Array) -> void:
	if not at(int(w.island_id)):
		return
	var spot = w._ship_spot(taken)
	if spot == null:
		return
	taken.append(spot)
	var sp: Sprite2D = w._ship_node("ship_kogge")
	sp.modulate = Color(str(_c("ship_tint", "#ffc27a")))
	sp.position = w.cell_to_pos(spot)
	w.entities.add_child(sp)
	w._ship_nodes[-1] = sp


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	state = _fresh()
	_next_tick = 0.0
	changed.emit()


func _on_save(d: Dictionary) -> void:
	d["merchant"] = state.duplicate(true)


func _lots_from(list) -> Array:
	var out := []
	if list is Array:
		for e in list:
			if e is Dictionary and tradeable(str(e.get("id", ""))):
				out.append({"id": str(e.id), "n": maxi(1, int(e.get("n", 1))), "gold": maxi(1, int(e.get("gold", 1))),
					"left": maxi(0, int(e.get("left", 0)))})
	return out


## Spielstand geladen. Fehlt "merchant" (alter Spielstand), kommt der erste Händler rules_day +
## first_after_days, falls es schon einen Hafen gibt (sonst 2 Tage nach dem ersten Hafen).
func _on_load(data: Dictionary, old_rules: int) -> void:
	state = _fresh()
	_next_tick = 0.0
	var e = data.get("merchant", null)
	if e is Dictionary:
		state.next = float(e.get("next", -1.0))
		state.plan = int(e.get("plan", -1))
		state.island = int(e.get("island", -1))
		state.until = float(e.get("until", 0.0))
		state.seq = maxi(0, int(e.get("seq", 0)))
		state.name_i = maxi(0, int(e.get("name_i", 0)))
		state.sells = _lots_from(e.get("sells", []))
		state.buys = _lots_from(e.get("buys", []))
		if int(state.island) >= 0 and world() == null:
			state.island = -1
			state.sells = []
			state.buys = []
		if int(state.plan) >= 0 and planned_world() == null:
			state.plan = -1
	elif has_harbor():
		state.next = Game.rules_day + float(_c("first_after_days", 2.0))
	if old_rules < 1:
		Game.rules_lines.append(tr("Jede Inselart hat Stärken. Palmeninseln haben Gewürze. Händler kommen an Häfen und handeln gegen Gold."))
	var w = world()
	if w != null:
		w.sync_ships()  # Sea.build_from_save hat die Schiffe schon vor dem Laden dieses Zustands gezeigt
	changed.emit()


# ---------------------------------------------------------------- Selbsttest
## Testhilfen (Game.systems): --merchant=off (keine Händler), --tradetest2=1 (Händler sofort auf der
## aktiven Insel, Kauf, Verkauf, Gründe, Speichern/Laden, Seehandel), --spicetest=1 (Generator, alter
## Spielstand, Sammler-Reihenfolge), --biometest=1 (Inselstärken), --goisland=N (vorher auf Insel N
## wechseln, für Bildschirmfotos; mit --goplace=typ,typ fertige Gebäude dort), --tradetest2=shot (nur den
## Händler hinlegen), --panel=trade (Handelsfenster offen lassen).
func autotest_setup(args: Dictionary, main) -> void:
	if str(args.get("merchant", "")) == "off":
		enabled = false
		print("Händler: aus")
	if args.has("goisland"):
		Sea.switch_to(int(args.goisland))
		for type in str(args.get("goplace", "")).split(",", false):  # fertige Gebäude auf dieser Insel
			print("Gebäude auf Insel %d: %s %s" % [int(args.goisland), type, main._place_on(Game.world, type)])
	if args.has("biometest"):
		MerchantTest.biome_test(main)
	if args.has("spicetest"):
		await MerchantTest.spice_test(main)
	if args.has("tradetest2"):
		await MerchantTest.trade_test(main, str(args.tradetest2))
	if str(args.get("panel", "")) == "trade":
		main.hud._trade_panel.open()


func autotest_report() -> String:
	if not enabled:
		print("   Händler: aus")
		return ""
	var where := "-"
	var day := -1.0
	var mode := "kein_hafen"
	if present():
		mode = "liegt"
		where = Sea.island_name(world())
		day = float(state.until) + 1.0
	elif planned_world() != null:
		mode = "angekuendigt"
		where = Sea.island_name(planned_world())
		day = float(state.next) + 1.0
	elif float(state.next) >= 0.0:
		mode = "naechster"
		day = float(state.next) + 1.0
	print("   Händler: %s %s Tag %.2f | Besuch Nr. %d, Handel %d | verkauft %s | kauft %s" % [mode, where, day,
		int(state.seq), int(Game.stats.get("trades", 0)), _lots_text(state.sells), _lots_text(state.buys)])
	var sp := []
	for w in Sea.all_worlds():
		var bushes: int = w.nodes.filter(func(n): return n.type == "gewuerzstrauch").size()
		if bushes > 0 or Game.amount("gewuerze", w) > 0:
			sp.append([Sea.island_name(w), bushes, Game.amount("gewuerze", w)])
	if not sp.is_empty():
		print("   Gewürze (Insel, Sträucher, Vorrat): ", sp)
	return ""


func _lots_text(list: Array) -> String:
	return ", ".join(list.map(func(l): return "%d %s=%dG x%d" % [int(l.n), str(l.id), int(l.gold), int(l.left)]))
