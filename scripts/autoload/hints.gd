extends Node
## Hinweis-Fenster (josh 2026-10-17): einmal je Spielstand ein kleines Fenster mit Symbol, Überschrift
## und 3 bis 5 Sätzen, wenn etwas Neues kommt. Texte in data/hints.json (aus dem Dokument „Hinweis-Fenster:
## Ereignisse und Texte“), Schlüssel:
## - age_<i>: Zeitalter i beginnt (Exams.passed; age_0 = Steinzeit beim Spielstart)
## - tier_<n>: die zweite Stufe eines Zeitalters, sobald ihre erste Forschung wählbar ist
## - tech_<id>: die Forschung ist fertig und schaltet ein Gebäude oder eine Funktion frei (reine
##   Verbesserungen wie Flechtkörbe haben keinen Eintrag und bekommen kein Fenster)
## - first_<art>: beim ersten Mal (winter, quests, event, pirates, merchant, exam, island, admin)
## Prüft jede Sekunde (echte Zeit), was gerade gilt; Neues kommt in die Warteschlange, Zeitalter zuerst.
## Die Hud zeigt das erste Fenster der Schlange (Hud._show_hint), das Spiel hält solange an.
## Unter Menü > Meldungen abschaltbar (Game.hints_on, settings.cfg [notify] hints): dann nur als Meldung.
## Spielstand: "hints" = {seen: [Schlüssel]}. Alter Spielstand ohne "hints": alles, was schon gilt, zählt
## als gesehen (keine Fenster für Dinge, die man schon hat).
## Selbsttests sehen keine Fenster (--autotest), außer mit --hinttest.
## Neue Insel (josh 2026-10-22), bei jeder neu besiedelten Insel, Schlüssel "isl_hunt:<Insel-ID>" und
## "isl_wood:<Insel-ID>": zuerst alle zu Jägern machen, damit die Tiere sie nicht töten; sind höchstens noch
## 2 erwachsene Tiere je Art übrig (so viele lassen die Jäger stehen), einer wird Holzfäller, dann ein Haus
## bauen. Ohne wilde Tiere gleich der zweite Schritt. Spielstand: "hints".isl = {Insel-ID: Schritt 1 oder 2}.

signal queued

const ORDER := ["age_", "tier_", "tech_", "first_"]

var texts: Dictionary = {}
var seen: Dictionary = {}  # Schlüssel -> true
var queue: Array = []  # Schlüssel, die auf ihr Fenster warten
var isl: Dictionary = {}  # Insel-ID (Text) -> Schritt der Anleitung für neue Inseln (1 Jäger, 2 Holzfäller und Haus)
var _seed := false  # beim nächsten Prüfen alles, was schon gilt, ohne Fenster als gesehen merken
var _next := 0.0
var _off := false  # Selbsttest ohne --hinttest


func _ready() -> void:
	texts = Data._load("hints")
	texts.erase("_info")
	var a := " ".join(OS.get_cmdline_user_args())
	_off = a.contains("--autotest") and not a.contains("--hinttest")
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(func(data: Dictionary): data["hints"] = {"seen": seen.keys(), "isl": isl.duplicate()})
	Game.state_load.connect(_on_load)


func _on_reset() -> void:
	seen = {}
	isl = {}
	queue = []
	_seed = false


func _on_load(data: Dictionary, _old_rules: int) -> void:
	seen = {}
	isl = {}
	queue = []
	var h = data.get("hints", null)
	if h is Dictionary:
		for k in h.get("seen", []):
			seen[str(k)] = true
		var ii = h.get("isl", null)
		if ii is Dictionary:
			for k in ii:
				isl[str(k)] = int(ii[k])
		else:
			for m in Sea.settled_islands():  # Spielstand von vor der Anleitung: bestehende Inseln haben sie hinter sich
				isl[str(int(m.id))] = 2
		_seed = false
	else:
		_seed = true


func _process(_delta: float) -> void:
	if _off or Game.world == null or Game.is_over or not Game.notes_live:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next:
		return
	_next = now + 1.0
	check()


