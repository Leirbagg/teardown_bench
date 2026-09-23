extends TestSuite
## Tests de fumée des scènes de game/ : instanciées dans l'arbre, pilotées par leurs signaux.
## Les touchers réels ne sont pas simulés : en headless la fenêtre fait 0×0.

const MAIN_SCENE: PackedScene = preload("res://game/main.tscn")
const DEVICE_VIEW_SCENE: PackedScene = preload("res://game/workbench/device_view.tscn")


const TEST_SAVE_PATH: String = "user://test_scenes_save.json"


## Scène principale isolée : sa propre sauvegarde, effacée avant chaque test.
func _fresh_main() -> Main:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)
	var main: Main = MAIN_SCENE.instantiate() as Main
	main.save_path = TEST_SAVE_PATH
	_root().add_child(main)
	return main


## Journée déterministe sur un appareil choisi : depuis que les deux modèles tombent au hasard,
## un test qui nomme une pièce doit dire sur quel appareil il travaille.
func _main_on(device_id: String, fault_id: String, customers: int = 2) -> Main:
	var main: Main = _fresh_main()
	var errors: Array[String] = []
	var catalog: DataCatalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	var device: DeviceDefinition = null
	for candidate: DeviceDefinition in catalog.devices:
		if candidate.id == device_id:
			device = candidate
	assert_true(device != null, "appareil '%s' du catalogue" % device_id)
	var faults: Array[FaultDefinition] = [catalog.find_fault(fault_id)]
	# Plusieurs clients : une journée d'un seul client n'a rien à reprendre après sauvegarde.
	var jobs: Array[RepairJob] = []
	for i: int in customers:
		jobs.append(RepairJob.create("job_%d" % (i + 1), device, faults, "Complaint.", errors))
	assert_no_errors(errors)
	main._begin_day(WorkDay.new(jobs))
	return main


## Traverse l'écran de choix en prenant le premier modèle réellement démontable, comme le ferait
## un joueur qui veut commencer tout de suite.
func _choose_first_playable(main: Main) -> CustomerScreen:
	var screen: ModelSelectScreen = main.current_screen as ModelSelectScreen
	assert_true(screen != null, "on démarre sur le choix du modèle")
	if screen == null:
		return null
	var errors: Array[String] = []
	var catalog: ModelCatalog = ModelCatalog.load_from(ModelCatalog.PATH, errors)
	assert_no_errors(errors)
	var playable: Array[ModelCatalog.Model] = catalog.playable()
	assert_false(playable.is_empty(), "au moins un modèle se joue")
	screen.choose(playable[0].id)
	return main.current_screen as CustomerScreen


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _ipone_13_state() -> DisassemblyState:
	var errors: Array[String] = []
	var catalog: DataCatalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	for device: DeviceDefinition in catalog.devices:
		if device.id == "ipone_13":
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
	var state: DisassemblyState = _ipone_13_state()
	var view: DeviceView = _device_view(state)
	assert_eq(view.face, "front", "on commence côté écran")
	assert_eq(view.component_at(_center_of(view, "pentalobe_left")), "pentalobe_left", "vis au-dessus de l'écran")
	assert_eq(view.component_at(_center_of(view, "display")), "display")
	assert_eq(view.component_at(_center_of(view, "battery")), "display", "batterie cachée : on touche l'écran")
	assert_eq(view.component_at(Vector2(-10, -10)), "")
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	assert_eq(view.component_at(_center_of(view, "battery")), "battery")
	# Le haut-parleur passe par-dessus les languettes de batterie : le guide le dépose avant elles.
	assert_true(view.component_at(_center_of(view, "battery_tab_top_left")) != "battery_tab_top_left",
		"languette encore couverte par le haut-parleur")
	DisassemblyFixture.remove_with_prerequisites(state, "loudspeaker")
	assert_eq(view.component_at(_center_of(view, "battery_tab_top_left")), "battery_tab_top_left",
		"haut-parleur retiré : la languette se touche")
	assert_true(view.component_at(_center_of(view, "pentalobe_left")) != "pentalobe_left", "vis retirée : plus touchable")
	view.face = "back"
	assert_eq(view.component_at(_center_of(view, "battery")), "", "dos scellé : rien à toucher")
	view.free()


