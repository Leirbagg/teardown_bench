extends TestSuite

var _graph: DisassemblyGraph = DisassemblyGraph.new(DisassemblyFixture.load_test_phone())


func _as_set(ids: Array[String]) -> Dictionary[String, bool]:
	var result: Dictionary[String, bool] = {}
	for id: String in ids:
		result[id] = true
	return result


func test_visibility_on_assembled_device() -> void:
	var nothing_removed: Dictionary[String, bool] = {}
	for id: String in ["back_screw_l", "back_cover", "screen_adhesive", "screen"]:
		assert_true(_graph.is_visible(id, nothing_removed), "%s visible" % id)
	for id: String in ["battery_connector", "battery_adhesive", "battery", "port_screw", "charge_port", "screen_flex"]:
		assert_false(_graph.is_visible(id, nothing_removed), "%s caché par back_cover" % id)


func test_removing_cover_reveals_components() -> void:
	var removed: Dictionary[String, bool] = _as_set(["back_screw_l", "back_screw_r", "back_cover"])
	assert_true(_graph.is_visible("battery_connector", removed))
	assert_true(_graph.is_visible("screen_flex", removed))


func test_removal_blockers_are_requires_still_in_place() -> void:
	var nothing_removed: Dictionary[String, bool] = {}
	assert_eq(_graph.removal_blockers("back_cover", nothing_removed), PackedStringArray(["back_screw_l", "back_screw_r"]))
	assert_eq(_graph.removal_blockers("back_cover", _as_set(["back_screw_l"])), PackedStringArray(["back_screw_r"]))
	assert_eq(_graph.removal_blockers("back_screw_l", nothing_removed), PackedStringArray())


func test_dependents_are_reverse_requires() -> void:
	assert_eq(_graph.dependents("back_cover"), PackedStringArray(["battery_connector", "battery_adhesive", "battery", "port_screw", "charge_port", "screen_flex"]))
	assert_eq(_graph.dependents("battery_connector"), PackedStringArray(["battery", "charge_port", "screen_flex"]))
	assert_eq(_graph.dependents("screen"), PackedStringArray())


func test_install_blockers_are_removed_dependents() -> void:
	var removed: Dictionary[String, bool] = _as_set(["back_screw_l", "back_screw_r", "back_cover"])
	assert_eq(_graph.install_blockers("back_screw_l", removed), PackedStringArray(["back_cover"]))
	assert_eq(_graph.install_blockers("back_cover", removed), PackedStringArray())
