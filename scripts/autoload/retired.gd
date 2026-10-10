class_name Retired
extends RefCounted
## Gebäude und Forschungen, die es nicht mehr gibt (kein Autoload; Game ruft es beim Laden auf).
## josh (Oktober 2026): "Lass den Brunnen weg. Entferne ihn aus dem Code." Alte Spielstände können
## noch Brunnen (fertig oder als Baustelle) und die Forschung Brunnenbau enthalten:
## - strip_save(d, backup) (aus Game.apply_save_header, vor dem Aufbau der Inseln): nimmt die Gebäude aus
##   den Inseldaten und aus der Sicherung für ältere Versionen (Game._v2_restore) und die Forschung aus
##   done/paid/progress/current und merkt sich je Insel das Baumaterial: fertige Gebäude ihre vollen
##   Baukosten, Baustellen das schon gelieferte Material, eine bezahlte Forschung ihre Kosten (Heimatinsel).
## - give_back() (aus Game.after_load, alle Inseln stehen): gibt das Material über Game.grant_reward
##   zurück (zuerst ins Lager der Insel, was dort keinen Platz hat, auf andere Inseln, der Rest wartet
##   auf Platz) und meldet einmal, was passiert ist.
## Die Kosten stehen hier, weil die Einträge aus buildings.json und techs.json verschwunden sind.
const BUILDINGS := {"brunnen": {"stein": 10, "holz": 4}}
const TECHS := {"brunnenbau": {"stein": 15, "holz": 15}}

## {"isl": {Insel-ID (Text): {Ware: Menge}}, "n": entfernte Gebäude, "techs": entfernte Forschungen}
static var pending: Dictionary = {}
## Für den Selbsttest: was beim letzten Laden geschah (Mengen, Zusammenfassung)
static var last: Dictionary = {}


static func strip_save(d: Dictionary, backup: Dictionary) -> void:
	pending = {"isl": {}, "n": 0, "techs": []}
	last = {}
	var seen := {}  # Insel-ID -> Gebäude-IDs, die schon gezählt sind
	var list = d.get("islands", [])
	if list is Array and not list.is_empty():
		for e in list:
			if e is Dictionary and e.get("world") is Dictionary:
				_strip_buildings(e.world, str(int(e.get("id", 0))), seen)
	elif d.get("world") is Dictionary:  # Version 1: eine Insel
		_strip_buildings(d.world, "0", seen)
	for key in backup:  # Sicherung für ältere Versionen: dort keine Brunnen mehr zurückholen
		var e = backup[key]
		if e is Dictionary and e.get("b") is Array:
			e["b"] = Array(e.b).filter(func(b): return not _take(b, str(key), seen))
	var r = d.get("research", {})
	if not (r is Dictionary):
		return
	var paid: Array = Array(r.get("paid", []))
	for t in TECHS:
		var had := false
		for k in ["done", "paid"]:
			if Array(r.get(k, [])).has(t):
				had = true
				r[k] = Array(r[k]).filter(func(x): return str(x) != t)
		if r.get("progress") is Dictionary and r.progress.has(t):
			had = true
			r.progress.erase(t)
		if str(r.get("current", "")) == t:
			had = true
			r["current"] = ""
		if had:
			pending.techs.append(t)
		if t in paid:
			_add("0", TECHS[t])  # bezahlt wurde aus dem Lager; zurück auf die Heimatinsel


## Entfernt die Gebäude aus einer Insel (Daten wie im Spielstand) und merkt sich das Material.
static func _strip_buildings(wd: Dictionary, key: String, seen: Dictionary) -> void:
	if wd.get("buildings") is Array:
		wd["buildings"] = Array(wd.buildings).filter(func(b): return not _take(b, key, seen))


## Ist b ein entferntes Gebäude? Dann Material merken (einmal je Gebäude-ID) und true.
static func _take(b, key: String, seen: Dictionary) -> bool:
	if not (b is Dictionary) or not BUILDINGS.has(str(b.get("type", ""))):
		return false
	var ids: Array = seen.get(key, [])
	var id := int(b.get("id", -1))
	if id in ids:
		return true
	ids.append(id)
	seen[key] = ids
	pending.n = int(pending.n) + 1
	if bool(b.get("complete", false)):
		_add(key, BUILDINGS[str(b.type)])
	elif b.get("delivered") is Dictionary:
		_add(key, b.delivered)
	return true


static func _add(key: String, goods: Dictionary) -> void:
	var e: Dictionary = pending.isl.get(key, {})
	for id in goods:
		if int(goods[id]) > 0:
			e[str(id)] = int(e.get(str(id), 0)) + int(goods[id])
	pending.isl[key] = e


