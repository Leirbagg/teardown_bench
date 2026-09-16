class_name FaultDefinition
extends RefCounted
## Panne ciblant un rôle. Lecture seule après from_dict(). Voir docs/data_schema.md.

const CLUE_TOOLS: PackedStringArray = ["loupe"]
const CLUE_VISIBILITIES: PackedStringArray = ["always", "exposed"]


class Clue:
	extends RefCounted
	var tool_id: String
	var role: String
	var clue_id: String
	## "always" ou "exposed" (quand le composant du rôle est visible).
	var visibility: String


var id: String
var tier: int
var target_role: String
var complaints: PackedStringArray
var clues: Array[Clue] = []
var target_time_s: float
## Ce que paie le client pour cette réparation.
var price: int


## Vrai si l'appareil possède le rôle ciblé.
func applies_to(device: DeviceDefinition) -> bool:
	return device.component_for_role(target_role) != null


## Construit la définition à partir d'un dictionnaire déjà validé par DeviceValidator.
static func from_dict(data: Dictionary) -> FaultDefinition:
	var fault: FaultDefinition = FaultDefinition.new()
	fault.id = data["id"]
	fault.tier = int(data["tier"])
	fault.target_role = data["target_role"]
	fault.complaints = PackedStringArray(data["complaints"])
	fault.target_time_s = float(data["target_time_s"])
	fault.price = int(data["price"])
	for raw: Dictionary in data["clues"]:
		var clue: Clue = Clue.new()
		clue.tool_id = raw["tool"]
		clue.role = raw["role"]
		clue.clue_id = raw["clue"]
		clue.visibility = raw["visible"]
		fault.clues.append(clue)
	return fault
