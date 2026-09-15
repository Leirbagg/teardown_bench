class_name DeviceView
extends Control
## Dessine la face courante de l'appareil (pièces en place et visibles) et transforme les
## touchers en gestes. N'applique aucune règle : lit DisassemblyState et émet des signaux.
## La pièce en cours de geste suit le doigt ; retraits, remontages et casses sont animés.

## Le doigt s'est posé sur un composant (hors mode loupe).
signal gesture_started(component_id: String)
## Un cran de plus dans le geste (quart de tour, palier de tirage…), pour sons et vibrations.
signal gesture_step(component_id: String, step: int, step_count: int)
## Le geste est allé au bout : à l'appelant de demander à core/ ce qu'il se passe.
signal gesture_completed(component_id: String)
## Le doigt s'est levé avant la fin : aucune conséquence.
signal gesture_cancelled(component_id: String)
## Toucher en mode loupe.
signal component_inspected(component_id: String)

const MIN_TOUCH_TARGET: float = 48.0
const VIEW_MARGIN: float = 16.0
const LABEL_MIN_WIDTH: float = 56.0
const BUBBLE_FONT_SIZE: int = 14
const BUBBLE_OFFSET: float = 64.0

const BODY_COLOR: Color = Color("20252b")
const RESIST_COLOR: Color = Color("f5a524")
const HEAT_COLOR: Color = Color("ff6a2b")
const PROGRESS_COLOR: Color = Color("46a758")
const CLUE_COLOR: Color = Color("ffd60a")
const BUBBLE_COLOR: Color = Color(0.05, 0.06, 0.08, 0.9)
const FLY_OUT_S: float = 0.35
const DROP_IN_S: float = 0.2
const BREAK_FLASH_S: float = 0.3
const SHARDS_S: float = 0.5
const SHAKE_S: float = 0.25
const SHAKE_PX: float = 5.0
## Tremblement d'une pièce retenue, qui grandit avec l'effort.
const RESIST_JITTER_PX: float = 3.0
## Une pièce retenue ne suit le doigt qu'un peu : elle résiste.
const RESIST_FOLLOW_RATIO: float = 0.15
const SCREW_LIFT_RATIO: float = 0.25
const PRY_LIFT_PX: float = 6.0

## Doigt fantôme du mode solution.
const GHOST_FINGER_COLOR: Color = Color(1, 1, 1, 0.45)
const GHOST_FINGER_RADIUS: float = 15.0
const GHOST_ROTATION_RADIUS: float = 14.0
## Marge au-delà du minimum requis, pour que le geste simulé aboutisse toujours.
const GHOST_OVERSHOOT: float = 1.15
const GHOST_SUBSTEPS_PER_SECOND: float = 120.0


## Animation ponctuelle dessinée par-dessus l'appareil.
class Effect:
	extends RefCounted
	var kind: String
	var rect: Rect2
	var color: Color
	var age_s: float = 0.0
	var duration_s: float
	var seed_value: int


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
var _last_step: int = 0
var _resisting: bool = false
var _effects: Array[Effect] = []
var _shake_s: float = 0.0
var _time_s: float = 0.0
var _painter: PartPainter = PartPainter.new()
var _ghost_active: bool = false
var _ghost_time_s: float = 0.0
var _ghost_duration_s: float = 1.0
var _ghost_speed: float = 1.0


func setup(state: DisassemblyState) -> void:
	_state = state
	_draw_order = _compute_draw_order(state.device)
	_device_bounds = _device_rect(state.device.components[0])
	for component: ComponentDefinition in state.device.components:
		_device_bounds = _device_bounds.merge(_device_rect(component))
	for decoration: DeviceDefinition.Decoration in state.device.decorations:
		_device_bounds = _device_bounds.merge(_decoration_rect(decoration))
	state.component_removed.connect(_on_component_removed)
	state.component_installed.connect(_on_component_installed)
	state.component_replaced.connect(_on_state_changed.unbind(1))
	state.component_broken.connect(_on_component_broken.unbind(1))
	face = state.device.faces[0]


## Affiche une résistance sur le composant en cours de geste : il est retenu.
func set_resisting(value: bool) -> void:
	_resisting = value
	queue_redraw()


