class_name ModelSelectScreen
extends Control
## Choix du modèle qu'on va réparer aujourd'hui. La gamme est présentée par famille de
## démontage : c'est ce qui distingue vraiment ces téléphones les uns des autres, et ce que le
## joueur a besoin d'apprendre. Un modèle dont le démontage n'existe pas encore se lit mais ne
## se choisit pas.

signal model_chosen(model_id: String)

const FAMILY_FONT_SIZE: int = 16
const SPEC_FONT_SIZE: int = 12
const NOTE_COLOR: Color = Color(1, 1, 1, 0.55)
const SOON_COLOR: Color = Color(1, 1, 1, 0.38)
## Deux lignes de texte, sans descendre sous la cible tactile.
const ROW_HEIGHT: float = 56.0
## Au-delà, le doigt fait défiler la liste : ce n'est plus un choix.
const TAP_TOLERANCE: float = 24.0

@onready var _list: VBoxContainer = %Models
@onready var _summary: Label = %Summary

var _buttons: Dictionary[String, Button] = {}
## Ligne sous le doigt et distance parcourue depuis l'appui.
var _pressed_id: String = ""
var _travelled: float = 0.0


## À appeler une fois la scène dans l'arbre.
func setup(catalog: ModelCatalog) -> void:
	for child: Node in _list.get_children():
		child.queue_free()
	_buttons.clear()
	var playable: int = catalog.playable().size()
	_summary.text = "%d models · %d ready to open" % [catalog.models.size(), playable]
	for family: ModelCatalog.Family in catalog.families:
		var models: Array[ModelCatalog.Model] = catalog.models.filter(
			func(model: ModelCatalog.Model) -> bool: return model.family == family.id)
		if models.is_empty():
			continue
		_list.add_child(_family_header(family))
		for model: ModelCatalog.Model in models:
			var button: Button = _model_button(model)
			_list.add_child(button)
			_buttons[model.id] = button


## Bouton d'un modèle, désactivé tant que son démontage n'existe pas.
func button_for(model_id: String) -> Button:
	return _buttons.get(model_id)


## Choisit un modèle, comme un tap sur sa ligne.
func choose(model_id: String) -> void:
	model_chosen.emit(model_id)


func _family_header(family: ModelCatalog.Family) -> VBoxContainer:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var title: Label = Label.new()
	title.text = family.label
	title.add_theme_font_size_override("font_size", FAMILY_FONT_SIZE)
	box.add_child(title)
	var note: Label = Label.new()
	note.text = family.note
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", SPEC_FONT_SIZE)
	note.add_theme_color_override("font_color", NOTE_COLOR)
	box.add_child(note)
	return box


func _model_button(model: ModelCatalog.Model) -> Button:
	var button: Button = Button.new()
	# PASS et non STOP : sinon la ligne avale le glissement du doigt et la liste ne défile plus.
	# Vérifié à la main dans une fenêtre : en STOP, un glissement parti d'une ligne ne bouge rien.
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "%s\n%s" % [model.name, _specs(model)]
	button.disabled = not model.is_playable()
	if not model.is_playable():
		button.tooltip_text = "Teardown not built yet."
	else:
		button.gui_input.connect(func(event: InputEvent) -> void: _on_row_input(event, model.id))
	return button


## Choix d'une ligne. En MOUSE_FILTER_PASS le bouton ne se déclenche plus tout seul : c'est le
## prix à payer pour que le glissement atteigne la liste, alors on distingue nous-mêmes le tap
## du défilement.
func _on_row_input(event: InputEvent, model_id: String) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_pressed_id = model_id
			_travelled = 0.0
		elif _pressed_id == model_id:
			_pressed_id = ""
			if _travelled <= TAP_TOLERANCE:
				choose(model_id)
		return
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null:
		_travelled += drag.relative.length()


## Ligne de caractéristiques, telle qu'on lit une fiche : année, écran, port, et l'état du
## démontage quand il manque.
static func _specs(model: ModelCatalog.Model) -> String:
	var parts: PackedStringArray = PackedStringArray([
		str(model.year),
		"%.1f\" %s" % [model.screen_inches, model.screen_tech.to_upper()],
		"USB-C" if model.port == "usb_c" else "Lightning",
	])
	if not model.is_playable():
		parts.append("soon")
	elif not model.verified:
		parts.append("unverified")
	return " · ".join(parts)
