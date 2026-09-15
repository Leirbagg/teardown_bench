class_name DayReportScreen
extends Control
## Bilan de fin de journée : une ligne par client et les totaux, tels que calculés par core/.

signal new_day_pressed

@onready var _summary: Label = %Summary
@onready var _jobs: VBoxContainer = %Jobs
@onready var _new_day_button: Button = %NewDayButton


func _ready() -> void:
	_new_day_button.pressed.connect(new_day_pressed.emit)


## À appeler une fois la scène dans l'arbre.
func setup(report: DayReport) -> void:
	_summary.text = "%d/%d repaired · %d on time · %d broken part(s) · %d diagnosis error(s)\nTotal repair time: %s" % [
		report.completed_jobs(), report.planned_jobs, report.deadlines_met(),
		report.broken_parts_count(), report.diagnosis_errors(), UiFormat.time(report.total_time_s()),
	]
	if report.assisted_jobs() > 0:
		_summary.text += "\n%d assisted repair(s), not counted in the totals" % report.assisted_jobs()
	for i: int in report.jobs.size():
		var job: RepairReport = report.jobs[i]
		var line: Label = Label.new()
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", 14)
		line.text = "#%d %s — %s\n%s / %s %s · broken: %d · diagnosis errors: %d" % [
			i + 1, UiFormat.label(job.device_id), UiFormat.labels(job.fault_ids),
			UiFormat.time(job.elapsed_s), UiFormat.time(job.deadline_s),
			"assisted" if job.assisted else ("on time" if job.deadline_met else "late"),
			job.broken_parts.size(), job.diagnosis_errors(),
		]
		_jobs.add_child(line)
