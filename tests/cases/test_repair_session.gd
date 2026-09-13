extends TestSuite

const FinalOutcome = FinalTestResult.Outcome

var _phone: DeviceDefinition = DisassemblyFixture.load_test_phone()
var _events: Array[String] = []


func _session(role: String = "screen", deadline_s: float = 100.0) -> RepairSession:
	_events.clear()
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("fault_" + role, role, 1, deadline_s)]
	var job: RepairJob = RepairJob.create("job_1", _phone, faults, "Complaint.", errors)
	assert_no_errors(errors)
	var session: RepairSession = RepairSession.new(job)
	session.deadline_exceeded.connect(func() -> void: _events.append("deadline_exceeded"))
	session.completed.connect(func(report: RepairReport) -> void: _events.append("completed:" + report.job_id))
	return session


# --- Temps ---

func test_time_advances_only_when_running() -> void:
	var session: RepairSession = _session()
	session.advance(10.0)
	session.pause()
	assert_true(session.is_paused())
	session.advance(50.0)
	session.resume()
	session.advance(-5.0)
	session.advance(2.5)
	assert_eq(session.elapsed_s, 12.5)


func test_deadline_exceeded_is_emitted_once() -> void:
	var session: RepairSession = _session("screen", 30.0)
	session.advance(30.0)
	assert_false(session.is_deadline_exceeded(), "pile au délai : respecté")
	assert_true(_events.is_empty())
	session.advance(0.1)
	session.advance(10.0)
	assert_true(session.is_deadline_exceeded())
	assert_eq(_events, ["deadline_exceeded"] as Array[String])


# --- Fin de réparation ---

func test_passing_final_test_completes_session() -> void:
	var session: RepairSession = _session()
	session.advance(40.0)
	DisassemblyFixture.repair_faults(session.state, session.job.faults)
	var result: FinalTestResult = session.run_final_test()
	assert_eq(result.outcome, FinalOutcome.PASSED)
	assert_true(session.is_completed())
	assert_eq(_events, ["completed:job_1"] as Array[String])
	session.advance(100.0)
	assert_eq(session.elapsed_s, 40.0, "le temps s'arrête à la fin")


func test_failed_final_test_keeps_session_open() -> void:
	var session: RepairSession = _session("battery")
	assert_eq(session.run_final_test().outcome, FinalOutcome.FAILED)
	assert_false(session.is_completed())
	assert_true(_events.is_empty())
	session.advance(5.0)
	assert_eq(session.elapsed_s, 5.0)


func test_final_test_after_completion_does_not_complete_twice() -> void:
	var session: RepairSession = _session()
	DisassemblyFixture.repair_faults(session.state, session.job.faults)
	session.run_final_test()
	assert_eq(session.run_final_test().outcome, FinalOutcome.PASSED)
	assert_eq(_events, ["completed:job_1"] as Array[String])


# --- Rapport ---

func test_report_of_clean_repair_on_time() -> void:
	var session: RepairSession = _session("screen", 100.0)
	session.advance(60.0)
	DisassemblyFixture.repair_faults(session.state, session.job.faults)
	session.run_final_test()
	var report: RepairReport = session.report()
	assert_eq(report.job_id, "job_1")
	assert_eq(report.device_id, "test_phone")
	assert_eq(report.fault_ids, PackedStringArray(["fault_screen"]))
	assert_eq(report.elapsed_s, 60.0)
	assert_eq(report.deadline_s, 100.0)
	assert_true(report.deadline_met)
	assert_true(report.completed)
	assert_eq(report.broken_parts, PackedStringArray())
	assert_eq(report.diagnosis_errors(), 0)


func test_report_counts_breaks_and_diagnosis_errors() -> void:
	var session: RepairSession = _session("screen", 100.0)
	session.state.commit_remove("back_cover")
	session.state.commit_remove("back_cover")
	DisassemblyFixture.remove_with_prerequisites(session.state, "battery")
	session.state.replace("battery")
	session.state.replace("back_cover")
	DisassemblyFixture.reassemble(session.state)
	session.run_final_test()
	session.advance(120.0)
	DisassemblyFixture.repair_faults(session.state, session.job.faults)
	session.run_final_test()
	var report: RepairReport = session.report()
	assert_eq(report.broken_parts, PackedStringArray(["back_cover"]), "forcer deux fois ne casse qu'une fois")
	assert_eq(report.unnecessary_replacements, 1, "batterie saine")
	assert_eq(report.failed_final_tests, 1)
	assert_eq(report.diagnosis_errors(), 2)
	assert_false(report.deadline_met)


func test_report_while_in_progress_is_not_completed() -> void:
	var session: RepairSession = _session()
	session.advance(10.0)
	var report: RepairReport = session.report()
	assert_false(report.completed)
	assert_eq(report.elapsed_s, 10.0)