## Was gilt gerade? Neues kommt in die Schlange (oder wird bei altem Spielstand still gemerkt).
func check() -> void:
	var fresh := []
	for k in due():
		if not seen.has(k):
			seen[k] = true
			fresh.append(k)
	var guide := island_guide(_seed)
	if _seed:
		_seed = false
		return
	fresh.append_array(guide)
	if fresh.is_empty():
		return
	fresh.sort_custom(func(a, b): return _rank(a) < _rank(b))
	for k in fresh:
		if Game.hints_on:
			queue.append(k)
		else:
			Game.notify("%s: %s" % [title(k), text(k)], icon(k), "forschung")
	queue.sort_custom(func(a, b): return _rank(a) < _rank(b))
	if not queue.is_empty():
		queued.emit()


func _rank(k: String) -> int:
	for i in ORDER.size():
		if k.begins_with(ORDER[i]):
			return i * 1000 + (int(k.get_slice("_", 1)) if i < 2 else 0)
	return 9999


## Anleitung für neu besiedelte Inseln: gibt die neuen Schlüssel zurück. quiet: nur merken (alter Spielstand).
func island_guide(quiet := false) -> Array:
	var out := []
	for w in Sea.all_worlds():
		if w == null or not is_instance_valid(w) or Sea.is_main(w) or w.settlers.is_empty():
			continue
		var id := str(int(w.island_id))
		var step := int(isl.get(id, 0))
		if quiet:
			isl[id] = 2
			continue
		if step == 0:
			isl[id] = 1 if not tame(w) else 2
			out.append(("isl_hunt:" if not tame(w) else "isl_wood:") + id)
		elif step == 1 and tame(w):
			isl[id] = 2
			out.append("isl_wood:" + id)
	return out


## Sind auf der Insel höchstens noch 2 erwachsene Tiere je Art (so viele lassen die Jäger stehen)?
func tame(w) -> bool:
	var keep := int(Data.bal("hunt_min_keep", 2))
	for a in w.animals:
		if is_instance_valid(a) and not a.dead and a.is_adult() and w.adult_count(a.type) > keep:
			return false
	return true


func _isl_name(k: String) -> String:
	return Sea.island_name(Sea.worlds.get(int(k.get_slice(":", 1))))


## Alle Schlüssel mit Text, deren Bedingung jetzt erfüllt ist.
func due() -> Array:
	var out := []
	for i in range(0, Exams.passed + 1):
		out.append("age_%d" % i)
	for t in Data.techs:
		var st := Game.tech_state(t)
		if st == "done":
			out.append("tech_" + t)
		if st == "available" or st == "current" or st == "done":
			out.append("tier_%d" % int(Data.techs[t].get("tier", 1)))
	var w = Game.world
	if Seasons.season() >= 2 or Seasons.year() > 1:
		out.append("first_winter")
	if Seasons.year() > 1:  # nach einem Jahr: Meldungen im Menü an- und abschalten (josh 2026-10-22)
		out.append("first_year")
	for wd in Sea.all_worlds():  # zum ersten Mal ist ein Lager voll (josh 2026-10-22)
		var vol := Game.storage_volume(wd)
		if vol > 0 and Game.used_volume(wd) >= vol - 3:
			out.append("first_storage_full")
			break
	if not Quests.offers.is_empty() or not Quests.active.is_empty():
		out.append("first_quests")
	for wd in Sea.all_worlds():
		var ev := Events.event_of(wd)
		if not ev.is_empty():
			out.append("first_pirates" if str(ev.get("type", "")) == "piraten" else "first_event")
	if Merchant.planned_world() != null or Merchant.present():
		out.append("first_merchant")
	if Exams.gated():
		out.append("first_exam")
	if Sea.islands.size() > 1:
		out.append("first_island")
	if Admin.manager() != null:
		out.append("first_admin")
	return out.filter(func(k): return texts.has(k) and w != null)


func title(k: String) -> String:
	if k.contains(":"):
		return tr(str(texts.get(k.get_slice(":", 0), {}).get("name", ""))) % _isl_name(k)
	return tr(str(texts.get(k, {}).get("name", "")))


func text(k: String) -> String:
	if k.begins_with("isl_hunt:") and not Data.job_unlocked("jaeger"):
		return tr(str(texts.get("isl_hunt", {}).get("locked", "")))
	if k.contains(":"):
		return tr(str(texts.get(k.get_slice(":", 0), {}).get("text", "")))
	return tr(str(texts.get(k, {}).get("text", "")))


