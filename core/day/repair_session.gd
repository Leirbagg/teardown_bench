class_name RepairSession
extends RefCounted
## Réparation d'un client : état physique, diagnostic et temps réel écoulé.
## game/ appelle advance(delta) à chaque frame et pause() quand l'application passe en
## arrière-plan. La session se termine au premier test final réussi.

signal deadline_exceeded
signal completed(report: RepairReport)

var job: RepairJob
var state: DisassemblyState
var diagnosis: Diagnosis
var elapsed_s: float = 0.0

var _paused: bool = false
var _completed: bool = false
var _assisted: bool = false
var _deadline_signaled: bool = false
var _broken_parts: PackedStringArray = PackedStringArray()


## `repair_job` a été validé par RepairJob.create : ses pannes s'appliquent à l'appareil.
func _init(repair_job: RepairJob) -> void:
	job = repair_job
	state = DisassemblyState.new(job.device)
	diagnosis = Diagnosis.new(state, job.faults)
	state.component_broken.connect(_on_component_broken)


func _on_component_broken(component_id: String, _cause_id: String) -> void:
	_broken_parts.append(component_id)


# --- Temps ---

## Ignoré en pause, après la fin de la réparation, ou si `delta_s` est négatif.
func advance(delta_s: float) -> void:
	if _paused or _completed or delta_s <= 0.0:
		return
	elapsed_s += delta_s
	if not _deadline_signaled and is_deadline_exceeded():
		_deadline_signaled = true
		deadline_exceeded.emit()


func pause() -> void:
	_paused = true


func resume() -> void:
	_paused = false


func is_paused() -> bool:
	return _paused


func is_deadline_exceeded() -> bool:
	return elapsed_s > job.deadline_s


# --- Fin ---

func is_completed() -> bool:
	return _completed


## Lance le test final. S'il réussit, la session se termine et émet `completed`.
func run_final_test() -> FinalTestResult:
	if _completed:
		return FinalTestResult.new(FinalTestResult.Outcome.PASSED)
	var result: FinalTestResult = diagnosis.run_final_test()
	if result.is_passed():
		_completed = true
		completed.emit(report())
	return result


## Le mode solution a été utilisé : définitif pour cette réparation.
func mark_assisted() -> void:
	_assisted = true


func is_assisted() -> bool:
	return _assisted


func report() -> RepairReport:
	var repair_report: RepairReport = RepairReport.new()
	repair_report.job_id = job.id
	repair_report.device_id = job.device.id
	repair_report.device_name = job.device.name
	for fault: FaultDefinition in job.faults:
		repair_report.fault_ids.append(fault.id)
	repair_report.completed = _completed
	repair_report.assisted = _assisted
	repair_report.elapsed_s = elapsed_s
	repair_report.deadline_s = job.deadline_s
	repair_report.deadline_met = not is_deadline_exceeded()
	repair_report.broken_parts = _broken_parts.duplicate()
	repair_report.unnecessary_replacements = diagnosis.unnecessary_replacement_count()
	repair_report.failed_final_tests = diagnosis.failed_final_test_count()
	repair_report.replaced_parts = state.replaced_ids()
	RepairPricing.bill(repair_report, job.device, job.faults, repair_report.replaced_parts)
	return repair_report
