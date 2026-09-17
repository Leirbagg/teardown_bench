class_name RepairPlanner
extends RefCounted
## Calcule, depuis l'état actuel, les étapes qui mènent à un test final réussi. Tout est déduit du
## graphe et des pannes : aucune séquence codée en dur. Jouer le plan ne force jamais une pièce.
##
## 1. Lancer les tests.
## 2. Retirer, dans l'ordre des pièces libres, uniquement ce qu'exigent les pièces à remplacer
##    (pannes non résolues et casses) et leurs replace_requires ; regarder chaque indice à la loupe
##    dès qu'il devient visible.
## 3. Remplacer, puis tout remonter, puis le test final.

const Kind = SolutionStep.Kind


static func plan(diagnosis: Diagnosis) -> Array[SolutionStep]:
	var device: DeviceDefinition = diagnosis.device
	var simulated: DisassemblyState = diagnosis.state.snapshot()
	var steps: Array[SolutionStep] = [SolutionStep.new(Kind.RUN_TESTS)]

	var targets: PackedStringArray = _targets(diagnosis, simulated)
	var needed: Dictionary[String, bool] = {}
	for target: String in targets:
		_collect_prerequisites(device, target, needed)
		for attached: String in device.get_component(target).replace_requires:
			_collect_prerequisites(device, attached, needed)
		# Ce qui est monté dessus se transfère : le démonter avant, le remonter après.
		for mounted: String in device.parts_mounted_on(target):
			_collect_prerequisites(device, mounted, needed)

	var inspected: Dictionary[String, bool] = {}
	_inspect_new_clues(diagnosis, simulated, steps, inspected)
	var progressed: bool = true
	while progressed:
		progressed = false
		for component: ComponentDefinition in device.components:
			if needed.has(component.id) and not simulated.is_removed(component.id) \
					and simulated.query_remove(component.id).outcome == DisassemblyResult.Outcome.REMOVED:
				simulated.commit_remove(component.id)
				steps.append(SolutionStep.new(Kind.REMOVE, component.id))
				_inspect_new_clues(diagnosis, simulated, steps, inspected)
				progressed = true

	for target: String in targets:
		simulated.replace(target)
		steps.append(SolutionStep.new(Kind.REPLACE, target))

	progressed = true
	while progressed:
		progressed = false
		var removed: PackedStringArray = simulated.removed_ids()
		removed.reverse()
		for id: String in removed:
			if simulated.query_install(id).outcome == DisassemblyResult.Outcome.INSTALLED:
				simulated.commit_install(id)
				steps.append(SolutionStep.new(Kind.INSTALL, id))
				progressed = true
				break

	steps.append(SolutionStep.new(Kind.FINAL_TEST))
	return steps


## Pièces à remplacer : celles des pannes non résolues, puis toutes les pièces cassées.
static func _targets(diagnosis: Diagnosis, simulated: DisassemblyState) -> PackedStringArray:
	var targets: PackedStringArray = PackedStringArray()
	for fault: FaultDefinition in diagnosis.unresolved_faults():
		var id: String = diagnosis.device.component_for_role(fault.target_role).id
		if id not in targets:
			targets.append(id)
	for id: String in simulated.broken_ids():
		if id not in targets:
			targets.append(id)
	return targets


static func _collect_prerequisites(device: DeviceDefinition, id: String, needed: Dictionary[String, bool]) -> void:
	if needed.has(id):
		return
	needed[id] = true
	for requirement: String in device.get_component(id).requires:
		_collect_prerequisites(device, requirement, needed)


static func _inspect_new_clues(diagnosis: Diagnosis, simulated: DisassemblyState, steps: Array[SolutionStep],
		inspected: Dictionary[String, bool]) -> void:
	for fault: FaultDefinition in diagnosis.unresolved_faults():
		for clue: FaultDefinition.Clue in fault.clues:
			var component: ComponentDefinition = diagnosis.device.component_for_role(clue.role)
			var key: String = "%s/%s" % [fault.id, clue.clue_id]
			if inspected.has(key) or component == null or simulated.is_removed(component.id):
				continue
			if Diagnosis.is_clue_visible(clue, simulated):
				inspected[key] = true
				steps.append(SolutionStep.new(Kind.INSPECT, component.id))
