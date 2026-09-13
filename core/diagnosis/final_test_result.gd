class_name FinalTestResult
extends RefCounted
## Résultat du test final joué en fin de réparation.

enum Outcome {
	PASSED,
	FAILED,
	## L'appareil n'est pas entièrement remonté : le test n'a pas eu lieu.
	NOT_ASSEMBLED,
}

var outcome: Outcome
## Tests logiciels qui ne sont pas PASS, dans l'ordre de l'appareil.
var failing_tests: PackedStringArray
## Pièces encore cassées, avec ou sans rôle.
var broken_ids: PackedStringArray


func _init(result_outcome: Outcome, failing: PackedStringArray = PackedStringArray(),
		broken: PackedStringArray = PackedStringArray()) -> void:
	outcome = result_outcome
	failing_tests = failing
	broken_ids = broken


func is_passed() -> bool:
	return outcome == Outcome.PASSED
