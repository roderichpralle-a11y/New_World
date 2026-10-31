class_name WorkDay
extends RefCounted
## Arbeitstag ab Wohlstand (josh 2026-10-31): Um 6 Uhr sind alle am Arbeitsplatz, dann 4 Stunden Arbeit,
## 1 Stunde Pause in der Nähe, 4 Stunden Arbeit, danach Feierabend (Freizeit). Jeder ist 18 Stunden wach:
## Wer weit zur Arbeit hat, steht früher auf und geht früher ins Bett. Der Weg zur Arbeit ist keine
## Arbeitszeit, das Bringen ins Lager schon. Kinder, Überstunden und Schichten folgen den alten Regeln.
##
## Zahlen in data/people.json "workday": start, block, pause, awake (Stunden).

const PHASES := ["sleep", "commute", "work", "pause", "free"]


static func _cfg(key: String, def: float) -> float:
	return float(Data.ppl("workday", {}).get(key, def))


## Gilt der feste Arbeitstag für diesen Siedler? Ab Lebensstil Wohlstand, nur Erwachsene, ohne Anordnung.
static func active(s) -> bool:
	if not s.is_adult() or s.world == null:
		return false
	if SettlerMind.comfort() < _cfg("from_comfort", 0.75):
		return false
	return not Admin.shift(s.job, s.world) and not Admin.overtime(s.job, s.world)


## Weg von der Wohnung zum nächsten Arbeitsplatz des Berufs in Spielstunden (einmal am Tag gerechnet).
static func travel_hours(s) -> float:
	var day := Game.day()
	var m = s.get_meta("wd_travel", [])
	if m is Array and m.size() == 3 and int(m[0]) == day and str(m[2]) == str(s.job):
		return float(m[1])
	var from: Vector2i = s.cell
	var home = s.world.building_by_id(s.home_id)
	if home != null:
		from = home.entrance_cell()
	var best := 0.0
	var spots: Array = Steward._job_spots(s.world, s.job)
	if not spots.is_empty():
		best = INF
		for c in spots:
			best = minf(best, Vector2(c - from).length())
	# Schritte (Umwege etwa 30 %) durch Felder je Spielstunde
	var per_hour := float(Data.bal("walk_speed")) / 16.0 * float(Data.bal("day_length")) / 24.0
	var h := clampf(best * 1.3 / maxf(1.0, per_hour), 0.0, 3.0)
	s.set_meta("wd_travel", [day, h, s.job])
	return h


## Aufstehzeit in Stunden (0..24): rechtzeitig, um um 6 Uhr am Arbeitsplatz zu sein.
static func wake_hour(s) -> float:
	return _cfg("start", 6.0) - travel_hours(s) - _cfg("get_up", 0.25)


static func phase(s, hour: float = -1.0) -> String:
	if hour < 0.0:
		hour = Game.time_of_day() * 24.0
	var start := _cfg("start", 6.0)
	var block := _cfg("block", 4.0)
	var pause := _cfg("pause", 1.0)
	var wake := wake_hour(s)
	var bed := fposmod(wake + _cfg("awake", 18.0), 24.0)
	var asleep := (hour >= bed or hour < wake) if bed > wake else (hour >= bed and hour < wake)
	if asleep:
		return "sleep"
	if hour < start:
		return "commute"
	if hour < start + block:
		return "work"
	if hour < start + block + pause:
		return "pause"
	if hour < start + 2.0 * block + pause:
		return "work"
	return "free"


## Stunden bis zum Ende der laufenden Pause (für die Mittagspause in der Nähe).
static func pause_left(s) -> float:
	var hour := Game.time_of_day() * 24.0
	return maxf(0.0, _cfg("start", 6.0) + _cfg("block", 4.0) + _cfg("pause", 1.0) - hour)
