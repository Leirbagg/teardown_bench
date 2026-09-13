class_name RepairJob
extends RefCounted
## Un client de la journée : un appareil, ses pannes, sa plainte et son délai.

var id: String
var device: DeviceDefinition
var faults: Array[FaultDefinition] = []
var complaint: String
## Temps réel de réparation promis au client, en secondes.
var deadline_s: float


## Renvoie null et ajoute une erreur si une panne ne s'applique pas à l'appareil.
## Le délai est la somme des target_time_s des pannes.
static func create(job_id: String, job_device: DeviceDefinition, job_faults: Array[FaultDefinition],
		job_complaint: String, errors: Array[String]) -> RepairJob:
	var valid: bool = true
	for fault: FaultDefinition in job_faults:
		if not fault.applies_to(job_device):
			errors.append("[inapplicable_fault] %s : %s n'a pas de rôle '%s'" % [job_id, job_device.id, fault.target_role])
			valid = false
	if not valid:
		return null
	var job: RepairJob = RepairJob.new()
	job.id = job_id
	job.device = job_device
	job.faults = job_faults.duplicate()
	job.complaint = job_complaint
	for fault: FaultDefinition in job_faults:
		job.deadline_s += fault.target_time_s
	return job
