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
	assert_eq(view.face, "front", "on commence côté écran")
	assert_eq(view.component_at(_center_of(view, "pentalobe_left")), "pentalobe_left", "vis au-dessus de l'écran")
	assert_eq(view.component_at(_center_of(view, "display")), "display")
	assert_eq(view.component_at(_center_of(view, "battery")), "display", "batterie cachée : on touche l'écran")
	assert_eq(view.component_at(Vector2(-10, -10)), "")
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	assert_eq(view.component_at(_center_of(view, "battery")), "battery")
	assert_eq(view.component_at(_center_of(view, "battery_tab_top_left")), "battery_tab_top_left", "languette au-dessus de la batterie")
	assert_true(view.component_at(_center_of(view, "pentalobe_left")) != "pentalobe_left", "vis retirée : plus touchable")
	view.face = "back"
	assert_eq(view.component_at(_center_of(view, "battery")), "", "dos scellé : rien à toucher")
	view.free()


## Régression : en mouse_filter IGNORE, l'interface ne transmet jamais les touchers à la vue.
func test_device_view_receives_touches_through_gui_input() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	assert_eq(view.mouse_filter, Control.MOUSE_FILTER_STOP, "la vue doit capter les touchers")
	var completed: Array[String] = []
	view.gesture_completed.connect(func(id: String) -> void: completed.append(id))
	DisassemblyFixture.remove_with_prerequisites(state, "connector_cover")
	var start: Vector2 = _center_of(view, "battery_connector")
	view._gui_input(_touch(start, true))
	for step: int in range(1, 11):
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.position = start + Vector2(10.0 * step, 0)
		view._gui_input(drag)
	view._gui_input(_touch(start + Vector2(100, 0), false))
	assert_eq(completed, ["battery_connector"] as Array[String], "tirer vers la droite débranche la batterie")
	view.free()


