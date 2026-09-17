extends TestSuite

const Kind = SolutionStep.Kind
const Outcome = DisassemblyResult.Outcome

var _device: DeviceDefinition = DisassemblyFixture.load_test_phone()


func _diagnosis(faults: Array[FaultDefinition]) -> Diagnosis:
	var errors: Array[String] = []
	var diagnosis: Diagnosis = Diagnosis.create(DisassemblyState.new(_device), faults, errors)
	assert_no_errors(errors)
	return diagnosis


func _all_faults() -> Array[FaultDefinition]:
	return [
		DisassemblyFixture.make_fault("screen_cracked", "screen"),
		DisassemblyFixture.make_fault("battery_dead", "battery"),
		DisassemblyFixture.make_fault("charge_port_faulty", "charge_port"),
	]


## Joue le plan sur l'état réel et vérifie que chaque étape donne l'issue attendue.
func _execute(diagnosis: Diagnosis, plan: Array[SolutionStep], context: String) -> void:
	var state: DisassemblyState = diagnosis.state
	for i: int in plan.size():
		var step: SolutionStep = plan[i]
		var where: String = "%s, étape %d (%s %s)" % [context, i, Kind.keys()[step.kind], step.component_id]
		match step.kind:
			Kind.REMOVE:
				assert_eq(state.commit_remove(step.component_id).outcome, Outcome.REMOVED, where)
			Kind.REPLACE:
				assert_eq(state.replace(step.component_id).outcome, Outcome.REPLACED, where)
			Kind.INSTALL:
				assert_eq(state.commit_install(step.component_id).outcome, Outcome.INSTALLED, where)
			Kind.INSPECT:
				var visible_roles: PackedStringArray = PackedStringArray()
				for clue: FaultDefinition.Clue in diagnosis.visible_clues():
					visible_roles.append(clue.role)
				assert_true(_device.get_component(step.component_id).role in visible_roles, where + " : indice visible")
			Kind.FINAL_TEST:
				assert_eq(diagnosis.run_final_test().outcome, FinalTestResult.Outcome.PASSED, where)
				assert_eq(i, plan.size() - 1, where + " : dernière étape")


func _kinds(plan: Array[SolutionStep]) -> PackedStringArray:
	var kinds: PackedStringArray = PackedStringArray()
	for step: SolutionStep in plan:
		kinds.append("%s:%s" % [Kind.keys()[step.kind], step.component_id])
	return kinds


func test_plan_from_closed_device_repairs_each_fault() -> void:
	for fault: FaultDefinition in _all_faults():
		var faults: Array[FaultDefinition] = [fault]
		var diagnosis: Diagnosis = _diagnosis(faults)
		var plan: Array[SolutionStep] = RepairPlanner.plan(diagnosis)
		assert_eq(plan[0].kind, Kind.RUN_TESTS, fault.id + " : on commence par les tests")
		assert_eq(plan[plan.size() - 1].kind, Kind.FINAL_TEST, fault.id)
		_execute(diagnosis, plan, fault.id)
		assert_eq(diagnosis.unnecessary_replacement_count(), 0, fault.id + " : aucun remplacement inutile")
		assert_eq(diagnosis.state.broken_ids(), PackedStringArray(), fault.id)


func test_plan_only_removes_what_the_repair_needs() -> void:
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("screen_cracked", "screen")]
	var plan: Array[SolutionStep] = RepairPlanner.plan(_diagnosis(faults))
	var kinds: PackedStringArray = _kinds(plan)
	assert_true("REMOVE:screen" in kinds)
	assert_false("REMOVE:battery" in kinds, "la batterie n'a rien à voir avec l'écran")
	assert_false("REMOVE:charge_port" in kinds)


func test_plan_inspects_clues_when_they_become_visible() -> void:
	var clue: Dictionary = {"tool": "loupe", "role": "charge_port", "clue": "corrosion", "visible": "exposed"}
	var data: Dictionary = {
		"schema_version": 1, "id": "charge_port_faulty", "tier": 1, "target_role": "charge_port",
		"complaints": ["No charge."], "clues": [clue], "target_time_s": 100, "price": 100,
	}
	var faults: Array[FaultDefinition] = [FaultDefinition.from_dict(data)]
	var plan: Array[SolutionStep] = RepairPlanner.plan(_diagnosis(faults))
	var kinds: PackedStringArray = _kinds(plan)
	var inspect: int = kinds.find("INSPECT:charge_port")
	assert_true(inspect > kinds.find("REMOVE:back_cover"), "après l'ouverture du cache")
	assert_true(inspect < kinds.find("REPLACE:charge_port"), "avant le remplacement")


