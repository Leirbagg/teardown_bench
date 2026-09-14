class_name PauseOverlay
extends ColorRect
## Voile de pause affiché quand l'application passe en arrière-plan.

signal resume_pressed

@onready var _resume_button: Button = %ResumeButton


## Le voile (mouse_filter STOP par défaut) intercepte les touchers destinés aux vues en dessous.
func _ready() -> void:
	_resume_button.pressed.connect(resume_pressed.emit)