## Rectangle d'un composant dans le repère de la vue.
func view_rect(component: ComponentDefinition) -> Rect2:
	return _to_view(_device_rect(component))


## Composant touché sous `position`, ou "" s'il n'y en a pas. Les petites pièces ont une zone de
## toucher agrandie à MIN_TOUCH_TARGET, sans jamais punir un doigt bien placé (pilier 2) :
## - une pièce visée en plein l'emporte sur la zone agrandie d'une voisine ;
## - mais une pièce posée sur une autre (vis sur l'écran) garde sa zone agrandie par-dessus.
func component_at(position: Vector2) -> String:
	if _state == null or _scale() <= 0.0:
		return ""
	var direct: ComponentDefinition = null
	var direct_level: int = -1
	var expanded: Array[int] = []
	for i: int in range(_draw_order.size() - 1, -1, -1):
		var component: ComponentDefinition = _draw_order[i]
		if not _is_drawn(component):
			continue
		var rect: Rect2 = view_rect(component)
		if direct == null and rect.has_point(position):
			direct = component
			direct_level = i
		elif _touch_rect(rect).has_point(position):
			expanded.append(i)

	var nearest_id: String = "" if direct == null else direct.id
	var nearest_distance: float = INF
	for i: int in expanded:
		var rect: Rect2 = view_rect(_draw_order[i])
		var sits_on_direct: bool = direct != null and i > direct_level and rect.intersects(view_rect(direct))
		if direct != null and not sits_on_direct:
			continue
		var distance: float = rect.get_center().distance_squared_to(position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = _draw_order[i].id
	return nearest_id


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


# --- Animation ---

func _process(delta: float) -> void:
	_time_s += delta
	if _ghost_active:
		_advance_ghost(delta)
	elif _active_id != "" and _recognizer.gesture == "hold":
		_recognizer.tick(delta)
		_check_progress()
	for effect: Effect in _effects:
		effect.age_s += delta
	_effects = _effects.filter(func(effect: Effect) -> bool: return effect.age_s < effect.duration_s)
	_shake_s = maxf(_shake_s - delta, 0.0)
	if _active_id != "" or not _effects.is_empty() or _shake_s > 0.0 or loupe_mode:
		queue_redraw()


func _spawn(kind: String, component_id: String, duration_s: float) -> void:
	var component: ComponentDefinition = _state.device.get_component(component_id)
	if component.face != face:
		return
	var effect: Effect = Effect.new()
	effect.kind = kind
	effect.rect = view_rect(component)
	effect.color = PartPainter.kind_color(component.kind)
	effect.duration_s = duration_s
	effect.seed_value = hash(component_id)
	_effects.append(effect)
	queue_redraw()


func _on_component_removed(component_id: String) -> void:
	_spawn("fly_out", component_id, FLY_OUT_S)


func _on_component_installed(component_id: String) -> void:
	_spawn("drop_in", component_id, DROP_IN_S)


func _on_component_broken(component_id: String) -> void:
	_spawn("flash", component_id, BREAK_FLASH_S)
	_spawn("shards", component_id, SHARDS_S)
	_shake_s = SHAKE_S


# --- Doigt fantôme (mode solution) ---

## Joue le geste d'un composant avec un doigt simulé. Passe par la même reconnaissance que le
## vrai doigt : la pièce suit, les crans sont émis, et gesture_completed arrive à la fin.
func start_ghost(component_id: String, speed: float = 1.0) -> void:
	var component: ComponentDefinition = _state.device.get_component(component_id)
	face = component.face
	_active_id = component_id
	_last_step = 0
	_resisting = false
	_ghost_time_s = 0.0
	_ghost_speed = maxf(speed, 0.01)
	_ghost_duration_s = ghost_duration(component) / _ghost_speed
	_ghost_active = true
	_recognizer.begin(component.gesture, component.gesture_params, view_rect(component), _ghost_position(component, 0.0))
	queue_redraw()


func is_ghost_running() -> bool:
	return _ghost_active


## Termine immédiatement le geste en cours, avec succès.
func finish_ghost() -> void:
	if _ghost_active:
		_advance_ghost(_ghost_duration_s - _ghost_time_s)


## Interrompt le geste sans retirer la pièce.
func stop_ghost() -> void:
	if _ghost_active:
		_cancel_touch()


## Durée d'un geste simulé à vitesse 1, lisible pour qui apprend.
static func ghost_duration(component: ComponentDefinition) -> float:
	match component.gesture:
		"rotate":
			return maxf(0.6, float(component.gesture_params.get("turns", GestureRecognizer.DEFAULT_TURNS)) * 0.8)
		"pull":
			return 0.8
		"hold":
			return float(component.gesture_params.get("duration_s", GestureRecognizer.DEFAULT_HOLD_S)) * GHOST_OVERSHOOT + 0.2
		"pry":
			return 1.8
	return 1.0


func _advance_ghost(delta: float) -> void:
	var component: ComponentDefinition = _state.device.get_component(_active_id)
	var target_time: float = minf(_ghost_time_s + maxf(delta, 0.0), _ghost_duration_s)
	# Petits pas : la rotation cumule des angles, un saut de plus d'un demi-tour serait mal compté.
	var substeps: int = maxi(1, ceili((target_time - _ghost_time_s) * GHOST_SUBSTEPS_PER_SECOND))
	var step_s: float = (target_time - _ghost_time_s) / substeps
	for i: int in substeps:
		_ghost_time_s += step_s
		_recognizer.drag(_ghost_position(component, _ghost_time_s / _ghost_duration_s))
		# L'appui long mesure un temps : accéléré comme le reste de la démonstration.
		_recognizer.tick(step_s * _ghost_speed)
	# Filet de sécurité : les chemins simulés dépassent le minimum requis et n'en ont pas besoin
	# (vérifié par les tests), mais un geste de démonstration ne doit jamais rester bloqué.
	if _ghost_time_s >= _ghost_duration_s - 0.0001 and not _recognizer.is_complete():
		_recognizer.progress = 1.0
	var completing: bool = _recognizer.is_complete()
	if completing:
		_ghost_active = false
	_check_progress()


## Position du doigt simulé à l'avancement `ratio` (0 à 1) du geste.
func _ghost_position(component: ComponentDefinition, ratio: float) -> Vector2:
	var rect: Rect2 = view_rect(component)
	var center: Vector2 = rect.get_center()
	match component.gesture:
		"rotate":
			var turns: float = float(component.gesture_params.get("turns", GestureRecognizer.DEFAULT_TURNS))
			return center + Vector2.from_angle(ratio * turns * TAU * GHOST_OVERSHOOT) * GHOST_ROTATION_RADIUS
		"pull":
			var direction: Vector2 = Vector2.from_angle(PI / 4.0)
			if component.gesture_params.has("direction_deg"):
				direction = Vector2.from_angle(-deg_to_rad(float(component.gesture_params["direction_deg"])))
			return center + direction * GestureRecognizer.PULL_DISTANCE * GHOST_OVERSHOOT * ratio
		"pry":
			var inset: Rect2 = rect.grow(-minf(6.0, minf(rect.size.x, rect.size.y) / 4.0))
			var corners: Array[Vector2] = [inset.position, Vector2(inset.position.x, inset.end.y), inset.end, Vector2(inset.end.x, inset.position.y)]
			var legs: Array[float] = [inset.size.y, inset.size.x, inset.size.y]
			var distance: float = ratio * (legs[0] + legs[1] + legs[2])
			for leg: int in 3:
				if distance <= legs[leg] or leg == 2:
					return corners[leg].lerp(corners[leg + 1], clampf(distance / maxf(legs[leg], 0.001), 0.0, 1.0))
				distance -= legs[leg]
	return center


# --- Dessin ---

func _draw() -> void:
	if _state == null or _scale() <= 0.0:
		return
	if _shake_s > 0.0:
		var strength: float = SHAKE_PX * _shake_s / SHAKE_S
		draw_set_transform(Vector2(randf_range(-strength, strength), randf_range(-strength, strength)))
	var font: Font = get_theme_default_font()
	draw_style_box(_painter.style("body", BODY_COLOR), _to_view(_device_bounds).grow(6.0))
	for decoration: DeviceDefinition.Decoration in _state.device.decorations:
		if decoration.face == face and decoration.attached_to.is_empty():
			_painter.draw_decoration(self, font, decoration, _to_view(_decoration_rect(decoration)))
	for component: ComponentDefinition in _draw_order:
		if _is_drawn(component):
			_draw_component(component)
			for decoration: DeviceDefinition.Decoration in _state.device.decorations:
				if decoration.attached_to == component.id:
					_painter.draw_decoration(self, font, decoration, _to_view(_decoration_rect(decoration)))
	for effect: Effect in _effects:
		_draw_effect(effect)
	draw_set_transform(Vector2.ZERO)
	if _active_id != "" and _state.device.has_component(_active_id):
		_draw_gesture_overlay(_state.device.get_component(_active_id))


func _draw_component(component: ComponentDefinition) -> void:
	var rect: Rect2 = view_rect(component)
	var color: Color = PartPainter.kind_color(component.kind)
	var active: bool = component.id == _active_id
	var progress: float = _recognizer.progress if active else 0.0

	if active:
		var offset: Vector2 = _recognizer.pull_offset() * (RESIST_FOLLOW_RATIO if _resisting else 1.0)
		if _resisting:
			var jitter: float = RESIST_JITTER_PX * (0.4 + progress)
			offset += Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))
		if component.gesture == "pry":
			draw_style_box(_painter.style(component.kind, PartPainter.SHADOW_COLOR), rect)
			offset += Vector2(-1.0, -1.0) * PRY_LIFT_PX * progress
		if component.gesture == "hold":
			color = color.lerp(HEAT_COLOR, progress)
		rect.position += offset

	_painter.draw_part(self, component, rect, color, _recognizer.rotation_angle() if active else 0.0,
		1.0 + SCREW_LIFT_RATIO * progress)
	if _state.is_broken(component.id):
		_painter.draw_broken(self, rect)
	_painter.draw_label(self, get_theme_default_font(), UiFormat.label(component.id), rect, LABEL_MIN_WIDTH)
	if loupe_mode and component.id in clue_component_ids:
		var pulse: float = 18.0 + 3.0 * sin(_time_s * 6.0)
		draw_arc(rect.get_center(), pulse, 0.0, TAU, 32, CLUE_COLOR, 3.0)