## Nach dem Aufbau der Inseln: Material zurückgeben und einmal melden.
static func give_back() -> void:
	if pending.is_empty() or (int(pending.get("n", 0)) == 0 and Array(pending.get("techs", [])).is_empty()):
		pending = {}
		return
	var parts := []
	var given := {}
	var total := {}  # alle Inseln und wartende Waren vorher (für den Selbsttest)
	for key in pending.isl:
		for id in pending.isl[key]:
			total[id] = _everywhere(id)
	for key in pending.isl:
		var w = Sea.worlds.get(int(key))
		if w == null:
			w = Sea.worlds.get(0, Game.world)
		var goods: Dictionary = pending.isl[key]
		if w == null or goods.is_empty():
			continue
		var before := {}
		for id in goods:
			before[id] = int(w.stock.get(id, 0))
		var txt := Game.grant_reward(w, goods)
		given[key] = {"goods": goods, "before": before, "text": txt}
		if txt != "":
			parts.append("%s: %s" % [Sea.island_name(w), txt] if pending.isl.size() > 1 else txt)
	var n := int(pending.n)
	var msg := Loc.t("Brunnen gibt es nicht mehr, auch nicht die Forschung Brunnenbau.")
	if n == 1:
		msg = Loc.t("Brunnen gibt es nicht mehr: Der Brunnen ist abgebaut.")
	elif n > 1:
		msg = Loc.t("Brunnen gibt es nicht mehr: %d Brunnen sind abgebaut.") % n
	if not parts.is_empty():
		msg += " " + Loc.t("Baumaterial zurück: %s.") % "; ".join(parts)
	for id in total:
		total[id] = [total[id], _everywhere(id)]
	last = {"n": n, "techs": pending.techs.duplicate(), "given": given, "total": total, "text": msg}
	print("Entfernt beim Laden: %d Brunnen, Forschung %s, Material %s" % [n, pending.techs, given])
	Game.queue_note(msg, "hammer")
	pending = {}


## Menge einer Ware auf allen Inseln plus die wartenden Belohnungen (Game.reward_wait).
static func _everywhere(id: String) -> int:
	var n := 0
	for w in Sea.all_worlds():
		n += int(w.stock.get(id, 0))
	for k in Game.reward_wait:
		n += int(Game.reward_wait[k].get(id, 0))
	return n


# ---------------------------------------------------------------- Selbsttest
## --retiredtest=n:3,stein:41,holz:25 (mit --fixture=<alter Spielstand mit Brunnen>): erwartete Zahl
## abgebauter Brunnen und zurückgegebenes Material (Summe aller Inseln). Prüft: keine Brunnen mehr auf
## den Inseln, Brunnenbau aus der Forschung, Material vollständig angekommen (Lager aller Inseln plus
## wartende Waren), Meldung; danach Speichern und erneut prüfen, dass nichts ein zweites Mal kommt.
static func autotest(spec: String) -> void:
	print("--- Test entfernte Brunnen")
	var want := {}
	for kv in spec.split(",", false):
		var p := kv.split(":")
		if p.size() == 2:
			want[p[0]] = int(p[1])
	var wells := 0
	for w in Sea.all_worlds():
		wells += w.buildings.filter(func(b): return BUILDINGS.has(b.type)).size()
	var r := Game.research
	var tech_left := false
	for t in TECHS:
		tech_left = tech_left or t in r.done or t in r.paid or Dictionary(r.progress).has(t) or str(r.current) == t
	var gone := wells == 0 and not tech_left and not Data.buildings.has("brunnen") and not Data.techs.has("brunnenbau")
	print("Entfernt ", _ok(gone), " keine Brunnen auf den Inseln (%d), Brunnenbau nicht in der Forschung, aktuelle Forschung '%s'" % [wells, r.current])
	var got := {}
	var arrived := true
	for key in last.get("given", {}):
		var g: Dictionary = last.given[key].goods
		for id in g:
			got[id] = int(got.get(id, 0)) + int(g[id])
	for id in last.get("total", {}):
		var t: Array = last.total[id]
		arrived = arrived and int(t[1]) - int(t[0]) == int(got.get(id, 0))
	var match_want := int(last.get("n", -1)) == int(want.get("n", 0))
	for id in want:
		if id != "n":
			match_want = match_want and int(got.get(id, 0)) == int(want[id])
	print("Entfernt ", _ok(match_want and arrived), " %d Brunnen abgebaut (erwartet %d), Material %s (erwartet %s), vollständig angekommen: %s %s" % [
		int(last.get("n", -1)), int(want.get("n", 0)), got, want, arrived, last.get("total", {})])
	for key in last.get("given", {}):
		var e: Dictionary = last.given[key]
		var w = Sea.worlds.get(int(key))
		var now := {}
		for id in e.goods:
			now[id] = int(w.stock.get(id, 0)) if w else -1
		if w:
			print("   Insel %s: Stauraum %d, belegt %d, Platz für Stein %d, Holz %d, Grenzen %s" % [key, Game.storage_volume(w), Game.used_volume(w), Game.space_for("stein", w), Game.space_for("holz", w), w.store_limits])
		print("   Insel %s: zurück %s, Lager vorher %s, jetzt %s, Meldung: %s" % [key, e.goods, e.before, now, e.text])
	var msg := str(last.get("text", ""))
	print("Entfernt ", _ok(msg != "" and got.keys().all(func(id): return str(got[id]) in msg)), " Meldung: ", msg)
	# Speichern und die gespeicherten Daten noch einmal prüfen: nichts mehr zu entfernen
	Game.save_game()
	var d = JSON.parse_string(FileAccess.get_file_as_string(Game.SAVE_PATH))
	var keep_last := last
	strip_save(d, {})
	var again: int = int(pending.n) + Array(pending.techs).size() + Dictionary(pending.isl).size()
	var in_backup := false
	var isl = d.islands[0].get("v2", {}).get("isl", {})
	for k in isl:
		in_backup = in_backup or Array(isl[k].get("b", [])).any(func(b): return BUILDINGS.has(str(b.get("type", ""))))
	pending = {}
	last = keep_last
	print("Entfernt ", _ok(again == 0 and not in_backup), " nach dem Speichern: nichts mehr zu entfernen (%d), keine Brunnen in der Sicherung für ältere Versionen" % again)


static func _ok(b: bool) -> String:
	return "OK" if b else "FEHLER"
