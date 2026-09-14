class_name DisassemblyResult
extends RefCounted
## Issue d'une action de démontage, de remontage ou de remplacement, réelle ou prévue.

enum Outcome {
	REMOVED,
	INSTALLED,
	REPLACED,
	## Composant visible mais retenu : le geste terminé casse les pièces de `broken`.
	FORCED,
	## Composant caché : aucune conséquence.
	HIDDEN,
	## Remontage dans le mauvais ordre : aucune conséquence.
	INSTALL_BLOCKED,
	ALREADY_REMOVED,
	ALREADY_INSTALLED,
	## Remplacement d'une pièce encore en place.
	NOT_REMOVED,
	## Remplacement refusé : des pièces de replace_requires sont encore en place (dans `blockers`).
	NOT_DETACHED,
	NOT_REPLACEABLE,
	UNKNOWN_COMPONENT,
}

var outcome: Outcome
var component_id: String
## Pièces qui empêchent l'action : requires en place (retrait), dépendants retirés (remontage).
var blockers: PackedStringArray
## Pièces nouvellement cassées par l'action (FORCED uniquement).
var broken: PackedStringArray


func _init(result_outcome: Outcome, id: String, blocking_ids: PackedStringArray = PackedStringArray(),
		broken_ids: PackedStringArray = PackedStringArray()) -> void:
	outcome = result_outcome
	component_id = id
	blockers = blocking_ids
	broken = broken_ids


func is_success() -> bool:
	return outcome in [Outcome.REMOVED, Outcome.INSTALLED, Outcome.REPLACED]
