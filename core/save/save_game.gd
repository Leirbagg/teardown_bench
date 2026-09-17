class_name SaveGame
extends RefCounted
## Sauvegarde de la progression dans user:// : l'atelier, la journée en cours et les clients déjà
## servis. Écrite après chaque client terminé. Une réparation interrompue reprend à son début.

const PATH: String = "user://save.json"
const VERSION: int = 1


static func save(path: String, workshop: Workshop, day: WorkDay) -> Error:
	var jobs: Array = []
	for job: RepairJob in day.remaining_jobs():
		jobs.append(_job_to_dict(job))
	var reports: Array = []
	for report: RepairReport in day.report().jobs:
		if report.completed:
			reports.append(_report_to_dict(report))
	var data: Dictionary = {
		"version": VERSION,
		"workshop": workshop.to_dict(),
		"day": {"jobs": jobs, "reports": reports},
	}
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return OK


## Dictionnaire vide s'il n'y a pas de sauvegarde ; `errors` décrit un fichier illisible.
static func load_from(path: String, errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("[json] %s:%d : %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY or int((json.data as Dictionary).get("version", 0)) != VERSION:
		errors.append("[version] %s : sauvegarde illisible ou d'une autre version" % path)
		return {}
	return json.data


## Reconstruit la journée sauvegardée, ou null s'il n'y a plus de client à servir.
static func restore_day(data: Dictionary, catalog: DataCatalog, errors: Array[String]) -> WorkDay:
	var day_data: Dictionary = data.get("day", {})
	var jobs: Array[RepairJob] = []
	for raw: Variant in day_data.get("jobs", []):
		var job: RepairJob = _job_from_dict(raw, catalog, errors)
		if job != null:
			jobs.append(job)
	if jobs.is_empty():
		return null
	var day: WorkDay = WorkDay.new(jobs)
	var reports: Array[RepairReport] = []
	for raw: Variant in day_data.get("reports", []):
		reports.append(_report_from_dict(raw))
	day.restore_completed(reports)
	return day


static func _job_to_dict(job: RepairJob) -> Dictionary:
	var fault_ids: PackedStringArray = PackedStringArray()
	for fault: FaultDefinition in job.faults:
		fault_ids.append(fault.id)
	return {"id": job.id, "device": job.device.id, "faults": fault_ids, "complaint": job.complaint}


static func _job_from_dict(raw: Variant, catalog: DataCatalog, errors: Array[String]) -> RepairJob:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("[bad_type] sauvegarde : un client doit être un objet")
		return null
	var data: Dictionary = raw
	var device: DeviceDefinition = catalog.find_device(str(data.get("device", "")))
	if device == null:
		errors.append("[unknown_ref] sauvegarde : appareil '%s' introuvable" % data.get("device", ""))
		return null
	var faults: Array[FaultDefinition] = []
	for fault_id: Variant in data.get("faults", []):
		var fault: FaultDefinition = catalog.find_fault(str(fault_id))
		if fault == null:
			errors.append("[unknown_ref] sauvegarde : panne '%s' introuvable" % fault_id)
			return null
		faults.append(fault)
	return RepairJob.create(str(data.get("id", "job")), device, faults, str(data.get("complaint", "")), errors)


static func _report_to_dict(report: RepairReport) -> Dictionary:
	return {
		"job_id": report.job_id, "device_id": report.device_id, "device_name": report.device_name,
		"fault_ids": report.fault_ids,
		"completed": report.completed, "assisted": report.assisted, "elapsed_s": report.elapsed_s,
		"deadline_s": report.deadline_s, "deadline_met": report.deadline_met,
		"broken_parts": report.broken_parts, "replaced_parts": report.replaced_parts,
		"unnecessary_replacements": report.unnecessary_replacements, "failed_final_tests": report.failed_final_tests,
		"payout": report.payout, "parts_cost": report.parts_cost, "deadline_bonus": report.deadline_bonus,
		"stars": report.stars,
	}


static func _report_from_dict(raw: Variant) -> RepairReport:
	var data: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
	var report: RepairReport = RepairReport.new()
	report.job_id = str(data.get("job_id", ""))
	report.device_id = str(data.get("device_id", ""))
	report.device_name = str(data.get("device_name", ""))
	report.fault_ids = PackedStringArray(data.get("fault_ids", []))
	report.completed = bool(data.get("completed", false))
	report.assisted = bool(data.get("assisted", false))
	report.elapsed_s = float(data.get("elapsed_s", 0.0))
	report.deadline_s = float(data.get("deadline_s", 0.0))
	report.deadline_met = bool(data.get("deadline_met", false))
	report.broken_parts = PackedStringArray(data.get("broken_parts", []))
	report.replaced_parts = PackedStringArray(data.get("replaced_parts", []))
	report.unnecessary_replacements = int(data.get("unnecessary_replacements", 0))
	report.failed_final_tests = int(data.get("failed_final_tests", 0))
	report.payout = int(data.get("payout", 0))
	report.parts_cost = int(data.get("parts_cost", 0))
	report.deadline_bonus = int(data.get("deadline_bonus", 0))
	report.stars = int(data.get("stars", 0))
	return report
