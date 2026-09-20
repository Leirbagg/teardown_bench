class_name Main
extends Control
## Enchaînement des écrans : accueil client → réparation → client suivant… → bilan.
## Suit les signaux de WorkDay ; le temps de jeu est transmis à core/ à chaque frame.

const MODEL_SELECT_SCREEN: PackedScene = preload("res://game/ui/model_select_screen.tscn")
const CUSTOMER_SCREEN: PackedScene = preload("res://game/ui/customer_screen.tscn")
const WORKBENCH: PackedScene = preload("res://game/workbench/workbench.tscn")
const DAY_REPORT_SCREEN: PackedScene = preload("res://game/ui/day_report_screen.tscn")
const PAUSE_OVERLAY: PackedScene = preload("res://game/ui/pause_overlay.tscn")
const DIAGNOSTICS_OVERLAY: PackedScene = preload("res://game/ui/diagnostics_overlay.tscn")

## Chemin de sauvegarde, remplaçable par les tests.
var save_path: String = SaveGame.PATH
var workshop: Workshop = Workshop.new()
var day: WorkDay
var current_screen: Control

## Marge minimale, même sans encoche : les coins arrondis rognent les bords.
const MIN_SAFE_MARGIN: int = 8

## Survit aux changements d'écran, pour ne pas couper un son en cours.
@onready var feedback: Feedback = %Feedback
## Les écrans vivent ici, à l'intérieur de la zone sûre de l'appareil.
@onready var screen_host: MarginContainer = %ScreenHost

var _catalog: DataCatalog
var _pause_overlay: PauseOverlay
var _diagnostics: DiagnosticsOverlay


func _ready() -> void:
	apply_safe_area()
	get_viewport().size_changed.connect(apply_safe_area)
	var errors: Array[String] = []
	_catalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	if _catalog == null:
		_show_error(errors)
		return
	var save_errors: Array[String] = []
	var saved: Dictionary = SaveGame.load_from(save_path, save_errors)
	if not save_errors.is_empty():
		push_warning("Sauvegarde ignorée : %s" % "\n".join(PackedStringArray(save_errors)))
	workshop = Workshop.from_dict(saved.get("workshop", {}))
	var resumed: WorkDay = SaveGame.restore_day(saved, _catalog, save_errors) if not saved.is_empty() else null
	if resumed != null:
		_begin_day(resumed)
	else:
		show_model_select()


## Choix du modèle de la journée. Une journée reprise depuis une sauvegarde ne repasse pas par
## là : son modèle est déjà décidé.
func show_model_select() -> ModelSelectScreen:
	var screen: ModelSelectScreen = _set_screen(MODEL_SELECT_SCREEN) as ModelSelectScreen
	screen.setup(_catalog.models)
	screen.model_chosen.connect(_on_model_chosen)
	return screen


func _on_model_chosen(model_id: String) -> void:
	var model: ModelCatalog.Model = _catalog.models.find(model_id)
	var device: DeviceDefinition = _catalog.find_device(model.teardown) if model != null else null
	if device == null:
		_show_error(["[unknown_ref] modèle '%s' : aucun démontage à ouvrir" % model_id])
		return
	start_new_day(device)


## Une journée entière sur le modèle choisi : ce sont les pannes qui varient, pas l'appareil.
func start_new_day(device: DeviceDefinition) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var errors: Array[String] = []
	var jobs: Array[RepairJob] = DayGenerator.generate([device], _catalog.faults, workshop.max_tier(), rng, errors)
	if not errors.is_empty():
		_show_error(errors)
		return
	_begin_day(WorkDay.new(jobs))


func _begin_day(new_day: WorkDay) -> void:
	day = new_day
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
	screen.setup(day.next_job(), day.next_job_number(), day.jobs.size(), workshop)
	screen.start_pressed.connect(_on_start_pressed)


func _on_start_pressed() -> void:
	var session: RepairSession = day.start_next_job()
	if session == null:
		return
	var workbench: Workbench = _set_screen(WORKBENCH) as Workbench
	workbench.setup(session, feedback)


