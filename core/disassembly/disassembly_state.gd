class_name DisassemblyState
extends RefCounted
## État physique d'un appareil pendant une réparation : pièces retirées, cassées, remplacées.
## Applique le pilier « on punit l'intention, pas la précision » (docs/data_schema.md) :
## game/ appelle query_* au début d'un geste et commit_* quand le geste est réussi.
##
## Invariant : si un composant est retiré, tous ses requires le sont aussi.

const Outcome = DisassemblyResult.Outcome

signal component_removed(component_id: String)
signal component_installed(component_id: String)
## `cause_id` est le composant forcé.
signal component_broken(component_id: String, cause_id: String)
## `was_broken` indique l'état de la pièce retirée, avant remplacement.
signal component_replaced(component_id: String, was_broken: bool)

var device: DeviceDefinition
var graph: DisassemblyGraph

var _removed: Dictionary[String, bool] = {}
var _broken: Dictionary[String, bool] = {}
var _replaced: PackedStringArray = PackedStringArray()


func _init(device_definition: DeviceDefinition) -> void:
	device = device_definition
	graph = DisassemblyGraph.new(device)


# --- Lecture ---

func is_removed(component_id: String) -> bool:
	return _removed.has(component_id)


func is_broken(component_id: String) -> bool:
	return _broken.has(component_id)


func is_visible(component_id: String) -> bool:
	return graph.is_visible(component_id, _removed)


func is_fully_assembled() -> bool:
	return _removed.is_empty()


func removed_ids() -> PackedStringArray:
	return PackedStringArray(_removed.keys())


func broken_ids() -> PackedStringArray:
	return PackedStringArray(_broken.keys())


## Remplacements dans l'ordre, doublons compris.
func replaced_ids() -> PackedStringArray:
	return _replaced.duplicate()


## Pièces de replace_requires encore en place. Pour une pièce retirée, non vide signifie « ouverte
## mais encore attachée » (un écran rabattu tenu par ses nappes).
func attached_parts(component_id: String) -> PackedStringArray:
	return graph.attached_for_replacement(component_id, _removed)


## Copie indépendante (sans signaux connectés), pour simuler des actions sans toucher à l'état.
func snapshot() -> DisassemblyState:
	var copy: DisassemblyState = DisassemblyState.new(device)
	copy._removed = _removed.duplicate()
	copy._broken = _broken.duplicate()
	copy._replaced = _replaced.duplicate()
	return copy


# --- Retrait ---

## Prévoit l'issue d'un retrait sans rien modifier.
func query_remove(component_id: String) -> DisassemblyResult:
	if not device.has_component(component_id):
		return DisassemblyResult.new(Outcome.UNKNOWN_COMPONENT, component_id)
	if is_removed(component_id):
		return DisassemblyResult.new(Outcome.ALREADY_REMOVED, component_id)
	var hiding: PackedStringArray = graph.hiding_parts(component_id, _removed)
	if not hiding.is_empty():
		return DisassemblyResult.new(Outcome.HIDDEN, component_id, hiding)
	var blockers: PackedStringArray = graph.removal_blockers(component_id, _removed)
	if blockers.is_empty():
		return DisassemblyResult.new(Outcome.REMOVED, component_id)
	var newly_broken: PackedStringArray = PackedStringArray()
	for target: String in device.get_component(component_id).force_breaks:
		if not is_broken(target):
			newly_broken.append(target)
	return DisassemblyResult.new(Outcome.FORCED, component_id, blockers, newly_broken)


## À appeler quand le geste de retrait est réussi.
func commit_remove(component_id: String) -> DisassemblyResult:
	var result: DisassemblyResult = query_remove(component_id)
	match result.outcome:
		Outcome.REMOVED:
			_removed[component_id] = true
			component_removed.emit(component_id)
		Outcome.FORCED:
			for target: String in result.broken:
				_broken[target] = true
				component_broken.emit(target, component_id)
	return result


# --- Remontage ---

## Prévoit l'issue d'un remontage sans rien modifier.
func query_install(component_id: String) -> DisassemblyResult:
	if not device.has_component(component_id):
		return DisassemblyResult.new(Outcome.UNKNOWN_COMPONENT, component_id)
	if not is_removed(component_id):
		return DisassemblyResult.new(Outcome.ALREADY_INSTALLED, component_id)
	var blockers: PackedStringArray = graph.install_blockers(component_id, _removed)
	if not blockers.is_empty():
		return DisassemblyResult.new(Outcome.INSTALL_BLOCKED, component_id, blockers)
	return DisassemblyResult.new(Outcome.INSTALLED, component_id)


## Remonter dans le mauvais ordre est refusé sans pénalité.
func commit_install(component_id: String) -> DisassemblyResult:
	var result: DisassemblyResult = query_install(component_id)
	if result.outcome == Outcome.INSTALLED:
		_removed.erase(component_id)
		component_installed.emit(component_id)
	return result


# --- Remplacement ---

## Remplace une pièce retirée par une neuve, cassée ou non. Juger si le remplacement était
## justifié revient au diagnostic.
func replace(component_id: String) -> DisassemblyResult:
	if not device.has_component(component_id):
		return DisassemblyResult.new(Outcome.UNKNOWN_COMPONENT, component_id)
	if not device.get_component(component_id).replaceable:
		return DisassemblyResult.new(Outcome.NOT_REPLACEABLE, component_id)
	if not is_removed(component_id):
		return DisassemblyResult.new(Outcome.NOT_REMOVED, component_id)
	var attached: PackedStringArray = graph.attached_for_replacement(component_id, _removed)
	if not attached.is_empty():
		return DisassemblyResult.new(Outcome.NOT_DETACHED, component_id, attached)
	var was_broken: bool = _broken.erase(component_id)
	_replaced.append(component_id)
	component_replaced.emit(component_id, was_broken)
	return DisassemblyResult.new(Outcome.REPLACED, component_id)
