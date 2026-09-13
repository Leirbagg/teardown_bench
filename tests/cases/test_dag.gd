extends TestSuite


func test_acyclic_graph_has_no_cycle() -> void:
	var edges: Dictionary = {
		"cover": PackedStringArray(["screw_a", "screw_b"]),
		"screw_a": PackedStringArray(),
		"screw_b": PackedStringArray(),
		"battery": PackedStringArray(["cover"]),
	}
	assert_eq(Dag.find_cycle(edges), PackedStringArray())


func test_detects_self_loop() -> void:
	var edges: Dictionary = {"a": PackedStringArray(["a"])}
	assert_eq(Dag.find_cycle(edges), PackedStringArray(["a", "a"]))


func test_returns_cycle_path() -> void:
	var edges: Dictionary = {
		"root": PackedStringArray(),
		"a": PackedStringArray(["b"]),
		"b": PackedStringArray(["c"]),
		"c": PackedStringArray(["a", "root"]),
	}
	assert_eq(Dag.find_cycle(edges), PackedStringArray(["a", "b", "c", "a"]))


func test_ignores_unknown_targets() -> void:
	var edges: Dictionary = {"a": PackedStringArray(["missing"])}
	assert_eq(Dag.find_cycle(edges), PackedStringArray())
