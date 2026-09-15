class_name MatMap
extends Control
## Tapis magnétique : chaque pièce détachée est posée à son emplacement d'origine, sur la
## silhouette de l'appareil, comme un réparateur range ses vis. Affichage et sélection seulement.

signal part_selected(component_id: String)

const MARGIN: float = 16.0
## Taille minimale d'une pièce dessinée : une micro-vis reste lisible et touchable.
const MIN_ITEM_SIZE: float = 22.0
const TOUCH_SIZE: float = 48.0
const MAT_COLOR: Color = Color("16262b")
const DOT_COLOR: Color = Color(1, 1, 1, 0.06)
const SILHOUETTE_COLOR: Color = Color(1, 1, 1, 0.14)
const SELECTED_COLOR: Color = Color("ffd60a")
const NEW_COLOR: Color = Color("46a758")
const LENGTH_FONT_SIZE: int = 9
## Une pièce plus grande que ce ratio de l'appareil (un écran) est dessinée en transparence :
## les vis et caches posés dessus restent lisibles.
const LARGE_PART_RATIO: float = 0.25
const LARGE_PART_ALPHA: float = 0.35

## "" si rien n'est sélectionné.
var selected_id: String = "":
	set(value):
		selected_id = value
		queue_redraw()

var _state: DisassemblyState
var _bounds: Rect2
var _painter: PartPainter = PartPainter.new()


func setup(state: DisassemblyState) -> void:
	_state = state
	_bounds = DeviceView._device_rect(state.device.components[0])
	for component: ComponentDefinition in state.device.components:
		_bounds = _bounds.merge(DeviceView._device_rect(component))
	state.component_removed.connect(_on_state_changed)
	state.component_installed.connect(_on_state_changed)
	state.component_replaced.connect(_on_state_changed.unbind(1))
	state.component_broken.connect(_on_state_changed.unbind(1))
	queue_redraw()


## Pièces posées sur le tapis : retirées, sauf une pièce à charnière encore attachée (rabattue).
func item_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	if _state == null:
		return ids
	for id: String in _state.removed_ids():
		var component: ComponentDefinition = _state.device.get_component(id)
		if component.visual.has("hinge") and not _state.attached_parts(id).is_empty():
			continue
		ids.append(id)
	return ids


## Rectangle dessiné d'une pièce, à son emplacement d'origine, agrandi à MIN_ITEM_SIZE.
func item_rect(component_id: String) -> Rect2:
	var rect: Rect2 = DeviceView._device_rect(_state.device.get_component(component_id))
	var mapped: Rect2 = Rect2(rect.position * _scale() + _offset(), rect.size * _scale())
	return _grow_to(mapped, MIN_ITEM_SIZE)


## Sélectionne la pièce sous le doigt : la plus petite qui contient le point (une vis posée sur
## l'écran l'emporte sur l'écran), sinon la plus proche dans sa zone de 48dp. Toucher la pièce
## déjà sélectionnée la désélectionne.
func select_at(position: Vector2) -> void:
	var picked: String = _pick(position)
	if picked.is_empty():
		return
	selected_id = "" if picked == selected_id else picked
	part_selected.emit(selected_id)


func _pick(position: Vector2) -> String:
	var best_inside: String = ""
	var best_area: float = INF
	var nearest: String = ""
	var nearest_distance: float = INF
	for id: String in item_ids():
		var rect: Rect2 = item_rect(id)
		if rect.has_point(position) and rect.get_area() < best_area:
			best_area = rect.get_area()
			best_inside = id
		elif _grow_to(rect, TOUCH_SIZE).has_point(position):
			var distance: float = rect.get_center().distance_squared_to(position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = id
	return best_inside if not best_inside.is_empty() else nearest


func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null and touch.pressed:
		select_at(touch.position)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), MAT_COLOR)
	for x: int in range(12, int(size.x), 24):
		for y: int in range(12, int(size.y), 24):
			draw_circle(Vector2(x, y), 1.5, DOT_COLOR)
	if _state == null:
		return
	var silhouette: StyleBoxFlat = _painter.style("mat", Color(0, 0, 0, 0))
	silhouette.border_color = SILHOUETTE_COLOR
	silhouette.set_border_width_all(2)
	draw_style_box(silhouette, Rect2(_bounds.position * _scale() + _offset(), _bounds.size * _scale()))

	var font: Font = get_theme_default_font()
	var ids: Array = Array(item_ids())
	# Les grandes pièces d'abord : les vis restent visibles par-dessus.
	ids.sort_custom(func(a: String, b: String) -> bool: return item_rect(a).get_area() > item_rect(b).get_area())
	var replaced: PackedStringArray = _state.replaced_ids()
	for id: String in ids:
		var component: ComponentDefinition = _state.device.get_component(id)
		var rect: Rect2 = item_rect(id)
		var color: Color = PartPainter.kind_color(component.kind)
		if rect.get_area() > _mapped_bounds_area() * LARGE_PART_RATIO:
			color.a = LARGE_PART_ALPHA
		_painter.draw_part(self, component, rect, color)
		if _state.is_broken(id):
			_painter.draw_broken(self, rect)
		elif id in replaced:
			draw_string(font, rect.position + Vector2(2, 11), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, LENGTH_FONT_SIZE, NEW_COLOR)
		_painter.draw_label(self, font, UiFormat.label(id), rect)
		if component.length_mm > 0.0:
			draw_string(font, Vector2(rect.position.x - 8, rect.end.y + LENGTH_FONT_SIZE + 1), "%.1f" % component.length_mm,
				HORIZONTAL_ALIGNMENT_CENTER, rect.size.x + 16, LENGTH_FONT_SIZE, PartPainter.DECORATION_LABEL_COLOR)
		if id == selected_id:
			draw_rect(rect.grow(4.0), SELECTED_COLOR, false, 3.0)


func _mapped_bounds_area() -> float:
	return _bounds.get_area() * _scale() * _scale()


func _scale() -> float:
	if not _bounds.has_area():
		return 0.0
	var available: Vector2 = size - Vector2.ONE * MARGIN * 2.0
	return maxf(minf(available.x / _bounds.size.x, available.y / _bounds.size.y), 0.0)


func _offset() -> Vector2:
	return (size - _bounds.size * _scale()) / 2.0 - _bounds.position * _scale()


func _on_state_changed(_component_id: String) -> void:
	if not selected_id.is_empty() and not selected_id in item_ids():
		selected_id = ""
		part_selected.emit("")
	queue_redraw()


static func _grow_to(rect: Rect2, minimum: float) -> Rect2:
	var missing: Vector2 = (Vector2.ONE * minimum - rect.size).max(Vector2.ZERO)
	return rect.grow_individual(missing.x / 2.0, missing.y / 2.0, missing.x / 2.0, missing.y / 2.0)
