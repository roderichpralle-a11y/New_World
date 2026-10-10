class_name TalentInfo
extends RefCounted
## Anzeige der Talente (Begabungen ab talent_show): Stern-Symbol, Textzeilen mit Bonus
## fuer Infofenster, Siedlerliste und Berufswahl. Zahlen aus SettlerMind.talent_work/_learn.

static var _star: Texture2D


## Kleiner Pixel-Stern (16x16), im Code gezeichnet, weil die Schrift kein ★ hat.
static func star() -> Texture2D:
	if _star:
		return _star
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var pts := PackedVector2Array()
	for i in 10:
		var r := 7.4 if i % 2 == 0 else 3.1
		var a := -PI / 2.0 + i * PI / 5.0
		pts.append(Vector2(8.0, 8.6) + Vector2(cos(a), sin(a)) * r)
	var inside := {}
	for y in 16:
		for x in 16:
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				inside[Vector2i(x, y)] = true
	for y in 16:
		for x in 16:
			var c := Vector2i(x, y)
			if inside.has(c):
				img.set_pixel(x, y, Color("#f2c230") if y < 9 else Color("#e0a020"))
			elif inside.has(c + Vector2i(1, 0)) or inside.has(c + Vector2i(-1, 0)) or inside.has(c + Vector2i(0, 1)) or inside.has(c + Vector2i(0, -1)):
				img.set_pixel(x, y, Color("#6a4a30"))
	_star = ImageTexture.create_from_image(img)
	return _star


## Arbeitstempo-Bonus in Prozent (gerundet), z. B. 40.
static func work_pct(m: SettlerMind, sk: String) -> int:
	return int(round((m.talent_work(sk) - 1.0) * 100.0))


## Lern-Bonus in Prozent gegenueber normal (gerundet), z. B. 160.
static func learn_pct(m: SettlerMind, sk: String) -> int:
	return int(round((m.talent_learn(sk) - 1.0) * 100.0))


## "Talent: Bauen (+40 % schneller, lernt +160 % schneller)"
static func line(m: SettlerMind, sk: String) -> String:
	return Loc.t("Talent: %s (+%d %% schneller, lernt +%d %% schneller)") % [
		Data.skills[sk].name, work_pct(m, sk), learn_pct(m, sk)]


## "Bauen +40 %"
static func short(m: SettlerMind, sk: String) -> String:
	return "%s +%d %%" % [Data.skills[sk].name, work_pct(m, sk)]


## Kurzliste aller Talente, z. B. "Holz +25 %, Handwerk +20 %" (leer ohne Talent).
static func short_list(m: SettlerMind) -> String:
	return ", ".join(m.best_talents().map(func(k): return short(m, k)))


## Text der Spalte "Talent" in der Siedlerliste: jedes Talent in einer eigenen Zeile, höchstens
## zwei Zeilen (gleich hohe Zeilen); gibt es mehr, endet die zweite mit "…" (alle im Tooltip).
static func column_text(m: SettlerMind) -> String:
	var parts: Array = m.best_talents().map(func(k): return short(m, k))
	if parts.size() > 2:
		parts = [parts[0], parts[1] + " …"]
	return "\n".join(parts)


## Passt der Beruf zu einem Talent des Siedlers?
static func job_match(m: SettlerMind, job: String) -> bool:
	var sk: String = Data.jobs.get(job, {}).get("skill", "")
	return sk != "" and m.is_talent(sk)
