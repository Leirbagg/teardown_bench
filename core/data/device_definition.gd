class_name DeviceDefinition
extends RefCounted
## Appareil réparable. Lecture seule après from_dict(). Voir docs/data_schema.md.

const FACES: PackedStringArray = ["front", "back"]


class SoftwareTest:
	extends RefCounted
	var id: String
	var roles: PackedStringArray
	## Tests préalables : si l'un échoue, celui-ci est indisponible.
	var after: PackedStringArray


var id: String
var name: String
var tier: int
var faces: PackedStringArray
## Dans l'ordre du fichier.
var components: Array[ComponentDefinition] = []
var software_tests: Array[SoftwareTest] = []

var _components_by_id: Dictionary[String, ComponentDefinition] = {}
var _components_by_role: Dictionary[String, ComponentDefinition] = {}


## Construit la définition à partir d'un dictionnaire déjà validé par DeviceValidator.
static func from_dict(data: Dictionary) -> DeviceDefinition:
	var device: DeviceDefinition = DeviceDefinition.new()
	device.id = data["id"]
	device.name = data["name"]
	device.tier = int(data["tier"])
	device.faces = PackedStringArray(data["faces"])
	for raw: Dictionary in data["components"]:
		var component: ComponentDefinition = ComponentDefinition.from_dict(raw)
		device.components.append(component)
		device._components_by_id[component.id] = component
		if not component.role.is_empty():
			device._components_by_role[component.role] = component
	for raw: Dictionary in data["software_tests"]:
		var test: SoftwareTest = SoftwareTest.new()
		test.id = raw["id"]
		test.roles = PackedStringArray(raw["roles"])
		test.after = PackedStringArray(raw["after"])
		device.software_tests.append(test)
	return device


func has_component(component_id: String) -> bool:
	return _components_by_id.has(component_id)


## Renvoie null si l'id est inconnu.
func get_component(component_id: String) -> ComponentDefinition:
	return _components_by_id.get(component_id)


## Renvoie null si aucun composant ne porte ce rôle.
func component_for_role(role: String) -> ComponentDefinition:
	return _components_by_role.get(role)


func component_ids() -> PackedStringArray:
	return PackedStringArray(_components_by_id.keys())
