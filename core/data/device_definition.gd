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


## Séquence exacte d'un guide public : l'ordre dans lequel un réparateur retire les pièces
## pour atteindre une pièce donnée. Le graphe autorise d'autres ordres ; celui-ci est celui
## qu'on montre et qu'on peut suivre pas à pas.
class Procedure:
	extends RefCounted
	var id: String
	var label: String
	## Rôle de la pièce qu'on vient remplacer.
	var target_role: String
	## Guide dont la séquence est tirée.
	var source: String
	## Ids des composants à retirer, dans l'ordre du guide.
	var steps: PackedStringArray


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
var procedures: Array[Procedure] = []
## Dans l'ordre du fichier, qui est l'ordre de dessin.
var decorations: Array[Decoration] = []

var _components_by_id: Dictionary[String, ComponentDefinition] = {}
var _components_by_role: Dictionary[String, ComponentDefinition] = {}
var _mounted_on: Dictionary[String, PackedStringArray] = {}


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
		if not component.mounted_on.is_empty():
			var carried: PackedStringArray = device._mounted_on.get(component.mounted_on, PackedStringArray())
			carried.append(component.id)
			device._mounted_on[component.mounted_on] = carried
	for raw: Dictionary in data["software_tests"]:
		var test: SoftwareTest = SoftwareTest.new()
		test.id = raw["id"]
		test.roles = PackedStringArray(raw["roles"])
		test.after = PackedStringArray(raw["after"])
		device.software_tests.append(test)
	for raw: Dictionary in data.get("procedures", []):
		var procedure: Procedure = Procedure.new()
		procedure.id = raw["id"]
		procedure.label = raw.get("label", "")
		procedure.target_role = raw["target_role"]
		procedure.source = raw.get("source", "")
		procedure.steps = PackedStringArray(raw["steps"])
		device.procedures.append(procedure)
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


## Pièces montées sur ce composant : elles partent avec lui si on le remplace.
func parts_mounted_on(component_id: String) -> PackedStringArray:
	return _mounted_on.get(component_id, PackedStringArray())


## Procédure menant à la pièce de ce rôle, null s'il n'y en a pas.
func procedure_for_role(role: String) -> Procedure:
	for procedure: Procedure in procedures:
		if procedure.target_role == role:
			return procedure
	return null


func component_ids() -> PackedStringArray:
	return PackedStringArray(_components_by_id.keys())
