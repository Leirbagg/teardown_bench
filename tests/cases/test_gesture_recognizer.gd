extends TestSuite

const RECT: Rect2 = Rect2(100, 100, 40, 40)


func _recognizer(gesture: String, params: Dictionary = {}, start: Vector2 = RECT.get_center()) -> GestureRecognizer:
	var recognizer: GestureRecognizer = GestureRecognizer.new()
	recognizer.begin(gesture, params, RECT, start)
	return recognizer


## Fait tourner le doigt autour du centre du rectangle, par pas de 10°.
func _circle(recognizer: GestureRecognizer, degrees: float, radius: float = 20.0) -> void:
	var center: Vector2 = RECT.get_center()
	var steps: int = int(absf(degrees) / 10.0)
	for i: int in range(1, steps + 1):
		var angle: float = deg_to_rad(signf(degrees) * 10.0 * i)
		recognizer.drag(center + Vector2(cos(angle), sin(angle)) * radius)


# --- Rotation ---

func test_rotation_completes_after_required_turns() -> void:
	var recognizer: GestureRecognizer = _recognizer("rotate", {"turns": 2}, RECT.get_center() + Vector2(20, 0))
	_circle(recognizer, 360.0)
	assert_true(absf(recognizer.progress - 0.5) < 0.01, "un tour sur deux")
	assert_false(recognizer.is_complete())
	_circle(recognizer, 360.0)
	assert_true(recognizer.is_complete())


func test_rotation_accepts_either_direction() -> void:
	var recognizer: GestureRecognizer = _recognizer("rotate", {}, RECT.get_center() + Vector2(20, 0))
	_circle(recognizer, -360.0)
	assert_true(recognizer.is_complete())


func test_rotation_back_and_forth_does_not_progress() -> void:
	var recognizer: GestureRecognizer = _recognizer("rotate", {}, RECT.get_center() + Vector2(20, 0))
	for i: int in 10:
		_circle(recognizer, 90.0)
		_circle(recognizer, -90.0)
	assert_true(recognizer.progress < 0.3, "le frottement ne visse pas")


func test_rotation_ignores_moves_at_the_center() -> void:
	var recognizer: GestureRecognizer = _recognizer("rotate")
	_circle(recognizer, 720.0, 2.0)
	assert_eq(recognizer.progress, 0.0)


# --- Tirer ---

func test_pull_in_required_direction() -> void:
	var recognizer: GestureRecognizer = _recognizer("pull", {"direction_deg": 90})
	recognizer.drag(RECT.get_center() + Vector2(0, -36))
	assert_true(absf(recognizer.progress - 0.5) < 0.01, "moitié du chemin vers le haut")
	recognizer.drag(RECT.get_center() + Vector2(0, -GestureRecognizer.PULL_DISTANCE))
	assert_true(recognizer.is_complete())


func test_pull_in_wrong_direction_does_not_progress() -> void:
	var recognizer: GestureRecognizer = _recognizer("pull", {"direction_deg": 90})
	recognizer.drag(RECT.get_center() + Vector2(0, 200))
	assert_eq(recognizer.progress, 0.0)
	recognizer.drag(RECT.get_center() + Vector2(200, 0))
	assert_true(recognizer.progress < 0.001, "perpendiculaire")


func test_pull_without_direction_accepts_any() -> void:
	var recognizer: GestureRecognizer = _recognizer("pull")
	recognizer.drag(RECT.get_center() + Vector2(-60, 60))
	assert_true(recognizer.is_complete())


# --- Appui long ---

func test_hold_completes_after_duration() -> void:
	var recognizer: GestureRecognizer = _recognizer("hold", {"duration_s": 2.0})
	recognizer.tick(1.0)
	recognizer.drag(RECT.get_center() + Vector2(10, 10))
	assert_true(absf(recognizer.progress - 0.5) < 0.01)
	recognizer.tick(1.0)
	assert_true(recognizer.is_complete())


func test_hold_restarts_when_finger_slides_away() -> void:
	var recognizer: GestureRecognizer = _recognizer("hold", {"duration_s": 2.0})
	recognizer.tick(1.5)
	recognizer.drag(RECT.get_center() + Vector2(GestureRecognizer.HOLD_MOVE_TOLERANCE + 1.0, 0))
	assert_eq(recognizer.progress, 0.0)
	recognizer.tick(1.5)
	assert_false(recognizer.is_complete())


func test_tick_only_affects_hold() -> void:
	var recognizer: GestureRecognizer = _recognizer("pull")
	recognizer.tick(10.0)
	assert_eq(recognizer.progress, 0.0)


# --- Levier ---

func test_pry_along_the_edge_completes() -> void:
	var recognizer: GestureRecognizer = _recognizer("pry", {}, RECT.position)
	for point: Vector2 in [Vector2(140, 100), Vector2(140, 140), Vector2(100, 140)]:
		recognizer.drag(point)
	assert_true(recognizer.is_complete(), "trois côtés sur un carré de 40 : plus de la moitié du périmètre")


func test_pry_through_the_middle_does_not_count() -> void:
	var big: Rect2 = Rect2(0, 0, 300, 300)
	var recognizer: GestureRecognizer = GestureRecognizer.new()
	recognizer.begin("pry", {}, big, Vector2(150, 150))
	for i: int in 20:
		recognizer.drag(Vector2(150, 100 + (i % 2) * 100))
	assert_eq(recognizer.progress, 0.0)
