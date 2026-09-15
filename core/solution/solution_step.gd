class_name SolutionStep
extends RefCounted
## Une étape du plan de réparation joué par le mode solution.

enum Kind {
	## Lancer les tests logiciels.
	RUN_TESTS,
	## Regarder un indice à la loupe sur `component_id`.
	INSPECT,
	REMOVE,
	REPLACE,
	INSTALL,
	FINAL_TEST,
}

var kind: Kind
## "" pour RUN_TESTS et FINAL_TEST.
var component_id: String


func _init(step_kind: Kind, id: String = "") -> void:
	kind = step_kind
	component_id = id
