class_name ResNode
extends Node2D
## Rohstoffquelle auf der Karte (Baum, Fels, Strauch, Fischgrund).
## Verhalten kommt komplett aus data/nodes.json.

var type: String
var def: Dictionary
var cell: Vector2i
var amount: int = 0
var regrow_at: float = -1.0  # Spielzeit (Tage), wann wieder voll
var variant: int = 0
var reserved_by: int = 0
var world

var _sprite: Sprite2D
var _shadow: Sprite2D
var _anim_t: float = 0.0
var _shake: float = 0.0


func setup(p_world, p_type: String, p_cell: Vector2i, p_variant: int = -1) -> void:
	world = p_world
	type = p_type
	def = Data.nodes[type]
	cell = p_cell
	amount = int(def.capacity)
	var fulls: Array = def.sprites.get("full", [])
	variant = p_variant if p_variant >= 0 else (hash(cell) & 0x7fffffff) % max(1, fulls.size())
	position = world.cell_to_pos(cell)
	_shadow = Sprite2D.new()
	_shadow.centered = true
	_sprite = Sprite2D.new()
	_sprite.centered = false
	add_child(_shadow)
	add_child(_sprite)
	refresh()


func is_available() -> bool:
	return amount > 0


func is_solid() -> bool:
	if not def.get("solid", true):
		return false
	# Baumstumpf/Setzling bleibt ein Hindernis, damit nichts darauf gebaut wird
	return true


func sprite_name() -> String:
	var s: Dictionary = def.sprites
	if amount <= 0:
		if regrow_at >= 0.0 and s.has("growing") and Game.time_days > regrow_at - float(def.regrow_days) * 0.5:
			return s.growing
		return s.get("empty", "")
	if s.has("low") and amount <= int(def.capacity) / 3:
		return s.low
	var fulls: Array = s.full
	return fulls[variant % fulls.size()]


func refresh() -> void:
	var name := sprite_name()
	_sprite.visible = name != ""
	if name == "":
		_shadow.visible = false
		return
	var tex := Data.object_tex(name, 0)
	_sprite.texture = tex
	var sz := tex.region.size
	_sprite.offset = Vector2(-sz.x / 2.0, -sz.y + (8 if sz.y <= 16 else 3))
	if sz.y <= 16:
		_sprite.offset.y = -sz.y + 6
	if type == "fischgrund":
		_sprite.offset = Vector2(-8, -8)
	_shadow.visible = type != "fischgrund"
	_shadow.texture = Data.object_tex("shadow_big" if sz.x >= 32 else "shadow")
	_shadow.position = Vector2(0, 2 if sz.y > 16 else 4)
	_shadow.scale = Vector2(0.8, 1.0) if name in ["stump", "sapling"] else Vector2.ONE


## Ein Arbeitsschritt; liefert geernteten Rohstoff (0 oder 1).
func harvest_one() -> int:
	if amount <= 0:
		return 0
	amount -= 1
	_shake = 0.25
	if amount <= 0:
		match def.get("on_empty", "regrow"):
			"remove":
				world.remove_node(self)
				return 1
			_:
				regrow_at = Game.time_days + float(def.regrow_days)
				if type == "baum":
					world.spawn_effect("leaves", position + Vector2(0, -16))
	refresh()
	return 1


func _process(delta: float) -> void:
	# Erlegte Tiere verderben nach ein paar Tagen
	if def.has("decay_days") and regrow_at >= 0.0 and Game.time_days >= regrow_at:
		world.remove_node(self)
		return
	if amount <= 0 and regrow_at >= 0.0:
		if Game.time_days >= regrow_at:
			amount = int(def.capacity)
			regrow_at = -1.0
			refresh()
		elif def.sprites.has("growing") and _sprite.texture != Data.object_tex(sprite_name()):
			refresh()
	if type == "fischgrund" and amount > 0:
		_anim_t += delta
		_sprite.texture = Data.object_tex("fish_anim", int(_anim_t * 3.0) % 4)
	if _shake > 0.0:
		_shake -= delta
		_sprite.position.x = sin(_shake * 60.0) * 1.0 if _shake > 0 else 0.0


func serialize() -> Array:
	return [type, cell.x, cell.y, amount, snappedf(regrow_at, 0.001), variant]
