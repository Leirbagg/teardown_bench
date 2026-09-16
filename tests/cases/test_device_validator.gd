extends TestSuite

const FIXTURES: String = "res://tests/fixtures/"


## Appareil minimal valide : vis → cache → batterie.
func _valid_device() -> Dictionary:
	return {
		"schema_version": 1,
		"id": "test_device",
		"name": "Test Device",
		"tier": 1,
		"faces": ["front", "back"],
		"software_tests": [
			{"id": "boot", "roles": ["battery"], "after": []},
		],
		"components": [
			{"id": "screw", "kind": "screw", "face": "back", "gesture": "rotate",
				"requires": [], "covered_by": []},
			{"id": "cover", "kind": "cover", "face": "back", "gesture": "pry",
				"requires": ["screw"], "covered_by": [], "replaceable": true},
			{"id": "battery", "kind": "module", "face": "back", "gesture": "pull",
				"requires": ["cover"], "covered_by": ["cover"], "role": "battery", "replaceable": true},
		],
	}


func _valid_fault() -> Dictionary:
	return {
		"schema_version": 1,
		"id": "battery_dead",
		"tier": 1,
		"target_role": "battery",
		"complaints": ["It won't turn on."],
		"clues": [{"tool": "loupe", "role": "battery", "clue": "swelling", "visible": "exposed"}],
		"target_time_s": 120,
		"price": 89,
	}


func _component(device: Dictionary, id: String) -> Dictionary:
	for component: Dictionary in device["components"]:
		if component["id"] == id:
			return component
	return {}


# --- Appareil : structure ---

func test_valid_device_has_no_errors() -> void:
	assert_no_errors(DeviceValidator.validate_device(_valid_device()))


func test_numbers_parsed_as_float_are_accepted() -> void:
	var device: Dictionary = _valid_device()
	device["schema_version"] = 1.0
	device["tier"] = 2.0
	assert_no_errors(DeviceValidator.validate_device(device))


func test_empty_dictionary_reports_missing_fields() -> void:
	var errors: Array[String] = DeviceValidator.validate_device({})
	assert_has_code(errors, "missing_field")


func test_rejects_wrong_schema_version() -> void:
	var device: Dictionary = _valid_device()
	device["schema_version"] = 2
	assert_has_code(DeviceValidator.validate_device(device), "bad_value")


func test_rejects_non_integer_tier() -> void:
	for tier: Variant in [0, 1.5, "1"]:
		var device: Dictionary = _valid_device()
		device["tier"] = tier
		assert_has_code(DeviceValidator.validate_device(device), "bad_value", "tier %s" % var_to_str(tier))


func test_rejects_unknown_face() -> void:
	var device: Dictionary = _valid_device()
	device["faces"] = ["front", "side"]
	assert_has_code(DeviceValidator.validate_device(device), "bad_value")


func test_rejects_components_that_are_not_objects() -> void:
	var device: Dictionary = _valid_device()
	device["components"] = ["screw"]
	assert_has_code(DeviceValidator.validate_device(device), "bad_type")


func test_rejects_empty_components() -> void:
	var device: Dictionary = _valid_device()
	device["components"] = []
	assert_has_code(DeviceValidator.validate_device(device), "bad_type")


func test_rejects_duplicate_id() -> void:
	var device: Dictionary = _valid_device()
	(device["components"] as Array).append(_component(device, "screw").duplicate())
	assert_has_code(DeviceValidator.validate_device(device), "duplicate_id")


func test_rejects_unknown_kind_gesture_and_face() -> void:
	for field: String in ["kind", "gesture", "face"]:
		var device: Dictionary = _valid_device()
		_component(device, "screw")[field] = "unknown"
		assert_has_code(DeviceValidator.validate_device(device), "bad_value", field)


func test_rejects_requires_with_non_string_items() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "cover")["requires"] = [3]
	assert_has_code(DeviceValidator.validate_device(device), "bad_type")


func test_visual_rect_must_have_four_numbers_and_positive_size() -> void:
	for rect: Variant in [[0, 0, 10], [0, 0, 10, 0], [0, "0", 10, 10], "0,0,10,10"]:
		var device: Dictionary = _valid_device()
		_component(device, "screw")["visual"] = {"rect": rect}
		assert_has_code(DeviceValidator.validate_device(device), "bad_value", var_to_str(rect))
	var valid: Dictionary = _valid_device()
	_component(valid, "screw")["visual"] = {"rect": [1.5, 2, 10, 10]}
	assert_no_errors(DeviceValidator.validate_device(valid))


