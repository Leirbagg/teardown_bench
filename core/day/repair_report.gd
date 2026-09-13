class_name RepairReport
extends RefCounted
## Ligne du bilan pour un client, en cours ou terminé.

var job_id: String
var device_id: String
var fault_ids: PackedStringArray
var completed: bool
var elapsed_s: float
var deadline_s: float
## Temps écoulé ≤ délai. Pour un client en cours, reflète la situation à cet instant.
var deadline_met: bool
## Une entrée par casse, dans l'ordre (une pièce cassée deux fois apparaît deux fois).
var broken_parts: PackedStringArray
var unnecessary_replacements: int
var failed_final_tests: int


## Erreurs de diagnostic : remplacements inutiles et tests finaux ratés.
func diagnosis_errors() -> int:
	return unnecessary_replacements + failed_final_tests
