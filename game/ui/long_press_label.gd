class_name LongPressLabel
extends Label
## Texte qui réagit à un appui long, sans occuper de place à l'écran : sert d'accès discret au
## diagnostic, utile sur un vrai téléphone où l'on ne peut rien inspecter.

signal long_pressed

const HOLD_S: float = 1.0
## Au-delà, le doigt glisse : ce n'est plus un appui.
const MOVE_TOLERANCE: float = 16.0

var _pressed_at: Vector2
var _held_s: float = -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		_held_s = 0.0 if touch.pressed else -1.0
		_pressed_at = touch.position
		accept_event()
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and drag.position.distance_to(_pressed_at) > MOVE_TOLERANCE:
		_held_s = -1.0


func _process(delta: float) -> void:
	if _held_s < 0.0:
		return
	_held_s += delta
	if _held_s >= HOLD_S:
		_held_s = -1.0
		long_pressed.emit()
