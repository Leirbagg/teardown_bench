extends TestSuite
## Tapis magnétique : pièces détachées à leur emplacement d'origine, sélection au doigt.

const PARTS_MAT_SCENE: PackedScene = preload("res://game/workbench/parts_mat.tscn")


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _starter_phone_state() -> DisassemblyState:
	var errors: Array[String] = []
	var catalog: DataCatalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	return DisassemblyState.new(catalog.devices[0])


func _mat(state: DisassemblyState) -> PartsMat:
	var mat: PartsMat = PARTS_MAT_SCENE.instantiate() as PartsMat
	_root().add_child(mat)
	mat.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mat.size = Vector2(360, 600)
	mat.setup(state)
	mat.open()
	# Les conteneurs disposent leurs enfants en différé : on force la disposition, sans frame.
	for container: Container in [mat, mat.get_node("Layout") as Container]:
		container.notification(Container.NOTIFICATION_SORT_CHILDREN)
	assert_true(_map(mat).size.y > 300.0, "préparation : tapis disposé")
	return mat


func _map(mat: PartsMat) -> MatMap:
	return mat.get_node("%MatMap") as MatMap


func test_mat_lists_detached_parts_only() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var mat: PartsMat = _mat(state)
	assert_eq(_map(mat).item_ids(), PackedStringArray())
	DisassemblyFixture.remove_with_prerequisites(state, "display")
	var items: PackedStringArray = _map(mat).item_ids()
	assert_true("pentalobe_left" in items and "display_adhesive" in items)
	assert_false("display" in items, "écran ouvert mais attaché : pas sur le tapis")
	DisassemblyFixture.remove_with_prerequisites(state, "display_connector")
	DisassemblyFixture.remove_with_prerequisites(state, "sensor_connector")
	assert_true("display" in _map(mat).item_ids(), "détaché : il rejoint le tapis")
	mat.free()


func test_touching_a_screw_on_the_mat_beats_the_display_under_it() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var mat: PartsMat = _mat(state)
	for id: String in ["display_connector", "sensor_connector"]:
		DisassemblyFixture.remove_with_prerequisites(state, id)
	var map: MatMap = _map(mat)
	var selected: Array[String] = []
	map.part_selected.connect(func(id: String) -> void: selected.append(id))
	map.select_at(map.item_rect("pentalobe_left").get_center())
	map.select_at(map.item_rect("display").get_center())
	assert_eq(selected, ["pentalobe_left", "display"] as Array[String])
	assert_eq(map.selected_id, "display")
	map.select_at(map.item_rect("display").get_center())
	assert_eq(map.selected_id, "", "toucher à nouveau désélectionne")
	mat.free()


func test_small_items_are_drawn_large_enough_to_touch() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var mat: PartsMat = _mat(state)
	DisassemblyFixture.remove_with_prerequisites(state, "connector_cover")
	var map: MatMap = _map(mat)
	assert_true(map.item_rect("cover_screw_1").size.x >= MatMap.MIN_ITEM_SIZE)
	mat.free()


func test_actions_follow_the_selected_part() -> void:
	var state: DisassemblyState = _starter_phone_state()
	var mat: PartsMat = _mat(state)
	DisassemblyFixture.remove_with_prerequisites(state, "connector_cover")
	var requests: Array[String] = []
	mat.reinstall_requested.connect(func(id: String) -> void: requests.append("reinstall:" + id))
	mat.replace_requested.connect(func(id: String) -> void: requests.append("replace:" + id))
	var reinstall: Button = mat.get_node("%MatReinstallButton") as Button
	var replace: Button = mat.get_node("%MatReplaceButton") as Button
	assert_true(reinstall.disabled and replace.disabled, "rien de sélectionné")
	var map: MatMap = _map(mat)
	map.select_at(map.item_rect("cover_screw_1").get_center())
	assert_false(reinstall.disabled)
	assert_true(replace.disabled, "une vis ne se remplace pas")
	assert_true((mat.get_node("%MatInfo") as Label).text.contains("Phillips 1.3 mm"), "tête et longueur affichées")
	reinstall.pressed.emit()
	map.select_at(map.item_rect("connector_cover").get_center())
	assert_false(replace.disabled)
	replace.pressed.emit()
	assert_eq(requests, ["reinstall:cover_screw_1", "replace:connector_cover"] as Array[String])
	mat.free()
