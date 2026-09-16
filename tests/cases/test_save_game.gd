extends TestSuite

const PATH: String = "user://test_save.json"

var _catalog: DataCatalog


func _before() -> DataCatalog:
	if _catalog == null:
		var errors: Array[String] = []
		_catalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
		assert_no_errors(errors)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	return _catalog


func _day(count: int) -> WorkDay:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var errors: Array[String] = []
	var jobs: Array[RepairJob] = DayGenerator.generate(_catalog.devices, _catalog.faults, 1, rng, errors)
	assert_no_errors(errors)
	return WorkDay.new(jobs.slice(0, count))


func test_no_save_file_reads_as_empty() -> void:
	_before()
	var errors: Array[String] = []
	assert_true(SaveGame.load_from(PATH, errors).is_empty())
	assert_no_errors(errors, "un fichier absent n'est pas une erreur")


func test_workshop_and_day_survive_a_save_and_load() -> void:
	var catalog: DataCatalog = _before()
	var workshop: Workshop = Workshop.new()
	workshop.money = 342
	workshop.day = 4
	var day: WorkDay = _day(3)
	var session: RepairSession = day.start_next_job()
	DisassemblyFixture.repair_faults(session.state, session.job.faults)
	session.advance(120.0)
	session.run_final_test()
	workshop.record_job(day.report().jobs[0])

	assert_eq(SaveGame.save(PATH, workshop, day), OK)
	var errors: Array[String] = []
	var data: Dictionary = SaveGame.load_from(PATH, errors)
	assert_no_errors(errors)
	var restored_workshop: Workshop = Workshop.from_dict(data["workshop"])
	assert_eq(restored_workshop.money, workshop.money)
	assert_eq(restored_workshop.day, 4)
	var restored_day: WorkDay = SaveGame.restore_day(data, catalog, errors)
	assert_no_errors(errors)
	assert_eq(restored_day.jobs.size(), 2, "les clients déjà servis ne reviennent pas")
	assert_eq(restored_day.jobs[0].id, day.jobs[1].id)
	assert_eq(restored_day.jobs[0].faults[0].id, day.jobs[1].faults[0].id)
	assert_eq(restored_day.jobs[0].device.id, day.jobs[1].device.id)
	assert_eq(restored_day.report().jobs.size(), 1, "le bilan garde le client terminé")
	assert_eq(restored_day.report().jobs[0].stars, day.report().jobs[0].stars)
	DirAccess.remove_absolute(PATH)


func test_a_client_left_unfinished_comes_back() -> void:
	var catalog: DataCatalog = _before()
	var day: WorkDay = _day(2)
	day.start_next_job()
	assert_eq(SaveGame.save(PATH, Workshop.new(), day), OK)
	var errors: Array[String] = []
	var restored: WorkDay = SaveGame.restore_day(SaveGame.load_from(PATH, errors), catalog, errors)
	assert_no_errors(errors)
	assert_eq(restored.jobs.size(), 2, "la réparation en cours est reprise depuis le début")
	DirAccess.remove_absolute(PATH)


func test_a_broken_save_is_reported_and_ignored() -> void:
	_before()
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	var errors: Array[String] = []
	assert_true(SaveGame.load_from(PATH, errors).is_empty())
	assert_has_code(errors, "json")
	DirAccess.remove_absolute(PATH)
