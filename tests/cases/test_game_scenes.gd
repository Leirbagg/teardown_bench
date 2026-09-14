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


func test_small_parts_get_a_48dp_touch_target() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var view: DeviceView = _device_view(state)
	var screw: Rect2 = view.view_rect(state.device.get_component("pentalobe_right"))
	assert_true(screw.size.x < DeviceView.MIN_TOUCH_TARGET, "préparation : la vis est plus petite que 48dp")
	var near_edge: Vector2 = screw.get_center() + Vector2(DeviceView.MIN_TOUCH_TARGET / 2.0 - 1.0, 0)
	assert_eq(view.component_at(near_edge), "pentalobe_right")
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


## Retire une vis par geste, force l'écran (fissure), puis répare et lance le test final.
func _play_repair(workbench: Workbench) -> void:
	var state: DisassemblyState = workbench.session.state
	var view: DeviceView = workbench.get_node("%DeviceView") as DeviceView
	view.gesture_started.emit("pentalobe_left")
	view.gesture_completed.emit("pentalobe_left")
	assert_true(state.is_removed("pentalobe_left"), "geste terminé → vis retirée")
	var tray: Container = workbench.get_node("%Tray") as Container
	assert_true(tray.get_children().any(func(child: Node) -> bool: return not child.is_queued_for_deletion()), "vis dans le bac")
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
