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
## Le contour est découpé en segments : il faut les visiter, pas seulement parcourir une distance.
const PRY_SEGMENTS: int = 16
## Part du contour à visiter par défaut ; `perimeter_ratio` dans les données peut l'augmenter.
const DEFAULT_PERIMETER_RATIO: float = 0.5
## Pas d'échantillonnage du trajet : un glissement rapide ne saute pas de segment.
const PRY_SAMPLE_STEP: float = 6.0

var gesture: String = ""
var progress: float = 0.0

var _params: Dictionary = {}
var _rect: Rect2
var _start: Vector2
var _last: Vector2
var _angle: float = 0.0
var _held_s: float = 0.0
var _pry_covered: PackedByteArray = PackedByteArray()


func begin(gesture_name: String, gesture_params: Dictionary, target_rect: Rect2, position: Vector2) -> void:
	gesture = gesture_name
	_params = gesture_params
	_rect = target_rect
	_start = position
	_last = position
	_angle = 0.0
	_held_s = 0.0
	_pry_covered = PackedByteArray()
	_pry_covered.resize(PRY_SEGMENTS)
	progress = 0.0


## Tolère l'erreur d'arrondi : un geste fait exactement jusqu'au bout doit compter.
func is_complete() -> bool:
	return progress >= 1.0 - COMPLETION_EPSILON


## Nombre de crans d'un geste complet, pour rythmer sons et vibrations : un par quart de tour,
## quelques-uns pour tirer, chauffer ou faire levier.
func step_count() -> int:
	match gesture:
		"rotate":
			return maxi(roundi(float(_params.get("turns", DEFAULT_TURNS)) * 4.0), 1)
		"pull":
			return 3
		"hold":
			return 5
		"pry":
			return 6
	return 1


## Cran atteint, de 0 à step_count().
func step() -> int:
	return floori((progress + COMPLETION_EPSILON) * step_count())


## Angle cumulé en radians, signé : la vis affichée tourne avec le doigt.
func rotation_angle() -> float:
	return _angle


## Déplacement de la pièce qui suit le doigt : projeté sur la direction de tirage s'il y en a
## une, borné à PULL_DISTANCE. Nul pour les autres gestes.
func pull_offset() -> Vector2:
	if gesture != "pull":
		return Vector2.ZERO
	var offset: Vector2 = _last - _start
	if _params.has("direction_deg"):
		var radians: float = deg_to_rad(float(_params["direction_deg"]))
		var direction: Vector2 = Vector2(cos(radians), -sin(radians))
		return direction * clampf(offset.dot(direction), 0.0, PULL_DISTANCE)
	return offset.limit_length(PULL_DISTANCE)


## Dernière position connue du doigt.
func finger_position() -> Vector2:
	return _last


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


## Marque les segments de contour visités par le médiator, puis compare à la part exigée.
func _track_pry(position: Vector2) -> void:
	var steps: int = maxi(1, ceili(_last.distance_to(position) / PRY_SAMPLE_STEP))
	for i: int in range(1, steps + 1):
		var point: Vector2 = _last.lerp(position, float(i) / steps)
		if _distance_to_edge(point) <= PRY_EDGE_DISTANCE:
			_pry_covered[_perimeter_segment(point)] = 1
	var covered: int = 0
	for visited: int in _pry_covered:
		covered += visited
	var required: float = maxf(PRY_SEGMENTS * float(_params.get("perimeter_ratio", DEFAULT_PERIMETER_RATIO)), 1.0)
	progress = minf(covered / required, 1.0)


## Segment du contour le plus proche du point, numéroté depuis le coin haut gauche.
func _perimeter_segment(position: Vector2) -> int:
	var point: Vector2 = position.clamp(_rect.position, _rect.end)
	var to_left: float = point.x - _rect.position.x
	var to_right: float = _rect.end.x - point.x
	var to_top: float = point.y - _rect.position.y
	var to_bottom: float = _rect.end.y - point.y
	var width: float = _rect.size.x
	var height: float = _rect.size.y
	var along: float = to_left
	var nearest: float = minf(minf(to_top, to_bottom), minf(to_left, to_right))
	if is_equal_approx(nearest, to_right):
		along = width + to_top
	elif is_equal_approx(nearest, to_bottom):
		along = width + height + (width - to_left)
	elif is_equal_approx(nearest, to_left):
		along = 2.0 * width + height + (height - to_top)
	var perimeter: float = maxf(2.0 * (width + height), 0.001)
	return clampi(floori(along / perimeter * PRY_SEGMENTS), 0, PRY_SEGMENTS - 1)


func _distance_to_edge(position: Vector2) -> float:
	if _rect.has_point(position):
		return minf(minf(position.x - _rect.position.x, _rect.end.x - position.x),
			minf(position.y - _rect.position.y, _rect.end.y - position.y))
	var clamped: Vector2 = position.clamp(_rect.position, _rect.end)
	return position.distance_to(clamped)
