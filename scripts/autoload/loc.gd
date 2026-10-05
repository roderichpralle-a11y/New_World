class_name Loc
extends RefCounted
## Sprache des Spiels. Der Quelltext ist deutsch; data/i18n/en.json uebersetzt jeden
## deutschen Text (Schluessel) ins Englische. Englisch ist Standard, Deutsch waehlbar.
##
## Im Code: tr("Deutscher Text") in Nodes und Objekten, Loc.t("...") in statischen
## Funktionen. Texte, die ganz in einem Label oder Knopf stehen, uebersetzt Godot von
## selbst. Spieldaten (Namen, Beschreibungen aus data/*.json) uebersetzt Data beim Laden.
## Fehlende Uebersetzungen zeigt `python3 tools/i18n.py`; dann bleibt der Text deutsch.

const SETTINGS_PATH := "user://settings.cfg"
const LANGUAGES := {"en": "English", "de": "Deutsch"}

static var language: String = "en"
static var _reverse: Dictionary = {}  # englisch -> deutsch (fuer gespeicherte Namen)


## Einmal beim Start (Data._ready), bevor Spieldaten geladen werden.
static func setup() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		language = str(cf.get_value("game", "language", "en"))
	if not LANGUAGES.has(language):
		language = "en"
	var f := FileAccess.open("res://data/i18n/en.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()) if f else null
	if d is Dictionary:
		var tr_en := Translation.new()
		tr_en.locale = "en"
		for k in d:
			var v := str(d[k])
			if v != "" and v != k and not k.begins_with("_"):
				tr_en.add_message(k, v)
				_reverse[v] = k
		# Nur fuer Englisch laden: Godot faellt sonst auch bei "de" auf Englisch zurueck.
		# Ein Sprachwechsel startet das Spiel ohnehin neu.
		if language == "en":
			TranslationServer.add_translation(tr_en)
	TranslationServer.set_locale(language)


static func t(text: String) -> String:
	return String(TranslationServer.translate(text))


## Gespeicherte Namen (Inseln, Schiffe) in der aktuellen Sprache zeigen.
static func name_of(text: String) -> String:
	if language == "de":
		return str(_reverse.get(text, text))
	return t(text)


static func set_language(l: String) -> void:
	if not LANGUAGES.has(l):
		return
	language = l
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)
	cf.set_value("game", "language", l)
	cf.save(SETTINGS_PATH)
