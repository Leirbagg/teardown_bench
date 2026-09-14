class_name GameSettings
extends RefCounted
## Préférences de l'appareil (son, vibrations), enregistrées dans user://. Pas une règle de jeu :
## elles ne concernent que le ressenti et restent donc dans game/.

signal changed

const DEFAULT_PATH: String = "user://settings.cfg"

static var _current: GameSettings = null

var sound_enabled: bool = true:
	set(value):
		if value != sound_enabled:
			sound_enabled = value
			changed.emit()
var vibration_enabled: bool = true:
	set(value):
		if value != vibration_enabled:
			vibration_enabled = value
			changed.emit()

var _path: String = DEFAULT_PATH


## Préférences partagées par tous les écrans, chargées au premier appel.
static func current() -> GameSettings:
	if _current == null:
		_current = load_from(DEFAULT_PATH)
	return _current


## Fichier absent ou illisible : valeurs par défaut.
static func load_from(path: String) -> GameSettings:
	var settings: GameSettings = GameSettings.new()
	settings._path = path
	var config: ConfigFile = ConfigFile.new()
	if config.load(path) == OK:
		settings.sound_enabled = bool(config.get_value("feedback", "sound_enabled", true))
		settings.vibration_enabled = bool(config.get_value("feedback", "vibration_enabled", true))
	return settings


func save() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("feedback", "sound_enabled", sound_enabled)
	config.set_value("feedback", "vibration_enabled", vibration_enabled)
	return config.save(_path)