func test_decorations_are_validated() -> void:
	var valid: Dictionary = _valid_device()
	valid["decorations"] = [
		{"id": "board", "face": "front", "kind": "board", "rect": [0, 0, 50, 80], "label": "Logic board"},
		{"id": "notch", "face": "front", "kind": "notch", "rect": [10, 0, 30, 8], "attached_to": "cover"},
	]
	assert_no_errors(DeviceValidator.validate_device(valid))
	var cases: Dictionary = {
		"unknown_kind": [{"id": "x", "face": "front", "kind": "sticker", "rect": [0, 0, 1, 1]}],
		"bad_face": [{"id": "x", "face": "side", "kind": "board", "rect": [0, 0, 1, 1]}],
		"bad_rect": [{"id": "x", "face": "front", "kind": "board", "rect": [0, 0, 0, 1]}],
		"duplicate": [{"id": "x", "face": "front", "kind": "board", "rect": [0, 0, 1, 1]}, {"id": "x", "face": "front", "kind": "chip", "rect": [0, 0, 1, 1]}],
	}
	var expected_codes: Dictionary = {"unknown_kind": "bad_value", "bad_face": "bad_value", "bad_rect": "bad_value", "duplicate": "duplicate_id"}
	for case: String in cases:
		var device: Dictionary = _valid_device()
		device["decorations"] = cases[case]
		assert_has_code(DeviceValidator.validate_device(device), expected_codes[case], case)
	var unknown_attach: Dictionary = _valid_device()
	unknown_attach["decorations"] = [{"id": "x", "face": "front", "kind": "notch", "rect": [0, 0, 1, 1], "attached_to": "ghost"}]
	assert_has_code(DeviceValidator.validate_device(unknown_attach), "unknown_ref")


func test_decorations_are_parsed_in_order() -> void:
	var data: Dictionary = _valid_device()
	data["decorations"] = [
		{"id": "board", "face": "back", "kind": "board", "rect": [1, 2, 3, 4], "label": "Logic board"},
		{"id": "lens", "face": "back", "kind": "lens", "rect": [5, 6, 7, 8], "attached_to": "cover"},
	]
	var device: DeviceDefinition = DeviceDefinition.from_dict(data)
	assert_eq(device.decorations.size(), 2)
	assert_eq(device.decorations[0].label, "Logic board")
	assert_eq(device.decorations[0].rect, PackedFloat32Array([1, 2, 3, 4]))
	assert_eq(device.decorations[1].attached_to, "cover")
	assert_eq(device.decorations[1].label, "")
	assert_eq(DeviceDefinition.from_dict(_valid_device()).decorations.size(), 0, "facultatif")


# --- Appareil : graphe ---

func test_rejects_unknown_requires() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "cover")["requires"] = ["screw", "ghost"]
	assert_has_code(DeviceValidator.validate_device(device), "unknown_ref")


func test_rejects_cycle() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "screw")["requires"] = ["battery"]
	var errors: Array[String] = DeviceValidator.validate_device(device)
	assert_has_code(errors, "cycle")
	assert_has_code(errors, "no_root")


func test_rejects_covered_by_outside_requires() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "battery")["covered_by"] = ["screw"]
	assert_has_code(DeviceValidator.validate_device(device), "covered_not_required")


func test_rejects_orphan() -> void:
	var device: Dictionary = _valid_device()
	(device["components"] as Array).append({"id": "sticker", "kind": "cover", "face": "front",
		"gesture": "pull", "requires": [], "covered_by": []})
	assert_has_code(DeviceValidator.validate_device(device), "orphan")


func test_forcing_must_not_break_irreplaceable_part() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "cover")["replaceable"] = false
	assert_has_code(DeviceValidator.validate_device(device), "breaks_irreplaceable")


func test_explicit_force_breaks_must_target_replaceable_part() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "cover")["force_breaks"] = ["screw"]
	assert_has_code(DeviceValidator.validate_device(device), "breaks_irreplaceable")


func test_hidden_only_component_may_be_irreplaceable() -> void:
	var device: Dictionary = _valid_device()
	(device["components"] as Array).append({"id": "connector", "kind": "connector", "face": "back",
		"gesture": "pull", "requires": ["cover"], "covered_by": ["cover"]})
	_component(device, "battery")["requires"] = ["cover", "connector"]
	assert_no_errors(DeviceValidator.validate_device(device))


