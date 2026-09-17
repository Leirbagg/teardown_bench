class_name RepairReport
extends RefCounted
## Ligne du bilan pour un client, en cours ou terminé.

var job_id: String
var device_id: String
## Nom du modèle tel que le joueur le lit ("Wren A6"), vide pour une sauvegarde d'avant.
var device_name: String
var fault_ids: PackedStringArray
var completed: bool
## Terminée avec le mode solution : exclue des totaux de performance du bilan.
var assisted: bool
var elapsed_s: float
var deadline_s: float
## Temps écoulé ≤ délai. Pour un client en cours, reflète la situation à cet instant.
var deadline_met: bool
## Une entrée par casse, dans l'ordre (une pièce cassée deux fois apparaît deux fois).
var broken_parts: PackedStringArray
var unnecessary_replacements: int
var failed_final_tests: int
## Pièces posées, dans l'ordre (doublons compris) : ce que l'atelier a payé.
var replaced_parts: PackedStringArray
## Rempli par RepairPricing : 0 pour une réparation assistée.
var payout: int
var parts_cost: int
var deadline_bonus: int
## Note de 1 à 5, 0 si la réparation ne compte pas.
var stars: int


## Modèle affiché au joueur. Les vieilles sauvegardes n'ont que l'identifiant : on s'en contente.
func model() -> String:
	return device_name if not device_name.is_empty() else device_id.capitalize()


## Vrai si cette réparation pèse dans les totaux et la réputation. Une réparation assistée
## n'entre nulle part : le bilan doit le dire sur sa ligne, sinon ses casses semblent oubliées.
func counted_in_totals() -> bool:
	return not assisted


## Erreurs de diagnostic : remplacements inutiles et tests finaux ratés.
func diagnosis_errors() -> int:
	return unnecessary_replacements + failed_final_tests


## Gain net de la réparation : prix client et bonus, moins les pièces posées.
func earnings() -> int:
	return payout + deadline_bonus - parts_cost
