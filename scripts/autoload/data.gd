extends Node
## Laedt alle Spieldaten aus res://data/*.json und stellt Sprite-Regionen bereit.
## Spaetere Etappen ergaenzen einfach weitere JSON-Eintraege.

var resources: Dictionary = {}
var nodes: Dictionary = {}
var buildings: Dictionary = {}
var jobs: Dictionary = {}
var skills: Dictionary = {}
var balance: Dictionary = {}
var names: Dictionary = {}
var techs: Dictionary = {}
var tiers: Array = []
var islands: Dictionary = {}  # Inselarten (Biome)
var animals: Dictionary = {}
var goals: Dictionary = {}  # Einfuehrung und Ziele

var tex_terrain: Texture2D = preload("res://assets/sprites/terrain.png")
var tex_objects: Texture2D = preload("res://assets/sprites/objects.png")
var tex_buildings: Texture2D = preload("res://assets/sprites/buildings.png")
var tex_icons: Texture2D = preload("res://assets/sprites/icons.png")
var tex_tools: Texture2D = preload("res://assets/sprites/tools.png")
var tex_ui: Texture2D = preload("res://assets/sprites/ui.png")
var tex_objects2: Texture2D = preload("res://assets/sprites/objects2.png")
var tex_animals: Texture2D = preload("res://assets/sprites/animals.png")
var font_regular: Font = preload("res://assets/fonts/pixelify-sans-latin-400-normal.woff2")
var font_bold: Font = preload("res://assets/fonts/pixelify-sans-latin-700-normal.woff2")

## Regionen in objects.png: name -> [x, y, w, h, frames]
const OBJECT_REGIONS := {
	"tree0": [0, 0, 32, 48, 1], "tree1": [32, 0, 32, 48, 1], "tree2": [64, 0, 32, 48, 1],
	"stump": [96, 0, 32, 48, 1], "sapling": [128, 0, 32, 48, 1],
	"hut": [0, 48, 48, 48, 1], "storehouse": [48, 48, 48, 48, 1], "construction": [96, 48, 48, 48, 1],
	"rock_big": [0, 96, 16, 16, 1], "rock_small": [16, 96, 16, 16, 1],
	"bush_full": [32, 96, 16, 16, 1], "bush_empty": [48, 96, 16, 16, 1],
	"grave": [64, 96, 16, 16, 1], "shadow": [80, 96, 16, 8, 1], "shadow_big": [96, 96, 32, 8, 1],
	"campfire": [0, 112, 16, 16, 4], "fish_anim": [64, 112, 16, 16, 4],
	"field0": [0, 128, 16, 16, 1], "field1": [16, 128, 16, 16, 1],
	"field2": [32, 128, 16, 16, 1], "field3": [48, 128, 16, 16, 1],
	"orchard0": [64, 128, 16, 16, 1], "orchard1": [80, 128, 16, 16, 1],
	"orchard2": [96, 128, 16, 16, 1], "orchard3": [112, 128, 16, 16, 1],
}
## Gebaeude aus Etappe 2 in buildings.png: Zellen 64x64, 8 je Zeile.
## Name -> [Zellindex, Frames]. Das Gebaeude steht unten mittig (Boden 4 px ueber Zellrand).
const BUILDING_CELLS := {
	"house_wood": [0, 1], "house_stone": [1, 1], "store_big": [2, 1], "mill": [3, 4],
	"bakery": [7, 1], "smokehouse": [8, 1], "henhouse": [9, 1], "sawpit": [10, 1],
	"claypit": [11, 1], "brickworks": [12, 1], "quarry": [13, 1], "charcoal": [14, 1],
	"mine": [15, 1], "smelter": [16, 1], "smithy": [17, 1], "scriptorium": [18, 1],
	"library": [19, 1], "shipyard": [20, 1], "tower": [21, 1], "lighthouse": [22, 2], "monument": [24, 1],
	"school": [25, 1],
}
## Etappe 3 in objects2.png: name -> [x, y, w, h, frames]
const OBJECT2_REGIONS := {
	"palm0": [0, 0, 32, 48, 1], "palm1": [32, 0, 32, 48, 1], "palm_empty": [64, 0, 32, 48, 1],
	"cave": [96, 0, 32, 48, 1],
	"mushrooms": [0, 48, 16, 16, 1], "ore_rock": [16, 48, 16, 16, 1], "gold_rock": [32, 48, 16, 16, 1],
	"den": [48, 48, 16, 16, 1], "wallow": [64, 48, 16, 16, 1], "carcass": [80, 48, 16, 16, 1],
	"arrow": [96, 48, 16, 16, 1],
	"boat": [0, 64, 32, 32, 2],
}
## Tiere in animals.png: Zellen 24x24, je Tier eine Zeile (Zeile aus animals.json),
## Spalten 0-3 Laufen, 4 Angriff.
const ANIMAL_CELL := 24
const TOOL_INDEX := {"axe": 0, "pick": 1, "basket": 2, "rod": 3, "hammer": 4, "sickle": 5,
	"spoon": 6, "book": 7, "shovel": 8, "spear": 9}

var _icon_index: Dictionary = {}
var _cache: Dictionary = {}


