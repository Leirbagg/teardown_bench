class_name DayGenerator
extends RefCounted
## Compose la file de clients d'une journée à partir des appareils et pannes disponibles.

## Réparations fidèles aux guides : 4 à 7 min chacune (GDD §3.1).
const MIN_CUSTOMERS: int = 2
const MAX_CUSTOMERS: int = 3


class _Candidate:
	extends RefCounted
	var device: DeviceDefinition
	var fault: FaultDefinition


## `customers` fixe le nombre de clients ; 0 le tire entre MIN_CUSTOMERS et MAX_CUSTOMERS.
## Tire les clients, chacun avec une panne applicable dont le
## tier (et celui de l'appareil) ne dépasse pas `max_tier`. Deux clients consécutifs n'ont pas
## la même panne quand une autre est possible. Résultat déterminé par la graine de `rng`.
## Renvoie un tableau vide et ajoute une erreur si aucun client n'est possible.
static func generate(devices: Array[DeviceDefinition], faults: Array[FaultDefinition], max_tier: int,
		rng: RandomNumberGenerator, errors: Array[String], customers: int = 0) -> Array[RepairJob]:
	var jobs: Array[RepairJob] = []
	var candidates: Array[_Candidate] = _candidates(devices, faults, max_tier)
	if candidates.is_empty():
		errors.append("[no_job_available] aucune panne de tier ≤ %d ne s'applique aux appareils fournis" % max_tier)
		return jobs

	var previous_fault_id: String = ""
	var count: int = customers if customers > 0 else rng.randi_range(MIN_CUSTOMERS, MAX_CUSTOMERS)
	for i: int in count:
		var pool: Array[_Candidate] = candidates.filter(func(c: _Candidate) -> bool: return c.fault.id != previous_fault_id)
		if pool.is_empty():
			pool = candidates
		var picked: _Candidate = pool[rng.randi_range(0, pool.size() - 1)]
		var complaint: String = picked.fault.complaints[rng.randi_range(0, picked.fault.complaints.size() - 1)]
		var picked_faults: Array[FaultDefinition] = [picked.fault]
		jobs.append(RepairJob.create("job_%d" % (i + 1), picked.device, picked_faults, complaint, errors))
		previous_fault_id = picked.fault.id
	return jobs


static func _candidates(devices: Array[DeviceDefinition], faults: Array[FaultDefinition], max_tier: int) -> Array[_Candidate]:
	var candidates: Array[_Candidate] = []
	for device: DeviceDefinition in devices:
		if device.tier > max_tier:
			continue
		for fault: FaultDefinition in faults:
			if fault.tier <= max_tier and fault.applies_to(device):
				var candidate: _Candidate = _Candidate.new()
				candidate.device = device
				candidate.fault = fault
				candidates.append(candidate)
	return candidates
