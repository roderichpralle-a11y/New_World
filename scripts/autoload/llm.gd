extends Node
## KI-Variante: Sprachmodelle. Der Inselrat fragt Llama-3.2-1B, jeder Siedler SmolLM-135M.
##
## Im Browser laufen beide Modelle in einem Web Worker (web/ki_llm.js, transformers.js).
## Das Spiel läuft weiter, während gerechnet wird: `choose` und `generate` geben sofort
## einen `Job` zurück, dessen Signal `done` später mit dem Ergebnis kommt (`await job.done`).
## - choose: Das Modell bekommt nummerierte Möglichkeiten und wir lesen ab, wie
##   wahrscheinlich es jede Nummer als Antwort schreiben würde (`probs`).
## - generate: freier Text (Begründungen, Antworten im Chat, Lehren).
## Ohne Browser (Tests mit --llmmock=1) antwortet eine Attrappe nach kurzer Zeit.
## Ob die Modelle geladen werden, entscheidet der Spieler je Gerät (user://ki_llm.cfg).

signal status_changed

const CFG_PATH := "user://ki_llm.cfg"


class Job:
	extends RefCounted
	signal done(result: Dictionary)
	var id: int = 0
	var data: Dictionary = {}
	var due: float = 0.0  # nur Attrappe
	var finished := false
	var result: Dictionary = {}

	## Ergebnis abwarten, auch wenn der Auftrag schon fertig ist
	func wait() -> Dictionary:
		if not finished:
			await done
		return result


var backend := ""  # "web", "mock" oder "" (aus)
var state := "aus"  # aus, laden, bereit, fehler
var device := ""  # webgpu-f16, webgpu, wasm, attrappe
var error := ""
var note := ""
var loaded: Dictionary = {}  # rat/siedler -> {id, dtype, device}
var progress: Dictionary = {}  # rat/siedler -> [geladen, gesamt] in Bytes
var choice := ""  # "", "llm", "regel" (je Gerät gespeichert)
var probe: Dictionary = {}  # was das Gerät kann (WebGPU, Speicher, Handy)
var stats: Dictionary = {"rat": [0, 0.0], "siedler": [0, 0.0]}  # Anfragen, Millisekunden gesamt
var last_log: Array = []
var pending: Dictionary = {}  # Job-ID -> Job
var _next := 1
var _poll := 0.0
var _rng := RandomNumberGenerator.new()
var _started := false
var force_big := false  # Llama-3.2-1B auch auf dem Handy versuchen
var mock_delay: Dictionary = {}  # Test: feste Rechenzeit der Attrappe je Modell
var _mock_free := 0.0
var skipped: Array = []  # Modelle, bei denen das Gerät abgestürzt ist (werden übersprungen)


func cfg(key: String, default = null):
	return Data.ki_llm.get(key, default)


func _ready() -> void:
	_rng.randomize()
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) == OK:
		choice = str(cf.get_value("ki", "choice", ""))
		force_big = bool(cf.get_value("ki", "force_big", false))
	var args := OS.get_cmdline_user_args()
	if "--llmmock=1" in args:
		backend = "mock"
		choice = "llm"
	elif "--llm=0" in args:
		choice = "regel"
	for a in args:
		if a.begins_with("--llmdelay="):
			# Test: Rechenzeit der Attrappe in Sekunden je Anfrage, "rat,siedler"
			var p := a.trim_prefix("--llmdelay=").split(",")
			mock_delay = {"rat": float(p[0]), "siedler": float(p[1]) if p.size() > 1 else float(p[0])}
	if OS.has_feature("web"):
		var p = JavaScriptBridge.eval("(function(){var n=navigator||{};return JSON.stringify({webgpu:!!n.gpu,memory:n.deviceMemory||0,mobile:/Android|iPhone|iPad|iPod|Mobile/i.test(n.userAgent||'')})})()", true)
		var d = JSON.parse_string(str(p)) if p != null else null
		if d is Dictionary:
			probe = d


## Sprachmodelle werden gerade benutzt (sonst entscheidet die Regel-KI).
func active() -> bool:
	return Society.enabled and state == "bereit"


## Muss der Spieler noch gefragt werden, ob die Modelle geladen werden?
func needs_consent() -> bool:
	return Society.enabled and choice == "" and backend != "mock"


func _save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("ki", "choice", choice)
	cf.set_value("ki", "force_big", force_big)
	cf.save(CFG_PATH)


## Auf dem Handy startet der Rat mit einem kleineren Modell (Llama-3.2-1B braucht zu viel Speicher).
func small_first() -> bool:
	return bool(probe.get("mobile", false)) and not force_big


