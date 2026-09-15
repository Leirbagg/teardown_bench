class_name PartsMat
extends PanelContainer
## Panneau du tapis magnétique, déplié par-dessus l'établi : les pièces détachées à leur place,
## le détail de la pièce choisie, et les actions de remontage ou de remplacement.

signal reinstall_requested(component_id: String)
signal replace_requested(component_id: String)
signal closed

var _state: DisassemblyState

@onready var _map: MatMap = %MatMap
@onready var _title: Label = %MatTitle
@onready var _info: Label = %MatInfo
@onready var _close_button: Button = %MatCloseButton
@onready var _reinstall_button: Button = %MatReinstallButton
@onready var _replace_button: Button = %MatReplaceButton


func _ready() -> void:
	_map.part_selected.connect(_on_part_selected)
	_close_button.pressed.connect(close)
	_reinstall_button.pressed.connect(func() -> void: reinstall_requested.emit(_map.selected_id))
	_replace_button.pressed.connect(func() -> void: replace_requested.emit(_map.selected_id))


func setup(state: DisassemblyState) -> void:
	_state = state
	_map.setup(state)
	for changed: Signal in [state.component_removed, state.component_installed]:
		changed.connect(_refresh.unbind(1))
	state.component_replaced.connect(_refresh.unbind(2))
	_refresh()


func open() -> void:
	visible = true
	_refresh()


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func selected_id() -> String:
	return _map.selected_id


## Nombre de pièces posées sur le tapis.
func item_count() -> int:
	return _map.item_ids().size()


## Message du jeu (refus, action réussie) affiché sous le tapis.
func show_message(text: String) -> void:
	if not text.is_empty():
		_info.text = text


func _on_part_selected(_component_id: String) -> void:
	_refresh()


func _refresh() -> void:
	if _state == null or not is_node_ready():
		return
	_title.text = "Magnetic mat · %d part(s)" % item_count()
	var id: String = _map.selected_id
	_reinstall_button.disabled = id.is_empty()
	_replace_button.disabled = id.is_empty() or not _state.device.get_component(id).replaceable
	if id.is_empty():
		_info.text = "Tap a part to reinstall or replace it." if item_count() > 0 else "Removed parts land here, where they came from."
		return
	var component: ComponentDefinition = _state.device.get_component(id)
	var details: PackedStringArray = PackedStringArray([UiFormat.label(id)])
	if not component.screw_type.is_empty():
		details.append("%s %.1f mm" % [UiFormat.label(component.screw_type), component.length_mm])
	if _state.is_broken(id):
		details.append("broken")
	_info.text = " · ".join(details)
