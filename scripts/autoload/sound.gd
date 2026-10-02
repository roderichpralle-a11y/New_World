extends Node
## Musik, Meeresrauschen und Soundeffekte. Alles in Echtzeit, unabhaengig von der
## Spielgeschwindigkeit. Lautstaerken liegen in `user://settings.cfg`.
##
## Effekte mit Ort (`play_at`) erklingen nur auf der sichtbaren Insel und nur, wenn
## der Ort im Bild ist; leiser, je weiter weg vom Bildmittelpunkt.

const SETTINGS_PATH := "user://settings.cfg"
const MUSIC := ["tag", "nacht", "insel"]
## Effekt -> Anzahl Varianten (Dateien name0, name1, ... oder nur name)
const SFX := {
	"klick": 1, "auf": 1, "zu": 1, "platzieren": 1, "hammer": 3, "axt": 2, "stein": 2,
	"pfluecken": 1, "platsch": 1, "saege": 1, "fertig": 1, "forschung": 1, "geburt": 1,
	"tod": 1, "morgen": 1, "heulen": 1, "knurren": 1, "grunzen": 1, "pfeil": 1,
	"treffer": 1, "autsch": 1, "glocke": 1, "entdeckt": 1, "verloren": 1, "warnung": 1,
	"fehler": 1, "stufe": 1, "essen": 1, "ziel": 1,
}
## Mindestabstand in Sekunden, bevor derselbe Effekt wieder erklingt
const GAP := {"hammer": 0.16, "axt": 0.2, "stein": 0.2, "pfluecken": 0.3, "platsch": 0.4,
	"saege": 0.8, "treffer": 0.12, "pfeil": 0.15, "klick": 0.04, "essen": 0.6, "heulen": 6.0,
	"knurren": 1.5, "grunzen": 1.5, "morgen": 20.0, "stufe": 15.0, "autsch": 0.3}
## Grundlautstaerke je Effekt in dB
const LEVEL := {"klick": -8.0, "hammer": -7.0, "axt": -6.0, "stein": -9.0, "pfluecken": -9.0,
	"platsch": -8.0, "saege": -12.0, "essen": -12.0, "morgen": -6.0, "heulen": -4.0,
	"pfeil": -6.0, "treffer": -5.0, "autsch": -6.0}
const VOICES := 12

var music_volume: float = 0.7
var sfx_volume: float = 0.8
var in_title: bool = true  # Titelbild: ruhige Musik

var _streams: Dictionary = {}  # Effekt -> Array[AudioStream]
var _music_streams: Dictionary = {}
var _voices: Array = []
var _last_play: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur: String = ""
var _music_pos: Dictionary = {}  # Stueck -> Stelle, an der es weitergeht
var _amb_a: AudioStreamPlayer
var _amb_b: AudioStreamPlayer
var _amb_cur: String = ""
var _check_t: float = 0.0
var _was_night: bool = false
var _music_bus: int = -1
var _sfx_bus: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_bus = _make_bus("Musik")
	_sfx_bus = _make_bus("Effekte")
	_load_settings()
	for name in SFX:
		var list := []
		var n: int = SFX[name]
		for i in n:
			var path := "res://assets/audio/sfx/%s.wav" % (name + (str(i) if n > 1 else ""))
			if ResourceLoader.exists(path):
				list.append(load(path))
		_streams[name] = list
	for m in MUSIC:
		var s = load("res://assets/audio/music/%s.ogg" % m)
		if s:
			s.loop = true
			_music_streams[m] = s
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Effekte"
		add_child(p)
		_voices.append(p)
	_music_a = _player("Musik")
	_music_b = _player("Musik")
	_amb_a = _player("Effekte")
	_amb_b = _player("Effekte")
	# Jeder Knopf klickt
	get_tree().node_added.connect(_on_node_added)


func _make_bus(name: String) -> int:
	var idx := AudioServer.get_bus_index(name)
	if idx >= 0:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	return p


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent"):
		n.pressed.connect(_on_button.bind(n))


func _on_button(b: BaseButton) -> void:
	if is_instance_valid(b):
		play("klick")


# ---------------------------------------------------------------- Einstellungen
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		music_volume = float(cf.get_value("audio", "music", music_volume))
		sfx_volume = float(cf.get_value("audio", "sfx", sfx_volume))
	_apply_volumes()


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	cf.save(SETTINGS_PATH)


func set_volumes(music: float, sfx: float) -> void:
	music_volume = clamp(music, 0.0, 1.0)
	sfx_volume = clamp(sfx, 0.0, 1.0)
	_apply_volumes()
	save_settings()


