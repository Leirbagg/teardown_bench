extends TestSuite

const Outcome = DisassemblyResult.Outcome

var _device: DeviceDefinition = DisassemblyFixture.load_test_phone()
var _events: Array[String] = []


func _new_state() -> DisassemblyState:
	_events.clear()
	var state: DisassemblyState = DisassemblyState.new(_device)
	state.component_removed.connect(func(id: String) -> void: _events.append("removed:" + id))
	state.component_installed.connect(func(id: String) -> void: _events.append("installed:" + id))
	state.component_broken.connect(func(id: String, cause: String) -> void: _events.append("broken:%s<-%s" % [id, cause]))
	state.component_replaced.connect(func(id: String, was_broken: bool) -> void: _events.append("replaced:%s(%s)" % [id, "broken" if was_broken else "healthy"]))
	return state


func _remove_all(state: DisassemblyState, ids: Array[String]) -> void:
	for id: String in ids:
		var result: DisassemblyResult = state.commit_remove(id)
		assert_eq(result.outcome, Outcome.REMOVED, "préparation : retrait de %s" % id)


func _assert_invariant(state: DisassemblyState, context: String) -> void:
	for id: String in state.removed_ids():
		for requirement: String in _device.get_component(id).requires:
			assert_true(state.is_removed(requirement), "%s : %s retiré mais %s en place" % [context, id, requirement])


# --- Retrait ---

func test_remove_free_component() -> void:
	var state: DisassemblyState = _new_state()
	var result: DisassemblyResult = state.commit_remove("back_screw_l")
	assert_eq(result.outcome, Outcome.REMOVED)
	assert_true(result.is_success())
	assert_true(state.is_removed("back_screw_l"))
	assert_eq(_events, ["removed:back_screw_l"] as Array[String])


func test_query_predicts_without_side_effects() -> void:
	var state: DisassemblyState = _new_state()
	var result: DisassemblyResult = state.query_remove("back_cover")
	assert_eq(result.outcome, Outcome.FORCED)
	assert_eq(result.blockers, PackedStringArray(["back_screw_l", "back_screw_r"]))
	assert_eq(result.broken, PackedStringArray(["back_cover"]))
	assert_false(state.is_broken("back_cover"))
	assert_true(_events.is_empty(), "aucun signal")


func test_forcing_held_component_breaks_it_and_keeps_it_in_place() -> void:
	var state: DisassemblyState = _new_state()
	var result: DisassemblyResult = state.commit_remove("back_cover")
	assert_eq(result.outcome, Outcome.FORCED)
	assert_false(result.is_success())
	assert_eq(result.broken, PackedStringArray(["back_cover"]))
	assert_true(state.is_broken("back_cover"))
	assert_false(state.is_removed("back_cover"), "reste en place")
	assert_eq(_events, ["broken:back_cover<-back_cover"] as Array[String])


func test_forcing_breaks_listed_parts() -> void:
	var state: DisassemblyState = _new_state()
	_remove_all(state, ["back_screw_l", "back_screw_r", "back_cover"])
	var result: DisassemblyResult = state.commit_remove("screen_flex")
	assert_eq(result.outcome, Outcome.FORCED)
	assert_eq(result.blockers, PackedStringArray(["battery_connector"]))
	assert_true(state.is_broken("screen"))
	assert_false(state.is_broken("screen_flex"))
	assert_false(state.is_removed("screen_flex"))


func test_forcing_again_breaks_nothing_new() -> void:
	var state: DisassemblyState = _new_state()
	state.commit_remove("back_cover")
	_events.clear()
	var result: DisassemblyResult = state.commit_remove("back_cover")
	assert_eq(result.outcome, Outcome.FORCED)
	assert_eq(result.broken, PackedStringArray())
	assert_true(_events.is_empty())


