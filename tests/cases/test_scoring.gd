extends TestSuite
## Comptage des scores de bout en bout : une casse réelle sur l'appareil doit se retrouver,
## sans se perdre ni se dédoubler, dans le rapport du client, dans le bilan de la journée, dans
## la note, dans le porte-monnaie et après une sauvegarde.
## Les suites test_economy et test_work_day vérifient chaque pièce isolément ; ici on vérifie
## qu'elles s'accordent, puisque c'est leur désaccord que le joueur lit à l'écran.

const SAVE_PATH: String = "user://test_scoring_save.json"

var _phone: DeviceDefinition = DisassemblyFixture.load_test_phone()


func _job(id: String, role: String, target_time_s: float = 100.0) -> RepairJob:
	var errors: Array[String] = []
	var faults: Array[FaultDefinition] = [DisassemblyFixture.make_fault("fault_" + id, role, 1, target_time_s)]
	var job: RepairJob = RepairJob.create(id, _phone, faults, "Complaint.", errors)
	assert_no_errors(errors)
	return job


func _day(roles: Array[String]) -> WorkDay:
	var jobs: Array[RepairJob] = []
	for i: int in roles.size():
		jobs.append(_job("job_%d" % (i + 1), roles[i]))
	return WorkDay.new(jobs)


## Journée faite d'appareils et de pannes du catalogue : la sauvegarde ne sait relire que ceux-là.
func _catalog_day(catalog: DataCatalog, fault_ids: Array[String]) -> WorkDay:
	var jobs: Array[RepairJob] = []
	for i: int in fault_ids.size():
		var errors: Array[String] = []
		var faults: Array[FaultDefinition] = [catalog.find_fault(fault_ids[i])]
		assert_true(faults[0] != null, "panne '%s' du catalogue" % fault_ids[i])
		jobs.append(RepairJob.create("job_%d" % (i + 1), catalog.devices[0], faults, "Complaint.", errors))
		assert_no_errors(errors)
	return WorkDay.new(jobs)


## Casse l'écran en arrachant sa nappe : le dos est ouvert, mais la nappe tient encore au
## connecteur de batterie. C'est le geste que le joueur peut faire, et qui casse.
func _force_the_screen_flex(state: DisassemblyState) -> DisassemblyResult:
	DisassemblyFixture.remove_with_prerequisites(state, "back_cover")
	return state.commit_remove("screen_flex")


## Pose une pièce neuve à la place de celle qu'on a cassée, nappes détachées comprises.
func _replace_part(state: DisassemblyState, component_id: String) -> void:
	DisassemblyFixture.remove_with_prerequisites(state, component_id)
	for attached: String in state.device.get_component(component_id).replace_requires:
		DisassemblyFixture.remove_with_prerequisites(state, attached)
	assert_eq(state.replace(component_id).outcome, DisassemblyResult.Outcome.REPLACED,
		"préparation : pièce neuve posée")


func _repair_and_finish(session: RepairSession) -> RepairReport:
	DisassemblyFixture.repair_faults(session.state, session.job.faults)
	assert_true(session.run_final_test().is_passed(), "préparation : réparation terminée")
	return session.report()


# --- Une casse, un compte ---

func test_a_breakage_reaches_the_report_once_per_break() -> void:
	var session: RepairSession = RepairSession.new(_job("job_1", "battery"))
	var forced: DisassemblyResult = _force_the_screen_flex(session.state)
	assert_eq(forced.outcome, DisassemblyResult.Outcome.FORCED, "préparation : la nappe résiste")
	assert_eq(forced.broken, PackedStringArray(["screen"]), "préparation : l'écran casse")
	assert_eq(session.report().broken_parts, PackedStringArray(["screen"]))

	# S'acharner sur la même nappe ne recasse pas un écran déjà cassé.
	_force_the_screen_flex(session.state)
	_force_the_screen_flex(session.state)
	assert_eq(session.report().broken_parts, PackedStringArray(["screen"]), "une casse, pas trois")


