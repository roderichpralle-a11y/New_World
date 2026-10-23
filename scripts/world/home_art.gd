class_name HomeArt
extends RefCounted
## First approved revision: native-resolution art for the home island only.

const SCALE := Vector2(0.25, 0.25)
const OBJECTS := {
	"tree0": preload("res://assets/home_v2/tree0.png"),
	"tree1": preload("res://assets/home_v2/tree1.png"),
	"tree2": preload("res://assets/home_v2/tree2.png"),
	"stump": preload("res://assets/home_v2/stump.png"),
	"sapling": preload("res://assets/home_v2/sapling.png"),
	"bush_full": preload("res://assets/home_v2/bush_full.png"),
	"bush_empty": preload("res://assets/home_v2/bush_empty.png"),
	"hut": preload("res://assets/home_v2/hut.png"),
	"hut_construction": preload("res://assets/home_v2/hut_construction.png"),
}
const JONAS := preload("res://assets/home_v2/jonas.png")
const LENA := preload("res://assets/home_v2/lena.png")
const MEADOW := preload("res://assets/home_v2/meadow.png")
const CHOP_PROPS := preload("res://assets/home_v2/chop_props.png")
const WALK_JONAS := preload("res://assets/walk_v4/jonas.png")
const WALK_LENA := preload("res://assets/walk_v4/lena.png")
const WALK_FRAMES := 4
static var _cache: Dictionary = {}


static func active(world) -> bool:
	return world != null and world.biome == "heimat"


static func object_tex(name: String) -> AtlasTexture:
	if not _cache.has(name):
		var at := AtlasTexture.new()
		at.atlas = OBJECTS[name]
		at.region = Rect2(Vector2.ZERO, at.atlas.get_size())
		_cache[name] = at
	return _cache[name]


static func apply(sprite: Sprite2D, name: String) -> void:
	var tex := object_tex(name)
	sprite.texture = tex
	sprite.scale = SCALE
	sprite.offset = Vector2(-tex.get_width() / 2.0, -tex.get_height() + 12.0)


static func portrait(look: Dictionary) -> Texture2D:
	match look.get("home_portrait", ""):
		"lena": return LENA
		"jonas": return JONAS
	return null


static func side_walk(look: Dictionary) -> Texture2D:
	return WALK_LENA if look.get("home_portrait", "") == "lena" else WALK_JONAS


static func chop_prop(frame: int) -> AtlasTexture:
	var key := "chop:%d" % frame
	if not _cache.has(key):
		var at := AtlasTexture.new()
		at.atlas = CHOP_PROPS
		at.region = Rect2(frame * 160, 0, 160, 128)
		_cache[key] = at
	return _cache[key]
