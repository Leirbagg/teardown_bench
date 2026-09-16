class_name RepairPricing
extends RefCounted
## Facture et note d'une réparation. Le client paie le prix de la panne, plus un bonus si le délai
## est tenu ; chaque pièce posée est payée par l'atelier, y compris celles qu'on a cassées ou
## remplacées pour rien. Une réparation assistée (mode solution) ne paie ni ne coûte rien.

const DEADLINE_BONUS_RATIO: float = 0.2
const MAX_STARS: int = 5
const MIN_STARS: int = 1


## Remplit les champs d'argent et la note du rapport.
static func bill(report: RepairReport, device: DeviceDefinition, faults: Array[FaultDefinition],
		replaced_parts: PackedStringArray) -> void:
	if report.assisted:
		return
	for fault: FaultDefinition in faults:
		report.payout += fault.price
	if report.deadline_met:
		report.deadline_bonus = roundi(report.payout * DEADLINE_BONUS_RATIO)
	for component_id: String in replaced_parts:
		if device.has_component(component_id):
			report.parts_cost += device.get_component(component_id).part_price
	report.stars = stars(report)


## 5 étoiles moins une par casse, une par erreur de diagnostic et une pour un retard.
static func stars(report: RepairReport) -> int:
	if report.assisted:
		return 0
	var penalties: int = report.broken_parts.size() + report.diagnosis_errors() + (0 if report.deadline_met else 1)
	return clampi(MAX_STARS - penalties, MIN_STARS, MAX_STARS)