func test_plan_detaches_replace_requires_before_replacing() -> void:
	var data: Dictionary = {
		"schema_version": 1, "id": "book", "name": "Book", "tier": 1, "faces": ["front"],
		"software_tests": [{"id": "display", "roles": ["screen"], "after": []}],
		"components": [
			{"id": "display", "kind": "module", "face": "front", "gesture": "pry", "role": "screen",
				"requires": [], "covered_by": [], "replaceable": true, "replace_requires": ["display_cable"]},
			{"id": "display_cable", "kind": "connector", "face": "front", "gesture": "pull",
				"requires": ["display"], "covered_by": ["display"]},
		],
	}
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("screen_cracked", "screen")]
	var diagnosis: Diagnosis = Diagnosis.create(DisassemblyState.new(DeviceDefinition.from_dict(data)), faults, errors)
	assert_no_errors(errors)
	var plan: Array[SolutionStep] = RepairPlanner.plan(diagnosis)
	var kinds: PackedStringArray = _kinds(plan)
	assert_true(kinds.find("REMOVE:display_cable") < kinds.find("REPLACE:display"))
	assert_true(kinds.find("INSTALL:display_cable") < kinds.find("INSTALL:display"), "rebrancher avant de refermer")
	for i: int in plan.size():
		var step: SolutionStep = plan[i]
		match step.kind:
			Kind.REMOVE:
				assert_eq(diagnosis.state.commit_remove(step.component_id).outcome, Outcome.REMOVED)
			Kind.REPLACE:
				assert_eq(diagnosis.state.replace(step.component_id).outcome, Outcome.REPLACED)
			Kind.INSTALL:
				assert_eq(diagnosis.state.commit_install(step.component_id).outcome, Outcome.INSTALLED)
			Kind.FINAL_TEST:
				assert_eq(diagnosis.run_final_test().outcome, FinalTestResult.Outcome.PASSED)


func test_plan_does_not_modify_the_real_state() -> void:
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("battery_dead", "battery")]
	var diagnosis: Diagnosis = _diagnosis(faults)
	RepairPlanner.plan(diagnosis)
	assert_true(diagnosis.state.is_fully_assembled())
	assert_eq(diagnosis.replacements().size(), 0)


func test_plan_recovers_from_any_messy_state() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var ids: PackedStringArray = _device.component_ids()
	var failures_before: int = _failures
	for seed_value: int in 150:
		rng.seed = seed_value
		var all_faults: Array[FaultDefinition] = _all_faults()
		var faults: Array[FaultDefinition] = [all_faults[rng.randi_range(0, all_faults.size() - 1)]]
		var diagnosis: Diagnosis = _diagnosis(faults)
		for action: int in rng.randi_range(0, 40):
			var id: String = ids[rng.randi_range(0, ids.size() - 1)]
			match rng.randi_range(0, 2):
				0:
					diagnosis.state.commit_remove(id)
				1:
					diagnosis.state.commit_install(id)
				2:
					diagnosis.state.replace(id)
		_execute(diagnosis, RepairPlanner.plan(diagnosis), "graine %d" % seed_value)
		if _failures > failures_before:
			return


## Le mode solution ne doit pas perdre les capteurs : il les démonte avant de changer l'écran,
## puis les remonte sur le neuf.
func test_plan_transfers_mounted_parts_instead_of_losing_them() -> void:
	var diagnosis: Diagnosis = _diagnosis([DisassemblyFixture.make_fault("screen_cracked", "screen")])
	var plan: Array[SolutionStep] = RepairPlanner.plan(diagnosis)
	var kinds: PackedStringArray = _kinds(plan)
	assert_true("REMOVE:front_sensors" in kinds, "capteurs démontés : %s" % ", ".join(kinds))
	assert_true(kinds.find("REMOVE:front_sensors") < kinds.find("REPLACE:screen"), "avant de poser l'écran neuf")
	assert_true("INSTALL:front_sensors" in kinds, "puis remontés")
	assert_false("REPLACE:front_sensors" in kinds, "sans en racheter")
	_execute(diagnosis, plan, "transfert des capteurs")
