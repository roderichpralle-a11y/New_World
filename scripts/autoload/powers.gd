extends Node
## Befugnisse des Verwalters (josh 2026-10-29, nur Version 2): Mit jeder Ausbaustufe der Verwaltung
## (Admin.level(), 1 Schreibstube bis 7 KI-Leitstelle) darf der Verwalter mehr Routine übernehmen. Jede
## Befugnis steht auf Aus (der Spieler macht es selbst), Fragen (Vorschlag im Reiter Vorschläge, ein Tipp auf
## Ja führt ihn aus) oder Selbst (er macht es und schreibt es ins Log). Neue Befugnisse starten auf Fragen.
## Statt Fenstern zeigt der Verwalter-Knopf die Zahl offener Vorschläge. Die Tagesbilanz zählt, was er erledigt.
## Vorschläge sind Daten ({kind, ...}), damit sie im Spielstand liegen; do_action führt sie aus.

signal changed

const AUS := 0
const FRAGEN := 1
const SELBST := 2
const MAX_PROPOSALS := 30
const PROPOSAL_DAYS := 1.0  # ein Vorschlag verfällt nach so vielen Tagen (die Lage hat sich geändert)

## Reihenfolge = Anzeige im Menü. level: nötige Ausbaustufe der Verwaltung.
const LIST := [
	{"id": "nachbesetzen", "level": 1, "icon": "person", "name": "Nachbesetzen",
		"desc": "Stirbt ein Siedler, übernimmt ein Freier seinen Beruf (einer mit passendem Talent zuerst). Gibt es keinen, lernt ihn das nächste Kind, das erwachsen wird. Den Verwalter selbst ersetzt das Spiel immer sofort, auch ohne diese Befugnis."},
	{"id": "grundbesetzung", "level": 1, "icon": "hammer", "name": "Grundbesetzung",
		"desc": "Freie gehen nur dorthin, wo Arbeit wartet: Werkstätten mit Zutaten, deren Ware gebraucht wird; Bauern nach Feldern und Ställen; Holzfäller so viele, wie die Wärme braucht; Baumeister für Baustellen; ein Koch, wenn frische Nahrung haltbar gemacht werden muss, bevor sie verdirbt; ein Jäger, wenn Raubtiere nahe den Arbeitsplätzen sind. Niemand kommt in einen Beruf, in dem gerade nichts zu holen ist (keine Bäume, Winter). Er nimmt den Geübtesten, der nah wohnt. Bleibt ein Siedler einen Tag frei, bekommt er einen Beruf, wo Mindestvorräte fehlen oder eine Werkstatt Arbeit hat."},
	{"id": "essen_waerme", "level": 2, "icon": "weizen", "name": "Essen und Wärme sichern",
		"desc": "Rechnet aus, was die Insel in den nächsten 3 Tagen an Essen und Brennstoff braucht (alle Bewohner und arbeitenden Gebäude; leere Häuser verbrauchen nichts), und vergleicht es mit Vorrat und Ertrag der jetzigen Arbeiter. Fehlt etwas, setzt er gerade so viele Leute ein, dass es reicht, notfalls auch deine."},
	{"id": "mindestvorrat", "level": 2, "icon": "haus", "name": "Mindestvorräte",
		"desc": "Liegt eine Ware unter dem Mindestvorrat, den du im Reiter Vorräte einstellst, schickt er Siedler in den passenden Beruf: Freie und solche, die er selbst eingeteilt hat und die gerade nicht gebraucht werden. Er folgt der Lieferkette bis zum Anfang (fehlt Glas, prüft er zuerst Lehm). Genauso sorgt er für die Waren, die die Häuser brauchen (Möbel, Lesestoff, Glas …)."},
	{"id": "notfall", "level": 3, "icon": "sonne", "name": "Überstunden im Notfall",
		"desc": "Lassen sich Essen oder Wärme nicht sichern, weil Leute fehlen, ordnet er für diese Berufe Überstunden an, reicht das nicht, Schichtarbeit. Ist die Not vorbei, beendet er sie."},
	{"id": "forschung", "level": 3, "icon": "wissen", "name": "Forschung weiterführen",
		"desc": "Ist eine Forschung fertig und nichts vorgemerkt, startet er die nächste bezahlbare. Er sorgt auch für die Schriften (Tontafeln, Papier …), ohne die nur mit 20 % geforscht wird."},
	{"id": "inseln", "level": 4, "icon": "anker", "name": "Andere Inseln mitverwalten",
		"desc": "Alle Befugnisse gelten auch auf Inseln mit Rundfunkanstalt (die Insel der Verwaltung braucht auch eine)."},
	{"id": "waren", "level": 4, "icon": "boot", "name": "Waren ausgleichen",
		"desc": "Fährt mit freien Schiffen ohne Route Waren zu Inseln unter ihrem Mindestvorrat und bringt Überschüsse über dem Höchststand weg."},
	{"id": "gutachten", "level": 5, "icon": "kompass", "name": "Aufbau-Gutachten",
		"desc": "Jeden Sommer rechnet der Planungsautomat aus, wie der Aufbau besser liefe: Karte, Straßen, Gebäude zum Verschieben, Tipps und welche Insel als Nächstes besiedelt werden sollte. Nur Vorschläge, er baut nichts."},
	{"id": "versorgung", "level": 5, "icon": "zeitalter", "name": "Versorgungsplan",
		"desc": "Mit Rundfunkanstalt berechnet er im Gutachten auch, wie viele Gebäude welcher Art mindestens nötig sind, damit alle versorgt sind, weiter geforscht wird und die nächsten Gebäude bezahlbar sind."},
	{"id": "droiden", "level": 6, "icon": "ki", "name": "Droiden einsetzen",
		"desc": "Ein neuer Droide übernimmt den Beruf, in dem gerade Leute fehlen (sonst den häufigsten)."},
	{"id": "ki", "level": 7, "icon": "ki", "name": "KI übernimmt",
		"desc": "Ab der Forschung Künstliche Intelligenz übernimmt die KI alle Befugnisse und baut selbst."},
]

