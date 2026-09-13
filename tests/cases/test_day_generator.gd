extends TestSuite

var _phone: DeviceDefinition = DisassemblyFixture.load_test_phone()


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _mvp_faults() -> Array[FaultDefinition]:
	return [
		DisassemblyFixture.make_fault("screen_cracked", "screen", 1, 180.0, ["Screen is cracked.", "I dropped it."]),
		DisassemblyFixture.make_fault("battery_dead", "battery", 1, 150.0),
		DisassemblyFixture.make_fault("charge_port_faulty", "charge_port", 1, 120.0),
	]


func _generate(faults: Array[FaultDefinition], max_tier: int, seed_value: int, errors: Array[String]) -> Array[RepairJob]:
	var devices: Array[DeviceDefinition] = [_phone]
	return DayGenerator.generate(devices, faults, max_tier, _rng(seed_value), errors)


func _fault_ids(jobs: Array[RepairJob]) -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for job: RepairJob in jobs:
		ids.append(job.faults[0].id)
	return ids


func test_customer_count_stays_within_bounds() -> void:
	var counts: Dictionary = {}
	for seed_value: int in 100:
		var errors: Array[String] = []
		var jobs: Array[RepairJob] = _generate(_mvp_faults(), 1, seed_value, errors)
		assert_no_errors(errors)
		assert_true(jobs.size() >= DayGenerator.MIN_CUSTOMERS and jobs.size() <= DayGenerator.MAX_CUSTOMERS, "graine %d : %d clients" % [seed_value, jobs.size()])
		counts[jobs.size()] = true
	assert_eq(counts.size(), DayGenerator.MAX_CUSTOMERS - DayGenerator.MIN_CUSTOMERS + 1, "toutes les tailles de journée apparaissent")


func test_same_seed_gives_same_day() -> void:
	var errors: Array[String] = []
	assert_eq(_fault_ids(_generate(_mvp_faults(), 1, 42, errors)), _fault_ids(_generate(_mvp_faults(), 1, 42, errors)))


func test_job_takes_complaint_and_deadline_from_fault() -> void:
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("screen_cracked", "screen", 1, 180.0, ["Screen is cracked.", "I dropped it."])]
	for job: RepairJob in _generate(faults, 1, 7, errors):
		assert_eq(job.device.id, "test_phone")
		assert_eq(job.deadline_s, 180.0)
		assert_true(job.complaint in faults[0].complaints, "plainte issue de la panne")
	assert_no_errors(errors)


func test_job_ids_are_unique_and_ordered() -> void:
	var errors: Array[String] = []
	var jobs: Array[RepairJob] = _generate(_mvp_faults(), 1, 3, errors)
	for i: int in jobs.size():
		assert_eq(jobs[i].id, "job_%d" % (i + 1))


func test_faults_above_max_tier_are_excluded() -> void:
	var faults: Array[FaultDefinition] = _mvp_faults()
	faults.append(DisassemblyFixture.make_fault("screen_flicker", "screen", 2))
	for seed_value: int in 50:
		var errors: Array[String] = []
		assert_false("screen_flicker" in _fault_ids(_generate(faults, 1, seed_value, errors)), "graine %d" % seed_value)


func test_inapplicable_faults_are_excluded() -> void:
	var faults: Array[FaultDefinition] = _mvp_faults()
	faults.append(DisassemblyFixture.make_fault("speaker_dead", "speaker"))
	for seed_value: int in 50:
		var errors: Array[String] = []
		assert_false("speaker_dead" in _fault_ids(_generate(faults, 1, seed_value, errors)), "graine %d" % seed_value)


func test_consecutive_customers_have_different_faults_when_possible() -> void:
	for seed_value: int in 100:
		var errors: Array[String] = []
		var ids: PackedStringArray = _fault_ids(_generate(_mvp_faults(), 1, seed_value, errors))
		for i: int in range(1, ids.size()):
			assert_true(ids[i] != ids[i - 1], "graine %d : %s deux fois de suite" % [seed_value, ids[i]])


func test_single_available_fault_can_repeat() -> void:
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("battery_dead", "battery")]
	var jobs: Array[RepairJob] = _generate(faults, 1, 1, errors)
	assert_no_errors(errors)
	assert_true(jobs.size() >= DayGenerator.MIN_CUSTOMERS)


func test_reports_error_when_no_job_is_possible() -> void:
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("battery_dead", "battery", 3)]
	assert_eq(_generate(faults, 1, 1, errors).size(), 0)
	assert_has_code(errors, "no_job_available")


func test_repair_job_rejects_inapplicable_fault() -> void:
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("speaker_dead", "speaker")]
	assert_eq(RepairJob.create("job_1", _phone, faults, "Complaint.", errors), null)
	assert_has_code(errors, "inapplicable_fault")