## Denkt der Rat mit dem großen Modell, das josh ausgesucht hat?
func big_council() -> bool:
	return "Llama" in str(loaded.get("rat", {}).get("id", "")) or backend == "mock"


## Llama-3.2-1B noch einmal versuchen (vergisst frühere Abstürze).
func retry_big() -> void:
	force_big = true
	_save_cfg()
	if backend == "web":
		JavaScriptBridge.eval("window.KiLlm && KiLlm.resetTooBig()", true)
	stop()
	start()


func set_choice(c: String) -> void:
	choice = c
	_save_cfg()
	if c == "llm":
		start()
	else:
		stop()


## Startet die Modelle, wenn der Spieler sie gewählt hat. Von Society beim Spielstart aufgerufen.
func maybe_start() -> void:
	if Society.enabled and choice == "llm" and not _started:
		start()


func start() -> void:
	if _started:
		return
	_started = true
	error = ""
	if backend == "mock" or not OS.has_feature("web"):
		backend = "mock"
		device = "attrappe"
		loaded = {"rat": {"id": "Attrappe (Test)", "dtype": "-", "device": "-"}, "siedler": {"id": "Attrappe (Test)", "dtype": "-", "device": "-"}}
		_set_state("bereit")
		return
	backend = "web"
	var f := FileAccess.open("res://web/ki_llm.js", FileAccess.READ)
	if f == null:
		error = "web/ki_llm.js fehlt im Spiel."
		_set_state("fehler")
		return
	JavaScriptBridge.eval(f.get_as_text(), true)
	var conf := {"lib_urls": cfg("lib_urls", []), "models": cfg("models", {}), "dtypes": cfg("dtypes", {}), "device": "auto",
		"small_first": small_first()}
	loaded = {}
	progress = {}
	var r = JavaScriptBridge.eval("window.KiLlm.init(%s)" % JSON.stringify(JSON.stringify(conf)), true)
	if str(r) == "fehler":
		_poll_web()
		return
	_set_state("laden")


func stop() -> void:
	_started = false
	if backend == "web":
		JavaScriptBridge.eval("if(window.KiLlm&&KiLlm.worker){KiLlm.worker.terminate();KiLlm.worker=null;KiLlm.st.state='aus';}", true)
	_fail_pending("Sprachmodelle ausgeschaltet")
	backend = "" if backend == "web" else backend
	_set_state("aus")


func _set_state(s: String) -> void:
	if s == state:
		return
	state = s
	if s == "fehler":
		_fail_pending(error)
	status_changed.emit()


## Wie heißt das Modell, das wirklich geladen ist (oder geladen werden soll)?
func model_name(role: String) -> String:
	if loaded.has(role):
		var id: String = loaded[role].id
		return id.get_file() if "/" in id else id
	return cfg("model_names", {}).get(role, role)


func status_text() -> String:
	match state:
		"bereit":
			var dev: String = {"webgpu-f16": "Grafikkarte", "webgpu": "Grafikkarte", "wasm": "Prozessor (langsam)", "attrappe": "Testattrappe"}.get(device, device)
			var rat := model_name("rat")
			var why := ""
			if loaded.get("rat", {}).get("shared", false):
				rat = "mit dem Siedlermodell"
				why = " Die größeren Ratsmodelle sind für dieses Gerät zu groß."
			elif not big_council():
				why = " Llama-3.2-1B ist für %s zu groß." % ("Handys" if small_first() else "dieses Gerät")
			return "Sprachmodelle: Rat %s, Siedler %s, rechnen auf %s.%s" % [rat, model_name("siedler"), dev, why]
		"laden":
			var a := 0.0
			var b := 0.0
			for role in progress:
				a += float(progress[role][0])
				b += float(progress[role][1])
			var pct := ("%d %%" % int(100.0 * a / b)) if b > 0.0 else "startet"
			return "Sprachmodelle werden geladen (%s, %d MB). %s" % [pct, int(a / 1048576.0), note]
		"fehler":
			return "Sprachmodelle gehen nicht: %s Es entscheidet die Regel-KI." % error
	if choice == "regel":
		return "Regel-KI (Sprachmodelle ausgeschaltet)."
	return "Regel-KI (Sprachmodelle nicht geladen)."


func avg_ms(role: String) -> float:
	var s: Array = stats.get(role, [0, 0.0])
	return float(s[1]) / maxf(1.0, float(s[0]))