func _touch(position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.position = position
	touch.pressed = pressed
	return touch


## Pilier 2 : viser une pièce en plein centre ne doit jamais attraper sa voisine, même si la
## zone agrandie de la voisine, dessinée par-dessus, recouvre le doigt.
func test_touching_a_part_squarely_never_picks_its_overlapping_neighbour() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	DisassemblyFixture.remove_with_prerequisites(state, "connector_cover")
	var battery_connector: Rect2 = view.view_rect(state.device.get_component("battery_connector"))
	var display_connector: Rect2 = view.view_rect(state.device.get_component("display_connector"))
	assert_true(DeviceView._touch_rect(display_connector).has_point(battery_connector.get_center()),
		"préparation : les zones de toucher se chevauchent")
	assert_eq(view.component_at(battery_connector.get_center()), "battery_connector")
	assert_eq(view.component_at(display_connector.get_center()), "display_connector")
	var between_but_closer_to_battery: Vector2 = battery_connector.get_center().lerp(display_connector.get_center(), 0.3)
	if not battery_connector.has_point(between_but_closer_to_battery) and not display_connector.has_point(between_but_closer_to_battery):
		assert_eq(view.component_at(between_but_closer_to_battery), "battery_connector", "hors des pièces : la plus proche")
	view.free()


## Le doigt fantôme du mode solution doit mener chaque type de geste à son terme.
func test_ghost_finger_completes_every_gesture_kind() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	var completed: Array[String] = []
	var steps: Array[int] = [0]
	view.gesture_completed.connect(func(id: String) -> void:
		completed.append(id)
		state.commit_remove(id))
	view.gesture_step.connect(func(_id: String, _step: int, _count: int) -> void: steps[0] += 1)
	var ids: Array[String] = ["pentalobe_left", "pentalobe_right", "display_adhesive", "display", "cover_screw_1",
		"cover_screw_2", "cover_screw_3", "connector_cover", "battery_connector"]
	for i: int in ids.size():
		var id: String = ids[i]
		var gesture: String = state.device.get_component(id).gesture
		view.start_ghost(id, 1.0 if i % 2 == 0 else 2.0)
		assert_true(view.is_ghost_running(), id)
		for frame: int in 400:
			if not view.is_ghost_running():
				break
			view._process(1.0 / 60.0)
		assert_false(view.is_ghost_running(), "%s (%s) : geste fantôme terminé" % [id, gesture])
		assert_true(state.is_removed(id), "%s (%s) : pièce retirée" % [id, gesture])
	assert_eq(completed.size(), 9)
	assert_true(steps[0] > 9, "des crans pendant les gestes")
	view.free()


func test_ghost_can_be_finished_early_or_stopped() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	var completed: Array[String] = []
	view.gesture_completed.connect(func(id: String) -> void: completed.append(id))
	view.start_ghost("display_adhesive", 2.0)
	view._process(0.1)
	view.finish_ghost()
	assert_false(view.is_ghost_running())
	assert_eq(completed, ["display_adhesive"] as Array[String], "fin immédiate, geste réussi")
	view.start_ghost("pentalobe_left")
	view._process(0.1)
	view.stop_ghost()
	for frame: int in 120:
		view._process(1.0 / 60.0)
	assert_eq(completed.size(), 1, "arrêté : pas de retrait")
	view.free()


## Laisse les animations (ouverture, décalage de l'appareil) aller au bout.
func _settle(view: DeviceView) -> void:
	for frame: int in 60:
		view._process(1.0 / 60.0)


func test_opened_display_is_shown_tethered_beside_the_device() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	var battery_before: Rect2 = view.view_rect(state.device.get_component("battery"))
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	_settle(view)
	assert_true(view.is_open_tethered("display"), "ouvert, encore tenu par ses nappes")
	var panel: Rect2 = view.open_panel_rect("display")
	var body: Rect2 = view.view_rect(state.device.get_component("display"))
	assert_true(panel.end.x <= body.position.x + 1.0, "rabattu à gauche, côté charnière")
	assert_true(view.view_rect(state.device.get_component("battery")).get_center().x > battery_before.get_center().x,
		"l'appareil se décale pour faire de la place")
	assert_true(panel.position.x >= 0.0, "le panneau reste dans la vue")
	assert_eq(view.component_at(panel.get_center()), "display", "on peut toucher l'écran ouvert")

	DisassemblyFixture.remove_with_prerequisites(state, "display_connector")
	assert_true(view.is_open_tethered("display"), "encore tenu par la nappe des capteurs")
	DisassemblyFixture.remove_with_prerequisites(state, "sensor_connector")
	_settle(view)
	assert_false(view.is_open_tethered("display"), "détaché : il quitte la position ouverte")
	assert_true(view.component_at(view.open_panel_rect("display").get_center()) != "display")
	view.free()


func test_pulling_the_open_display_toward_the_device_closes_it() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	var completed: Array[String] = []
	view.gesture_completed.connect(func(id: String) -> void: completed.append(id))
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	_settle(view)
	var start: Vector2 = view.open_panel_rect("display").get_center()
	view._gui_input(_touch(start, true))
	for step: int in range(1, 11):
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.position = start + Vector2(10.0 * step, 0)
		view._gui_input(drag)
	view._gui_input(_touch(start + Vector2(100, 0), false))
	assert_eq(completed, ["display"] as Array[String], "tirer vers la charnière referme l'écran")
	view.free()


func test_workbench_closes_the_open_display_or_explains_what_to_reconnect() -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	_root().add_child(main)
	(main.current_screen as CustomerScreen).start_pressed.emit()
	var workbench: Workbench = main.current_screen as Workbench
	var state: DisassemblyState = workbench.session.state
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	DisassemblyFixture.remove_with_prerequisites(state, "display_connector")
	view.gesture_started.emit("display")
	view.gesture_completed.emit("display")
	assert_true(state.is_removed("display"), "nappe débranchée : on ne referme pas")
	assert_true((workbench.get_node("%Status") as Label).text.begins_with("Reinstall first"), "le jeu dit quoi rebrancher")
	assert_eq(state.broken_ids(), PackedStringArray(), "sans pénalité")
	for id: String in ["display_connector", "battery_connector", "connector_cover"]:
		assert_eq(state.commit_install(id).outcome, DisassemblyResult.Outcome.INSTALLED, "préparation : " + id)
	for screw: String in ["cover_screw_1", "cover_screw_2", "cover_screw_3"]:
		state.commit_install(screw)
	view.gesture_completed.emit("display")
	assert_false(state.is_removed("display"), "tout rebranché : l'écran se referme")
	main.free()


func test_workbench_mat_reinstalls_parts_and_hands_back_control() -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	_root().add_child(main)
	(main.current_screen as CustomerScreen).start_pressed.emit()
	var workbench: Workbench = main.current_screen as Workbench
	var state: DisassemblyState = workbench.session.state
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	view.gesture_completed.emit("pentalobe_left")
	var mat_button: Button = workbench.get_node("%MatButton") as Button
	assert_true(mat_button.text.begins_with("Mat · 1"), "compteur du tapis : " + mat_button.text)
	mat_button.pressed.emit()
	assert_true(workbench.parts_mat.visible)
	assert_false(view.input_enabled, "tapis ouvert : pas de geste sur l'appareil")
	workbench.parts_mat.reinstall_requested.emit("pentalobe_left")
	assert_false(state.is_removed("pentalobe_left"), "remontée depuis le tapis")
	assert_true((workbench.parts_mat.get_node("%MatInfo") as Label).text.begins_with("Reinstalled"), "message visible sur le tapis")
	(workbench.parts_mat.get_node("%MatCloseButton") as Button).pressed.emit()
	assert_false(workbench.parts_mat.visible)
	assert_true(view.input_enabled, "tapis fermé : on reprend les gestes")
	main.free()


func test_small_parts_get_a_48dp_touch_target() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	var screw: Rect2 = view.view_rect(state.device.get_component("pentalobe_right"))
	assert_true(screw.size.x < DeviceView.MIN_TOUCH_TARGET, "préparation : la vis est plus petite que 48dp")
	var near_edge: Vector2 = screw.get_center() + Vector2(DeviceView.MIN_TOUCH_TARGET / 2.0 - 1.0, 0)
	assert_eq(view.component_at(near_edge), "pentalobe_right")
	view.free()


# --- Mode solution ---

## Fait tourner le lecteur et la vue comme des frames, jusqu'à l'arrêt du lecteur.
func _run_solution(workbench: Workbench, max_frames: int = 20000) -> void:
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	for frame: int in max_frames:
		if not workbench.solution_player.is_running():
			return
		workbench.solution_player.advance(1.0 / 30.0)
		view._process(1.0 / 30.0)


func test_solution_mode_repairs_from_a_damaged_state_and_marks_the_job_assisted() -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	_root().add_child(main)
	(main.current_screen as CustomerScreen).start_pressed.emit()
	var workbench: Workbench = main.current_screen as Workbench
	var session: RepairSession = workbench.session
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	view.gesture_completed.emit("display")
	assert_true(session.state.is_broken("display"), "préparation : écran forcé et cassé par le joueur")

	var captions: Array[String] = []
	workbench.solution_player.step_started.connect(func(_i: int, _n: int, caption: String) -> void: captions.append(caption))
	(workbench.get_node("%SolutionButton") as Button).pressed.emit()
	assert_true(workbench.solution_player.is_running())
	assert_true(session.is_assisted())
	assert_false(view.input_enabled, "le joueur ne touche pas pendant la démo")
	assert_true((workbench.get_node("%SolutionBar") as Control).visible)
	workbench.solution_player.speed = 4.0
	_run_solution(workbench)

	assert_true(session.is_completed(), "test final réussi à la fin de la démo")
	assert_eq(session.state.broken_ids(), PackedStringArray(), "l'écran cassé a été remplacé")
	assert_true(captions.any(func(caption: String) -> bool: return caption.begins_with("Always disconnect the battery first")),
		"les explications viennent des hints")
	assert_true(captions.all(func(caption: String) -> bool: return not caption.is_empty()))
	assert_true(main.day.report().jobs[0].assisted)
	main.free()


func test_solution_mode_can_be_stopped_to_take_over() -> void:
	var main: Main = MAIN_SCENE.instantiate() as Main
	_root().add_child(main)
	(main.current_screen as CustomerScreen).start_pressed.emit()
	var workbench: Workbench = main.current_screen as Workbench
	(workbench.get_node("%SolutionButton") as Button).pressed.emit()
	_run_solution(workbench, 90)
	(workbench.get_node("%SolutionStopButton") as Button).pressed.emit()
	assert_false(workbench.solution_player.is_running())
	assert_true((workbench.get_node("%DeviceView") as DeviceView).input_enabled, "le joueur reprend la main")
	assert_false((workbench.get_node("%SolutionBar") as Control).visible)
	assert_true(workbench.session.is_assisted(), "reste assistée")
	assert_false(workbench.session.is_completed())
	main.free()


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


## Retire une vis par geste, force l'écran (fissure), puis répare et lance le test final.
func _play_repair(workbench: Workbench) -> void:
	var state: DisassemblyState = workbench.session.state
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	view.gesture_started.emit("pentalobe_left")
	view.gesture_completed.emit("pentalobe_left")
	assert_true(state.is_removed("pentalobe_left"), "geste terminé → vis retirée")
	assert_true(workbench.parts_mat.item_count() > 0, "vis posée sur le tapis")
	view.gesture_completed.emit("display")
	assert_true(state.is_broken("display"), "écran forcé sans chauffer → cassé")
	(workbench.get_node("%TestsButton") as Button).pressed.emit()
	assert_true((workbench.get_node("%InfoPanel") as Control).visible, "résultats des tests affichés")
	(workbench.get_node("%InfoCloseButton") as Button).pressed.emit()
	(workbench.get_node("%FinalTestButton") as Button).pressed.emit()
	assert_false(workbench.session.is_completed(), "appareil ouvert : pas de fin")
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	for attached: String in state.device.get_component("display").replace_requires:
		DisassemblyFixture.remove_with_prerequisites(state, attached)
	assert_eq(state.replace("display").outcome, DisassemblyResult.Outcome.REPLACED, "nappes débranchées → écran remplacé")
	DisassemblyFixture.repair_faults(state, workbench.session.job.faults)
	(workbench.get_node("%FinalTestButton") as Button).pressed.emit()
	assert_true(workbench.session.is_completed(), "réparation terminée")