func _draw_effect(effect: Effect) -> void:
	var t: float = effect.age_s / effect.duration_s
	match effect.kind:
		"fly_out":
			var eased: float = t * t
			var target: Vector2 = Vector2(effect.rect.get_center().x, size.y + effect.rect.size.y)
			var center: Vector2 = effect.rect.get_center().lerp(target, eased)
			var scaled: Vector2 = effect.rect.size * (1.0 - 0.6 * eased)
			var faded: Color = Color(effect.color, 1.0 - t)
			draw_rect(Rect2(center - scaled / 2.0, scaled), faded)
		"drop_in":
			var grow: float = 8.0 * (1.0 - t)
			draw_rect(effect.rect.grow(grow), Color(1, 1, 1, 0.25 * (1.0 - t)), false, 2.0)
		"flash":
			draw_rect(effect.rect.grow(4.0), Color(PartPainter.BROKEN_COLOR, 0.6 * (1.0 - t)))
		"shards":
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = effect.seed_value
			var center: Vector2 = effect.rect.get_center()
			for i: int in 8:
				var direction: Vector2 = Vector2.from_angle(rng.randf() * TAU)
				var start: Vector2 = center + direction * (6.0 + 60.0 * t)
				draw_line(start, start + direction * 8.0, Color(PartPainter.BROKEN_COLOR, 1.0 - t), 2.0)


