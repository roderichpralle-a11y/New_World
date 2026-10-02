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

var tex_terrain: Texture2D = preload("res://assets/sprites/terrain.png")
var tex_objects: Texture2D = preload("res://assets/sprites/objects.png")
var tex_icons: Texture2D = preload("res://assets/sprites/icons.png")
var tex_tools: Texture2D = preload("res://assets/sprites/tools.png")
var tex_ui: Texture2D = preload("res://assets/sprites/ui.png")
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
}
const TOOL_INDEX := {"axe": 0, "pick": 1, "basket": 2, "rod": 3, "hammer": 4, "sickle": 5}

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
	var r: Array = OBJECT_REGIONS.get(name, [0, 0, 16, 16, 1])
	var at := AtlasTexture.new()
	at.atlas = tex_objects
	at.region = Rect2(r[0] + r[2] * frame, r[1], r[2], r[3])
	_cache[key] = at
	return at


func object_frames(name: String) -> int:
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
