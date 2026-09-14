class_name Main
extends Control
## Enchaînement des écrans : accueil client → réparation → client suivant… → bilan.
## Suit les signaux de WorkDay ; le temps de jeu est transmis à core/ à chaque frame.

const CUSTOMER_SCREEN: PackedScene = preload("res://game/ui/customer_screen.tscn")
const WORKBENCH: PackedScene = preload("res://game/workbench/workbench.tscn")
const DAY_REPORT_SCREEN: PackedScene = preload("res://game/ui/day_report_screen.tscn")
const PAUSE_OVERLAY: PackedScene = preload("res://game/ui/pause_overlay.tscn")
## MVP : uniquement des pannes évidentes (GDD §3.4).
const MAX_TIER: int = 1

var day: WorkDay
var current_screen: Control

## Survit aux changements d'écran, pour ne pas couper un son en cours.
@onready var feedback: Feedback = %Feedback

var _catalog: DataCatalog
var _pause_overlay: PauseOverlay


func _ready() -> void:
	var errors: Array[String] = []
	_catalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	if _catalog == null:
		_show_error(errors)
		return
	start_new_day()


func start_new_day() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var errors: Array[String] = []
	var jobs: Array[RepairJob] = DayGenerator.generate(_catalog.devices, _catalog.faults, MAX_TIER, rng, errors)
	if not errors.is_empty():
		_show_error(errors)
		return
	day = WorkDay.new(jobs)
	day.job_completed.connect(_on_job_completed)
	day.day_completed.connect(_on_day_completed)
	_show_next_customer()


func _process(delta: float) -> void:
	if day != null:
		day.advance(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_pause()


# --- Écrans ---

func _show_next_customer() -> void:
	var screen: CustomerScreen = _set_screen(CUSTOMER_SCREEN) as CustomerScreen
	screen.setup(day.next_job(), day.next_job_number(), day.jobs.size())
	screen.start_pressed.connect(_on_start_pressed)


func _on_start_pressed() -> void:
	var session: RepairSession = day.start_next_job()
	if session == null:
		return
	var workbench: Workbench = _set_screen(WORKBENCH) as Workbench
	workbench.setup(session, feedback)


func _on_job_completed(_report: RepairReport) -> void:
	if day.has_next_job():
		_show_next_customer()


func _on_day_completed(report: DayReport) -> void:
	var screen: DayReportScreen = _set_screen(DAY_REPORT_SCREEN) as DayReportScreen
	screen.setup(report)
	screen.new_day_pressed.connect(start_new_day)


## Remplace l'écran courant. L'ancien est libéré en fin de frame : il peut être à l'origine
## du signal qui déclenche le changement.
func _set_screen(scene: PackedScene) -> Control:
	if current_screen != null:
		current_screen.queue_free()
	current_screen = scene.instantiate() as Control
	add_child(current_screen)
	if _pause_overlay != null:
		move_child(_pause_overlay, -1)
	return current_screen


# --- Pause ---

func _pause() -> void:
	if day == null or day.current_session == null or _pause_overlay != null:
		return
	day.pause()
	_pause_overlay = PAUSE_OVERLAY.instantiate() as PauseOverlay
	add_child(_pause_overlay)
	_pause_overlay.resume_pressed.connect(_resume)


func _resume() -> void:
	day.resume()
	_pause_overlay.queue_free()
	_pause_overlay = null


func _show_error(errors: Array[String]) -> void:
	var label: Label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Could not load game data:\n" + "\n".join(PackedStringArray(errors))
	add_child(label)
	push_error(label.text)