var mode: Dictionary = {}       # Befugnis -> AUS/FRAGEN/SELBST (fehlt = FRAGEN)
var proposals: Array = []       # [{key, power, text, day, act: {kind, ...}}]
var done: Dictionary = {}       # "Jahr:Tag" -> {Art: Anzahl}; Arten: job, trip, order, research
var seen_level := 0             # höchste Stufe, deren Befugnisse der Spieler schon gesehen hat (Punkt am Knopf)


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


func info(id: String) -> Dictionary:
	for p in LIST:
		if p.id == id:
			return p
	return {}


## Ist die Befugnis freigeschaltet (Ausbaustufe erreicht, Verwalter da)?
func unlocked(id: String) -> bool:
	if AiRule.ki():
		return true
	return Admin.level() >= int(info(id).get("level", 99))


func mode_of(id: String) -> int:
	if AiRule.ki():
		return SELBST  # die KI entscheidet alles selbst
	return int(mode.get(id, FRAGEN))


func set_mode(id: String, m: int) -> void:
	mode[id] = clampi(m, AUS, SELBST)
	AiRule.player_changed("power:" + id)
	if m != FRAGEN:
		proposals = proposals.filter(func(p): return p.power != id)
	changed.emit()


## Arbeitet die Befugnis (freigeschaltet und nicht Aus)?
func on(id: String) -> bool:
	return unlocked(id) and mode_of(id) != AUS


## Verwaltet der Verwalter diese Insel? Die Insel der Verwaltung immer, andere mit „Andere Inseln
## mitverwalten“ und Rundfunkanstalt (auf beiden Inseln). Unter der KI alle.
func covers(w) -> bool:
	if w == null or not is_instance_valid(w):
		return false
	if AiRule.ki():
		return true
	if Admin.level() < 1:
		return false
	var aw = Admin.admin_world()
	if w == aw:
		return true
	return on("inseln") and Steward.has_radio(w) and Steward.has_radio(aw)


## Eine Entscheidung des Verwalters. Selbst: sofort ausführen (Log, Tagesbilanz, Meldung nur wenn loud).
## Fragen: als Vorschlag merken (gleicher key ersetzt den alten). Gibt true zurück, wenn ausgeführt.
func decide(power: String, key: String, text: String, act: Dictionary, loud := false) -> bool:
	if not on(power):
		return false
	if mode_of(power) == SELBST:
		if not do_action(act):
			return false
		var who := Steward.who()
		if loud:
			Game.notify(who + ": " + text, info(power).get("icon", "person"), "verwaltung")
		else:
			Admin.add_log(who + ": " + text)
		return true
	for p in proposals:
		if p.key == key:
			p.text = text
			p.act = act
			p.day = Game.time_days
			return false
	proposals.append({"key": key, "power": power, "text": text, "day": Game.time_days, "act": act})
	if proposals.size() > MAX_PROPOSALS:
		proposals.pop_front()
	changed.emit()
	return false


## Liegt schon ein Vorschlag mit diesem key vor?
func proposed(key: String) -> bool:
	return proposals.any(func(p): return p.key == key)


