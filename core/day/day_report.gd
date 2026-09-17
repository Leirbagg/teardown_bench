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


func assisted_jobs() -> int:
	return jobs.filter(func(job: RepairReport) -> bool: return job.assisted).size()


## Clients dont la ligne pèse dans les totaux ci-dessous : les totaux se lisent sur ceux-là.
func jobs_in_totals() -> int:
	return jobs.filter(func(job: RepairReport) -> bool: return job.counted_in_totals()).size()


## Parmi les clients terminés sans le mode solution.
func deadlines_met() -> int:
	return jobs.filter(func(job: RepairReport) -> bool: return job.completed and job.deadline_met and job.counted_in_totals()).size()


## Hors réparations assistées.
func broken_parts_count() -> int:
	var total: int = 0
	for job: RepairReport in jobs:
		if job.counted_in_totals():
			total += job.broken_parts.size()
	return total


## Hors réparations assistées.
func diagnosis_errors() -> int:
	var total: int = 0
	for job: RepairReport in jobs:
		if job.counted_in_totals():
			total += job.diagnosis_errors()
	return total