func test_breaking_a_part_twice_counts_twice() -> void:
	var session: RepairSession = RepairSession.new(_job("job_1", "battery"))
	_force_the_screen_flex(session.state)
	_replace_part(session.state, "screen")
	DisassemblyFixture.reassemble(session.state)
	_force_the_screen_flex(session.state)
	assert_eq(session.report().broken_parts, PackedStringArray(["screen", "screen"]),
		"une pièce neuve recassée est une seconde casse")


func test_a_breakage_costs_a_star_and_the_new_part() -> void:
	var session: RepairSession = RepairSession.new(_job("job_1", "battery"))
	var clean: RepairReport = _repair_and_finish(RepairSession.new(_job("job_1", "battery")))
	_force_the_screen_flex(session.state)
	_replace_part(session.state, "screen")
	var report: RepairReport = _repair_and_finish(session)

	assert_eq(report.broken_parts.size(), 1)
	assert_eq(report.stars, clean.stars - 1, "une casse coûte une étoile, et une seule")
	assert_eq(report.unnecessary_replacements, 0, "remplacer la pièce qu'on a cassée n'est pas une erreur de plus")
	assert_eq(report.parts_cost, clean.parts_cost + _phone.get_component("screen").part_price,
		"l'atelier paie l'écran cassé")
	assert_eq(report.earnings(), report.payout + report.deadline_bonus - report.parts_cost)


func test_a_broken_part_left_in_place_fails_the_final_test() -> void:
	var session: RepairSession = RepairSession.new(_job("job_1", "battery"))
	_force_the_screen_flex(session.state)
	DisassemblyFixture.repair_faults(session.state, session.job.faults)
	assert_false(session.run_final_test().is_passed(), "l'écran cassé reste cassé")
	var report: RepairReport = session.report()
	assert_false(report.completed)
	assert_eq(report.failed_final_tests, 1)
	assert_eq(report.stars, RepairPricing.MAX_STARS - 2, "la casse et le test raté comptent chacun")


# --- Bilan de la journée ---

## Le joueur lit le total en haut et les lignes en dessous : ils doivent raconter la même chose.
func test_the_day_totals_match_the_sum_of_the_lines() -> void:
	var day: WorkDay = _day(["battery", "screen"])
	var first: RepairSession = day.start_next_job()
	day.advance(10.0)
	_force_the_screen_flex(first.state)
	_replace_part(first.state, "screen")
	_repair_and_finish(first)

	var second: RepairSession = day.start_next_job()
	day.advance(10.0)
	_repair_and_finish(second)

	var report: DayReport = day.report()
	var broken: int = 0
	var errors: int = 0
	var time: float = 0.0
	for job: RepairReport in report.jobs:
		broken += job.broken_parts.size()
		errors += job.diagnosis_errors()
		time += job.elapsed_s
	assert_eq(report.jobs.size(), 2, "une ligne par client")
	assert_eq(report.broken_parts_count(), broken, "total des casses = somme des lignes")
	assert_eq(report.diagnosis_errors(), errors)
	assert_eq(report.total_time_s(), time)
	assert_eq(report.completed_jobs(), 2)
	assert_eq(report.planned_jobs, 2)


## Une réparation assistée sort des totaux de performance (GDD §3.7) : sa ligne doit le dire,
## sinon le joueur croit à un total faux.
func test_an_assisted_repair_is_visibly_out_of_the_totals() -> void:
	var day: WorkDay = _day(["battery"])
	var session: RepairSession = day.start_next_job()
	day.advance(10.0)
	_force_the_screen_flex(session.state)
	_replace_part(session.state, "screen")
	session.mark_assisted()
	_repair_and_finish(session)

	var report: DayReport = day.report()
	var line: RepairReport = report.jobs[0]
	assert_eq(report.assisted_jobs(), 1)
	assert_eq(line.broken_parts.size(), 1, "la casse a bien eu lieu")
	assert_eq(report.broken_parts_count(), 0, "mais elle ne compte pas dans les totaux")
	assert_eq(line.counted_in_totals(), false, "la ligne sait qu'elle ne compte pas")
	assert_eq(report.deadlines_met(), 0, "ni dans les délais tenus")
	assert_eq(report.jobs_in_totals(), 0, "aucun client ne compte aujourd'hui")