## Der Spieler nimmt Vorschlag i an (true) oder lehnt ihn ab.
func answer(i: int, yes: bool) -> void:
	if i < 0 or i >= proposals.size():
		return
	var p: Dictionary = proposals[i]
	proposals.remove_at(i)
	if yes and do_action(p.act):
		Admin.add_log(tr("Du: %s") % p.text)
	changed.emit()


func answer_all() -> void:
	while not proposals.is_empty():
		answer(0, true)


## Führt eine Entscheidung aus. Gibt false zurück, wenn sie nicht mehr geht (Siedler weg, Schiff fort).
func do_action(a: Dictionary) -> bool:
	match str(a.get("kind", "")):
		"job":
			var w = Sea.worlds.get(int(a.island))
			if w == null:
				return false
			for s in w.settlers:
				if int(s.id) == int(a.sid) and s.is_adult():
					if s.job == str(a.job):
						return false
					if not JobDesk.assign(s, str(a.job), "verwalter", Steward.KEEP_DAYS, bool(a.get("force", false))):
						return false
					count("job")
					return true
			return false
		"order":
			if str(a.what) == "ot":
				if Admin.set_overtime(str(a.job), bool(a.on), true) != "":
					return false
			else:
				Admin.set_shift(str(a.job), bool(a.on), true)
			count("order")
			return true
		"research":
			if Game.research.current != "" or Game.start_research(str(a.tech)) != "":
				return false
			count("research")
			return true
		"trip":
			if not Steward.ship_now(int(a.from), int(a.to), a.goods, str(a.why)):
				return false
			count("trip")
			return true
	return false


func count(what: String) -> void:
	var k := _day_key()
	if not done.has(k):
		done[k] = {}
		for old in done.keys():  # nur die letzten 400 Tage behalten
			if float(str(old).split(":")[1]) < floor(Game.time_days) - 400:
				done.erase(old)
	done[k][what] = int(done[k].get(what, 0)) + 1


func _day_key(t: float = -1.0) -> String:
	if t < 0.0:
		t = Game.time_days
	return "%d:%d" % [Seasons.year(t), int(floor(t))]


## Was hat er heute (today) bzw. dieses Jahr erledigt? {job, trip, order, research}
func tally(today: bool) -> Dictionary:
	var out := {}
	var y := Seasons.year()
	var d := int(floor(Game.time_days))
	for k in done:
		var parts := str(k).split(":")
		if int(parts[0]) != y or (today and int(parts[1]) != d):
			continue
		for what in done[k]:
			out[what] = int(out.get(what, 0)) + int(done[k][what])
	return out


## Punkt am Verwalter-Knopf: offene Vorschläge, oder eine neue Stufe, deren Befugnisse noch keiner angesehen hat.
func badge() -> int:
	return proposals.size()


func new_level() -> bool:
	return Admin.level() > seen_level


func _process(_delta: float) -> void:
	if proposals.is_empty() or Game.world == null:
		return
	var n := proposals.size()
	proposals = proposals.filter(func(p): return Game.time_days - float(p.day) < PROPOSAL_DAYS and on(str(p.power)) and mode_of(str(p.power)) == FRAGEN)
	if proposals.size() != n:
		changed.emit()


func autotest_setup(args: Dictionary, main) -> void:
	if args.has("powerstest"):
		await PowersTest.run(main, str(args.powerstest))
	if args.has("vlab"):
		await StewardLab.run(main, str(args.vlab))


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	mode = {}
	proposals = []
	done = {}
	seen_level = 0


func _on_save(d: Dictionary) -> void:
	d["powers"] = {"mode": mode.duplicate(), "proposals": proposals.duplicate(true), "done": done.duplicate(true), "seen": seen_level}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var e = data.get("powers", null)
	if e is Dictionary:
		for k in e.get("mode", {}):
			mode[str(k)] = int(e.mode[k])
		for p in e.get("proposals", []):
			if p is Dictionary and p.has("act"):
				proposals.append(p)
		var dn = e.get("done", {})
		if dn is Dictionary:
			done = dn
		seen_level = int(e.get("seen", 0))
		return
	# Ältere Spielstände: was bisher lief, steht auf Selbst
	var st = data.get("steward", {})
	if st is Dictionary and bool(st.get("on", false)):
		for k in ["grundbesetzung", "essen_waerme", "mindestvorrat", "inseln", "waren"]:
			mode[k] = SELBST
	var ad = data.get("admin", {})
	if ad is Dictionary:
		if bool(ad.get("auto", false)):
			mode["nachbesetzen"] = SELBST
		if bool(ad.get("self_orders", false)):
			mode["notfall"] = SELBST