func icon(k: String) -> String:
	var e: Dictionary = texts.get(k.get_slice(":", 0), {})
	if e.has("icon"):
		return str(e.icon)
	if k.begins_with("age_") or k.begins_with("tier_"):
		return "zeitalter"
	if k.begins_with("tech_"):
		return str(Data.techs.get(k.substr(5), {}).get("icon", "wissen"))
	return {"first_winter": "holz", "first_quests": "ziel", "first_event": "ereignis", "first_pirates": "ereignis",
		"first_merchant": "haendler", "first_exam": "zeitalter", "first_island": "kompass", "first_admin": "wissen", "first_storage_full": "kiste", "first_year": "glocke"}.get(k, "wissen")


## Nächster Hinweis aus der Schlange ("" = keiner).
func pop() -> String:
	return "" if queue.is_empty() else str(queue.pop_front())


# ---------------------------------------------------------------- Selbsttest
## --hinttest=1: neues Spiel zeigt die Steinzeit, fertige Forschung mit Text kommt in die Schlange,
## Stufe 2 nach Holzbearbeitung, Reihenfolge Zeitalter zuerst, Fenster hält das Spiel an, Spielstand,
## alter Spielstand ohne Fenster, abgeschaltet nur Meldung. Druckt "Hinweise OK/FEHLER".
func autotest_setup(args: Dictionary, main) -> void:
	if args.has("hintshot"):  # Bildschirmfoto eines Hinweis-Fensters (mit --shot), z. B. --hintshot=age_1
		queue.append(str(args.hintshot))
	if not args.has("hinttest"):
		return
	var fails := [0]
	var ok := func(c: bool, what: String):
		if not c:
			fails[0] += 1
		print("Hinweise ", "OK " if c else "FEHLER ", what)
	_on_reset()
	queue.clear()
	check()
	ok.call(queue.has("age_0"), "neues Spiel: Steinzeit %s" % [queue])
	ok.call(not queue.has("tier_2"), "Stufe 2 noch nicht")
	queue.clear()
	for t in ["steinwerkzeuge", "holzbearbeitung", "schrift"]:
		if not t in Game.research.done:
			Game.research.done.append(t)
	Game.refresh_effects()
	check()
	ok.call(queue.has("tech_holzbearbeitung") and queue.has("tech_schrift"), "Holzbearbeitung und Schrift %s" % [queue])
	ok.call(not queue.has("tech_steinwerkzeuge"), "Steinwerkzeuge (nur Verbesserung) ohne Fenster")
	ok.call(queue.has("tier_2") and queue[0] == "tier_2", "Stufe 2 vor den Gebäuden %s" % [queue])
	check()
	ok.call(queue.size() == 3, "kein Hinweis doppelt")
	# Fenster hält das Spiel an
	Game.set_speed(1)
	var n := queue.size()
	for i in 30:
		await main.get_tree().process_frame
	ok.call(main.hud._hint_dialog != null and Game.speed == 0 and queue.size() == n - 1, "Fenster offen, Spiel steht")
	var title_ok := main.hud._hint_dialog != null and str(title("tier_2")) != ""
	ok.call(title_ok, "Überschrift „%s“" % title("tier_2"))
	while main.hud._hint_dialog != null:
		main.hud._hint_dialog.queue_free()
		main.hud._hint_dialog = null
		Game.set_speed(1)
		for i in 5:
			await main.get_tree().process_frame
	ok.call(queue.is_empty(), "alle Fenster nacheinander gezeigt")
	# Spielstand
	var data := {}
	Game.state_save.emit(data)
	var keep: Array = data.get("hints", {}).get("seen", [])
	_on_load(data, 1)
	check()
	ok.call(seen.size() == keep.size() and queue.is_empty(), "Spielstand: gesehen bleibt gesehen (%d)" % keep.size())
	# alter Spielstand: nichts kommt
	_on_load({}, 0)
	Game.research.done.append("zimmerei")
	Game.refresh_effects()
	check()
	ok.call(queue.is_empty() and seen.has("tech_zimmerei") and seen.has("age_0"), "alter Spielstand: kein Fenster")
	# abgeschaltet: nur Meldung
	var got := []
	var cb := func(t, _i, _c): got.append(t)
	Game.notified.connect(cb)
	Game.hints_on = false
	Game.research.done.append("toepferei")
	Game.refresh_effects()
	check()
	Game.hints_on = true
	Game.notified.disconnect(cb)
	ok.call(queue.is_empty() and got.any(func(t): return str(t).begins_with(title("tech_toepferei"))), "abgeschaltet: nur Meldung")
	print("Hinweise Ergebnis: %d Fehler" % fails[0])