## Régression : en mouse_filter IGNORE, l'interface ne transmet jamais les touchers à la vue.
func test_device_view_receives_touches_through_gui_input() -> void:
	var state: DisassemblyState = _ipone_13_state()
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


## Le joint entoure l'écran : on le chauffe sur ses bords, on touche l'écran au milieu.
func test_the_seal_is_only_touchable_on_its_band() -> void:
	var state: DisassemblyState = _ipone_13_state()
	var view: DeviceView = _device_view(state)
	var screen: Rect2 = view.view_rect(state.device.get_component("display"))
	assert_eq(view.component_at(screen.get_center()), "display", "au milieu : l'écran")
	var on_band: Vector2 = Vector2(screen.get_center().x, screen.position.y + 4.0)
	assert_eq(view.component_at(on_band), "display_adhesive", "sur le bord : le joint")
	var seal: ComponentDefinition = state.device.get_component("display_adhesive")
	assert_true(PartPainter.frame_thickness(seal, view.view_rect(seal)) > 0.0, "dessiné en cadre")
	view.free()


## Pilier 2 : viser une pièce en plein centre ne doit jamais attraper sa voisine, même si la
## zone agrandie de la voisine, dessinée par-dessus, recouvre le doigt.
func test_touching_a_part_squarely_never_picks_its_overlapping_neighbour() -> void:
	var state: DisassemblyState = _ipone_13_state()
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


## Une nappe reste attachée à sa pièce : débranchée sur place, rebranchée par un geste.
func test_an_unplugged_connector_stays_next_to_its_socket_and_plugs_back() -> void:
	var state: DisassemblyState = _ipone_13_state()
	var view: DeviceView = _device_view(state)
	var completed: Array[String] = []
	view.gesture_completed.connect(func(id: String) -> void: completed.append(id))
	DisassemblyFixture.remove_with_prerequisites(state, "battery_connector")
	_settle(view)
	assert_true(view.is_unplugged("battery_connector"))
	var socket: Rect2 = view.view_rect(state.device.get_component("battery_connector"))
	var plug: Rect2 = view.unplugged_rect("battery_connector")
	assert_true(plug.position.x > socket.position.x, "tiré dans le sens du débranchement")
	assert_eq(view.component_at(plug.get_center()), "battery_connector", "touchable à sa place")

	var start: Vector2 = plug.get_center()
	view._gui_input(_touch(start, true))
	for step: int in range(1, 11):
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.position = start + Vector2(-10.0 * step, 0)
		view._gui_input(drag)
	view._gui_input(_touch(start + Vector2(-100, 0), false))
	assert_eq(completed, ["battery_connector"] as Array[String], "ramener la nappe vers son socle la rebranche")
	view.free()


## Une nappe suit sa pièce : l'écran parti sur le tapis, sa nappe quitte le socle et s'estompe.
func test_a_cable_follows_its_part_to_the_mat() -> void:
	var state: DisassemblyState = _ipone_13_state()
	var view: DeviceView = _device_view(state)
	DisassemblyFixture.remove_with_prerequisites(state, "display_connector")
	_settle(view)
	assert_true(view.is_unplugged("display_connector"), "écran rabattu : la nappe pend près de son socle")
	assert_false(view.is_cable_away("display_connector"))
	var near_socket: Rect2 = view.unplugged_rect("display_connector")
	DisassemblyFixture.remove_with_prerequisites(state, "sensor_connector")
	_settle(view)
	assert_true(view.is_cable_away("display_connector"), "écran détaché : la nappe part avec lui")
	var away: Rect2 = view.unplugged_rect("display_connector")
	assert_true(away.position.y > near_socket.position.y + 40.0, "tirée vers le tapis")
	assert_eq(view.component_at(away.get_center()), "display_connector", "toujours rebranchable")
	view.free()


