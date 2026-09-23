class_name Diagnosis
extends RefCounted
## Diagnostic d'une réparation : résultats des tests logiciels, indices visibles à la loupe,
## jugement des remplacements et test final. Lit un DisassemblyState sans jamais le modifier.
##
## Règles (docs/data_schema.md) :
## - Un rôle est opérationnel si son composant est en place et que ses connecteurs directs
##   (requires et replace_requires de kind "connector") sont branchés.
## - Un rôle est en panne s'il porte une panne non résolue ou si son composant est cassé.
## - Une panne est résolue au premier remplacement du composant de son rôle.
## - Un test est BLOCKED si un test de `after` n'est pas PASS, DISCONNECTED si un de ses
##   rôles n'est pas opérationnel, FAIL si un de ses rôles est en panne, PASS sinon.

enum TestStatus { PASS, FAIL, BLOCKED, DISCONNECTED }

enum ReplacementVerdict {
	## La pièce portait une panne non résolue.
	FIXED_FAULT,
	## La pièce était cassée, sans panne à résoudre.
	FIXED_BREAK,
	## La pièce était saine : erreur de diagnostic.
	UNNECESSARY,
}


class Replacement:
	extends RefCounted
	var component_id: String
	var verdict: ReplacementVerdict


var state: DisassemblyState
var device: DeviceDefinition

var _faults: Array[FaultDefinition] = []
var _resolved_fault_ids: Dictionary[String, bool] = {}
var _replacements: Array[Replacement] = []
var _failed_final_tests: int = 0


## Renvoie null et ajoute une erreur si une panne cible un rôle absent de l'appareil.
static func create(disassembly_state: DisassemblyState, faults: Array[FaultDefinition], errors: Array[String]) -> Diagnosis:
	var valid: bool = true
	for fault: FaultDefinition in faults:
		if not fault.applies_to(disassembly_state.device):
			errors.append("[inapplicable_fault] %s : l'appareil %s n'a pas de rôle '%s'" % [fault.id, disassembly_state.device.id, fault.target_role])
			valid = false
	if not valid:
		return null
	return Diagnosis.new(disassembly_state, faults)


## Préférer create(), qui vérifie que les pannes s'appliquent à l'appareil.
func _init(disassembly_state: DisassemblyState, faults: Array[FaultDefinition]) -> void:
	state = disassembly_state
	device = disassembly_state.device
	_faults = faults.duplicate()
	state.component_replaced.connect(_on_component_replaced)


# --- Rôles ---

func is_role_operational(role: String) -> bool:
	var component: ComponentDefinition = device.component_for_role(role)
	if component == null or state.is_removed(component.id):
		return false
	# Ses propres nappes comptent aussi : un écran reposé mais pas rebranché n'affiche rien.
	for requirement: String in component.requires + component.replace_requires:
		if device.get_component(requirement).kind == "connector" and state.is_removed(requirement):
			return false
	return true


func is_role_faulty(role: String) -> bool:
	var component: ComponentDefinition = device.component_for_role(role)
	if component == null:
		return false
	return state.is_broken(component.id) or not _unresolved_faults_for(role).is_empty()


func unresolved_faults() -> Array[FaultDefinition]:
	var result: Array[FaultDefinition] = []
	for fault: FaultDefinition in _faults:
		if not _resolved_fault_ids.has(fault.id):
			result.append(fault)
	return result


# --- Tests logiciels ---

## Résultat de chaque test logiciel, dans l'ordre de l'appareil.
func software_test_results() -> Dictionary[String, TestStatus]:
	var results: Dictionary[String, TestStatus] = {}
	var tests_by_id: Dictionary[String, DeviceDefinition.SoftwareTest] = {}
	for test: DeviceDefinition.SoftwareTest in device.software_tests:
		tests_by_id[test.id] = test
	for test: DeviceDefinition.SoftwareTest in device.software_tests:
		_evaluate(test, tests_by_id, results)
	var ordered: Dictionary[String, TestStatus] = {}
	for test: DeviceDefinition.SoftwareTest in device.software_tests:
		ordered[test.id] = results[test.id]
	return ordered


