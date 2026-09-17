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
## En deçà, le doigt a tapé ; au-delà, il a déplacé la pièce.
const TAP_TOLERANCE: float = 6.0
## Espace entre deux pièces rangées.
const TIDY_GAP: float = 8.0
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
## Déplacements décidés par le joueur, par pièce, en pixels du tapis.
var _offsets: Dictionary[String, Vector2] = {}
var _drag_id: String = ""
var _drag_start: Vector2
var _drag_origin: Vector2
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
		if component.visual.has("cable_to"):
			# Une nappe reste attachée à sa pièce : elle se débranche sur place, jamais sur le tapis.
			continue
		ids.append(id)
	return ids


## Rectangle dessiné d'une pièce : son emplacement d'origine, plus le déplacement du joueur,
## agrandi à MIN_ITEM_SIZE.
func item_rect(component_id: String) -> Rect2:
	var placed: Rect2 = _origin_rect(component_id)
	placed.position += _offsets.get(component_id, Vector2.ZERO)
	return placed


## Emplacement d'origine de la pièce sur le tapis, avant déplacement.
func _origin_rect(component_id: String) -> Rect2:
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
		var component: ComponentDefinition = _state.device.get_component(id)
		if PartPainter.contains_point(component, rect, position) and rect.get_area() < best_area:
			best_area = rect.get_area()
			best_inside = id
		elif _grow_to(rect, TOUCH_SIZE) != rect and _grow_to(rect, TOUCH_SIZE).has_point(position):
			var distance: float = rect.get_center().distance_squared_to(position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = id
	return best_inside if not best_inside.is_empty() else nearest


## Range les pièces en rangées, de la plus grande à la plus petite : vis et caches ne se
## chevauchent plus. Les pièces aussi grandes que l'appareil (un écran détaché) restent à leur
## place : elles servent de fond et aucune grille ne les contiendrait.
func tidy() -> void:
	var ids: Array = Array(item_ids()).filter(func(id: String) -> bool: return not _is_large(_origin_rect(id)))
	ids.sort_custom(func(a: String, b: String) -> bool: return _origin_rect(a).size.y > _origin_rect(b).size.y)
	var pen: Vector2 = Vector2(TIDY_GAP, TIDY_GAP)
	var row_height: float = 0.0
	for id: String in ids:
		var origin: Rect2 = _origin_rect(id)
		if pen.x + origin.size.x > size.x - TIDY_GAP:
			pen = Vector2(TIDY_GAP, pen.y + row_height + TIDY_GAP)
			row_height = 0.0
		_offsets[id] = _clamped_offset(id, pen - origin.position)
		pen.x += origin.size.x + TIDY_GAP
		row_height = maxf(row_height, origin.size.y)
	queue_redraw()


func _is_large(rect: Rect2) -> bool:
	return rect.get_area() > _mapped_bounds_area() * LARGE_PART_RATIO


func _gui_input(event: InputEvent) -> void:
	var touch: InputEventScreenTouch = event as InputEventScreenTouch
	if touch != null:
		if touch.pressed:
			_begin_drag(touch.position)
		else:
			_end_drag(touch.position)
		accept_event()
	var drag: InputEventScreenDrag = event as InputEventScreenDrag
	if drag != null and not _drag_id.is_empty():
		_offsets[_drag_id] = _clamped_offset(_drag_id, _drag_origin + drag.position - _drag_start)
		queue_redraw()
		accept_event()


func _begin_drag(position: Vector2) -> void:
	_drag_id = _pick(position)
	_drag_start = position
	_drag_origin = _offsets.get(_drag_id, Vector2.ZERO)


## Doigt levé : un appui bref sélectionne, un déplacement garde la pièce où on l'a posée.
func _end_drag(position: Vector2) -> void:
	if _drag_id.is_empty():
		return
	if position.distance_to(_drag_start) <= TAP_TOLERANCE:
		select_at(_drag_start)
	elif selected_id != _drag_id:
		selected_id = _drag_id
		part_selected.emit(selected_id)
	_drag_id = ""


## Garde la pièce entièrement sur le tapis.
func _clamped_offset(component_id: String, wanted: Vector2) -> Vector2:
	var base: Rect2 = item_rect(component_id)
	base.position -= _offsets.get(component_id, Vector2.ZERO)
	var minimum: Vector2 = -base.position
	var maximum: Vector2 = size - base.size - base.position
	return wanted.clamp(minimum.min(maximum), maximum.max(minimum))


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
		if _is_large(rect):
			color.a = LARGE_PART_ALPHA
		_painter.draw_part(self, component, rect, color)
		if _state.is_broken(id):
			_painter.draw_broken(self, rect)
		elif id in replaced:
			draw_string(font, rect.position + Vector2(2, 11), "NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, LENGTH_FONT_SIZE, NEW_COLOR)
		_painter.draw_label(self, font, UiFormat.label(id), rect, 56.0, component)
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
	# Une pièce remontée oublie sa place : elle repartira de son emplacement d'origine.
	var on_mat: PackedStringArray = item_ids()
	for id: String in _offsets.keys():
		if not id in on_mat:
			_offsets.erase(id)
	queue_redraw()


static func _grow_to(rect: Rect2, minimum: float) -> Rect2:
	var missing: Vector2 = (Vector2.ONE * minimum - rect.size).max(Vector2.ZERO)
	return rect.grow_individual(missing.x / 2.0, missing.y / 2.0, missing.x / 2.0, missing.y / 2.0)