## Le doigt fantôme du mode solution doit mener chaque type de geste à son terme.
func test_ghost_finger_completes_every_gesture_kind() -> void:
	var state: DisassemblyState = _ipone_13_state()
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
	var state: DisassemblyState = _ipone_13_state()
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
## Première pièce que le joueur peut retirer sur cet appareil : une vis si l'une est accessible,
## sinon n'importe quelle pièce libre (le dos collé du second modèle commence par son joint).
func _first_removable(state: DisassemblyState) -> String:
	var fallback: String = ""
	for component: ComponentDefinition in state.device.components:
		if state.query_remove(component.id).outcome != DisassemblyResult.Outcome.REMOVED:
			continue
		if component.kind == "screw":
			return component.id
		if fallback.is_empty():
			fallback = component.id
	return fallback


func _settle(view: DeviceView) -> void:
	for frame: int in 60:
		view._process(1.0 / 60.0)


func test_opened_display_is_shown_tethered_beside_the_device() -> void:
	var state: DisassemblyState = _ipone_13_state()
	var view: DeviceView = _device_view(state)
	var battery_before: Rect2 = view.view_rect(state.device.get_component("battery"))
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	_settle(view)
	assert_true(view.is_open_tethered("display"), "ouvert, encore tenu par ses nappes")
	var panel: Rect2 = view.open_panel_rect("display")
	var body: Rect2 = view.view_rect(state.device.get_component("display"))
	# Le côté dépend du modèle : ce 13 s'ouvre vers la droite, l'x et le 11 vers la gauche.
	var to_the_right: bool = str(state.device.get_component("display").visual["hinge"]) == "right"
	if to_the_right:
		assert_true(panel.position.x >= body.end.x - 1.0, "rabattu du côté de sa charnière")
		assert_true(view.view_rect(state.device.get_component("battery")).get_center().x < battery_before.get_center().x,
			"l'appareil se décale pour faire de la place")
	else:
		assert_true(panel.end.x <= body.position.x + 1.0, "rabattu du côté de sa charnière")
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
	var state: DisassemblyState = _ipone_13_state()
	var view: DeviceView = _device_view(state)
	var completed: Array[String] = []
	view.gesture_completed.connect(func(id: String) -> void: completed.append(id))
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	_settle(view)
	var start: Vector2 = view.open_panel_rect("display").get_center()
	# On referme en ramenant le panneau vers l'appareil, quel que soit le côté de la charnière.
	var toward: float = signf(view.view_rect(state.device.get_component("display")).get_center().x - start.x)
	view._gui_input(_touch(start, true))
	for step: int in range(1, 11):
		var drag: InputEventScreenDrag = InputEventScreenDrag.new()
		drag.position = start + Vector2(10.0 * step * toward, 0)
		view._gui_input(drag)
	view._gui_input(_touch(start + Vector2(100.0 * toward, 0), false))
	assert_eq(completed, ["display"] as Array[String], "tirer vers la charnière referme l'écran")
	view.free()


func test_workbench_closes_the_open_display_or_explains_what_to_reconnect() -> void:
	# L'écran rabattu comme un livre est propre au premier modèle : celui-ci se démonte entier.
	var main: Main = _main_on("ipone_13", "screen_cracked")
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
	var main: Main = _main_on("ipone_13", "screen_cracked")
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
	var state: DisassemblyState = _ipone_13_state()
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
	var main: Main = _main_on("ipone_13", "screen_cracked")
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
	var main: Main = _main_on("ipone_13", "screen_cracked")
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


## Rien ne doit être plus large que l'écran le plus étroit visé (360dp, CLAUDE.md) : sinon les
## rangées de boutons et les textes sortent de l'écran des deux côtés.
func test_no_screen_is_wider_than_the_narrowest_phone() -> void:
	const NARROWEST: float = 360.0
	var available: float = NARROWEST - 2.0 * Main.MIN_SAFE_MARGIN
	var main: Main = _fresh_main()
	var screens: Array[Control] = [main.current_screen]
	_choose_first_playable(main)
	screens.append(main.current_screen)
	(main.current_screen as CustomerScreen).start_pressed.emit()
	var workbench: Workbench = main.current_screen as Workbench
	screens.append(workbench)
	workbench.start_solution()
	screens.append(workbench.parts_mat)
	for screen: Control in screens:
		var minimum: float = screen.get_combined_minimum_size().x
		assert_true(minimum <= available, "%s : %.0f dp de large, %.0f disponibles" % [screen.name, minimum, available])
	for path: String in ["Margin/Layout/Tools", "Margin/Layout/MatBar", "Margin/Layout/SolutionBar"]:
		var row: Control = workbench.get_node(path)
		assert_true(row.get_combined_minimum_size().x <= available, "%s : %.0f dp" % [path, row.get_combined_minimum_size().x])
	main.free()