## Anneau de progression, contour de résistance et nom de la pièce au-dessus du doigt.
func _draw_gesture_overlay(component: ComponentDefinition) -> void:
	var rect: Rect2 = view_rect(component)
	if _resisting:
		draw_rect(rect.grow(3.0), RESIST_COLOR, false, 3.0)
	if component.gesture == "pry":
		_draw_pry_edge(rect)
	draw_arc(rect.get_center(), 26.0, -PI / 2.0, -PI / 2.0 + TAU * _recognizer.progress, 48, PROGRESS_COLOR, 5.0)
	if _ghost_active:
		draw_circle(_recognizer.finger_position(), GHOST_FINGER_RADIUS, GHOST_FINGER_COLOR)
		draw_arc(_recognizer.finger_position(), GHOST_FINGER_RADIUS, 0.0, TAU, 32, Color(1, 1, 1, 0.8), 2.0)

	var font: Font = get_theme_default_font()
	var text: String = UiFormat.label(component.id)
	var text_size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT_SIZE)
	var bubble: Rect2 = Rect2(_recognizer.finger_position() - Vector2(text_size.x / 2.0 + 10.0, BUBBLE_OFFSET),
		text_size + Vector2(20.0, 12.0))
	if bubble.position.y < 0.0:
		# Trop près du haut : sous le doigt plutôt que plaquée sur la pièce.
		bubble.position.y = _recognizer.finger_position().y + BUBBLE_OFFSET - bubble.size.y
	bubble.position = bubble.position.clamp(Vector2.ZERO, (size - bubble.size).max(Vector2.ZERO))
	draw_style_box(_painter.style("bubble", BUBBLE_COLOR), bubble)
	draw_string(font, bubble.position + Vector2(10.0, 6.0 + text_size.y * 0.78), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, BUBBLE_FONT_SIZE, _resisting_color())


