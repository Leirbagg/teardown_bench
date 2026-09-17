extends SceneTree

## Lance les suites de tests/cases.
##
##   godot --headless --script res://tests/run_tests.gd              # tout
##   godot --headless --script res://tests/run_tests.gd -- scoring   # seulement test_scoring.gd
##
## Le filtre est un fragment de nom de fichier. Un filtre qui ne correspond à rien est une erreur :
## sans cela, une faute de frappe afficherait « FAILURES: 0 » sans avoir rien testé.

## Plus long que le son le plus long (success.wav, 0,58 s).
const AUDIO_RELEASE_S: float = 0.8

func _initialize() -> void:
	_run.call_deferred()


## Attend une frame : l'arbre de scène doit être prêt pour les tests qui instancient des scènes.
func _run() -> void:
	await process_frame
	var filters := OS.get_cmdline_user_args()
	var paths := _suite_paths(DirAccess.get_files_at("res://tests/cases"), filters)
	if paths.is_empty():
		push_error("Aucune suite ne correspond à : %s" % " ".join(filters))
		print("FAILURES: 1")
		quit(1)
		return
	if not filters.is_empty():
		print("Filtre %s : %d suite(s)" % [" ".join(filters), paths.size()])
	var failures := 0
	for path in paths:
		var suite = load("res://tests/cases/" + path).new()
		failures += suite.run()
	print("FAILURES: %d" % failures)
	# Laisse les sons lancés par les tests de scènes se terminer : quitter pendant une lecture
	# affiche « resources still in use at exit » et masquerait une vraie fuite.
	await create_timer(AUDIO_RELEASE_S).timeout
	quit(1 if failures > 0 else 0)


## Suites à jouer, dans l'ordre du dossier. Sans filtre, toutes.
static func _suite_paths(files: PackedStringArray, filters: PackedStringArray) -> PackedStringArray:
	var paths := PackedStringArray()
	for path in files:
		if not path.ends_with(".gd"):
			continue
		if filters.is_empty():
			paths.append(path)
			continue
		for filter in filters:
			if filter in path:
				paths.append(path)
				break
	return paths
