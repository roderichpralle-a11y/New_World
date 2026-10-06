class_name CouncilNet
extends RefCounted
## KI-Variante: trainiertes Netz des Inselrats (Reinforcement Learning, josh 2026-10-06).
##
## Ein kleines neuronales Netz (Eingänge -> 16 versteckte Knoten mit tanh -> Ausgänge). Es
## entscheidet nicht allein, sondern verschiebt die Regeln des Rats: Zu jeder Strategie kommt
## ein Wert auf die Lagebewertung (Society.situation_scores), und jeder Beruf bekommt einen
## Faktor exp(Wert) auf seinen Anteil an der Arbeit. Mit allen Ausgängen 0 handelt der Rat
## genau wie nach Regeln; das Training (tools/rl/train.py) lernt, wann es besser anders geht.
## Gerechnet wird in GDScript, also auch im Browser und auf dem Handy ohne Zusatzprogramme.

const STRATS := ["nahrung", "winter", "wachstum", "bauen", "wissen", "sicherheit", "seefahrt"]
const JOBS := ["sammler", "fischer", "bauer", "koch", "holzfaeller", "steinmetz", "baumeister", "handwerker", "forscher", "jaeger"]
const N_IN := 33
const N_HID := 16
const N_OUT := 17  # 7 Strategien + 10 Berufe

var w1: PackedFloat32Array  # N_HID x N_IN
var b1: PackedFloat32Array
var w2: PackedFloat32Array  # N_OUT x N_HID
var b2: PackedFloat32Array
var info: Dictionary = {}  # Herkunft: Generation, Punkte, Datum


static func param_count() -> int:
	return N_HID * N_IN + N_HID + N_OUT * N_HID + N_OUT


## Netz aus einer Liste aller Gewichte (Reihenfolge wie param_count).
static func from_params(p: Array, meta: Dictionary = {}) -> CouncilNet:
	if p.size() != param_count():
		return null
	var n := CouncilNet.new()
	var i := 0
	n.w1 = PackedFloat32Array(p.slice(i, i + N_HID * N_IN))
	i += N_HID * N_IN
	n.b1 = PackedFloat32Array(p.slice(i, i + N_HID))
	i += N_HID
	n.w2 = PackedFloat32Array(p.slice(i, i + N_OUT * N_HID))
	i += N_OUT * N_HID
	n.b2 = PackedFloat32Array(p.slice(i, i + N_OUT))
	n.info = meta
	return n


## Lädt {"params": [...], "info": {...}} aus einer JSON-Datei; null, wenn es nicht passt.
static func load_file(path: String) -> CouncilNet:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary) or not (d.get("params") is Array):
		return null
	return from_params(d.params, d.get("info", {}))


## Was das Netz von der Insel sieht, alles grob auf 0..1 gebracht.
static func features(w, sit: Dictionary, cap: Dictionary) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	var season := int(sit.season)
	for s in 4:
		x.append(1.0 if season == s else 0.0)
	x.append(float(Seasons.day_in_season() - 1) / maxf(1.0, float(Seasons.season_days())))
	var pop := float(sit.pop)
	x.append(minf(pop / 20.0, 2.0))
	x.append(float(sit.adults) / pop)
	x.append(float(sit.kids) / pop)
	x.append(minf(float(sit.housing) / pop, 3.0) / 3.0)
	x.append(clampf(Game.food_days(w) / 10.0, 0.0, 2.0))
	x.append(minf(float(sit.food_ratio), 2.0) / 2.0)
	x.append(minf(float(sit.wood) / maxf(1.0, float(sit.wood_target)), 2.0) / 2.0)
	x.append(minf(float(sit.stone) / maxf(1.0, float(sit.stone_target)), 2.0) / 2.0)
	x.append(clampf(float(sit.storage_full), 0.0, 1.0))
	x.append(minf(float(sit.sites) / 3.0, 1.0))
	x.append(minf(float(sit.predators) / 5.0, 1.0))
	x.append(float(sit.vit_low) / pop)
	var mood := 0.0
	var sick := 0
	for s in w.settlers:
		mood += s.mind.mood
		if s.mind.sick != "":
			sick += 1
	x.append(mood / maxf(1.0, w.settlers.size()) / 100.0)
	x.append(float(sick) / pop)
	x.append(minf(float(sit.farms) / pop, 2.0) / 2.0)
	x.append(1.0 if Game.research.current != "" else 0.0)
	x.append(minf(Game.research.done.size() / 30.0, 1.0))
	x.append(minf(Sea.settled_islands().size() / 3.0, 1.0))
	var adults := maxf(1.0, float(sit.adults))
	for j in JOBS:
		x.append(minf(float(cap.get(j, {}).get("n", 0)) / adults, 2.0) / 2.0)
	return x


## Ausgänge: [7 Werte für die Strategien, 10 Werte für die Berufe].
func forward(x: PackedFloat32Array) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(N_HID)
	for i in N_HID:
		var s := b1[i]
		var o := i * N_IN
		for k in N_IN:
			s += w1[o + k] * x[k]
		h[i] = tanh(s)
	var y := PackedFloat32Array()
	y.resize(N_OUT)
	for i in N_OUT:
		var s := b2[i]
		var o := i * N_HID
		for k in N_HID:
			s += w2[o + k] * h[k]
		y[i] = s
	return y