## Le total du haut ignore les réparations assistées : la ligne doit dire pourquoi elle n'y est
## pas, sinon le joueur croit ses casses mal comptées.
func test_the_day_report_marks_the_lines_that_do_not_count() -> void:
	var report: DayReport = DayReport.new()
	report.planned_jobs = 2
	report.jobs = [_repair_line(true, "display"), _repair_line(false, "battery")]
	var screen: DayReportScreen = preload("res://game/ui/day_report_screen.tscn").instantiate() as DayReportScreen
	_root().add_child(screen)
	screen.setup(report, Workshop.new())

	var summary: String = screen.get_node("%Summary").text
	assert_true(summary.contains("1 broken part(s)"), "seule la casse qui compte est au total : %s" % summary)
	assert_true(summary.contains("not counted in the totals"), "l'exclusion est annoncée")
	var lines: Array[Node] = screen.get_node("%Jobs").get_children()
	assert_eq(lines.size(), 2, "une ligne par client")
	assert_true((lines[0] as Label).text.contains("(not counted)"), "la ligne assistée le dit")
	assert_false((lines[1] as Label).text.contains("(not counted)"), "la ligne ordinaire compte")
	screen.free()


func _repair_line(assisted: bool, broken_part: String) -> RepairReport:
	var line: RepairReport = RepairReport.new()
	line.device_id = "ipone_13"
	line.completed = true
	line.assisted = assisted
	line.deadline_met = true
	line.elapsed_s = 60.0
	line.deadline_s = 120.0
	line.broken_parts = PackedStringArray([broken_part])
	line.stars = 0 if assisted else 4
	return line


## Sur le téléphone, un souci d'affichage ne se décrit pas : l'appareil le dit lui-même.
func test_a_long_press_opens_the_diagnostics_from_any_screen() -> void:
	var main: Main = _fresh_main()
	var counter: LongPressLabel = main.current_screen.find_children("*", "LongPressLabel", true, false)[0]
	counter._gui_input(_touch(Vector2.ZERO, true))
	counter._process(LongPressLabel.HOLD_S / 2.0)
	assert_true(main._diagnostics == null, "un appui court ne l'ouvre pas")
	counter._process(LongPressLabel.HOLD_S)
	var overlay: DiagnosticsOverlay = main._diagnostics
	assert_true(overlay != null, "ouvert après l'appui long")

	var report: String = DiagnosticsOverlay.report(Vector2(360, 720), Vector2i(1080, 2160),
		Rect2i(0, 90, 1080, 2010), Vector4i(8, 30, 8, 20), TEST_SAVE_PATH)
	assert_true(report.contains("360 × 720"), "taille de la vue")
	assert_true(report.contains("left 8, top 30"), "marges appliquées")
	# Un testeur doit pouvoir dire quelle version il a en main : elle est gravée à la construction.
	assert_true(report.contains(DiagnosticsOverlay.app_version()), "version du jeu : %s" % report)
	assert_false(DiagnosticsOverlay.app_version().is_empty(), "jamais vide, même hors build")

	overlay._close_button.pressed.emit()
	assert_true(main._diagnostics == null, "refermé")

	# L'établi expose le même accès, sur le chrono.
	_choose_first_playable(main)
	(main.current_screen as CustomerScreen).start_pressed.emit()
	assert_eq(main.current_screen.find_children("*", "LongPressLabel", true, false).size(), 1, "chrono de l'établi")
	main.free()


