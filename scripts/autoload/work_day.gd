class_name WorkDay
extends RefCounted
## Arbeitstag ab Wohlstand (josh 2026-10-31): Um 6 Uhr sind alle am Arbeitsplatz, dann 4 Stunden Arbeit,
## 1 Stunde Pause in der Nähe, 4 Stunden Arbeit, danach Feierabend (Freizeit). Jeder ist 18 Stunden wach:
## Wer weit zur Arbeit hat, steht früher auf und geht früher ins Bett. Der Weg zur Arbeit ist keine
## Arbeitszeit, das Bringen ins Lager schon. Kinder, Überstunden und Schichten folgen den alten Regeln.
##
## Zahlen in data/people.json "workday": start, block, pause, awake (Stunden).

const PHASES := ["sleep", "commute", "work", "pause", "free"]
static var off := false  # Testhilfe --workday=0: alter Tagesablauf zum Vergleich
static var log_on := false  # Testhilfe --daylog=1: Ankunftszeiten je Siedler (main.gd druckt sie je Tag)
static var arr := {}


static func log_arrival(s, ph: String) -> void:
	var h := Game.time_of_day() * 24.0
	var key := ""
	if ph == "commute" and not s.sleeping:
		key = "auf"
	elif ph == "work" and s._working and h < 10.0:
		key = "morgens"
	elif ph == "work" and s._working and h >= 10.0 and h < 15.0:
		key = "mittags"
	elif ph == "sleep" and s.sleeping and h > 12.0:
		key = "Bett"
	if key != "" and not arr.has(str(s.id) + key):
		arr[str(s.id) + key] = h


static func _cfg(key: String, def: float) -> float:
	return float(Data.ppl("workday", {}).get(key, def))


## Gilt der feste Arbeitstag für diesen Siedler? Ab Lebensstil Wohlstand, nur Erwachsene, ohne Anordnung.
static func active(s) -> bool:
	if off or not s.is_adult() or s.world == null:
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
	return _cfg("start", 6.0) - travel_hours(s) - _cfg("get_up", 0.25) - _cfg("spare", 0.25)


## Spielstunden für einen Weg von a nach b (Umwege etwa 30 %). Gilt, solange die Nacht nicht schneller
## läuft, und das tut sie nicht, solange jemand mit festem Arbeitstag wach ist (Admin.night_work_now).
static func walk_hours(a: Vector2i, b: Vector2i) -> float:
	var per_hour := float(Data.bal("walk_speed")) / 16.0 * float(Data.bal("day_length")) / 24.0
	return Vector2(b - a).length() * 1.3 / maxf(1.0, per_hour)


## Weg von hier zurück zum nächsten Arbeitsplatz des Berufs (alle Viertelstunde neu gerechnet).
static func back_hours(s) -> float:
	var m = s.get_meta("wd_back", [])
	if m is Array and m.size() == 2 and absf(float(m[0]) - Game.time_days) < 0.25 / 24.0:
		return float(m[1])
	var h := 0.0
	var spots: Array = Steward._job_spots(s.world, s.job)
	if not spots.is_empty():
		h = INF
		for c in spots:
			h = minf(h, walk_hours(s.cell, c))
	h = minf(h, 3.0)
	s.set_meta("wd_back", [Game.time_days, h])
	return h


## Weg von hier nach Hause (ohne Haus: zum nächsten Lager, dort schläft er).
static func home_hours(s) -> float:
	var m = s.get_meta("wd_home", [])
	if m is Array and m.size() == 2 and absf(float(m[0]) - Game.time_days) < 0.25 / 24.0:
		return float(m[1])
	var to: Vector2i = s.cell
	var home = s.world.building_by_id(s.home_id)
	if home != null and home.complete:
		to = home.entrance_cell()
	else:
		var st = s.world.nearest_storage(s.cell)
		if st != null:
			to = st.entrance_cell()
	var h := minf(walk_hours(s.cell, to), 3.0)
	s.set_meta("wd_home", [Game.time_days, h])
	return h


static func bed_hour(s) -> float:
	return fposmod(wake_hour(s) + _cfg("awake", 18.0), 24.0)


## Abschnitt des Tages für diesen Siedler. Die Wege sind eingeplant (josh 2026-10-31):
## - morgens steht er so früh auf, dass er um 6 Uhr am Arbeitsplatz ist ("commute"),
## - aus der Pause bricht er so früh auf, dass er um 11 Uhr wieder dort ist,
## - abends geht er so früh heim, dass er zur Schlafenszeit im Bett liegt.
## Ist er einmal aufgebrochen, bleibt es dabei (sonst würde der kürzere Rest den Aufbruch wieder aufheben).
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
	var day := Game.day()
	if hour < start + block + pause:
		if int(s.get_meta("wd_back_day", -1)) == day:
			return "work"
		if hour >= start + block + pause - back_hours(s) - _cfg("spare", 0.25):
			s.set_meta("wd_back_day", day)
			return "work"
		return "pause"
	if hour < start + 2.0 * block + pause:
		return "work"
	if bed > hour:
		if int(s.get_meta("wd_home_day", -1)) == day:
			return "sleep"
		if hour >= bed - home_hours(s) - 0.1:
			s.set_meta("wd_home_day", day)
			return "sleep"
	return "free"


## Stunden bis zum Ende der laufenden Pause (für die Mittagspause in der Nähe).
static func pause_left(s) -> float:
	var hour := Game.time_of_day() * 24.0
	return maxf(0.0, _cfg("start", 6.0) + _cfg("block", 4.0) + _cfg("pause", 1.0) - hour)
