class_name DisassemblyGraph
extends RefCounted
## Graphe de démontage d'un appareil, sans état. Les requêtes prennent l'ensemble des
## composants retirés sous forme de Dictionary[String, bool].

var device: DeviceDefinition

var _dependents: Dictionary[String, PackedStringArray] = {}


func _init(device_definition: DeviceDefinition) -> void:
	device = device_definition
	for component: ComponentDefinition in device.components:
		_dependents[component.id] = PackedStringArray()
	for component: ComponentDefinition in device.components:
		for requirement: String in component.requires:
			_dependents[requirement].append(component.id)


## Vrai si aucune pièce de covered_by n'est en place.
func is_visible(component_id: String, removed: Dictionary[String, bool]) -> bool:
	return _in_place(device.get_component(component_id).covered_by, removed).is_empty()


## Pièces de covered_by encore en place.
func hiding_parts(component_id: String, removed: Dictionary[String, bool]) -> PackedStringArray:
	return _in_place(device.get_component(component_id).covered_by, removed)


## Prérequis encore en place : le composant ne peut être retiré que si la liste est vide.
func removal_blockers(component_id: String, removed: Dictionary[String, bool]) -> PackedStringArray:
	return _in_place(device.get_component(component_id).requires, removed)


## Pièces de replace_requires encore en place : le remplacement attend qu'elles soient retirées.
func attached_for_replacement(component_id: String, removed: Dictionary[String, bool]) -> PackedStringArray:
	return _in_place(device.get_component(component_id).replace_requires, removed)


## Composants qui requièrent celui-ci, dans l'ordre du fichier.
func dependents(component_id: String) -> PackedStringArray:
	return _dependents[component_id]


## Dépendants encore retirés : le composant ne peut être remonté que si la liste est vide.
func install_blockers(component_id: String, removed: Dictionary[String, bool]) -> PackedStringArray:
	var blockers: PackedStringArray = PackedStringArray()
	for dependent: String in _dependents[component_id]:
		if removed.has(dependent):
			blockers.append(dependent)
	return blockers


func _in_place(ids: PackedStringArray, removed: Dictionary[String, bool]) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for id: String in ids:
		if not removed.has(id):
			result.append(id)
	return result
