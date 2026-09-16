class_name WorkDay
extends RefCounted
## Déroulé d'une journée d'atelier : les clients passent un par un, puis vient le bilan.
## Le temps entre deux clients n'est pas compté.

signal job_started(session: RepairSession)
signal job_completed(report: RepairReport)
signal day_completed(report: DayReport)

var jobs: Array[RepairJob] = []
## Réparation en cours, null entre deux clients.
var current_session: RepairSession = null

var _next_job_index: int = 0
var _completed_reports: Array[RepairReport] = []
var _paused: bool = false


func _init(day_jobs: Array[RepairJob]) -> void:
	jobs = day_jobs.duplicate()


func has_next_job() -> bool:
	return _next_job_index < jobs.size()


## Prochain client à accueillir, null s'il n'en reste plus.
func next_job() -> RepairJob:
	return jobs[_next_job_index] if has_next_job() else null


## Clients qui restent à servir, en comptant celui en cours : une réparation interrompue
## recommence depuis le début (GDD §4).
func remaining_jobs() -> Array[RepairJob]:
	var first: int = _next_job_index - (1 if current_session != null else 0)
	return jobs.slice(first)


## Réinjecte les clients déjà servis, au chargement d'une sauvegarde.
func restore_completed(reports: Array[RepairReport]) -> void:
	_completed_reports = reports.duplicate()


## Rang du prochain client, à partir de 1.
func next_job_number() -> int:
	return _next_job_index + 1


func is_over() -> bool:
	return current_session == null and not has_next_job()


## Renvoie null si un client est déjà en cours ou s'il n'en reste plus.
func start_next_job() -> RepairSession:
	if current_session != null or not has_next_job():
		return null
	current_session = RepairSession.new(jobs[_next_job_index])
	_next_job_index += 1
	if _paused:
		current_session.pause()
	current_session.completed.connect(_on_session_completed)
	job_started.emit(current_session)
	return current_session


# --- Temps ---

func advance(delta_s: float) -> void:
	if current_session != null:
		current_session.advance(delta_s)


## La pause persiste d'un client au suivant jusqu'à resume().
func pause() -> void:
	_paused = true
	if current_session != null:
		current_session.pause()


func resume() -> void:
	_paused = false
	if current_session != null:
		current_session.resume()


# --- Bilan ---

func report() -> DayReport:
	var day_report: DayReport = DayReport.new()
	day_report.planned_jobs = jobs.size()
	day_report.jobs = _completed_reports.duplicate()
	if current_session != null:
		day_report.jobs.append(current_session.report())
	return day_report


func _on_session_completed(repair_report: RepairReport) -> void:
	_completed_reports.append(repair_report)
	current_session = null
	job_completed.emit(repair_report)
	if is_over():
		day_completed.emit(report())
