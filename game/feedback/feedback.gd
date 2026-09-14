class_name Feedback
extends Node
## Sons et vibrations des gestes, selon GameSettings. Chaque retour sonore a aussi son
## équivalent visuel dans DeviceView : le jeu reste lisible son coupé (GDD §6).

const SOUNDS: Dictionary[StringName, AudioStream] = {
	&"screw_tick": preload("res://assets/audio/screw_tick.wav"),
	&"pop": preload("res://assets/audio/pop.wav"),
	&"creak": preload("res://assets/audio/creak.wav"),
	&"crack": preload("res://assets/audio/crack.wav"),
	&"sizzle": preload("res://assets/audio/sizzle.wav"),
	&"click": preload("res://assets/audio/click.wav"),
	&"success": preload("res://assets/audio/success.wav"),
	&"failure": preload("res://assets/audio/failure.wav"),
}
## Sons simultanés possibles : un cran de vis peut chevaucher un déclic.
const VOICES: int = 4
const PITCH_VARIATION: float = 0.06

var settings: GameSettings = GameSettings.current()

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0


func _ready() -> void:
	for i: int in VOICES:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)


## Joue un son avec une légère variation de hauteur, pour éviter la répétition mécanique.
func play(sound: StringName) -> void:
	if not settings.sound_enabled or not SOUNDS.has(sound) or _players.is_empty():
		return
	var player: AudioStreamPlayer = _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = SOUNDS[sound]
	player.pitch_scale = randf_range(1.0 - PITCH_VARIATION, 1.0 + PITCH_VARIATION)
	player.play()


func vibrate(duration_ms: int) -> void:
	if settings.vibration_enabled:
		Input.vibrate_handheld(duration_ms)


## Son et vibration ensemble.
func pulse(sound: StringName, duration_ms: int) -> void:
	play(sound)
	vibrate(duration_ms)