## L'encoche et les coins arrondis rogneaient les bords sur un vrai téléphone.
func test_screens_keep_a_margin_inside_the_safe_area() -> void:
	var main: Main = _fresh_main()
	assert_eq(main.current_screen.get_parent(), main.screen_host, "les écrans vivent dans la zone sûre")
	for side: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		assert_true(main.screen_host.get_theme_constant(side) >= Main.MIN_SAFE_MARGIN, side)

	# Encoche de 90 px en haut et barre de 60 px en bas, sur une fenêtre de 1080×2160 → vue 360×720.
	var insets: Vector4i = Main.safe_area_insets(Rect2i(0, 90, 1080, 2010), Vector2i(1080, 2160), Vector2(360, 720), 8)
	assert_eq(insets, Vector4i(8, 30, 8, 20), "converties dans les unités de la vue")
	assert_eq(Main.safe_area_insets(Rect2i(), Vector2i(), Vector2(360, 720), 8), Vector4i(8, 8, 8, 8),
		"sans information, la marge minimale")
	main.free()


# --- Progression et sauvegarde ---

## Répare le client en cours par les mêmes appels que le joueur, puis lance le test final.
func _finish_current_job(main: Main, seconds: float) -> void:
	(main.current_screen as CustomerScreen).start_pressed.emit()
	var workbench: Workbench = main.current_screen as Workbench
	workbench.session.advance(seconds)
	DisassemblyFixture.repair_faults(workbench.session.state, workbench.session.job.faults)
	assert_true(workbench.session.run_final_test().is_passed(), "préparation : réparation réussie")


func test_a_finished_client_pays_and_the_day_is_saved_then_resumed() -> void:
	var main: Main = _main_on("ipone_13", "screen_cracked")
	var job_count: int = main.day.jobs.size()
	var money_before: int = main.workshop.money
	_finish_current_job(main, 60.0)
	assert_true(main.workshop.money > money_before, "le client paie plus que la pièce")
	assert_eq(main.workshop.jobs_done(), 1)
	assert_true(main.workshop.reputation() > 0.0)
	assert_true(FileAccess.file_exists(TEST_SAVE_PATH), "sauvegardé après le client")
	var saved_money: int = main.workshop.money
	main.free()

	var resumed: Main = MAIN_SCENE.instantiate() as Main
	resumed.save_path = TEST_SAVE_PATH
	_root().add_child(resumed)
	assert_eq(resumed.workshop.money, saved_money, "argent retrouvé")
	assert_eq(resumed.workshop.jobs_done(), 1)
	assert_eq(resumed.day.jobs.size(), job_count - 1, "la journée reprend où elle s'était arrêtée")
	assert_eq(resumed.day.report().jobs.size(), 1, "le client servi reste au bilan")
	assert_true((resumed.current_screen as CustomerScreen) != null)
	resumed.free()


func test_a_new_day_starts_after_the_last_client() -> void:
	var main: Main = _main_on("ipone_13", "screen_cracked")
	var day_before: int = main.workshop.day
	while not main.day.is_over():
		_finish_current_job(main, 30.0)
	var report: DayReportScreen = main.current_screen as DayReportScreen
	assert_true(report != null, "bilan de fin de journée")
	assert_eq(main.workshop.day, day_before + 1)
	# Le lendemain repasse par le choix du modèle : on peut changer de téléphone.
	report.new_day_pressed.emit()
	assert_true((main.current_screen as ModelSelectScreen) != null, "on rechoisit un modèle")
	assert_true(_choose_first_playable(main) != null, "puis le client suivant se présente")
	main.free()

	var next_launch: Main = MAIN_SCENE.instantiate() as Main
	next_launch.save_path = TEST_SAVE_PATH
	_root().add_child(next_launch)
	assert_eq(next_launch.workshop.day, day_before + 1, "on reprend au jour suivant")
	# La journée sauvegardée était terminée : on ne reprend rien, on rechoisit un modèle.
	assert_true((next_launch.current_screen as ModelSelectScreen) != null, "retour au choix du modèle")
	assert_true(_choose_first_playable(next_launch) != null, "puis le premier client arrive")
	assert_eq(next_launch.day.jobs.size(), Main.CUSTOMERS_PER_VISIT, "une réparation par passage au menu")
	next_launch.free()


