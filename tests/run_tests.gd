extends SceneTree

func _initialize() -> void:
	var failures := 0
	for path in DirAccess.get_files_at("res://tests/cases"):
		if not path.ends_with(".gd"): continue
		var suite = load("res://tests/cases/" + path).new()
		failures += suite.run()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)
