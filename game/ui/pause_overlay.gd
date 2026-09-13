class_name PauseOverlay
extends ColorRect
## Voile de pause affiché quand l'application passe en arrière-plan.

signal resume_pressed

@onready var _resume_button: Button = %ResumeButton


func _ready() -> void:
	_resume_button.pressed.connect(resume_pressed.emit)


## Bloque les touchers destinés aux vues en dessous, qui lisent _unhandled_input.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