func test_replace_requires_must_reference_existing_other_parts_of_a_replaceable_part() -> void:
	var unknown: Dictionary = _valid_device()
	_component(unknown, "battery")["replace_requires"] = ["ghost"]
	assert_has_code(DeviceValidator.validate_device(unknown), "unknown_ref")
	var itself: Dictionary = _valid_device()
	_component(itself, "battery")["replace_requires"] = ["battery"]
	assert_has_code(DeviceValidator.validate_device(itself), "bad_value")
	var irreplaceable: Dictionary = _valid_device()
	_component(irreplaceable, "screw")["replace_requires"] = ["cover"]
	assert_has_code(DeviceValidator.validate_device(irreplaceable), "replace_requires_irreplaceable")
	var valid: Dictionary = _valid_device()
	_component(valid, "battery")["replace_requires"] = ["screw"]
	assert_no_errors(DeviceValidator.validate_device(valid))


func test_hint_is_an_optional_string() -> void:
	var valid: Dictionary = _valid_device()
	_component(valid, "battery")["hint"] = "Disconnect the battery first."
	assert_no_errors(DeviceValidator.validate_device(valid))
	assert_eq(DeviceDefinition.from_dict(valid).get_component("battery").hint, "Disconnect the battery first.")
	assert_eq(DeviceDefinition.from_dict(_valid_device()).get_component("battery").hint, "")
	var invalid: Dictionary = _valid_device()
	_component(invalid, "battery")["hint"] = 3
	assert_has_code(DeviceValidator.validate_device(invalid), "bad_type")


func test_screw_details_are_validated_and_parsed() -> void:
	var valid: Dictionary = _valid_device()
	_component(valid, "screw")["screw_type"] = "tri_point"
	_component(valid, "screw")["length_mm"] = 1.8
	assert_no_errors(DeviceValidator.validate_device(valid))
	var screw: ComponentDefinition = DeviceDefinition.from_dict(valid).get_component("screw")
	assert_eq(screw.screw_type, "tri_point")
	assert_eq(screw.length_mm, 1.8)
	assert_eq(DeviceDefinition.from_dict(_valid_device()).get_component("screw").length_mm, 0.0, "facultatif")
	var cases: Dictionary = {
		"screw_type": ["torx", "bad_value"],
		"length_mm": [0, "bad_value"],
	}
	for field: String in cases:
		var device: Dictionary = _valid_device()
		_component(device, "screw")[field] = cases[field][0]
		assert_has_code(DeviceValidator.validate_device(device), cases[field][1], field)
	var not_a_screw: Dictionary = _valid_device()
	_component(not_a_screw, "cover")["screw_type"] = "phillips"
	assert_has_code(DeviceValidator.validate_device(not_a_screw), "bad_value")


func test_visual_hinge_must_be_a_side() -> void:
	var valid: Dictionary = _valid_device()
	_component(valid, "battery")["visual"] = {"rect": [0, 0, 10, 10], "hinge": "left"}
	assert_no_errors(DeviceValidator.validate_device(valid))
	var invalid: Dictionary = _valid_device()
	_component(invalid, "battery")["visual"] = {"rect": [0, 0, 10, 10], "hinge": "middle"}
	assert_has_code(DeviceValidator.validate_device(invalid), "bad_value")


func test_rejects_duplicate_role() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "cover")["role"] = "battery"
	assert_has_code(DeviceValidator.validate_device(device), "duplicate_role")


func test_rejects_role_on_irreplaceable_component() -> void:
	var device: Dictionary = _valid_device()
	_component(device, "screw")["role"] = "screw_role"
	assert_has_code(DeviceValidator.validate_device(device), "role_not_replaceable")


# --- Appareil : tests logiciels ---

func test_rejects_software_test_with_unknown_role() -> void:
	var device: Dictionary = _valid_device()
	device["software_tests"][0]["roles"] = ["screen"]
	assert_has_code(DeviceValidator.validate_device(device), "unknown_ref")


func test_rejects_software_test_with_unknown_after() -> void:
	var device: Dictionary = _valid_device()
	device["software_tests"][0]["after"] = ["ghost"]
	assert_has_code(DeviceValidator.validate_device(device), "unknown_ref")


func test_rejects_software_test_cycle() -> void:
	var device: Dictionary = _valid_device()
	device["software_tests"] = [
		{"id": "boot", "roles": ["battery"], "after": ["charge"]},
		{"id": "charge", "roles": ["battery"], "after": ["boot"]},
	]
	assert_has_code(DeviceValidator.validate_device(device), "cycle")


