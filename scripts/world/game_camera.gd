class_name GameCamera
extends Camera2D
## Kamera mit Ziehen (Maus/Finger), Mausrad- und Zwei-Finger-Zoom.
## Ein kurzer Klick/Tipp ohne Bewegung meldet `tapped`.

signal tapped(world_pos: Vector2)
signal hovered(world_pos: Vector2)

const ZOOM_MIN := 1.0
const ZOOM_MAX := 6.0
const TAP_SLOP := 10.0

var bounds := Rect2(0, 0, 1024, 1024)
var _dragging := false
var _press_pos := Vector2.ZERO
var _moved := false
var _touches: Dictionary = {}
var _pinch_dist := 0.0
var _multi := false


func _ready() -> void:
	zoom = Vector2(3, 3)
	position_smoothing_enabled = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			_multi = true
			_dragging = false
			_pinch_dist = _touch_dist()
		elif _touches.is_empty():
			_multi = false
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var d := _touch_dist()
			if _pinch_dist > 0.0 and d > 0.0:
				var mid := _touch_mid()
				_zoom_at(zoom.x * d / _pinch_dist, mid)
			_pinch_dist = d
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_dragging = true
				_moved = false
				_press_pos = mb.position
			else:
				if _dragging and not _moved and not _multi and mb.button_index == MOUSE_BUTTON_LEFT:
					tapped.emit(screen_to_world(mb.position))
				_dragging = false
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(zoom.x * 1.15, mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(zoom.x / 1.15, mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging and not _multi:
			if (mm.position - _press_pos).length() > TAP_SLOP:
				_moved = true
			if _moved:
				position -= mm.relative / zoom.x
				_clamp()
		elif not _dragging:
			hovered.emit(screen_to_world(mm.position))
	elif event is InputEventMagnifyGesture:
		_zoom_at(zoom.x * event.factor, event.position)
	elif event is InputEventPanGesture:
		position += event.delta * 8.0 / zoom.x
		_clamp()


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		# Echtzeit, unabhaengig von der Spielgeschwindigkeit
		var real: float = delta / max(Engine.time_scale, 0.001) if Engine.time_scale > 0 else 1.0 / 60.0
		position += v.normalized() * 260.0 * real / zoom.x
		_clamp()


func _touch_dist() -> float:
	var p := _touches.values()
	return (p[0] - p[1]).length() if p.size() >= 2 else 0.0


func _touch_mid() -> Vector2:
	var p := _touches.values()
	return (p[0] + p[1]) / 2.0


func screen_to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * screen_pos


func _zoom_at(z: float, screen_pos: Vector2) -> void:
	z = clamp(z, ZOOM_MIN, ZOOM_MAX)
	var before := screen_to_world(screen_pos)
	zoom = Vector2(z, z)
	force_update_scroll()
	var after := screen_to_world(screen_pos)
	position += before - after
	_clamp()


func _clamp() -> void:
	var view := get_viewport_rect().size / zoom.x
	var minp := bounds.position + view / 2.0
	var maxp := bounds.end - view / 2.0
	position.x = clamp(position.x, minp.x, max(minp.x, maxp.x)) if maxp.x > minp.x else bounds.get_center().x
	position.y = clamp(position.y, minp.y, max(minp.y, maxp.y)) if maxp.y > minp.y else bounds.get_center().y


func focus(p: Vector2) -> void:
	position = p
	_clamp()
