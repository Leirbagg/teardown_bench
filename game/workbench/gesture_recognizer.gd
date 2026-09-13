class_name GestureRecognizer
extends RefCounted
## Suit un doigt sur un composant et mesure l'avancement de son geste, de 0 à 1.
## Seule la précision est jugée ici : un geste raté se réessaie sans conséquence. Savoir si le
## retrait est permis, ou s'il force la pièce, relève de core/ (DisassemblyState).
## Positions et rectangles en coordonnées locales de la vue, en dp.

const COMPLETION_EPSILON: float = 0.001
const DEFAULT_TURNS: float = 1.0
## Rayon sous lequel la rotation est ignorée : trop près du centre, l'angle est instable.
const MIN_ROTATION_RADIUS: float = 6.0
const PULL_DISTANCE: float = 72.0
const DEFAULT_HOLD_S: float = 1.5
## Au-delà, l'appui long repart de zéro.
const HOLD_MOVE_TOLERANCE: float = 32.0
## Distance au bord du composant pour que le glissement compte comme un levier.
const PRY_EDGE_DISTANCE: float = 32.0
const PRY_PERIMETER_RATIO: float = 0.5
const PRY_MAX_PATH: float = 360.0

var gesture: String = ""
var progress: float = 0.0

var _params: Dictionary = {}
var _rect: Rect2
var _start: Vector2
var _last: Vector2
var _angle: float = 0.0
var _held_s: float = 0.0
var _pry_path: float = 0.0


func begin(gesture_name: String, gesture_params: Dictionary, target_rect: Rect2, position: Vector2) -> void:
	gesture = gesture_name
	_params = gesture_params
	_rect = target_rect
	_start = position
	_last = position
	_angle = 0.0
	_held_s = 0.0
	_pry_path = 0.0
	progress = 0.0


## Tolère l'erreur d'arrondi : un geste fait exactement jusqu'au bout doit compter.
func is_complete() -> bool:
	return progress >= 1.0 - COMPLETION_EPSILON


## Nouvelle position du doigt. Renvoie l'avancement.
func drag(position: Vector2) -> float:
	match gesture:
		"rotate":
			_track_rotation(position)
		"pull":
			_track_pull(position)
		"hold":
			if position.distance_to(_start) > HOLD_MOVE_TOLERANCE:
				_start = position
				_held_s = 0.0
				progress = 0.0
		"pry":
			_track_pry(position)
	_last = position
	return progress


## Temps écoulé doigt posé, utile à l'appui long. Renvoie l'avancement.
func tick(delta_s: float) -> float:
	if gesture == "hold" and delta_s > 0.0:
		_held_s += delta_s
		progress = minf(_held_s / float(_params.get("duration_s", DEFAULT_HOLD_S)), 1.0)
	return progress


## Angle cumulé autour du centre : un aller-retour s'annule, seule la rotation continue compte.
func _track_rotation(position: Vector2) -> void:
	var center: Vector2 = _rect.get_center()
	var from: Vector2 = _last - center
	var to: Vector2 = position - center
	if from.length() < MIN_ROTATION_RADIUS or to.length() < MIN_ROTATION_RADIUS:
		return
	_angle += from.angle_to(to)
	var required: float = float(_params.get("turns", DEFAULT_TURNS)) * TAU
	progress = minf(absf(_angle) / required, 1.0)


## direction_deg : 0 = vers la droite, 90 = vers le haut. Sans direction, tout sens convient.
func _track_pull(position: Vector2) -> void:
	var offset: Vector2 = position - _start
	var distance: float = offset.length()
	if _params.has("direction_deg"):
		var radians: float = deg_to_rad(float(_params["direction_deg"]))
		distance = offset.dot(Vector2(cos(radians), -sin(radians)))
	progress = clampf(distance / PULL_DISTANCE, 0.0, 1.0)


func _track_pry(position: Vector2) -> void:
	if _distance_to_edge(position) <= PRY_EDGE_DISTANCE and _distance_to_edge(_last) <= PRY_EDGE_DISTANCE:
		_pry_path += _last.distance_to(position)
	var required: float = minf((_rect.size.x + _rect.size.y) * 2.0 * PRY_PERIMETER_RATIO, PRY_MAX_PATH)
	progress = minf(_pry_path / required, 1.0)


func _distance_to_edge(position: Vector2) -> float:
	if _rect.has_point(position):
		return minf(minf(position.x - _rect.position.x, _rect.end.x - position.x),
			minf(position.y - _rect.position.y, _rect.end.y - position.y))
	var clamped: Vector2 = position.clamp(_rect.position, _rect.end)
	return position.distance_to(clamped)
