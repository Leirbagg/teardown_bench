class_name ComponentDefinition
extends RefCounted
## Composant d'un appareil. Lecture seule après from_dict(). Voir docs/data_schema.md.

const KINDS: PackedStringArray = ["screw", "cover", "connector", "adhesive", "module"]
const GESTURES: PackedStringArray = ["rotate", "pull", "hold", "pry"]

var id: String
var kind: String
var face: String
var gesture: String
## Réglages de reconnaissance du geste, lus par game/ uniquement.
var gesture_params: Dictionary
var requires: PackedStringArray
## Sous-ensemble de requires : pièces qui cachent le composant.
var covered_by: PackedStringArray
## Chaîne vide si le composant n'a pas de rôle.
var role: String
var replaceable: bool
var force_breaks: PackedStringArray
## Vrai si le composant peut être visible tout en étant retenu, donc forcé.
var forceable: bool
## Données d'affichage, ignorées par core/.
var visual: Dictionary


## Construit la définition à partir d'un dictionnaire déjà validé par DeviceValidator.
static func from_dict(data: Dictionary) -> ComponentDefinition:
	var component: ComponentDefinition = ComponentDefinition.new()
	component.id = data["id"]
	component.kind = data["kind"]
	component.face = data["face"]
	component.gesture = data["gesture"]
	component.gesture_params = data.get("gesture_params", {})
	component.requires = PackedStringArray(data["requires"])
	component.covered_by = PackedStringArray(data["covered_by"])
	component.role = data.get("role", "")
	component.replaceable = data.get("replaceable", false)
	component.force_breaks = resolve_force_breaks(component.id, PackedStringArray(data.get("force_breaks", [])))
	component.forceable = is_forceable(component.requires, component.covered_by)
	component.visual = data.get("visual", {})
	return component


## Un composant est forçable si au moins un prérequis le retient sans le cacher.
static func is_forceable(requires_ids: PackedStringArray, covered_by_ids: PackedStringArray) -> bool:
	for requirement: String in requires_ids:
		if requirement not in covered_by_ids:
			return true
	return false


## Sans force_breaks explicite, forcer un composant casse le composant lui-même.
static func resolve_force_breaks(component_id: String, listed: PackedStringArray) -> PackedStringArray:
	return listed if not listed.is_empty() else PackedStringArray([component_id])
