class_name DayReport
extends RefCounted
## Bilan de la journée : une ligne par client commencé, et les totaux.

var planned_jobs: int
## Clients terminés puis client en cours éventuel, dans l'ordre de passage.
var jobs: Array[RepairReport] = []


func completed_jobs() -> int:
	return jobs.filter(func(job: RepairReport) -> bool: return job.completed).size()


func total_time_s() -> float:
	var total: float = 0.0
	for job: RepairReport in jobs:
		total += job.elapsed_s
	return total


## Parmi les clients terminés.
func deadlines_met() -> int:
	return jobs.filter(func(job: RepairReport) -> bool: return job.completed and job.deadline_met).size()


func broken_parts_count() -> int:
	var total: int = 0
	for job: RepairReport in jobs:
		total += job.broken_parts.size()
	return total


func diagnosis_errors() -> int:
	var total: int = 0
	for job: RepairReport in jobs:
		total += job.diagnosis_errors()
	return total
