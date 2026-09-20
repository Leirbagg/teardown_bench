extends TestSuite
## Vérifie le contenu réel de data/ : chaque fichier est valide et cohérent avec les autres.

const DEVICES_DIR: String = "res://data/devices/"
const FAULTS_DIR: String = "res://data/faults/"


func _json_files(directory: String) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for file: String in DirAccess.get_files_at(directory):
		if file.ends_with(".json"):
			paths.append(directory + file)
	return paths


func _load_devices() -> Array[DeviceDefinition]:
	var devices: Array[DeviceDefinition] = []
	for path: String in _json_files(DEVICES_DIR):
		var errors: Array[String] = []
		var device: DeviceDefinition = DeviceLoader.load_device(path, errors)
		assert_no_errors(errors, path)
		if device != null:
			assert_eq(device.id, path.get_file().get_basename(), "l'id correspond au nom de fichier")
			devices.append(device)
	return devices


func _load_faults() -> Array[FaultDefinition]:
	var faults: Array[FaultDefinition] = []
	for path: String in _json_files(FAULTS_DIR):
		var errors: Array[String] = []
		var fault: FaultDefinition = DeviceLoader.load_fault(path, errors)
		assert_no_errors(errors, path)
		if fault != null:
			assert_eq(fault.id, path.get_file().get_basename(), "l'id correspond au nom de fichier")
			faults.append(fault)
	return faults


