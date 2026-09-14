class_name DeviceView
extends Control
## Dessine la face courante de l'appareil (pièces en place et visibles) et transforme les
## touchers en gestes. N'applique aucune règle : lit DisassemblyState et émet des signaux.

## Le doigt s'est posé sur un composant (hors mode loupe).
signal gesture_started(component_id: String)
## Le geste est allé au bout : à l'appelant de demander à core/ ce qu'il se passe.
signal gesture_completed(component_id: String)
## Le doigt s'est levé avant la fin : aucune conséquence.
signal gesture_cancelled(component_id: String)
## Toucher en mode loupe.
signal component_inspected(component_id: String)

const MIN_TOUCH_TARGET: float = 48.0
const VIEW_MARGIN: float = 16.0
const LABEL_MIN_WIDTH: float = 56.0
const LABEL_FONT_SIZE: int = 11
const BODY_COLOR: Color = Color("20252b")
const OUTLINE_COLOR: Color = Color("0d1014")
const LABEL_COLOR: Color = Color(1, 1, 1, 0.85)
const BROKEN_COLOR: Color = Color("e5484d")
const RESIST_COLOR: Color = Color("f5a524")
const PROGRESS_COLOR: Color = Color("46a758")
const CLUE_COLOR: Color = Color("ffd60a")
const KIND_COLORS: Dictionary[String, Color] = {
	"screw": Color("9aa4ad"),
	"cover": Color("3b4754"),
	"connector": Color("d4a72c"),
	"adhesive": Color("e8dcc0"),
	"module": Color("2f7f86"),
}

var face: String = "":
	set(value):
		face = value
		_cancel_touch()
		queue_redraw()
var loupe_mode: bool = false:
	set(value):
		loupe_mode = value
		_cancel_touch()
		queue_redraw()
## Désactivé quand un panneau recouvre la vue.
var input_enabled: bool = true:
	set(value):
		input_enabled = value
		_cancel_touch()
## Composants à marquer d'un indice en mode loupe.
var clue_component_ids: PackedStringArray = PackedStringArray():
	set(value):
		clue_component_ids = value
		queue_redraw()

var _state: DisassemblyState
## Du dessous vers le dessus : une pièce est dessinée après celles qu'elle retient.
var _draw_order: Array[ComponentDefinition] = []
var _device_bounds: Rect2
var _recognizer: GestureRecognizer = GestureRecognizer.new()
var _touch_index: int = -1
var _active_id: String = ""
var _resisting: bool = false


func setup(state: DisassemblyState) -> void:
	_state = state
	_draw_order = _compute_draw_order(state.device)
	_device_bounds = _device_rect(state.device.components[0])
	for component: ComponentDefinition in state.device.components:
		_device_bounds = _device_bounds.merge(_device_rect(component))
	state.component_removed.connect(_on_state_changed)
	state.component_installed.connect(_on_state_changed)
	state.component_replaced.connect(_on_state_changed.unbind(1))
	state.component_broken.connect(_on_state_changed.unbind(1))
	face = state.device.faces[0]


## Affiche une résistance sur le composant en cours de geste : il est retenu.
func set_resisting(value: bool) -> void:
	_resisting = value
	queue_redraw()


## Rectangle d'un composant dans le repère de la vue.
func view_rect(component: ComponentDefinition) -> Rect2:
	return _to_view(_device_rect(component))


## Composant touchable le plus haut sous `position`, ou "" s'il n'y en a pas. La zone de toucher
## est agrandie à MIN_TOUCH_TARGET pour les petites pièces.
func component_at(position: Vector2) -> String:
	if _state == null or _scale() <= 0.0:
		return ""
	for i: int in range(_draw_order.size() - 1, -1, -1):
		var component: ComponentDefinition = _draw_order[i]
		if _is_drawn(component) and _touch_rect(view_rect(component)).has_point(position):
			return component.id
	return ""


## Repère local de l'appareil vers la vue : mis à l'échelle et centré.
func _to_view(device_rect: Rect2) -> Rect2:
	var scale_factor: float = _scale()
	var offset: Vector2 = (size - _device_bounds.size * scale_factor) / 2.0 - _device_bounds.position * scale_factor
	return Rect2(device_rect.position * scale_factor + offset, device_rect.size * scale_factor)


func _scale() -> float:
	if not _device_bounds.has_area():
		return 0.0
	var available: Vector2 = size - Vector2.ONE * VIEW_MARGIN * 2.0
	return maxf(minf(available.x / _device_bounds.size.x, available.y / _device_bounds.size.y), 0.0)


func _is_drawn(component: ComponentDefinition) -> bool:
	return component.face == face and not _state.is_removed(component.id) and _state.is_visible(component.id)


# --- Dessin ---