func _on_job_completed(report: RepairReport) -> void:
	workshop.record_job(report)
	_save()
	if day.has_next_job():
		_show_next_customer()


func _on_day_completed(report: DayReport) -> void:
	workshop.finish_day()
	_save()
	var screen: DayReportScreen = _set_screen(DAY_REPORT_SCREEN) as DayReportScreen
	screen.setup(report, workshop)
	# Le lendemain, on rechoisit : c'est là que le joueur change de modèle.
	screen.new_day_pressed.connect(func() -> void: show_model_select())


## Remplace l'écran courant. L'ancien est libéré en fin de frame : il peut être à l'origine
## du signal qui déclenche le changement.
func _set_screen(scene: PackedScene) -> Control:
	if current_screen != null:
		current_screen.queue_free()
	current_screen = scene.instantiate() as Control
	screen_host.add_child(current_screen)
	for trigger: LongPressLabel in current_screen.find_children("*", "LongPressLabel", true, false):
		trigger.long_pressed.connect(show_diagnostics)
	if _pause_overlay != null:
		move_child(_pause_overlay, -1)
	return current_screen


## Écarte les écrans des bords : encoche, barre système et coins arrondis rognent l'affichage.
func apply_safe_area() -> void:
	# Sur ordinateur, la zone sûre est celle du bureau (dock compris) et n'a rien à voir avec la
	# fenêtre : seule la marge minimale s'applique.
	var safe: Rect2i = DisplayServer.get_display_safe_area() if OS.has_feature("mobile") else Rect2i()
	var insets: Vector4i = safe_area_insets(safe, DisplayServer.window_get_size(),
		get_viewport_rect().size, MIN_SAFE_MARGIN)
	screen_host.add_theme_constant_override("margin_left", insets.x)
	screen_host.add_theme_constant_override("margin_top", insets.y)
	screen_host.add_theme_constant_override("margin_right", insets.z)
	screen_host.add_theme_constant_override("margin_bottom", insets.w)


## Ce que l'appareil dit de lui-même, ouvert par un appui long sur le compteur ou le chrono :
## de quoi comprendre un souci d'affichage sur un vrai téléphone.
func show_diagnostics() -> DiagnosticsOverlay:
	if _diagnostics != null:
		return _diagnostics
	_diagnostics = DIAGNOSTICS_OVERLAY.instantiate() as DiagnosticsOverlay
	add_child(_diagnostics)
	_diagnostics.closed.connect(func() -> void: _diagnostics = null)
	_diagnostics.show_report(get_viewport_rect().size, applied_insets(), save_path)
	return _diagnostics


## Marges effectivement posées autour des écrans : gauche, haut, droite, bas.
func applied_insets() -> Vector4i:
	return Vector4i(
		screen_host.get_theme_constant("margin_left"),
		screen_host.get_theme_constant("margin_top"),
		screen_host.get_theme_constant("margin_right"),
		screen_host.get_theme_constant("margin_bottom"))


## Marges gauche, haut, droite, bas, en unités de la vue. `minimum` s'applique toujours.
static func safe_area_insets(safe: Rect2i, window: Vector2i, viewport: Vector2, minimum: int) -> Vector4i:
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4i(minimum, minimum, minimum, minimum)
	var scale: Vector2 = viewport / Vector2(window)
	return Vector4i(
		maxi(roundi(safe.position.x * scale.x), minimum),
		maxi(roundi(safe.position.y * scale.y), minimum),
		maxi(roundi((window.x - safe.end.x) * scale.x), minimum),
		maxi(roundi((window.y - safe.end.y) * scale.y), minimum))


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


func _save() -> void:
	var error: Error = SaveGame.save(save_path, workshop, day)
	if error != OK:
		push_warning("Sauvegarde impossible (%s) : %d" % [save_path, error])


func _show_error(errors: Array[String]) -> void:
	var label: Label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "Could not load game data:\n" + "\n".join(PackedStringArray(errors))
	add_child(label)
	push_error(label.text)
