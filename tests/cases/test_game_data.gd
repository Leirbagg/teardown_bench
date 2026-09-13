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
	for path: String in on_disk:
		assert_true(path in listed, "%s absent du manifeste : il ne serait pas exporté" % path)
	for path: String in listed:
		assert_true(path in on_disk, "%s listé mais introuvable" % path)
	var catalog: DataCatalog = DataCatalog.load_manifest(DataCatalog.MANIFEST_PATH, errors)
	assert_no_errors(errors)
	if catalog != null:
		assert_eq(catalog.devices.size() + catalog.faults.size(), on_disk.size())


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
	assert_true("starter_phone" in device_ids, "starter_phone présent")
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
