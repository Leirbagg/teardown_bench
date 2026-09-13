extends TestSuite

const TestStatus = Diagnosis.TestStatus
const Verdict = Diagnosis.ReplacementVerdict
const FinalOutcome = FinalTestResult.Outcome

var _device: DeviceDefinition = DisassemblyFixture.load_test_phone()


func _fault(id: String, role: String, clues: Array = []) -> FaultDefinition:
	var data: Dictionary = {
		"schema_version": 1, "id": id, "tier": 1, "target_role": role,
		"complaints": ["Test complaint."], "clues": clues, "target_time_s": 100,
	}
	assert_no_errors(DeviceValidator.validate_fault(data), "panne de test %s" % id)
	return FaultDefinition.from_dict(data)


func _screen_cracked() -> FaultDefinition:
	return _fault("screen_cracked", "screen", [{"tool": "loupe", "role": "screen", "clue": "crack", "visible": "always"}])


func _charge_port_faulty() -> FaultDefinition:
	return _fault("charge_port_faulty", "charge_port", [{"tool": "loupe", "role": "charge_port", "clue": "corrosion", "visible": "exposed"}])


## Crée un état neuf et son diagnostic avec les pannes données.
func _session(faults: Array[FaultDefinition]) -> Diagnosis:
	var errors: Array[String] = []
	var diagnosis: Diagnosis = Diagnosis.create(DisassemblyState.new(_device), faults, errors)
	assert_no_errors(errors)
	return diagnosis


func _results(diagnosis: Diagnosis) -> Dictionary:
	var readable: Dictionary = {}
	var results: Dictionary[String, TestStatus] = diagnosis.software_test_results()
	for test_id: String in results:
		readable[test_id] = TestStatus.keys()[results[test_id]]
	return readable


func _clue_ids(diagnosis: Diagnosis) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for clue: FaultDefinition.Clue in diagnosis.visible_clues():
		ids.append(clue.clue_id)
	return ids


# --- Création ---

func test_create_rejects_fault_for_missing_role() -> void:
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [_fault("speaker_dead", "speaker")]
	assert_eq(Diagnosis.create(DisassemblyState.new(_device), faults, errors), null)
	assert_has_code(errors, "inapplicable_fault")


# --- Tests logiciels ---

func test_healthy_device_passes_every_test() -> void:
	var diagnosis: Diagnosis = _session([])
	assert_eq(_results(diagnosis), {"boot": "PASS", "display": "PASS", "touch": "PASS", "charging": "PASS"})


func test_fault_fails_tests_of_its_role() -> void:
	var diagnosis: Diagnosis = _session([_screen_cracked()])
	assert_eq(_results(diagnosis), {"boot": "PASS", "display": "FAIL", "touch": "FAIL", "charging": "PASS"})


func test_failed_prerequisite_blocks_dependent_tests() -> void:
	var diagnosis: Diagnosis = _session([_fault("battery_dead", "battery")])
	assert_eq(_results(diagnosis), {"boot": "FAIL", "display": "BLOCKED", "touch": "BLOCKED", "charging": "BLOCKED"})


func test_disconnected_connector_reports_disconnected() -> void:
	var diagnosis: Diagnosis = _session([])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "battery_connector")
	assert_false(diagnosis.is_role_operational("battery"))
	assert_eq(_results(diagnosis), {"boot": "DISCONNECTED", "display": "BLOCKED", "touch": "BLOCKED", "charging": "BLOCKED"})


func test_open_device_can_still_be_tested() -> void:
	var diagnosis: Diagnosis = _session([_charge_port_faulty()])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "back_cover")
	assert_eq(_results(diagnosis), {"boot": "PASS", "display": "PASS", "touch": "PASS", "charging": "FAIL"})


func test_removed_or_unplugged_role_part_is_not_operational() -> void:
	var diagnosis: Diagnosis = _session([])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "screen_flex")
	assert_false(diagnosis.is_role_operational("screen"), "nappe d'écran débranchée")
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "screen")
	assert_false(diagnosis.is_role_operational("screen"), "écran retiré")
	assert_false(diagnosis.is_role_operational("unknown_role"))


func test_broken_part_behaves_like_a_fault() -> void:
	var diagnosis: Diagnosis = _session([])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "back_cover")
	diagnosis.state.commit_remove("screen_flex")
	assert_true(diagnosis.state.is_broken("screen"), "préparation : forcer la nappe casse l'écran")
	assert_true(diagnosis.is_role_faulty("screen"))
	assert_eq(_results(diagnosis), {"boot": "PASS", "display": "FAIL", "touch": "FAIL", "charging": "PASS"})


# --- Indices ---

