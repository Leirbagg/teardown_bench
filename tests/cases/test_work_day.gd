extends TestSuite

var _phone: DeviceDefinition = DisassemblyFixture.load_test_phone()
var _events: Array[String] = []


func _day(roles: Array[String]) -> WorkDay:
	_events.clear()
	var jobs: Array[RepairJob] = []
	for i: int in roles.size():
		var errors: Array[String] = []
		var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("fault_" + roles[i], roles[i], 1, 100.0)]
		jobs.append(RepairJob.create("job_%d" % (i + 1), _phone, faults, "Complaint.", errors))
		assert_no_errors(errors)
	var day: WorkDay = WorkDay.new(jobs)
	day.job_started.connect(func(session: RepairSession) -> void: _events.append("started:" + session.job.id))
	day.job_completed.connect(func(report: RepairReport) -> void: _events.append("completed:" + report.job_id))
	day.day_completed.connect(func(_report: DayReport) -> void: _events.append("day_completed"))
	return day


func _finish_current(day: WorkDay, seconds: float) -> void:
	day.advance(seconds)
	DisassemblyFixture.repair_faults(day.current_session.state, day.current_session.job.faults)
	assert_true(day.current_session.run_final_test().is_passed(), "préparation : réparation réussie")


func test_next_job_advances_as_jobs_start() -> void:
	var day: WorkDay = _day(["screen", "battery"])
	assert_eq(day.next_job().id, "job_1")
	assert_eq(day.next_job_number(), 1)
	day.start_next_job()
	assert_eq(day.next_job().id, "job_2")
	assert_eq(day.next_job_number(), 2)
	_finish_current(day, 1.0)
	day.start_next_job()
	assert_eq(day.next_job(), null)


func test_jobs_run_one_at_a_time() -> void:
	var day: WorkDay = _day(["screen", "battery"])
	assert_eq(day.current_session, null)
	var session: RepairSession = day.start_next_job()
	assert_eq(session.job.id, "job_1")
	assert_eq(day.start_next_job(), null, "un client à la fois")
	assert_eq(_events, ["started:job_1"] as Array[String])


func test_completing_a_job_frees_the_bench() -> void:
	var day: WorkDay = _day(["screen", "battery"])
	day.start_next_job()
	_finish_current(day, 30.0)
	assert_eq(day.current_session, null)
	assert_true(day.has_next_job())
	assert_false(day.is_over())
	assert_eq(_events, ["started:job_1", "completed:job_1"] as Array[String])


func test_last_job_completes_the_day() -> void:
	var day: WorkDay = _day(["screen", "battery"])
	day.start_next_job()
	_finish_current(day, 30.0)
	day.start_next_job()
	_finish_current(day, 45.0)
	assert_true(day.is_over())
	assert_false(day.has_next_job())
	assert_eq(day.start_next_job(), null)
	assert_eq(_events, ["started:job_1", "completed:job_1", "started:job_2", "completed:job_2", "day_completed"] as Array[String])


func test_time_between_jobs_is_not_counted() -> void:
	var day: WorkDay = _day(["screen"])
	day.advance(500.0)
	day.start_next_job()
	day.advance(20.0)
	assert_eq(day.current_session.elapsed_s, 20.0)


func test_pause_is_forwarded_and_survives_job_start() -> void:
	var day: WorkDay = _day(["screen", "battery"])
	day.start_next_job()
	day.pause()
	day.advance(50.0)
	assert_eq(day.current_session.elapsed_s, 0.0)
	day.resume()
	_finish_current(day, 10.0)
	day.pause()
	day.start_next_job()
	day.advance(50.0)
	assert_eq(day.current_session.elapsed_s, 0.0, "une journée en pause démarre le client suivant en pause")


func test_day_report_totals() -> void:
	var day: WorkDay = _day(["screen", "battery", "charge_port"])
	day.start_next_job()
	_finish_current(day, 60.0)
	var second: RepairSession = day.start_next_job()
	second.state.commit_remove("back_cover")
	second.run_final_test()
	DisassemblyFixture.remove_with_prerequisites(second.state, "back_cover")
	second.state.replace("back_cover")
	_finish_current(day, 130.0)
	day.start_next_job()
	day.advance(15.0)

	var report: DayReport = day.report()
	assert_eq(report.planned_jobs, 3)
	assert_eq(report.jobs.size(), 3, "le client en cours figure au rapport")
	assert_eq(report.completed_jobs(), 2)
	assert_eq(report.total_time_s(), 205.0)
	assert_eq(report.deadlines_met(), 1)
	assert_eq(report.broken_parts_count(), 1)
	assert_eq(report.diagnosis_errors(), 1)
	assert_false(report.jobs[2].completed)


func test_empty_day_is_over_immediately() -> void:
	var day: WorkDay = WorkDay.new([] as Array[RepairJob])
	assert_true(day.is_over())
	assert_eq(day.start_next_job(), null)
	assert_eq(day.report().planned_jobs, 0)