func test_a_day_where_nothing_counts_still_reports_its_lines() -> void:
	var day: WorkDay = _day(["battery"])
	var session: RepairSession = day.start_next_job()
	session.mark_assisted()
	_repair_and_finish(session)
	var report: DayReport = day.report()
	assert_eq(report.completed_jobs(), 1, "le client est bien reparti réparé")
	assert_eq(report.jobs_in_totals(), 0)
	assert_eq(report.broken_parts_count(), 0)


func test_the_deadline_is_judged_on_the_time_actually_spent() -> void:
	var day: WorkDay = _day(["battery"])
	var session: RepairSession = day.start_next_job()
	day.advance(session.job.deadline_s + 1.0)
	var report: RepairReport = _repair_and_finish(session)
	assert_false(report.deadline_met)
	assert_eq(report.deadline_bonus, 0)
	assert_eq(day.report().deadlines_met(), 0)
	assert_eq(report.stars, RepairPricing.MAX_STARS - 1, "le retard coûte une étoile")


# --- Sauvegarde ---

## Le bilan s'affiche après la sauvegarde : il doit survivre au rechargement sans rien perdre.
## Journée bâtie sur le vrai catalogue, seul chemin que la sauvegarde sait relire.
func test_a_resumed_day_keeps_its_score_and_its_client_count() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	var errors: Array[String] = []
	var catalog: DataCatalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	var day: WorkDay = _catalog_day(catalog, ["battery_dead", "screen_cracked"])
	var workshop: Workshop = Workshop.new()
	var session: RepairSession = day.start_next_job()
	day.advance(10.0)
	# Arracher la nappe de l'écran alors que la batterie est encore branchée casse l'écran.
	DisassemblyFixture.remove_with_prerequisites(session.state, "connector_cover")
	var forced: DisassemblyResult = session.state.commit_remove("display_connector")
	assert_eq(forced.outcome, DisassemblyResult.Outcome.FORCED, "préparation : la nappe est retenue")
	_replace_part(session.state, "display")
	var first: RepairReport = _repair_and_finish(session)
	assert_eq(first.broken_parts, PackedStringArray(["display"]), "préparation : l'écran a cassé")
	workshop.record_job(first)
	assert_eq(SaveGame.save(SAVE_PATH, workshop, day), OK)

	var data: Dictionary = SaveGame.load_from(SAVE_PATH, errors)
	assert_no_errors(errors)
	var resumed: WorkDay = SaveGame.restore_day(data, catalog, errors)
	assert_no_errors(errors)
	assert_true(resumed != null, "la journée reprend")

	var report: DayReport = resumed.report()
	var restored: RepairReport = report.jobs[0]
	assert_eq(restored.broken_parts, first.broken_parts, "les casses survivent")
	assert_eq(restored.stars, first.stars)
	assert_eq(restored.earnings(), first.earnings())
	assert_eq(report.broken_parts_count(), 1, "et comptent encore dans le bilan")
	assert_eq(report.planned_jobs, 2, "la journée comptait deux clients, pas seulement ceux qui restent")
	assert_eq(report.completed_jobs(), 1)
	assert_true(report.completed_jobs() <= report.planned_jobs,
		"on ne répare jamais plus de clients qu'il n'en était prévu")
	DirAccess.remove_absolute(SAVE_PATH)


# --- Atelier ---

func test_the_wallet_follows_the_reports_of_the_day() -> void:
	var day: WorkDay = _day(["battery", "screen"])
	var workshop: Workshop = Workshop.new()
	var start: int = workshop.money
	var expected: int = 0
	while day.has_next_job():
		var session: RepairSession = day.start_next_job()
		day.advance(10.0)
		var report: RepairReport = _repair_and_finish(session)
		expected += report.earnings()
		workshop.record_job(report)
	assert_eq(workshop.money, start + expected, "le porte-monnaie suit les gains affichés")
	assert_eq(workshop.jobs_done(), 2)
	assert_eq(workshop.reputation(), 5.0, "deux réparations propres")
