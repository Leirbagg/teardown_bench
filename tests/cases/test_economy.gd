extends TestSuite

var _device: DeviceDefinition = DisassemblyFixture.load_test_phone()


func _report(overrides: Dictionary = {}) -> RepairReport:
	var report: RepairReport = RepairReport.new()
	report.job_id = "job_1"
	report.device_id = _device.id
	report.completed = true
	report.deadline_met = true
	report.elapsed_s = 100.0
	report.deadline_s = 200.0
	for key: String in overrides:
		report.set(key, overrides[key])
	return report


func _priced(faults: Array[FaultDefinition], replaced: PackedStringArray, overrides: Dictionary = {}) -> RepairReport:
	var report: RepairReport = _report(overrides)
	RepairPricing.bill(report, _device, faults, replaced)
	return report


func _fault(price: int) -> Array[FaultDefinition]:
	var data: Dictionary = {
		"schema_version": 1, "id": "screen_cracked", "tier": 1, "target_role": "screen",
		"complaints": ["Cracked."], "clues": [], "target_time_s": 100, "price": price,
	}
	return [FaultDefinition.from_dict(data)]


# --- Facture ---

func test_clean_repair_pays_the_fault_price_minus_the_part() -> void:
	var report: RepairReport = _priced(_fault(149), PackedStringArray(["screen"]))
	assert_eq(report.payout, 149)
	assert_eq(report.deadline_bonus, roundi(149 * RepairPricing.DEADLINE_BONUS_RATIO))
	assert_eq(report.parts_cost, _device.get_component("screen").part_price)
	assert_eq(report.earnings(), report.payout + report.deadline_bonus - report.parts_cost)
	assert_eq(report.stars, 5)


func test_late_repair_loses_the_bonus_and_a_star() -> void:
	var report: RepairReport = _priced(_fault(149), PackedStringArray(["screen"]), {"deadline_met": false})
	assert_eq(report.deadline_bonus, 0)
	assert_eq(report.stars, 4)


func test_wasted_parts_and_breakages_eat_the_margin() -> void:
	var report: RepairReport = _priced(_fault(149), PackedStringArray(["screen", "battery", "back_cover"]),
		{"broken_parts": PackedStringArray(["back_cover"]), "unnecessary_replacements": 1})
	var expected: int = _device.get_component("screen").part_price + _device.get_component("battery").part_price \
		+ _device.get_component("back_cover").part_price
	assert_eq(report.parts_cost, expected, "chaque pièce posée est payée")
	assert_eq(report.stars, 3, "une casse et une erreur de diagnostic")


func test_stars_never_go_below_one_on_a_finished_repair() -> void:
	var report: RepairReport = _priced(_fault(149), PackedStringArray(),
		{"deadline_met": false, "broken_parts": PackedStringArray(["a", "b", "c"]), "unnecessary_replacements": 4})
	assert_eq(report.stars, 1)


func test_assisted_repair_neither_pays_nor_costs() -> void:
	var report: RepairReport = _priced(_fault(149), PackedStringArray(["screen"]), {"assisted": true})
	assert_eq(report.payout, 0)
	assert_eq(report.parts_cost, 0)
	assert_eq(report.earnings(), 0)
	assert_eq(report.stars, 0, "pas de note pour un entraînement")


# --- Atelier ---

func test_workshop_accumulates_money_and_ratings() -> void:
	var workshop: Workshop = Workshop.new()
	var start: int = workshop.money
	var report: RepairReport = _priced(_fault(149), PackedStringArray(["screen"]))
	assert_eq(workshop.record_job(report), report.earnings())
	assert_eq(workshop.money, start + report.earnings())
	assert_eq(workshop.reputation(), 5.0)
	assert_eq(workshop.jobs_done(), 1)


func test_assisted_and_unfinished_jobs_do_not_count() -> void:
	var workshop: Workshop = Workshop.new()
	var start: int = workshop.money
	workshop.record_job(_priced(_fault(149), PackedStringArray(["screen"]), {"assisted": true}))
	workshop.record_job(_priced(_fault(149), PackedStringArray([]), {"completed": false}))
	assert_eq(workshop.money, start)
	assert_eq(workshop.jobs_done(), 0)
	assert_eq(workshop.reputation(), 0.0)


func test_money_never_goes_below_zero() -> void:
	var workshop: Workshop = Workshop.new()
	workshop.money = 10
	var ruinous: PackedStringArray = PackedStringArray(["screen", "screen", "screen", "battery"])
	var report: RepairReport = _priced(_fault(20), ruinous)
	assert_true(report.earnings() < 0, "préparation : réparation à perte")
	workshop.record_job(report)
	assert_eq(workshop.money, 0, "jamais bloqué, jamais de dette")


func test_reputation_unlocks_the_next_tier() -> void:
	var workshop: Workshop = Workshop.new()
	assert_eq(workshop.max_tier(), 1)
	for i: int in 3:
		workshop.record_job(_priced(_fault(149), PackedStringArray(["screen"])))
	assert_eq(workshop.reputation(), 5.0)
	assert_eq(workshop.max_tier(), Workshop.TIER_THRESHOLDS.size() + 1, "5 étoiles : tout est débloqué")
	var messy: RepairReport = _priced(_fault(149), PackedStringArray(),
		{"deadline_met": false, "broken_parts": PackedStringArray(["a", "b"]), "unnecessary_replacements": 2})
	for i: int in 6:
		workshop.record_job(messy)
	assert_true(workshop.reputation() < 3.5, "des réparations ratées font redescendre")
	assert_eq(workshop.max_tier(), 1)


func test_reputation_only_looks_at_the_recent_repairs() -> void:
	var workshop: Workshop = Workshop.new()
	var messy: RepairReport = _priced(_fault(149), PackedStringArray(),
		{"deadline_met": false, "broken_parts": PackedStringArray(["a", "b", "c"]), "unnecessary_replacements": 4})
	for i: int in 6:
		workshop.record_job(messy)
	assert_eq(workshop.reputation(), 1.0)
	for i: int in Workshop.RATING_WINDOW:
		workshop.record_job(_priced(_fault(149), PackedStringArray(["screen"])))
	assert_eq(workshop.reputation(), 5.0, "les vieilles réparations sortent de la moyenne")
	assert_eq(workshop.jobs_done(), 6 + Workshop.RATING_WINDOW, "mais le compteur garde tout")


func test_workshop_survives_a_save_and_load() -> void:
	var workshop: Workshop = Workshop.new()
	workshop.record_job(_priced(_fault(149), PackedStringArray(["screen"])))
	workshop.finish_day()
	var restored: Workshop = Workshop.from_dict(workshop.to_dict())
	assert_eq(restored.money, workshop.money)
	assert_eq(restored.day, workshop.day)
	assert_eq(restored.reputation(), workshop.reputation())
	assert_eq(restored.jobs_done(), workshop.jobs_done())