func _ready() -> void:
	resources = _load("resources")
	nodes = _load("nodes")
	buildings = _load("buildings")
	jobs = _load("jobs")
	skills = _load("skills")
	balance = _load("balance")
	names = _load("names")
	techs = _load("techs")
	tiers = techs.get("_tiers", [])
	techs.erase("_tiers")
	islands = _load("islands")
	goals = _load("goals")
	animals = _load("animals")
	var f := FileAccess.open("res://assets/sprites/icons.txt", FileAccess.READ)
	if f:
		var i := 0
		for line in f.get_as_text().split("\n"):
			if line.strip_edges() != "":
				_icon_index[line.strip_edges()] = i
				i += 1


func _load(name: String) -> Dictionary:
	var path := "res://data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Daten fehlen: " + path)
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func bal(key: String, default = 0.0):
	return balance.get(key, default)


## AtlasTexture fuer ein Objekt (Frame f bei animierten Regionen).
func object_tex(name: String, frame: int = 0) -> AtlasTexture:
	var key := "o:%s:%d" % [name, frame]
	if _cache.has(key):
		return _cache[key]
	var at := AtlasTexture.new()
	if BUILDING_CELLS.has(name):
		var i: int = BUILDING_CELLS[name][0] + frame
		at.atlas = tex_buildings
		at.region = Rect2((i % 8) * 64, (i / 8) * 64, 64, 64)
	elif OBJECT2_REGIONS.has(name):
		var r2: Array = OBJECT2_REGIONS[name]
		at.atlas = tex_objects2
		at.region = Rect2(r2[0] + r2[2] * frame, r2[1], r2[2], r2[3])
	else:
		var r: Array = OBJECT_REGIONS.get(name, [0, 0, 16, 16, 1])
		at.atlas = tex_objects
		at.region = Rect2(r[0] + r[2] * frame, r[1], r[2], r[3])
	_cache[key] = at
	return at


func object_frames(name: String) -> int:
	if BUILDING_CELLS.has(name):
		return BUILDING_CELLS[name][1]
	if OBJECT2_REGIONS.has(name):
		return OBJECT2_REGIONS[name][4]
	return OBJECT_REGIONS.get(name, [0, 0, 0, 0, 1])[4]


func icon(name: String) -> AtlasTexture:
	var key := "i:" + name
	if _cache.has(key):
		return _cache[key]
	var at := AtlasTexture.new()
	at.atlas = tex_icons
	at.region = Rect2(16 * int(_icon_index.get(name, 0)), 0, 16, 16)
	_cache[key] = at
	return at


func tool_tex(name: String) -> AtlasTexture:
	var key := "t:" + name
	if _cache.has(key):
		return _cache[key]
	var at := AtlasTexture.new()
	at.atlas = tex_tools
	at.region = Rect2(16 * int(TOOL_INDEX.get(name, 0)), 0, 16, 16)
	_cache[key] = at
	return at


func resource_name(id: String) -> String:
	return resources.get(id, {}).get("name", id)


func food_ids() -> Array:
	var out := []
	for id in resources:
		if resources[id].get("category", "") == "food":
			out.append(id)
	out.sort_custom(func(a, b): return resources[a].get("nutrition", 0) > resources[b].get("nutrition", 0))
	return out


func sorted_resource_ids() -> Array:
	var ids := resources.keys()
	ids.sort_custom(func(a, b): return resources[a].get("order", 0) < resources[b].get("order", 0))
	return ids


func res_icon(id: String) -> AtlasTexture:
	return icon(resources.get(id, {}).get("icon", id))


## Bild fuer ein Gebaeude im Menue (Felder zeigen eine reife Kachel).
func building_tex(type: String) -> AtlasTexture:
	var def: Dictionary = buildings.get(type, {})
	if def.has("farm"):
		return object_tex("%s3" % def.farm.get("tiles", "field"))
	return object_tex(def.get("sprite", "hut"))


## Gebaeude, die eine Forschung freischaltet.
func tech_unlocks(tech: String) -> Array:
	var out := []
	for b in buildings:
		if buildings[b].get("requires", "") == tech:
			out.append(b)
	return out


## Bild fuer eine Forschung: eigenes Icon oder das erste freigeschaltete Gebaeude.
func tech_tex(tech: String) -> Texture2D:
	var def: Dictionary = techs.get(tech, {})
	if def.has("icon"):
		return icon(def.icon)
	var u := tech_unlocks(tech)
	if not u.is_empty():
		return building_tex(u[0])
	return icon("wissen")


func sorted_tech_ids() -> Array:
	var ids := techs.keys()
	ids.sort_custom(func(a, b):
		if int(techs[a].tier) != int(techs[b].tier):
			return int(techs[a].tier) < int(techs[b].tier)
		return int(techs[a].points) < int(techs[b].points))
	return ids


func animal_tex(type: String, frame: int) -> AtlasTexture:
	var key := "a:%s:%d" % [type, frame]
	if _cache.has(key):
		return _cache[key]
	var at := AtlasTexture.new()
	at.atlas = tex_animals
	var row := int(animals.get(type, {}).get("row", 0))
	at.region = Rect2(frame * ANIMAL_CELL, row * ANIMAL_CELL, ANIMAL_CELL, ANIMAL_CELL)
	_cache[key] = at
	return at


## Beruf ist freigeschaltet (manche brauchen eine Forschung).
func job_unlocked(job: String) -> bool:
	return Game.is_researched(jobs.get(job, {}).get("requires", ""))
