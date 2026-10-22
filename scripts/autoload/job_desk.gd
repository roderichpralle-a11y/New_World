extends Node
## Vergabestelle für Berufe (josh 2026-10-22, Testversion /neu/): Alle Systeme, die Berufe von selbst ändern,
## gehen hier durch, damit sie einander nicht überschreiben. Wer einem Siedler einen Beruf gibt, hält ihn für
## HOLD Tage. In der Zeit darf nur ein Rang darüber ihn umsetzen, der gleiche Rang und alle darunter nicht.
## Rangfolge (höher gewinnt):
##   spieler   der Spieler selbst (Liste, Infofenster, Anheuern); hält LOCK_DAYS, unter der KI OVERRIDE_DAYS
##   ki        die KI-Herrschaft (AiRule)
##   automat   Planungsautomat (Planner) und Droiden, die einen Siedler ablösen
##   verwalter Verwalter (Steward) und die Neuzuweisung nach einem Todesfall (Admin)
##   zentrum   KI-Zentrum (AiJobs); es verteilt nur, wenn auf der Insel kein Verwalter die Berufe steuert
## Die Halte-Zeiten liegen im Spielstand ("job_desk"); ältere Spielstände übernehmen die Sperren des Verwalters.

const RANK := {"zentrum": 1, "verwalter": 2, "automat": 3, "ki": 4, "spieler": 9}
const HOLD := {"zentrum": 0.5, "verwalter": 0.5, "automat": 1.0, "ki": 0.5, "spieler": 2.0}

var claims: Dictionary = {}  # Siedler-ID -> [bis Spieltag, Rang]


func _ready() -> void:
	Game.register_system(self)
	Game.state_reset.connect(_on_reset)
	Game.state_save.connect(_on_save)
	Game.state_load.connect(_on_load)


## Darf `by` den Beruf dieses Siedlers jetzt ändern?
func may(s, by: String) -> bool:
	if s == null or not is_instance_valid(s):
		return false
	if by == "spieler":
		return true
	var c = claims.get(int(s.id), null)
	if c == null or float(c[0]) <= Game.time_days:
		return true
	return int(RANK.get(by, 0)) > int(c[1])


## Hält jemand den Siedler gerade (egal wer)?
func held(s) -> bool:
	var c = claims.get(int(s.id), null)
	return c != null and float(c[0]) > Game.time_days


## Wer hält den Siedler gerade? "" = niemand.
func holder(s) -> String:
	if not held(s):
		return ""
	var r := int(claims[int(s.id)][1])
	for k in RANK:
		if int(RANK[k]) == r:
			return k
	return ""


## Gibt dem Siedler den Beruf, wenn `by` darf. days < 0: die übliche Halte-Zeit von `by`.
## force: Ereignisse der Geschichte (Superintelligenz) setzen sich über alles hinweg. Gibt true zurück, wenn
## der Beruf jetzt gilt.
func assign(s, job: String, by: String, days: float = -1.0, force := false) -> bool:
	if not force and not may(s, by):
		return false
	s.set_job(job, by != "spieler")
	hold(s, by, days)
	if by == "spieler":
		AiRule.player_changed("job:%d" % int(s.id))
	return true


## Hält den Siedler für `by` (ohne den Beruf zu ändern).
func hold(s, by: String, days: float = -1.0) -> void:
	if days < 0.0:
		days = float(HOLD.get(by, 0.5))
		if by == "spieler" and AiRule.ki():
			days = AiRule.OVERRIDE_DAYS
	claims[int(s.id)] = [Game.time_days + days, int(RANK.get(by, 0))]


func release(sid: int) -> void:
	claims.erase(sid)


## Darf auf dieser Insel das KI-Zentrum verteilen? Nein, solange dort der Verwalter die Berufe steuert.
func center_allowed(w) -> bool:
	return not (Steward.active() and Steward.blocked_on(w) == "")


func _prune() -> void:
	for k in claims.keys():
		if float(claims[k][0]) <= Game.time_days:
			claims.erase(k)


# ---------------------------------------------------------------- Spielstand
func _on_reset() -> void:
	claims = {}


func _on_save(d: Dictionary) -> void:
	_prune()
	d["job_desk"] = claims.duplicate(true)


func _on_load(data: Dictionary, _old_rules: int) -> void:
	_on_reset()
	var c = data.get("job_desk", null)
	if c is Dictionary:
		for k in c:
			var v = c[k]
			if v is Array and v.size() == 2:
				claims[int(k)] = [float(v[0]), int(v[1])]
		return
	# Ältere Spielstände: Sperren des Verwalters (Siedler-ID -> Spieltag) gelten als Sperren des Spielers
	var st = data.get("steward", {})
	var l = st.get("locks", {}) if st is Dictionary else {}
	if l is Dictionary:
		for k in l:
			claims[int(k)] = [float(l[k]), int(RANK.spieler)]