func _apply_volumes() -> void:
	_set_bus(_music_bus, music_volume)
	_set_bus(_sfx_bus, sfx_volume)


func _set_bus(idx: int, v: float) -> void:
	if idx < 0:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(max(v, 0.001)))


# ---------------------------------------------------------------- Effekte
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Spielt einen Effekt ohne Ort (Oberflaeche, Meldungen).
func play(name: String, db: float = 0.0, pitch_var: float = 0.0) -> void:
	if sfx_volume <= 0.001 or not _streams.has(name) or _streams[name].is_empty():
		return
	var now := _now()
	if now - float(_last_play.get(name, -99.0)) < float(GAP.get(name, 0.06)):
		return
	_last_play[name] = now
	var p: AudioStreamPlayer = null
	for v in _voices:
		if not v.playing:
			p = v
			break
	if p == null:
		return
	var list: Array = _streams[name]
	p.stream = list[randi() % list.size()]
	p.volume_db = float(LEVEL.get(name, 0.0)) + db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var) if pitch_var > 0.0 else 1.0
	p.play()


## Spielt einen Effekt an einem Ort auf einer Insel: nur sichtbar und in Hoerweite.
func play_at(name: String, w, pos: Vector2, pitch_var: float = 0.06) -> void:
	if w == null or w != Game.world or not is_instance_valid(w):
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var view := get_viewport().get_visible_rect().size / cam.zoom
	var d := (pos - cam.get_screen_center_position()) / (view * 0.5)
	var dist := d.length()
	if dist > 1.25:
		return
	# Leiser am Rand und weit herausgezoomt
	var db: float = -9.0 * clampf(dist - 0.3, 0.0, 1.0) - 5.0 * clampf((3.0 - cam.zoom.x) / 2.0, 0.0, 1.0)
	play(name, db, pitch_var)


## Spielt einen Effekt, wenn die Insel gerade sichtbar ist (egal wo auf der Insel).
func play_on(name: String, w, db: float = 0.0) -> void:
	if w == null or w == Game.world:
		play(name, db)


# ---------------------------------------------------------------- Musik
func _process(_delta: float) -> void:
	var now := _now()
	if now - _check_t < 1.0:
		return
	_check_t = now
	var night := Game.is_night()
	if _was_night and not night and not in_title and Game.speed > 0:
		play("morgen")
	_was_night = night
	# Nachts heult ab und zu ein Wolf auf der sichtbaren Insel
	if night and not in_title and Game.speed > 0 and Game.world and is_instance_valid(Game.world) and randf() < 0.05:
		for a in Game.world.animals:
			if a.type == "wolf":
				play("heulen", -8.0, 0.08)
				break
	var want := "tag"
	var amb := "meer_tag"
	if not in_title and Game.world != null and is_instance_valid(Game.world):
		if Game.is_night():
			want = "nacht"
			amb = "meer_nacht"
		elif Sea.meta(Game.world.island_id).get("biome", "heimat") != "heimat":
			want = "insel"
	if Game.is_over:
		want = "nacht"
	if want != _music_cur:
		_switch_music(want)
	if amb != _amb_cur:
		_switch_ambient(amb)


func _switch_music(m: String) -> void:
	if not _music_streams.has(m):
		return
	# Altes Stueck ausblenden und Stelle merken
	var old := _music_a
	if _music_cur != "" and old.playing:
		_music_pos[_music_cur] = old.get_playback_position()
		_fade(old, -50.0, 3.0, true)
	_music_a = _music_b
	_music_b = old
	_music_cur = m
	_music_a.stream = _music_streams[m]
	_music_a.volume_db = -40.0
	_music_a.play(float(_music_pos.get(m, 0.0)))
	_fade(_music_a, -6.0, 3.0, false)


func _switch_ambient(a: String) -> void:
	var s = load("res://assets/audio/ambient/%s.ogg" % a)
	if s == null:
		return
	s.loop = true
	var old := _amb_a
	if old.playing:
		_fade(old, -50.0, 4.0, true)
	_amb_a = _amb_b
	_amb_b = old
	_amb_cur = a
	_amb_a.stream = s
	_amb_a.volume_db = -40.0
	_amb_a.play(randf() * 10.0)
	_fade(_amb_a, -17.0, 4.0, false)


func _fade(p: AudioStreamPlayer, to_db: float, secs: float, stop_after: bool) -> void:
	var old = p.get_meta("tween") if p.has_meta("tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	var tw := create_tween()
	p.set_meta("tween", tw)
	tw.set_ignore_time_scale(true)
	tw.tween_property(p, "volume_db", to_db, secs)
	if stop_after:
		tw.tween_callback(p.stop)
