extends TestSuite

const TEST_PATH: String = "user://test_settings.cfg"


func _clean() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)


func test_defaults_enable_sound_and_vibration() -> void:
	_clean()
	var settings: GameSettings = GameSettings.load_from(TEST_PATH)
	assert_true(settings.sound_enabled)
	assert_true(settings.vibration_enabled)


func test_changes_persist_across_loads() -> void:
	_clean()
	var settings: GameSettings = GameSettings.load_from(TEST_PATH)
	settings.sound_enabled = false
	settings.vibration_enabled = false
	assert_eq(settings.save(), OK)
	var reloaded: GameSettings = GameSettings.load_from(TEST_PATH)
	assert_false(reloaded.sound_enabled)
	assert_false(reloaded.vibration_enabled)
	_clean()


func test_changed_signal_fires_on_toggle() -> void:
	_clean()
	var settings: GameSettings = GameSettings.load_from(TEST_PATH)
	var count: Array[int] = [0]
	settings.changed.connect(func() -> void: count[0] += 1)
	settings.sound_enabled = false
	settings.sound_enabled = false
	settings.vibration_enabled = false
	assert_eq(count[0], 2, "une notification par vrai changement")
	_clean()


func test_corrupted_file_falls_back_to_defaults() -> void:
	var file: FileAccess = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	file.store_string("[audio\nsound_enabled = ???")
	file.close()
	expect_engine_errors(1)
	var settings: GameSettings = GameSettings.load_from(TEST_PATH)
	assert_true(settings.sound_enabled)
	_clean()
