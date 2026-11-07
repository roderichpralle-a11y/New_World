extends Node
## Befugnisse des Verwalters (josh 2026-10-29, nur Version 2; seit 2026-11-07 nur noch Nachbesetzen und
## Auslastung). Jede Befugnis steht auf Aus (der Spieler macht es selbst) oder Selbst (er macht es und schreibt es
## ins Log). Die Tagesbilanz zählt, was er erledigt. do_action führt eine Entscheidung ({kind: "job", ...}) aus.

signal changed

const AUS := 0
const FRAGEN := 1  # nur noch für alte Spielstände (zählt wie Selbst)
const SELBST := 2

## Reihenfolge = Anzeige im Menü. level: nötige Ausbaustufe der Verwaltung. Seit josh 2026-11-07 gibt es nur
## noch diese zwei; alle anderen Befugnisse (Essen und Wärme, Mindestvorräte, Obergrenzen, Notfall, Forschung,
## andere Inseln, Waren, Gutachten, Versorgungsplan, Droiden, KI) sind gestrichen.
const LIST := [
	{"id": "nachbesetzen", "level": 1, "icon": "person", "name": "Nachbesetzen",
		"desc": "Stirbt ein Siedler, übernimmt ein Freier seinen Beruf (einer mit passendem Talent zuerst). Gibt es keinen, lernt ihn das nächste Kind, das erwachsen wird. Den Verwalter selbst ersetzt das Spiel immer sofort, auch ohne diese Befugnis."},
	{"id": "auslastung", "level": 1, "icon": "hammer", "name": "Auslastung",
		"desc": "Er schaut je Insel, wie ausgelastet jeder Beruf ist (Anteil der Arbeitszeit im eigenen Beruf). Unter 80 % stellt er einen Siedler dieses Berufs frei, über 90 % bekommt der Beruf einen Freien dazu. Es gibt immer einen Baumeister, einen Verwalter und einen Fischer. Leben auf einer Insel weniger als 7 Erwachsene, meldet er das, teilt einmal Holzfäller, Fischer und Sammler in dieser Reihenfolge ein und hört dann auf. Er verteilt Berufe auf der Insel der Verwaltung und auf Inseln, die mit einer Rundfunkanstalt am Funknetz hängen (die Insel der Verwaltung braucht dann auch eine)."},
]

var mode: Dictionary = {}       # Befugnis -> AUS/SELBST (fehlt = SELBST; Fragen gibt es seit 2026-11-07 nicht mehr)
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
	return AUS if int(mode.get(id, SELBST)) == AUS else SELBST


func set_mode(id: String, m: int) -> void:
	mode[id] = AUS if m == AUS else SELBST
	AiRule.player_changed("power:" + id)
	changed.emit()


## Arbeitet die Befugnis (freigeschaltet und nicht Aus)?
func on(id: String) -> bool:
	return unlocked(id) and mode_of(id) != AUS


## Verwaltet der Verwalter diese Insel? Die Insel der Verwaltung immer, andere, wenn sie am Funknetz hängen
## (Rundfunkanstalt auf beiden Inseln, josh 2026-11-07). Unter der KI alle.
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
	return Steward.has_radio(w) and Steward.has_radio(aw)


## Eine Entscheidung des Verwalters: sofort ausführen (Log, Tagesbilanz, Meldung nur wenn loud).
## Gibt true zurück, wenn ausgeführt. (Fragen und Vorschläge gibt es seit josh 2026-11-07 nicht mehr.)
func decide(power: String, _key: String, text: String, act: Dictionary, loud := false) -> bool:
	if not on(power):
		return false
	if not do_action(act):
		return false
	var who := Steward.who()
	if loud:
		Game.notify(who + ": " + text, info(power).get("icon", "person"), "verwaltung")
	else:
		Admin.add_log(who + ": " + text)
	return true


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


## Zahl am Verwalter-Knopf: keine Vorschläge mehr (josh 2026-11-07).
func badge() -> int:
	return 0


func new_level() -> bool:
	return Admin.level() >= 1 and seen_level < 1  # nur die erste Stufe bringt Befugnisse


func autotest_setup(args: Dictionary, main) -> void:
	if args.has("powerstest"):
		await PowersTest.run(main, str(args.powerstest))
	if args.has("vlab"):
		await StewardLab.run(main, str(args.vlab))


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	mode = {}
	done = {}
	seen_level = 0


func _on_save(d: Dictionary) -> void:
	d["powers"] = {"mode": mode.duplicate(), "done": done.duplicate(true), "seen": seen_level}


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var e = data.get("powers", null)
	if e is Dictionary:
		for k in e.get("mode", {}):
			mode[str(k)] = int(e.mode[k])
		# Auslastung ist neu (josh 2026-11-07): der alte Schalter der Grundbesetzung gilt nicht, sie startet auf Selbst
		var dn = e.get("done", {})
		if dn is Dictionary:
			done = dn
		seen_level = int(e.get("seen", 0))
		return
	# Ältere Spielstände: was bisher lief, steht auf Selbst
	var ad = data.get("admin", {})
	if ad is Dictionary and not bool(ad.get("auto", true)):
		mode["nachbesetzen"] = AUS
