class_name SettingsToggles
extends HBoxContainer
## Interrupteurs son et vibrations, enregistrés dès qu'on les touche.

var settings: GameSettings = GameSettings.current()

@onready var _sound_button: Button = %SoundButton
@onready var _vibration_button: Button = %VibrationButton


func _ready() -> void:
	_sound_button.toggled.connect(_on_sound_toggled)
	_vibration_button.toggled.connect(_on_vibration_toggled)
	_refresh()


func _on_sound_toggled(enabled: bool) -> void:
	settings.sound_enabled = enabled
	settings.save()
	_refresh()


func _on_vibration_toggled(enabled: bool) -> void:
	settings.vibration_enabled = enabled
	settings.save()
	_refresh()


func _refresh() -> void:
	_sound_button.set_pressed_no_signal(settings.sound_enabled)
	_vibration_button.set_pressed_no_signal(settings.vibration_enabled)
	_sound_button.text = "Sound: %s" % ("on" if settings.sound_enabled else "off")
	_vibration_button.text = "Vibration: %s" % ("on" if settings.vibration_enabled else "off")
