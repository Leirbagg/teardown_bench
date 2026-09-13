extends TestSuite
## Tests de fumée des scènes de game/ : instanciées dans l'arbre, pilotées par leurs signaux.
## Les touchers réels ne sont pas simulés : en headless la fenêtre fait 0×0.

const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")
const DEVICE_VIEW_SCENE: PackedScene = preload("res://game/workbench/device_view.tscn")


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _starter_phone_state() -> DisassemblyState:
	var errors: Array[String] = []
	var catalog: DataCatalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	for device: DeviceDefinition in catalog.devices:
		if device.id == "starter_phone":
			return DisassemblyState.new(device)
	return null


func _device_view(state: DisassemblyState) -> DeviceView:
	var view: DeviceView = DEVICE_VIEW_SCENE.instantiate() as DeviceView
	_root().add_child(view)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(360, 420)
	view.setup(state)
	return view


func _center_of(view: DeviceView, component_id: String) -> Vector2:
	return view.view_rect(view._state.device.get_component(component_id)).get_center()


# --- Vue de l'appareil ---

func test_device_view_hits_topmost_visible_part() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	view.face = "back"
	assert_eq(view.component_at(_center_of(view, "back_screw_l")), "back_screw_l", "vis au-dessus du cache")
	assert_eq(view.component_at(_center_of(view, "back_cover")), "back_cover")
	assert_eq(view.component_at(_center_of(view, "battery")), "back_cover", "batterie cachée : on touche le cache")
	assert_eq(view.component_at(Vector2(-10, -10)), "")
	DisassemblyFixture.remove_with_prerequisites(state, "back_cover")
	assert_eq(view.component_at(_center_of(view, "battery")), "battery")
	assert_eq(view.component_at(_center_of(view, "battery_connector")), "battery_connector", "connecteur au-dessus de la batterie")
	assert_eq(view.component_at(_center_of(view, "back_screw_l")), "", "vis retirée")
	view.face = "front"
	assert_eq(view.component_at(_center_of(view, "screen")), "screen")
	view.free()


func test_small_parts_get_a_48dp_touch_target() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	view.face = "back"
	var screw: Rect2 = view.view_rect(state.device.get_component("back_screw_r"))
	assert_true(screw.size.x < DeviceView.MIN_TOUCH_TARGET, "préparation : la vis est plus petite que 48dp")
	var near_edge: Vector2 = screw.get_center() + Vector2(DeviceView.MIN_TOUCH_TARGET / 2.0 - 1.0, 0)
	assert_eq(view.component_at(near_edge), "back_screw_r")
	view.free()


# --- Enchaînement complet ---

func test_main_plays_a_full_day_through_screen_signals() -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	_root().add_child(main)
	assert_true(main.day != null, "journée générée depuis data/")
	if main.day == null:
		main.free()
		return
	var job_count: int = main.day.jobs.size()
	for i: int in job_count:
		var customer: CustomerScreen = main.current_screen as CustomerScreen
		assert_true(customer != null, "client %d : écran d'accueil" % (i + 1))
		if customer == null:
			break
		customer.start_pressed.emit()
		var workbench: Workbench = main.current_screen as Workbench
		assert_true(workbench != null, "client %d : établi" % (i + 1))
		if workbench == null:
			break
		_play_repair(workbench)
	var report_screen: DayReportScreen = main.current_screen as DayReportScreen
	assert_true(report_screen != null, "bilan affiché en fin de journée")
	assert_eq(main.day.report().completed_jobs(), job_count)
	main.free()


## Retire une vis par geste, force le cache (casse), puis répare et lance le test final.
func _play_repair(workbench: Workbench) -> void:
	var state: DisassemblyState = workbench.session.state
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	view.gesture_started.emit("back_screw_l")
	view.gesture_completed.emit("back_screw_l")
	assert_true(state.is_removed("back_screw_l"), "geste terminé → vis retirée")
	var tray: HFlowContainer = workbench.get_node("%Tray") as HFlowContainer
	assert_true(tray.get_children().any(func(child: Node) -> bool: return not child.is_queued_for_deletion()), "vis dans le bac")
	view.gesture_completed.emit("back_cover")
	assert_true(state.is_broken("back_cover"), "cache forcé → cassé")
	(workbench.get_node("%TestsButton") as Button).pressed.emit()
	assert_true((workbench.get_node("%InfoPanel") as Control).visible, "résultats des tests affichés")
	(workbench.get_node("%InfoCloseButton") as Button).pressed.emit()
	(workbench.get_node("%FinalTestButton") as Button).pressed.emit()
	assert_false(workbench.session.is_completed(), "appareil ouvert : pas de fin")
	DisassemblyFixture.remove_with_prerequisites(state, "back_cover")
	state.replace("back_cover")
	DisassemblyFixture.repair_faults(state, workbench.session.job.faults)
	(workbench.get_node("%FinalTestButton") as Button).pressed.emit()
	assert_true(workbench.session.is_completed(), "réparation terminée")
