class_name DeviceDefinition
extends RefCounted
## Appareil réparable. Lecture seule après from_dict(). Voir docs/data_schema.md.

const FACES: PackedStringArray = ["front", "back"]
const DECORATION_KINDS: PackedStringArray = ["frame", "board", "chip", "camera", "lens", "glass", "notch"]


class SoftwareTest:
	extends RefCounted
	var id: String
	var roles: PackedStringArray
	## Tests préalables : si l'un échoue, celui-ci est indisponible.
	var after: PackedStringArray


## Élément purement visuel (carte mère, caméra…), ignoré par les règles.
class Decoration:
	extends RefCounted
	var id: String
	var face: String
	var kind: String
	## [x, y, largeur, hauteur] dans le repère de l'appareil.
	var rect: PackedFloat32Array
	## Composant dont l'élément fait partie ("" si aucun) : affiché seulement avec lui.
	var attached_to: String
	var label: String


var id: String
var name: String
var tier: int
var faces: PackedStringArray
## Dans l'ordre du fichier.
var components: Array[ComponentDefinition] = []
var software_tests: Array[SoftwareTest] = []
## Dans l'ordre du fichier, qui est l'ordre de dessin.
var decorations: Array[Decoration] = []

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
	for raw: Dictionary in data.get("decorations", []):
		var decoration: Decoration = Decoration.new()
		decoration.id = raw["id"]
		decoration.face = raw["face"]
		decoration.kind = raw["kind"]
		decoration.rect = PackedFloat32Array(raw["rect"])
		decoration.attached_to = raw.get("attached_to", "")
		decoration.label = raw.get("label", "")
		device.decorations.append(decoration)
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