func test_manifest_lists_exactly_the_data_files() -> void:
	var errors: Array[String] = []
	var manifest: Dictionary = DeviceLoader.read_json(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	var listed: PackedStringArray = DataCatalog.listed_paths(manifest)
	var on_disk: PackedStringArray = _json_files(DEVICES_DIR) + _json_files(FAULTS_DIR)
	on_disk.append(ModelCatalog.PATH)
	for path: String in on_disk:
		assert_true(path in listed, "%s absent du manifeste : il ne serait pas exporté" % path)
	for path: String in listed:
		assert_true(path in on_disk, "%s listé mais introuvable" % path)
	var catalog: DataCatalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	if catalog != null:
		assert_eq(catalog.devices.size() + catalog.faults.size() + 1, on_disk.size())


func test_every_component_has_a_display_rect() -> void:
	for device: DeviceDefinition in _load_devices():
		for component: ComponentDefinition in device.components:
			assert_true(component.visual.has("rect"), "%s.%s : visual.rect manquant pour l'affichage" % [device.id, component.id])


func test_mvp_content_is_present() -> void:
	var device_ids: PackedStringArray = PackedStringArray()
	for device: DeviceDefinition in _load_devices():
		device_ids.append(device.id)
	var fault_ids: PackedStringArray = PackedStringArray()
	for fault: FaultDefinition in _load_faults():
		fault_ids.append(fault.id)
	assert_true("ipone_13" in device_ids, "ipone_13 présent")
	for fault_id: String in ["screen_cracked", "battery_dead", "charge_port_faulty"]:
		assert_true(fault_id in fault_ids, "%s présent" % fault_id)


func test_every_fault_applies_to_a_device_with_its_clue_roles() -> void:
	var devices: Array[DeviceDefinition] = _load_devices()
	for fault: FaultDefinition in _load_faults():
		var applicable: int = 0
		for device: DeviceDefinition in devices:
			if device.component_for_role(fault.target_role) == null:
				continue
			applicable += 1
			for clue: FaultDefinition.Clue in fault.clues:
				assert_true(device.component_for_role(clue.role) != null,
					"%s sur %s : rôle d'indice '%s' absent" % [fault.id, device.id, clue.role])
		assert_true(applicable > 0, "%s : aucun appareil ne porte le rôle '%s'" % [fault.id, fault.target_role])


func test_tier_one_day_can_be_generated_and_played_to_the_report() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2026
	var errors: Array[String] = []
	var jobs: Array[RepairJob] = DayGenerator.generate(_load_devices(), _load_faults(), 1, rng, errors)
	assert_no_errors(errors)
	var day: WorkDay = WorkDay.new(jobs)
	while not day.is_over():
		var session: RepairSession = day.start_next_job()
		session.advance(60.0)
		DisassemblyFixture.repair_faults(session.state, session.job.faults)
		assert_true(session.run_final_test().is_passed(), "%s : %s réparable" % [session.job.id, session.job.faults[0].id])
		if not session.is_completed():
			return
	var report: DayReport = day.report()
	assert_eq(report.completed_jobs(), jobs.size())
	assert_eq(report.broken_parts_count(), 0)
	assert_eq(report.diagnosis_errors(), 0)


func test_every_device_can_be_torn_down_and_reassembled_cleanly() -> void:
	for device: DeviceDefinition in _load_devices():
		var state: DisassemblyState = DisassemblyState.new(device)
		var order: PackedStringArray = DisassemblyFixture.teardown(state)
		assert_eq(order.size(), device.components.size(), "%s : tout est démontable" % device.id)
		assert_eq(state.broken_ids(), PackedStringArray(), "%s : démontage sans casse" % device.id)
		order.reverse()
		for id: String in order:
			state.commit_install(id)
		assert_true(state.is_fully_assembled(), "%s : remontage complet" % device.id)


## Deux appareils, deux façons d'ouvrir : le joueur doit pouvoir les distinguer et les nommer.
func test_each_device_is_a_recognisable_model() -> void:
	var names: PackedStringArray = PackedStringArray()
	for device: DeviceDefinition in _load_devices():
		assert_false(device.name.is_empty(), "%s : un nom de modèle" % device.id)
		assert_true(device.name not in names, "%s : nom déjà porté par un autre appareil" % device.name)
		names.append(device.name)
		var badges: Array = device.decorations.filter(
			func(d: DeviceDefinition.Decoration) -> bool: return d.id == "model_badge")
		assert_eq(badges.size(), 1, "%s : une plaque de modèle gravée au dos" % device.id)
		assert_true(device.name.to_upper() in (badges[0] as DeviceDefinition.Decoration).label,
			"%s : la plaque porte le nom du modèle" % device.id)


func test_tier_two_day_can_be_generated_and_played_to_the_report() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var seen: PackedStringArray = PackedStringArray()
	var faults_seen: PackedStringArray = PackedStringArray()
	for seed_value: int in 40:
		rng.seed = seed_value
		var errors: Array[String] = []
		var jobs: Array[RepairJob] = DayGenerator.generate(_load_devices(), _load_faults(), 2, rng, errors)
		assert_no_errors(errors)
		for job: RepairJob in jobs:
			if job.device.id not in seen:
				seen.append(job.device.id)
			if job.faults[0].id not in faults_seen:
				faults_seen.append(job.faults[0].id)
			var session: RepairSession = RepairSession.new(job)
			session.advance(60.0)
			DisassemblyFixture.repair_faults(session.state, job.faults)
			assert_true(session.run_final_test().is_passed(),
				"%s sur %s : réparable" % [job.faults[0].id, job.device.id])
			assert_eq(session.report().broken_parts, PackedStringArray(),
				"%s sur %s : réparation propre, sans casse" % [job.faults[0].id, job.device.id])
	assert_true("front_sensors_dead" in faults_seen, "la panne de tier 2 arrive : %s" % ", ".join(faults_seen))


## Le mode solution sert surtout face à un modèle qu'on ne connaît pas : il doit mener chaque
## panne du catalogue au test final, sur chaque appareil, sans jamais forcer une pièce.
func test_solution_mode_repairs_every_fault_of_every_device() -> void:
	for device: DeviceDefinition in _load_devices():
		for fault: FaultDefinition in _load_faults():
			if not fault.applies_to(device):
				continue
			var errors: Array[String] = []
			var state: DisassemblyState = DisassemblyState.new(device)
			var diagnosis: Diagnosis = Diagnosis.create(state, [fault], errors)
			assert_no_errors(errors)
			var where: String = "%s sur %s" % [fault.id, device.id]
			for step: SolutionStep in RepairPlanner.plan(diagnosis):
				match step.kind:
					SolutionStep.Kind.REMOVE:
						assert_eq(state.commit_remove(step.component_id).outcome,
							DisassemblyResult.Outcome.REMOVED, "%s : retrait de %s" % [where, step.component_id])
					SolutionStep.Kind.REPLACE:
						assert_eq(state.replace(step.component_id).outcome,
							DisassemblyResult.Outcome.REPLACED, "%s : pose de %s" % [where, step.component_id])
					SolutionStep.Kind.INSTALL:
						assert_eq(state.commit_install(step.component_id).outcome,
							DisassemblyResult.Outcome.INSTALLED, "%s : remontage de %s" % [where, step.component_id])
					SolutionStep.Kind.FINAL_TEST:
						assert_true(diagnosis.run_final_test().is_passed(), "%s : test final réussi" % where)
			assert_eq(state.broken_ids(), PackedStringArray(), "%s : rien de cassé en chemin" % where)
			assert_true(state.is_fully_assembled(), "%s : appareil refermé" % where)


# --- Fiches de la gamme ---

func _models() -> ModelCatalog:
	var errors: Array[String] = []
	var catalog: ModelCatalog = ModelCatalog.load_from(ModelCatalog.PATH, errors)
	assert_no_errors(errors)
	return catalog


## La gamme entière est consultable, même là où le démontage n'existe pas encore.
func test_the_whole_line_up_has_a_card() -> void:
	var catalog: ModelCatalog = _models()
	assert_true(catalog.models.size() >= 30, "la gamme va de l'X au dernier : %d fiches" % catalog.models.size())
	var ids: PackedStringArray = PackedStringArray()
	for model: ModelCatalog.Model in catalog.models:
		assert_true(model.id not in ids, "%s : fiche en double" % model.id)
		ids.append(model.id)
		assert_false(model.name.is_empty(), "%s : un nom affichable" % model.id)
		assert_true(model.year >= 2017, "%s : année plausible (%d)" % [model.id, model.year])
		assert_true(model.screen_inches > 4.0 and model.screen_inches < 8.0,
			"%s : diagonale plausible (%.1f)" % [model.id, model.screen_inches])
		assert_true(model.screen_tech in ["oled", "lcd"], "%s : dalle '%s'" % [model.id, model.screen_tech])
		assert_true(model.port in ["lightning", "usb_c"], "%s : port '%s'" % [model.id, model.port])
		assert_true(model.opens_from in ["screen", "screen_or_back"], "%s : ouverture '%s'" % [model.id, model.opens_from])
	for bound: String in ["ipone_x", "ipone_17_pro_max"]:
		assert_true(catalog.find(bound) != null, "%s présent : c'est une borne de la gamme" % bound)


## Chaque fiche renvoie à une famille décrite, et en hérite la façon de s'ouvrir.
func test_every_card_belongs_to_a_described_family() -> void:
	var catalog: ModelCatalog = _models()
	assert_true(catalog.families.size() >= 4, "plusieurs familles de démontage")
	for model: ModelCatalog.Model in catalog.models:
		var family: ModelCatalog.Family = null
		for candidate: ModelCatalog.Family in catalog.families:
			if candidate.id == model.family:
				family = candidate
		assert_true(family != null, "%s : famille '%s' décrite" % [model.id, model.family])
		if family != null:
			assert_eq(model.opens_from, family.opens_from, "%s : s'ouvre comme sa famille" % model.id)
			assert_false(family.note.is_empty(), "famille %s : une note pour le joueur" % family.id)


## Un modèle jouable désigne un démontage réellement chargé ; les autres sont consultables.
func test_playable_models_point_at_a_real_teardown() -> void:
	var catalog: ModelCatalog = _models()
	var errors: Array[String] = []
	catalog.check_teardowns(_load_devices(), errors)
	assert_no_errors(errors)
	assert_true(catalog.playable().size() >= 1, "au moins un modèle se joue")
	for model: ModelCatalog.Model in catalog.playable():
		assert_true(model.verified, "%s est jouable : sa fiche doit être vérifiée" % model.id)
	for device: DeviceDefinition in _load_devices():
		var model: ModelCatalog.Model = catalog.for_teardown(device.id)
		assert_true(model != null, "l'appareil %s doit avoir sa fiche" % device.id)
		if model != null:
			assert_eq(model.name, device.name, "%s : même nom sur la fiche et sur l'appareil" % device.id)


## Le catalogue refuse une fiche rattachée à une famille qui n'existe pas.
func test_a_card_without_a_family_is_rejected() -> void:
	var errors: Array[String] = []
	var catalog: ModelCatalog = ModelCatalog.load_from("res://tests/fixtures/models_bad_family.json", errors)
	assert_has_code(errors, "unknown_ref")
	assert_true(catalog == null, "catalogue refusé")


func _device(device_id: String) -> DeviceDefinition:
	for device: DeviceDefinition in _load_devices():
		if device.id == device_id:
			return device
	return null


## Le 14 s'ouvre des deux côtés : la batterie se débranche au dos, et comme les nappes d'écran
## l'exigent, une réparation d'écran commence forcément par retourner l'appareil.
func test_the_14_makes_you_flip_the_phone_before_touching_the_screen() -> void:
	var device: DeviceDefinition = _device("ipone_14")
	assert_true(device != null, "ipone_14 présent")
	if device == null:
		return
	assert_eq(device.get_component("battery_connector").face, "back", "la batterie se débranche au dos")
	assert_eq(device.get_component("display_connector").face, "front", "les nappes d'écran sont à l'avant")
	assert_true("battery_connector" in device.get_component("display_connector").requires,
		"on débranche la batterie avant la nappe d'écran")

	# Rabattre l'écran ne demande rien ; c'est le remplacer qui oblige à passer par le dos,
	# puisqu'il faut d'abord débrancher ses nappes, donc la batterie.
	var opened: DisassemblyState = DisassemblyState.new(device)
	DisassemblyFixture.remove_with_prerequisites(opened, "display")
	assert_false(opened.is_removed("back_glass"), "ouvrir l'écran seul n'exige pas le dos")

	var state: DisassemblyState = DisassemblyState.new(device)
	DisassemblyFixture.replace_part(state, "display")
	assert_true(state.is_removed("back_glass"), "remplacer l'écran a exigé d'ouvrir le dos")
	assert_true(state.is_removed("back_shield"), "et de déposer la plaque")
	assert_true(state.is_removed("battery_connector"), "pour débrancher la batterie")


## L'x se démonte entièrement par l'avant, mais sa carte mère est repliée en deux étages.
func test_the_x_hides_its_board_under_a_second_layer() -> void:
	var device: DeviceDefinition = _device("ipone_x")
	assert_true(device != null, "ipone_x présent")
	if device == null:
		return
	for component: ComponentDefinition in device.components:
		assert_eq(component.face, "front", "%s : tout passe par l'avant sur ce modèle" % component.id)
	assert_true("upper_board" in device.get_component("logic_board").requires,
		"l'étage supérieur part avant la carte mère")
	assert_true("upper_board" in device.get_component("logic_board").covered_by,
		"et la cache tant qu'il est en place")
	var tabs: int = 0
	for component: ComponentDefinition in device.components:
		if component.id.begins_with("battery_tab"):
			tabs += 1
	assert_eq(tabs, 2, "deux languettes de batterie, là où le 13 en a quatre")


## La route vers la batterie découle de la façon dont l'appareil s'ouvre : par l'avant sur un
## châssis d'une seule pièce, par le dos sur un châssis qui se démonte des deux côtés. Deux
## modèles d'une même génération de châssis partagent légitimement ce chemin — le 14 et le 15
## le font, et le jeu ne doit pas prétendre le contraire.
func test_the_battery_route_matches_how_the_model_opens() -> void:
	var catalog: ModelCatalog = _models()
	for device: DeviceDefinition in _load_devices():
		var model: ModelCatalog.Model = catalog.for_teardown(device.id)
		assert_true(model != null, "%s : une fiche" % device.id)
		if model == null:
			continue
		var state: DisassemblyState = DisassemblyState.new(device)
		DisassemblyFixture.replace_part(state, device.component_for_role("battery").id)
		assert_true(state.removed_ids().size() >= 3, "%s : changer la batterie demande plusieurs gestes" % device.id)
		var through_the_back: bool = false
		for id: String in state.removed_ids():
			if device.get_component(id).face == "back":
				through_the_back = true
		if model.opens_from == "screen_or_back":
			assert_true(through_the_back, "%s s'ouvre des deux côtés : la batterie passe par le dos" % device.id)
			assert_true(state.is_removed("back_glass"), "%s : le verre arrière est déposé" % device.id)
		else:
			assert_false(through_the_back, "%s s'ouvre par l'écran : la batterie ne passe pas par le dos" % device.id)


## Deux modèles ne sont jamais le même appareil recopié : leurs pièces diffèrent, ne serait-ce
## que par le port de charge.
func test_no_two_models_share_the_same_teardown() -> void:
	var seen: Dictionary[String, String] = {}
	for device: DeviceDefinition in _load_devices():
		var ids: PackedStringArray = device.component_ids()
		ids.sort()
		var signature: String = ",".join(ids)
		assert_false(seen.has(signature), "%s est la copie de %s" % [device.id, seen.get(signature, "")])
		seen[signature] = device.id