## La gamme entière est présentée, mais on ne peut ouvrir que ce qui est démontable.
func test_the_model_picker_shows_the_whole_line_up_and_opens_only_what_exists() -> void:
	var main: Main = _fresh_main()
	var screen: ModelSelectScreen = main.current_screen as ModelSelectScreen
	assert_true(screen != null, "le jeu s'ouvre sur le choix du modèle")
	var errors: Array[String] = []
	var catalog: ModelCatalog = ModelCatalog.load_from(ModelCatalog.PATH, errors)
	assert_no_errors(errors)

	for model: ModelCatalog.Model in catalog.models:
		var button: Button = screen.button_for(model.id)
		assert_true(button != null, "%s : une ligne dans la liste" % model.id)
		if button == null:
			continue
		assert_true(model.name in button.text, "%s : son nom est lisible" % model.id)
		assert_eq(button.disabled, not model.is_playable(), "%s : ouvrable seulement s'il est démontable" % model.id)
		assert_true(button.custom_minimum_size.y >= 48.0, "%s : cible tactile" % model.id)
		if not model.is_playable():
			assert_true("soon" in button.text, "%s : on dit pourquoi il ne s'ouvre pas" % model.id)

	var chosen: Array[String] = []
	screen.model_chosen.connect(func(id: String) -> void: chosen.append(id))
	var playable: ModelCatalog.Model = catalog.playable()[0]
	screen.choose(playable.id)
	assert_eq(chosen, [playable.id] as Array[String], "choisir un modèle l'annonce")
	var customer: CustomerScreen = main.current_screen as CustomerScreen
	assert_true(customer != null, "et le premier client se présente")
	assert_eq(main.day.jobs[0].device.id, playable.teardown, "la journée porte sur le modèle choisi")
	main.free()


## Une journée ne mélange pas les modèles : on a choisi un téléphone, on le garde.
func test_a_day_stays_on_the_chosen_model() -> void:
	var main: Main = _fresh_main()
	_choose_first_playable(main)
	var first: String = main.day.jobs[0].device.id
	for job: RepairJob in main.day.jobs:
		assert_eq(job.device.id, first, "tous les clients apportent le même modèle")
	main.free()


# --- Enchaînement complet ---

func test_main_plays_a_full_day_through_screen_signals() -> void:
	var main: Main = _fresh_main()
	_choose_first_playable(main)
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


## Retire la première pièce accessible par geste, force l'écran (fissure), puis répare et lance
## le test final. Rien de codé en dur : la journée tire l'un ou l'autre appareil au hasard.
func _play_repair(workbench: Workbench) -> void:
	var state: DisassemblyState = workbench.session.state
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	var first: String = _first_removable(state)
	assert_false(first.is_empty(), "%s : une pièce à retirer" % state.device.id)
	view.gesture_started.emit(first)
	view.gesture_completed.emit(first)
	assert_true(state.is_removed(first), "geste terminé → %s retirée" % first)
	assert_true(workbench.parts_mat.item_count() > 0, "pièce posée sur le tapis")
	var screen: String = state.device.component_for_role("screen").id
	view.gesture_completed.emit(screen)
	assert_true(state.is_broken(screen), "écran forcé sans chauffer → cassé")
	(workbench.get_node("%TestsButton") as Button).pressed.emit()
	assert_true((workbench.get_node("%InfoPanel") as Control).visible, "résultats des tests affichés")
	(workbench.get_node("%InfoCloseButton") as Button).pressed.emit()
	(workbench.get_node("%FinalTestButton") as Button).pressed.emit()
	assert_false(workbench.session.is_completed(), "appareil ouvert : pas de fin")
	DisassemblyFixture.replace_part(state, screen)
	assert_true(screen in state.replaced_ids(), "nappes débranchées, capteurs transférés → écran remplacé")
	assert_false(state.is_broken("front_sensors"), "les capteurs n'ont pas été perdus en route")
	DisassemblyFixture.repair_faults(state, workbench.session.job.faults)
	(workbench.get_node("%FinalTestButton") as Button).pressed.emit()
	assert_true(workbench.session.is_completed(), "réparation terminée")