func _draw() -> void:
	if _state == null or _scale() <= 0.0:
		return
	var font: Font = get_theme_default_font()
	var body: Rect2 = _to_view(_device_bounds).grow(6.0)
	draw_rect(body, BODY_COLOR)
	for component: ComponentDefinition in _draw_order:
		if not _is_drawn(component):
			continue
		var rect: Rect2 = view_rect(component)
		draw_rect(rect, KIND_COLORS.get(component.kind, Color.MAGENTA))
		draw_rect(rect, OUTLINE_COLOR, false, 1.0)
		if _state.is_broken(component.id):
			draw_line(rect.position, rect.end, BROKEN_COLOR, 3.0)
			draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), BROKEN_COLOR, 3.0)
		if rect.size.x >= LABEL_MIN_WIDTH and rect.size.y >= LABEL_FONT_SIZE + 6:
			draw_string(font, Vector2(rect.position.x, rect.get_center().y + LABEL_FONT_SIZE / 2.0),
				component.id.capitalize(), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, LABEL_FONT_SIZE, LABEL_COLOR)
		if loupe_mode and component.id in clue_component_ids:
			draw_arc(rect.get_center(), 18.0, 0.0, TAU, 32, CLUE_COLOR, 3.0)
	if _active_id != "" and _state.device.has_component(_active_id):
		var active: Rect2 = view_rect(_state.device.get_component(_active_id))
		if _resisting:
			draw_rect(active.grow(3.0), RESIST_COLOR, false, 3.0)
		draw_arc(active.get_center(), 26.0, -PI / 2.0, -PI / 2.0 + TAU * _recognizer.progress, 48, PROGRESS_COLOR, 5.0)


# --- Toucher ---

## L'interface route les touchers vers le contrôle sous le doigt, puis garde ce contrôle pour le
## glissement et le relâchement : ils arrivent ici en coordonnées locales, même hors de la vue.
func _gui_input(event: InputEvent) -> void:
	if _state == null or not input_enabled:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		accept_event()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		if _active_id != "":
			_recognizer.drag((event as InputEventScreenDrag).position)
			_check_completion()
		accept_event()


func _process(delta: float) -> void:
	if _active_id != "" and _recognizer.gesture == "hold":
		_recognizer.tick(delta)
		_check_completion()


func _on_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _touch_index != -1 or not Rect2(Vector2.ZERO, size).has_point(touch.position):
			return
		var component_id: String = component_at(touch.position)
		if component_id == "":
			return
		if loupe_mode:
			component_inspected.emit(component_id)
			return
		var component: ComponentDefinition = _state.device.get_component(component_id)
		_touch_index = touch.index
		_active_id = component_id
		_resisting = false
		_recognizer.begin(component.gesture, component.gesture_params, view_rect(component), touch.position)
		gesture_started.emit(component_id)
		queue_redraw()
	elif touch.index == _touch_index:
		var cancelled_id: String = _active_id
		_cancel_touch()
		if cancelled_id != "":
			gesture_cancelled.emit(cancelled_id)


func _check_completion() -> void:
	queue_redraw()
	if not _recognizer.is_complete():
		return
	var completed_id: String = _active_id
	_active_id = ""
	_resisting = false
	gesture_completed.emit(completed_id)


## Oublie le geste en cours sans émettre de signal.
func _cancel_touch() -> void:
	_touch_index = -1
	_active_id = ""
	_resisting = false
	queue_redraw()


func _on_state_changed(_component_id: String) -> void:
	queue_redraw()


# --- Données d'affichage ---

static func _device_rect(component: ComponentDefinition) -> Rect2:
	var rect: Array = component.visual.get("rect", [0, 0, 0, 0])
	return Rect2(float(rect[0]), float(rect[1]), float(rect[2]), float(rect[3]))


## Agrandit un rectangle trop petit pour le doigt, autour de son centre.
static func _touch_rect(rect: Rect2) -> Rect2:
	var missing: Vector2 = (Vector2.ONE * MIN_TOUCH_TARGET - rect.size).max(Vector2.ZERO)
	return rect.grow_individual(missing.x / 2.0, missing.y / 2.0, missing.x / 2.0, missing.y / 2.0)


## Ordre de dessin : une pièce apparaît après tous les composants qu'elle retient (requires),
## qui sont donc dessous. Déduit des données, sans ordre codé en dur.
static func _compute_draw_order(device: DeviceDefinition) -> Array[ComponentDefinition]:
	var requires_first: Array[ComponentDefinition] = []
	var visited: Dictionary[String, bool] = {}
	for component: ComponentDefinition in device.components:
		_visit(device, component, visited, requires_first)
	requires_first.reverse()
	return requires_first


static func _visit(device: DeviceDefinition, component: ComponentDefinition, visited: Dictionary[String, bool],
		order: Array[ComponentDefinition]) -> void:
	if visited.has(component.id):
		return
	visited[component.id] = true
	for requirement: String in component.requires:
		_visit(device, device.get_component(requirement), visited, order)
	order.append(component)
