class_name DisassemblyFixture
extends RefCounted
## Charge l'appareil de test partagé par les suites de démontage.

const TEST_PHONE_PATH: String = "res://tests/fixtures/devices/test_phone.json"


static func load_test_phone() -> DeviceDefinition:
	var errors: Array[String] = []
	var device: DeviceDefinition = DeviceLoader.load_device(TEST_PHONE_PATH, errors)
	if device == null:
		push_error("test_phone.json invalide :\n%s" % "\n".join(PackedStringArray(errors)))
	return device


## Panne minimale valide ciblant `role`.
static func make_fault(id: String, role: String, tier: int = 1, target_time_s: float = 100.0,
		complaints: Array = ["Test complaint."]) -> FaultDefinition:
	var data: Dictionary = {
		"schema_version": 1, "id": id, "tier": tier, "target_role": role,
		"complaints": complaints, "clues": [], "target_time_s": target_time_s, "price": 100,
	}
	var errors: Array[String] = DeviceValidator.validate_fault(data)
	if not errors.is_empty():
		push_error("panne de test invalide :\n%s" % "\n".join(PackedStringArray(errors)))
	return FaultDefinition.from_dict(data)


## Retire le composant après avoir retiré, récursivement, tous ses prérequis.
static func remove_with_prerequisites(state: DisassemblyState, component_id: String) -> void:
	if state.is_removed(component_id):
		return
	for requirement: String in state.device.get_component(component_id).requires:
		remove_with_prerequisites(state, requirement)
	state.commit_remove(component_id)


## Remonte tout ce qui peut l'être jusqu'à ne plus progresser.
static func reassemble(state: DisassemblyState) -> void:
	var progressed: bool = true
	while progressed:
		progressed = false
		for id: String in state.removed_ids():
			if state.commit_install(id).outcome == DisassemblyResult.Outcome.INSTALLED:
				progressed = true


## Répare proprement : remplace la pièce de chaque panne, puis remonte tout.
static func repair_faults(state: DisassemblyState, faults: Array[FaultDefinition]) -> void:
	for fault: FaultDefinition in faults:
		var component_id: String = state.device.component_for_role(fault.target_role).id
		remove_with_prerequisites(state, component_id)
		for attached: String in state.device.get_component(component_id).replace_requires:
			remove_with_prerequisites(state, attached)
		state.replace(component_id)
	reassemble(state)


## Retire tout ce qui est libre jusqu'à ne plus progresser, sans séquence codée en dur.
## Renvoie l'ordre de retrait.
static func teardown(state: DisassemblyState) -> PackedStringArray:
	var order: PackedStringArray = PackedStringArray()
	var progressed: bool = true
	while progressed:
		progressed = false
		for id: String in state.device.component_ids():
			if not state.is_removed(id) and state.query_remove(id).outcome == DisassemblyResult.Outcome.REMOVED:
				state.commit_remove(id)
				order.append(id)
				progressed = true
	return order