# ================================================================== Anfragen
## Nummer wählen lassen: Das Modell sieht die Nachrichten (die letzte endet mit den
## Möglichkeiten 1..n) und wir lesen ab, welche Nummer es wie wahrscheinlich schreibt.
## `hint` sind Gewichte, die nur die Testattrappe benutzt.
## `prefix` steht schon am Anfang der Antwort (z. B. "My choice:"), damit als Nächstes die Nummer kommt.
func choose(role: String, messages: Array, n: int, hint: Array = [], prefix: String = "") -> Job:
	var d := {"model": role, "mode": "choose", "messages": messages, "n": clampi(n, 1, 9)}
	if prefix != "":
		d["prefix"] = prefix
	return _submit(d, hint, "")


## Freien Text schreiben lassen. `hint_text` benutzt nur die Testattrappe.
func generate(role: String, messages: Array, max_tokens: int, temperature: float = 0.0, hint_text: String = "") -> Job:
	return _submit({"model": role, "mode": "generate", "messages": messages, "max_new_tokens": max_tokens,
		"temperature": temperature}, [], hint_text)


func _submit(data: Dictionary, hint: Array, hint_text: String) -> Job:
	var j := Job.new()
	j.id = _next
	_next += 1
	data.id = j.id
	j.data = data
	pending[j.id] = j
	if state != "bereit":
		_finish.call_deferred(j.id, {"ok": false, "error": "Sprachmodelle nicht bereit"})
		return j
	if backend == "mock":
		var dl: Array = cfg("mock_delay", [0.05, 0.25])
		var now := Time.get_ticks_msec() / 1000.0
		if mock_delay.has(data.model):
			# Wie ein echtes Modell: eine Anfrage nach der anderen, feste Rechenzeit je Modell
			_mock_free = maxf(_mock_free, now) + float(mock_delay[data.model]) * _rng.randf_range(0.8, 1.2)
			j.due = _mock_free
		else:
			j.due = now + _rng.randf_range(float(dl[0]), float(dl[1]))
		j.data["_hint"] = hint
		j.data["_hint_text"] = hint_text
	else:
		JavaScriptBridge.eval("window.KiLlm.submit(%s)" % JSON.stringify(JSON.stringify(data)), true)
	return j


func _finish(id: int, res: Dictionary) -> void:
	var j: Job = pending.get(id)
	if j == null:
		return
	pending.erase(id)
	var role: String = j.data.get("model", "")
	if res.get("ok", false) and stats.has(role):
		stats[role][0] = int(stats[role][0]) + 1
		stats[role][1] = float(stats[role][1]) + float(res.get("ms", 0.0))
	j.finished = true
	j.result = res
	j.done.emit(res)


func _fail_pending(why: String) -> void:
	for id in pending.keys():
		_finish.call_deferred(id, {"ok": false, "error": why})


func _process(delta: float) -> void:
	if backend == "mock":
		var now := Time.get_ticks_msec() / 1000.0
		for id in pending.keys():
			var j: Job = pending[id]
			if j.due > 0.0 and now >= j.due:
				j.due = 0.0
				_finish(id, _mock_result(j.data))
		return
	if backend != "web" or state == "aus":
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.1
	_poll_web()


func _poll_web() -> void:
	var raw = JavaScriptBridge.eval("window.KiLlm ? window.KiLlm.poll() : ''", true)
	if raw == null or str(raw) == "":
		return
	var d = JSON.parse_string(str(raw))
	if not d is Dictionary:
		return
	var st: Dictionary = d.get("status", {})
	device = str(st.get("device", device))
	note = str(st.get("note", ""))
	loaded = st.get("models", loaded)
	skipped = st.get("skipped", skipped)
	progress = st.get("progress", progress)
	last_log = st.get("log", [])
	if str(st.get("error", "")) != "":
		error = str(st.get("error"))
	var s := str(st.get("state", state))
	if s != state:
		_set_state(s)
	for r in d.get("results", []):
		_finish(int(r.get("id", 0)), r)


## Testattrappe: wählt nach den Gewichten mit etwas Zufall, schreibt den vorgegebenen Text.
func _mock_result(data: Dictionary) -> Dictionary:
	if data.mode == "generate":
		var t: String = data.get("_hint_text", "")
		return {"ok": true, "text": t if t != "" else "Wir arbeiten gemeinsam weiter.", "ms": 5.0, "tokens": 100}
	var n := int(data.n)
	var hint: Array = data.get("_hint", [])
	var p := []
	var sum := 0.0
	for i in n:
		var v := (float(hint[i]) if i < hint.size() else 0.2) + _rng.randf_range(0.0, 0.25)
		v = maxf(0.001, v)
		p.append(v)
		sum += v
	for i in n:
		p[i] = p[i] / sum
	return {"ok": true, "probs": p, "mass": 0.9, "top": "1", "ms": 5.0, "tokens": 100}