## Les capteurs sont montés sur l'écran : quand il se rabat, ils partent avec lui, et c'est là
## qu'on va les chercher pour les transférer.
func test_front_sensors_travel_with_the_open_screen() -> void:
	var state: DisassemblyState = _ipone_13_state()
	var view: DeviceView = _device_view(state)
	var sensors: ComponentDefinition = state.device.get_component("front_sensors")
	var closed: Rect2 = view.view_rect(sensors)
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	_settle(view)
	assert_true(view.is_open_tethered("display"), "préparation : écran rabattu sur le côté")

	var opened: Rect2 = view.view_rect(sensors)
	assert_true(absf(opened.get_center().x - closed.get_center().x) > 20.0, "les capteurs ont suivi le panneau")
	assert_true(view.open_panel_rect("display").grow(8.0).encloses(opened), "posés sur le panneau ouvert")
	assert_eq(view.component_at(opened.get_center()), "front_sensors", "et se touchent là où on les voit")
	assert_eq(view.component_at(view.open_panel_rect("display").position + Vector2(4.0, 4.0)), "display",
		"le reste du panneau referme toujours l'écran")
	view.free()


## Une réparation, puis le menu : plus d'enchaînement de clients dans une journée.
func test_a_repair_sends_you_back_to_the_model_menu() -> void:
	var main: Main = _fresh_main()
	_choose_first_playable(main)
	assert_eq(main.day.jobs.size(), 1, "un seul client par passage")
	_finish_current_job(main, 30.0)
	var report: DayReportScreen = main.current_screen as DayReportScreen
	assert_true(report != null, "le bilan de la réparation s'affiche")
	if report != null:
		assert_eq((report.get_node("%Title") as Label).text, "Repair done", "il parle de réparation, pas de journée")
		assert_true((report.get_node("%NewDayButton") as Button).text.contains("model"), "et renvoie au choix du modèle")
		report.new_day_pressed.emit()
	assert_true((main.current_screen as ModelSelectScreen) != null, "retour au menu des modèles")
	main.free()


## Régression : sur le téléphone, la liste ne défilait pas. Un bouton en MOUSE_FILTER_STOP avale
## le glissement du doigt, qui n'atteint jamais le conteneur — vérifié dans une vraie fenêtre :
## en STOP le défilement reste à zéro, en PASS il suit le doigt.
func test_the_model_rows_let_the_drag_through_to_the_list() -> void:
	var main: Main = _fresh_main()
	var screen: ModelSelectScreen = main.current_screen as ModelSelectScreen
	var errors: Array[String] = []
	var catalog: ModelCatalog = ModelCatalog.load_from(ModelCatalog.PATH, errors)
	assert_no_errors(errors)
	for model: ModelCatalog.Model in catalog.models:
		var row: Button = screen.button_for(model.id)
		assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS,
			"%s : la ligne doit laisser passer le glissement, sinon la liste ne défile plus" % model.id)
	var scroll: ScrollContainer = screen.get_node("Margin/Layout/Scroll") as ScrollContainer
	assert_true(scroll.scroll_deadzone > 0, "une petite zone morte évite qu'un tremblement fasse défiler")
	main.free()


## Le tap n'est plus celui du bouton : on le reconnaît nous-mêmes, et un glissement ne doit
## jamais valoir un choix.
func test_a_tap_picks_a_model_but_a_drag_does_not() -> void:
	var main: Main = _fresh_main()
	var screen: ModelSelectScreen = main.current_screen as ModelSelectScreen
	var chosen: Array[String] = []
	screen.model_chosen.connect(func(id: String) -> void: chosen.append(id))
	var errors: Array[String] = []
	var catalog: ModelCatalog = ModelCatalog.load_from(ModelCatalog.PATH, errors)
	assert_no_errors(errors)
	var playable: String = catalog.playable()[0].id

	# Doigt qui glisse : la liste défile, rien n'est choisi.
	screen._on_row_input(_touch(Vector2(40, 20), true), playable)
	var drag: InputEventScreenDrag = InputEventScreenDrag.new()
	drag.relative = Vector2(0, -ModelSelectScreen.TAP_TOLERANCE * 2.0)
	screen._on_row_input(drag, playable)
	screen._on_row_input(_touch(Vector2(40, 20), false), playable)
	assert_eq(chosen, [] as Array[String], "glisser ne choisit pas un modèle")

	# Doigt qui tape : le modèle est choisi.
	screen._on_row_input(_touch(Vector2(40, 20), true), playable)
	screen._on_row_input(_touch(Vector2(40, 20), false), playable)
	assert_eq(chosen, [playable] as Array[String], "taper choisit le modèle")
	main.free()