## Surligne le bord le plus proche du doigt, là où le médiator s'insère.
func _draw_pry_edge(rect: Rect2) -> void:
	var finger: Vector2 = _recognizer.finger_position().clamp(rect.position, rect.end)
	var distances: Array[float] = [finger.x - rect.position.x, rect.end.x - finger.x, finger.y - rect.position.y, rect.end.y - finger.y]
	var nearest: int = distances.find(distances.min())
	var half: float = 22.0
	var from: Vector2
	var to: Vector2
	match nearest:
		0:
			from = Vector2(rect.position.x, finger.y - half)
			to = Vector2(rect.position.x, finger.y + half)
		1:
			from = Vector2(rect.end.x, finger.y - half)
			to = Vector2(rect.end.x, finger.y + half)
		2:
			from = Vector2(finger.x - half, rect.position.y)
			to = Vector2(finger.x + half, rect.position.y)
		_:
			from = Vector2(finger.x - half, rect.end.y)
			to = Vector2(finger.x + half, rect.end.y)
	draw_line(from, to, PROGRESS_COLOR.lightened(0.4), 4.0)


func _resisting_color() -> Color:
	return RESIST_COLOR if _resisting else Color.WHITE


# --- Toucher ---

## L'interface route les touchers vers le contrôle sous le doigt, puis garde ce contrôle pour le
## glissement et le relâchement : ils arrivent ici en coordonnées locales, même hors de la vue.
func _gui_input(event: InputEvent) -> void:
	if _state == null or not input_enabled or _ghost_active:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
		accept_event()
	elif event is InputEventScreenDrag and (event as InputEventScreenDrag).index == _touch_index:
		if _active_id != "":
			_recognizer.drag((event as InputEventScreenDrag).position)
			_check_progress()
		accept_event()


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
		_last_step = 0
		_resisting = false
		_recognizer.begin(component.gesture, component.gesture_params, view_rect(component), touch.position)
		gesture_started.emit(component_id)
		queue_redraw()
	elif touch.index == _touch_index:
		var cancelled_id: String = _active_id
		_cancel_touch()
		if cancelled_id != "":
			gesture_cancelled.emit(cancelled_id)


func _check_progress() -> void:
	queue_redraw()
	var step: int = _recognizer.step()
	if step > _last_step:
		_last_step = step
		gesture_step.emit(_active_id, step, _recognizer.step_count())
	elif step < _last_step:
		_last_step = step
	if not _recognizer.is_complete():
		return
	var completed_id: String = _active_id
	_active_id = ""
	_resisting = false
	gesture_completed.emit(completed_id)


## Oublie le geste en cours (réel ou fantôme) sans émettre de signal.
func _cancel_touch() -> void:
	_ghost_active = false
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


static func _decoration_rect(decoration: DeviceDefinition.Decoration) -> Rect2:
	return Rect2(decoration.rect[0], decoration.rect[1], decoration.rect[2], decoration.rect[3])


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