# --- Pannes ---

func test_valid_fault_has_no_errors() -> void:
	assert_no_errors(DeviceValidator.validate_fault(_valid_fault()))


func test_fault_requires_complaints() -> void:
	var fault: Dictionary = _valid_fault()
	fault["complaints"] = []
	assert_has_code(DeviceValidator.validate_fault(fault), "bad_value")


func test_fault_rejects_unknown_clue_visibility_and_tool() -> void:
	for field: String in ["visible", "tool"]:
		var fault: Dictionary = _valid_fault()
		fault["clues"][0][field] = "unknown"
		assert_has_code(DeviceValidator.validate_fault(fault), "bad_value", field)


func test_fault_requires_a_positive_price() -> void:
	var fault: Dictionary = _valid_fault()
	fault.erase("price")
	assert_has_code(DeviceValidator.validate_fault(fault), "missing_field")
	fault["price"] = 0
	assert_has_code(DeviceValidator.validate_fault(fault), "bad_value")
	fault["price"] = 89
	assert_no_errors(DeviceValidator.validate_fault(fault))
	assert_eq(FaultDefinition.from_dict(fault).price, 89)


func test_part_price_is_reserved_for_replaceable_parts() -> void:
	var valid: Dictionary = _valid_device()
	_component(valid, "battery")["part_price"] = 35
	assert_no_errors(DeviceValidator.validate_device(valid))
	assert_eq(DeviceDefinition.from_dict(valid).get_component("battery").part_price, 35)
	assert_eq(DeviceDefinition.from_dict(_valid_device()).get_component("battery").part_price, 0, "facultatif")
	var on_screw: Dictionary = _valid_device()
	_component(on_screw, "screw")["part_price"] = 2
	assert_has_code(DeviceValidator.validate_device(on_screw), "bad_value")
	var negative: Dictionary = _valid_device()
	_component(negative, "battery")["part_price"] = -5
	assert_has_code(DeviceValidator.validate_device(negative), "bad_value")


func test_fault_rejects_non_positive_target_time() -> void:
	var fault: Dictionary = _valid_fault()
	fault["target_time_s"] = 0
	assert_has_code(DeviceValidator.validate_fault(fault), "bad_value")


# --- Chargement de fichiers ---

func test_loader_builds_device_definition() -> void:
	var errors: Array[String] = []
	var device: DeviceDefinition = DeviceLoader.load_device(FIXTURES + "devices/valid_minimal.json", errors)
	assert_no_errors(errors)
	if device == null:
		return
	assert_eq(device.id, "valid_minimal")
	assert_eq(device.tier, 1)
	assert_eq(device.components.size(), 3)
	assert_eq(device.software_tests[0].after, PackedStringArray())
	var cover: ComponentDefinition = device.get_component("cover")
	assert_true(cover.forceable, "cover retenu par une vis visible : forçable")
	assert_eq(cover.force_breaks, PackedStringArray(["cover"]))
	assert_false(device.get_component("battery").forceable, "battery seulement cachée : non forçable")
	assert_eq(device.component_for_role("battery").id, "battery")
	assert_eq(device.component_for_role("screen"), null)


func test_loader_rejects_invalid_fixtures() -> void:
	var expected: Dictionary = {
		"cycle.json": "cycle",
		"missing_requires.json": "unknown_ref",
		"orphan.json": "orphan",
		"covered_not_required.json": "covered_not_required",
	}
	for file: String in expected:
		var errors: Array[String] = []
		var device: DeviceDefinition = DeviceLoader.load_device(FIXTURES + "devices/" + file, errors)
		assert_eq(device, null, file)
		assert_has_code(errors, expected[file], file)


func test_loader_reports_malformed_json_and_missing_file() -> void:
	var errors: Array[String] = []
	assert_eq(DeviceLoader.load_device(FIXTURES + "devices/malformed.txt", errors), null)
	assert_has_code(errors, "json")
	errors.clear()
	assert_eq(DeviceLoader.load_device(FIXTURES + "devices/absent.json", errors), null)
	assert_has_code(errors, "file")


func test_loader_builds_fault_definition() -> void:
	var errors: Array[String] = []
	var fault: FaultDefinition = DeviceLoader.load_fault(FIXTURES + "faults/valid_fault.json", errors)
	assert_no_errors(errors)
	if fault == null:
		return
	assert_eq(fault.target_role, "battery")
	assert_eq(fault.target_time_s, 120.0)
	assert_eq(fault.clues[0].visibility, "exposed")
