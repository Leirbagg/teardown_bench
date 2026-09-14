extends SceneTree

## Plus long que le son le plus long (success.wav, 0,58 s).
const AUDIO_RELEASE_S: float = 0.8

func _initialize() -> void:
	_run.call_deferred()


## Attend une frame : l'arbre de scène doit être prêt pour les tests qui instancient des scènes.
func _run() -> void:
	await process_frame
	var failures := 0
	for path in DirAccess.get_files_at("res://tests/cases"):
		if not path.ends_with(".gd"): continue
		var suite = load("res://tests/cases/" + path).new()
		failures += suite.run()
	print("FAILURES: %d" % failures)
	# Laisse les sons lancés par les tests de scènes se terminer : quitter pendant une lecture
	# affiche « resources still in use at exit » et masquerait une vraie fuite.
	await create_timer(AUDIO_RELEASE_S).timeout
	quit(1 if failures > 0 else 0)