func test_touching_hidden_component_has_no_effect() -> void:
	var state: DisassemblyState = _new_state()
	var result: DisassemblyResult = state.commit_remove("battery_connector")
	assert_eq(result.outcome, Outcome.HIDDEN)
	assert_eq(result.blockers, PackedStringArray(["back_cover"]))
	assert_eq(state.broken_ids(), PackedStringArray())
	assert_false(state.is_removed("battery_connector"))
	assert_true(_events.is_empty())


func test_remove_already_removed_or_unknown() -> void:
	var state: DisassemblyState = _new_state()
	state.commit_remove("back_screw_l")
	_events.clear()
	assert_eq(state.commit_remove("back_screw_l").outcome, Outcome.ALREADY_REMOVED)
	assert_eq(state.commit_remove("ghost").outcome, Outcome.UNKNOWN_COMPONENT)
	assert_true(_events.is_empty())


func test_broken_component_can_be_removed_normally() -> void:
	var state: DisassemblyState = _new_state()
	state.commit_remove("back_cover")
	_remove_all(state, ["back_screw_l", "back_screw_r", "back_cover"])
	assert_true(state.is_broken("back_cover"))


# --- Remontage ---

func test_install_in_wrong_order_is_refused_without_penalty() -> void:
	var state: DisassemblyState = _new_state()
	_remove_all(state, ["back_screw_l", "back_screw_r", "back_cover"])
	_events.clear()
	var result: DisassemblyResult = state.commit_install("back_screw_l")
	assert_eq(result.outcome, Outcome.INSTALL_BLOCKED)
	assert_eq(result.blockers, PackedStringArray(["back_cover"]))
	assert_true(state.is_removed("back_screw_l"))
	assert_eq(state.broken_ids(), PackedStringArray())
	assert_true(_events.is_empty())


func test_install_in_right_order() -> void:
	var state: DisassemblyState = _new_state()
	_remove_all(state, ["back_screw_l", "back_screw_r", "back_cover"])
	_events.clear()
	for id: String in ["back_cover", "back_screw_r", "back_screw_l"]:
		assert_eq(state.commit_install(id).outcome, Outcome.INSTALLED, id)
	assert_true(state.is_fully_assembled())
	assert_eq(_events, ["installed:back_cover", "installed:back_screw_r", "installed:back_screw_l"] as Array[String])


func test_install_component_already_in_place() -> void:
	var state: DisassemblyState = _new_state()
	assert_eq(state.commit_install("screen").outcome, Outcome.ALREADY_INSTALLED)
	assert_eq(state.commit_install("ghost").outcome, Outcome.UNKNOWN_COMPONENT)


# --- Remplacement ---

func test_replace_requires_removed_replaceable_part() -> void:
	var state: DisassemblyState = _new_state()
	assert_eq(state.replace("back_cover").outcome, Outcome.NOT_REMOVED)
	state.commit_remove("back_screw_l")
	assert_eq(state.replace("back_screw_l").outcome, Outcome.NOT_REPLACEABLE)
	assert_eq(state.replace("ghost").outcome, Outcome.UNKNOWN_COMPONENT)
	assert_eq(state.replaced_ids(), PackedStringArray())


func test_replace_repairs_broken_part() -> void:
	var state: DisassemblyState = _new_state()
	state.commit_remove("back_cover")
	_remove_all(state, ["back_screw_l", "back_screw_r", "back_cover"])
	_events.clear()
	var result: DisassemblyResult = state.replace("back_cover")
	assert_eq(result.outcome, Outcome.REPLACED)
	assert_false(state.is_broken("back_cover"))
	assert_true(state.is_removed("back_cover"), "la pièce neuve reste à remonter")
	assert_eq(state.replaced_ids(), PackedStringArray(["back_cover"]))
	assert_eq(_events, ["replaced:back_cover(broken)"] as Array[String])