## Évalue un test après ses prérequis ; `after` est acyclique (DeviceValidator).
func _evaluate(test: DeviceDefinition.SoftwareTest, tests_by_id: Dictionary[String, DeviceDefinition.SoftwareTest],
		results: Dictionary[String, TestStatus]) -> TestStatus:
	if results.has(test.id):
		return results[test.id]
	var status: TestStatus = TestStatus.PASS
	for prerequisite: String in test.after:
		if _evaluate(tests_by_id[prerequisite], tests_by_id, results) != TestStatus.PASS:
			status = TestStatus.BLOCKED
	if status == TestStatus.PASS:
		for role: String in test.roles:
			if not is_role_operational(role):
				status = TestStatus.DISCONNECTED
				break
	if status == TestStatus.PASS:
		for role: String in test.roles:
			if is_role_faulty(role):
				status = TestStatus.FAIL
				break
	results[test.id] = status
	return status


# --- Indices ---

## Indices des pannes non résolues visibles maintenant : "always" en permanence, "exposed"
## quand le composant du rôle est visible.
func visible_clues() -> Array[FaultDefinition.Clue]:
	var clues: Array[FaultDefinition.Clue] = []
	for fault: FaultDefinition in unresolved_faults():
		for clue: FaultDefinition.Clue in fault.clues:
			if is_clue_visible(clue, state):
				clues.append(clue)
	return clues


## Visibilité d'un indice sur un état donné (réel ou simulé) : "always", ou "exposed" quand le
## composant du rôle est en place et visible.
static func is_clue_visible(clue: FaultDefinition.Clue, disassembly_state: DisassemblyState) -> bool:
	if clue.visibility == "always":
		return true
	var component: ComponentDefinition = disassembly_state.device.component_for_role(clue.role)
	return component != null and not disassembly_state.is_removed(component.id) and disassembly_state.is_visible(component.id)


# --- Remplacements ---

## Remplacements dans l'ordre, avec leur verdict.
func replacements() -> Array[Replacement]:
	return _replacements.duplicate()


func unnecessary_replacement_count() -> int:
	var count: int = 0
	for replacement: Replacement in _replacements:
		if replacement.verdict == ReplacementVerdict.UNNECESSARY:
			count += 1
	return count


func _on_component_replaced(component_id: String, was_broken: bool) -> void:
	var replacement: Replacement = Replacement.new()
	replacement.component_id = component_id
	var fixed_faults: Array[FaultDefinition] = _unresolved_faults_for(device.get_component(component_id).role)
	if not fixed_faults.is_empty():
		replacement.verdict = ReplacementVerdict.FIXED_FAULT
		for fault: FaultDefinition in fixed_faults:
			_resolved_fault_ids[fault.id] = true
	elif was_broken:
		replacement.verdict = ReplacementVerdict.FIXED_BREAK
	else:
		replacement.verdict = ReplacementVerdict.UNNECESSARY
	_replacements.append(replacement)


func _unresolved_faults_for(role: String) -> Array[FaultDefinition]:
	var result: Array[FaultDefinition] = []
	for fault: FaultDefinition in unresolved_faults():
		if fault.target_role == role:
			result.append(fault)
	return result


# --- Test final ---

## Réussi si l'appareil est remonté, que tous les tests logiciels passent et qu'aucune pièce
## n'est cassée. Seuls les échecs sur appareil remonté sont comptés.
func run_final_test() -> FinalTestResult:
	if not state.is_fully_assembled():
		return FinalTestResult.new(FinalTestResult.Outcome.NOT_ASSEMBLED)
	var failing: PackedStringArray = PackedStringArray()
	var results: Dictionary[String, TestStatus] = software_test_results()
	for test_id: String in results:
		if results[test_id] != TestStatus.PASS:
			failing.append(test_id)
	var broken: PackedStringArray = state.broken_ids()
	if failing.is_empty() and broken.is_empty():
		return FinalTestResult.new(FinalTestResult.Outcome.PASSED)
	_failed_final_tests += 1
	return FinalTestResult.new(FinalTestResult.Outcome.FAILED, failing, broken)


func failed_final_test_count() -> int:
	return _failed_final_tests
