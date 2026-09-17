class_name SolutionPlayer
extends Node
## Joue le plan du mode solution sur l'établi, étape par étape : explication, action, courte
## pause. Le plan vient de core/ (RepairPlanner) ; l'établi exécute chaque étape par les mêmes
## chemins que le joueur. Piloté par advance(delta), sans timer asynchrone : testable sans écran.

signal step_started(index: int, count: int, caption: String)
## Arrêt demandé par le joueur, qui reprend la main.
signal stopped
## Plan joué jusqu'au test final.
signal finished

enum Phase { IDLE, INTRO, ACTING, OUTRO }

## Temps de lecture de l'explication avant l'action, à vitesse 1.
const INTRO_S: float = 1.4
const OUTRO_S: float = 0.5
## Les remontages s'enchaînent vite : ils ne demandent pas de geste.
const QUICK_INTRO_S: float = 0.35
const QUICK_OUTRO_S: float = 0.15

var speed: float = 1.0
var paused: bool = false

var _workbench: Workbench
var _plan: Array[SolutionStep] = []
var _index: int = -1
var _phase: Phase = Phase.IDLE
var _timer_s: float = 0.0


func is_running() -> bool:
	return _phase != Phase.IDLE


## Recalcule le plan depuis l'état actuel de la réparation et commence.
func start(workbench: Workbench) -> void:
	_workbench = workbench
	_plan = RepairPlanner.plan(workbench.session.diagnosis)
	_index = -1
	paused = false
	_next_step()


func stop() -> void:
	if not is_running():
		return
	_phase = Phase.IDLE
	_workbench.cancel_solution_step()
	stopped.emit()


## Passe à la suite sans attendre : saute la pause, ou termine le geste en cours.
func skip() -> void:
	match _phase:
		Phase.INTRO, Phase.OUTRO:
			_timer_s = 0.0
		Phase.ACTING:
			_workbench.finish_solution_step()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if _phase == Phase.IDLE or paused:
		return
	match _phase:
		Phase.INTRO:
			_timer_s -= delta * speed
			if _timer_s <= 0.0:
				_act()
		Phase.ACTING:
			if not _workbench.is_solution_step_running():
				_phase = Phase.OUTRO
				_timer_s = QUICK_OUTRO_S if _is_quick(_plan[_index]) else OUTRO_S
		Phase.OUTRO:
			_timer_s -= delta * speed
			if _timer_s <= 0.0:
				_next_step()


func _next_step() -> void:
	_index += 1
	if _index >= _plan.size():
		_phase = Phase.IDLE
		finished.emit()
		return
	var step: SolutionStep = _plan[_index]
	_phase = Phase.INTRO
	_timer_s = QUICK_INTRO_S if _is_quick(step) else INTRO_S
	step_started.emit(_index, _plan.size(), _workbench.solution_caption(step))


func _act() -> void:
	var step: SolutionStep = _plan[_index]
	if step.kind == SolutionStep.Kind.FINAL_TEST:
		# Test réussi : l'écran peut être remplacé aussitôt, plus rien ne doit suivre.
		_phase = Phase.IDLE
		finished.emit()
		_workbench.perform_solution_step(step, speed)
		return
	_phase = Phase.ACTING
	_workbench.perform_solution_step(step, speed)


func _is_quick(step: SolutionStep) -> bool:
	return step.kind == SolutionStep.Kind.INSTALL and not _workbench.shows_install_gesture(step.component_id)