func test_replacing_healthy_part_is_recorded() -> void:
	var state: DisassemblyState = _new_state()
	DisassemblyFixture.teardown(state)
	_events.clear()
	state.replace("battery")
	state.replace("battery")
	assert_eq(state.replaced_ids(), PackedStringArray(["battery", "battery"]))
	assert_eq(_events, ["replaced:battery(healthy)", "replaced:battery(healthy)"] as Array[String])


## Écran qui s'ouvre comme un livre : il cache sa propre nappe, qu'on ne peut débrancher
## qu'une fois l'écran ouvert, et qu'il faut débrancher avant de le remplacer.
func _book_opening_device() -> DeviceDefinition:
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
	assert_no_errors(DeviceValidator.validate_device(data), "préparation")
	return DeviceDefinition.from_dict(data)


func test_replace_waits_for_listed_parts_to_be_detached() -> void:
	var state: DisassemblyState = DisassemblyState.new(_book_opening_device())
	state.commit_remove("display")
	var result: DisassemblyResult = state.replace("display")
	assert_eq(result.outcome, Outcome.NOT_DETACHED)
	assert_eq(result.blockers, PackedStringArray(["display_cable"]))
	assert_false(result.is_success())
	assert_eq(state.replaced_ids(), PackedStringArray())
	state.commit_remove("display_cable")
	assert_eq(state.replace("display").outcome, Outcome.REPLACED)


func test_attached_parts_tell_an_open_but_tethered_part() -> void:
	var state: DisassemblyState = DisassemblyState.new(_book_opening_device())
	assert_eq(state.attached_parts("display"), PackedStringArray(["display_cable"]))
	state.commit_remove("display")
	assert_eq(state.attached_parts("display"), PackedStringArray(["display_cable"]), "ouvert, encore tenu par sa nappe")
	state.commit_remove("display_cable")
	assert_eq(state.attached_parts("display"), PackedStringArray(), "détaché")


func test_detached_part_must_be_reconnected_before_closing() -> void:
	var state: DisassemblyState = DisassemblyState.new(_book_opening_device())
	state.commit_remove("display")
	state.commit_remove("display_cable")
	state.replace("display")
	assert_eq(state.commit_install("display").outcome, Outcome.INSTALL_BLOCKED, "rebrancher la nappe d'abord")
	assert_eq(state.commit_install("display_cable").outcome, Outcome.INSTALLED)
	assert_eq(state.commit_install("display").outcome, Outcome.INSTALLED)


# --- Propriétés ---

func test_full_teardown_then_reassembly() -> void:
	var state: DisassemblyState = _new_state()
	var order: PackedStringArray = DisassemblyFixture.teardown(state)
	assert_eq(order.size(), _device.components.size(), "tout est démontable")
	assert_eq(state.broken_ids(), PackedStringArray(), "démontage propre sans casse")
	order.reverse()
	for id: String in order:
		assert_eq(state.commit_install(id).outcome, Outcome.INSTALLED, id)
	assert_true(state.is_fully_assembled())


func test_random_actions_keep_invariant_and_match_queries() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var ids: PackedStringArray = _device.component_ids()
	var failures_before: int = _failures
	for sequence: int in 200:
		rng.seed = sequence
		var state: DisassemblyState = _new_state()
		for step: int in 60:
			var id: String = ids[rng.randi_range(0, ids.size() - 1)]
			var context: String = "graine %d, étape %d, %s" % [sequence, step, id]
			match rng.randi_range(0, 2):
				0:
					var predicted: DisassemblyResult = state.query_remove(id)
					var actual: DisassemblyResult = state.commit_remove(id)
					assert_eq(actual.outcome, predicted.outcome, context)
					assert_eq(actual.broken, predicted.broken, context)
				1:
					var predicted_install: DisassemblyResult = state.query_install(id)
					assert_eq(state.commit_install(id).outcome, predicted_install.outcome, context)
				2:
					state.replace(id)
			_assert_invariant(state, context)
		if _failures > failures_before:
			return