func test_always_clue_is_visible_from_the_start() -> void:
	var diagnosis: Diagnosis = _session([_screen_cracked()])
	assert_eq(_clue_ids(diagnosis), PackedStringArray(["crack"]))


func test_exposed_clue_appears_when_part_becomes_visible() -> void:
	var diagnosis: Diagnosis = _session([_charge_port_faulty()])
	assert_eq(_clue_ids(diagnosis), PackedStringArray(), "port caché par le cache arrière")
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "back_cover")
	assert_eq(_clue_ids(diagnosis), PackedStringArray(["corrosion"]))


func test_clue_disappears_once_fault_is_resolved() -> void:
	var diagnosis: Diagnosis = _session([_screen_cracked()])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "screen")
	diagnosis.state.replace("screen")
	assert_eq(_clue_ids(diagnosis), PackedStringArray())


# --- Remplacements ---

func test_replacing_faulty_part_resolves_fault() -> void:
	var diagnosis: Diagnosis = _session([_screen_cracked()])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "screen")
	diagnosis.state.replace("screen")
	assert_eq(diagnosis.unresolved_faults().size(), 0)
	assert_eq(diagnosis.replacements().size(), 1)
	assert_eq(diagnosis.replacements()[0].component_id, "screen")
	assert_eq(diagnosis.replacements()[0].verdict, Verdict.FIXED_FAULT)
	assert_eq(diagnosis.unnecessary_replacement_count(), 0)


func test_replacing_healthy_part_is_unnecessary() -> void:
	var diagnosis: Diagnosis = _session([_screen_cracked()])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "battery")
	diagnosis.state.replace("battery")
	assert_eq(diagnosis.replacements()[0].verdict, Verdict.UNNECESSARY)
	assert_eq(diagnosis.unnecessary_replacement_count(), 1)
	assert_eq(diagnosis.unresolved_faults().size(), 1)


func test_replacing_broken_part_is_a_fixed_break() -> void:
	var diagnosis: Diagnosis = _session([])
	diagnosis.state.commit_remove("back_cover")
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "back_cover")
	diagnosis.state.replace("back_cover")
	assert_eq(diagnosis.replacements()[0].verdict, Verdict.FIXED_BREAK)
	assert_eq(diagnosis.unnecessary_replacement_count(), 0)


func test_replacing_again_after_resolution_is_unnecessary() -> void:
	var diagnosis: Diagnosis = _session([_screen_cracked()])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "screen")
	diagnosis.state.replace("screen")
	diagnosis.state.replace("screen")
	assert_eq(diagnosis.replacements()[1].verdict, Verdict.UNNECESSARY)


# --- Test final ---

func test_final_test_requires_assembled_device() -> void:
	var diagnosis: Diagnosis = _session([])
	diagnosis.state.commit_remove("back_screw_l")
	var result: FinalTestResult = diagnosis.run_final_test()
	assert_eq(result.outcome, FinalOutcome.NOT_ASSEMBLED)
	assert_false(result.is_passed())
	assert_eq(diagnosis.failed_final_test_count(), 0, "une tentative sur appareil ouvert ne compte pas")


func test_final_test_passes_after_correct_repair() -> void:
	var diagnosis: Diagnosis = _session([_screen_cracked()])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "screen")
	diagnosis.state.replace("screen")
	DisassemblyFixture.reassemble(diagnosis.state)
	var result: FinalTestResult = diagnosis.run_final_test()
	assert_eq(result.outcome, FinalOutcome.PASSED)
	assert_true(result.is_passed())
	assert_eq(result.failing_tests, PackedStringArray())


func test_final_test_fails_after_wrong_diagnosis() -> void:
	var diagnosis: Diagnosis = _session([_fault("battery_dead", "battery")])
	DisassemblyFixture.remove_with_prerequisites(diagnosis.state, "screen")
	diagnosis.state.replace("screen")
	DisassemblyFixture.reassemble(diagnosis.state)
	var result: FinalTestResult = diagnosis.run_final_test()
	assert_eq(result.outcome, FinalOutcome.FAILED)
	assert_eq(result.failing_tests, PackedStringArray(["boot", "display", "touch", "charging"]))
	assert_eq(diagnosis.failed_final_test_count(), 1)


func test_final_test_fails_with_broken_part_without_role() -> void:
	var diagnosis: Diagnosis = _session([])
	diagnosis.state.commit_remove("back_cover")
	var result: FinalTestResult = diagnosis.run_final_test()
	assert_eq(result.outcome, FinalOutcome.FAILED)
	assert_eq(result.failing_tests, PackedStringArray())
	assert_eq(result.broken_ids, PackedStringArray(["back_cover"]))
