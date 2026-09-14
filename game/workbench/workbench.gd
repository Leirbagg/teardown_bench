class_name Workbench
extends Control
## Écran de réparation d'un client. Relaie gestes et boutons vers core/ (DisassemblyState,
## Diagnosis, RepairSession) et affiche ce qu'ils répondent. Aucune règle de jeu ici.

const Outcome = DisassemblyResult.Outcome
const TestStatus = Diagnosis.TestStatus
const VIBRATE_STEP_MS: int = 8
const VIBRATE_STRAIN_MS: int = 25
const VIBRATE_REMOVED_MS: int = 30
const VIBRATE_BREAK_MS: int = 120
const VIBRATE_CLICK_MS: int = 15
const TIMER_COLOR: Color = Color(1, 1, 1, 0.8)
const TIMER_LATE_COLOR: Color = Color("e5484d")

var session: RepairSession

var _feedback: Feedback
var _selected_tray_id: String = ""
## Pièce en cours de geste alors qu'elle est retenue : ses crans grincent.
var _resisting_id: String = ""

@onready var _complaint: Label = %Complaint
@onready var _timer: Label = %Timer
@onready var _device_view: DeviceView = %DeviceView
@onready var _flip_button: Button = %FlipButton
@onready var _loupe_button: Button = %LoupeButton
@onready var _tests_button: Button = %TestsButton
@onready var _final_test_button: Button = %FinalTestButton
@onready var _tray: HBoxContainer = %Tray
@onready var _reinstall_button: Button = %ReinstallButton
@onready var _replace_button: Button = %ReplaceButton
@onready var _status: Label = %Status
@onready var _info_panel: PanelContainer = %InfoPanel
@onready var _info_text: Label = %InfoText
@onready var _info_close_button: Button = %InfoCloseButton


func _ready() -> void:
	_flip_button.pressed.connect(_on_flip_pressed)
	_loupe_button.toggled.connect(_on_loupe_toggled)
	_tests_button.pressed.connect(_on_tests_pressed)
	_final_test_button.pressed.connect(_on_final_test_pressed)
	_reinstall_button.pressed.connect(_on_reinstall_pressed)
	_replace_button.pressed.connect(_on_replace_pressed)
	_info_close_button.pressed.connect(_close_info)
	_device_view.gesture_started.connect(_on_gesture_started)
	_device_view.gesture_step.connect(_on_gesture_step)
	_device_view.gesture_completed.connect(_on_gesture_completed)
	_device_view.gesture_cancelled.connect(_on_gesture_cancelled)
	_device_view.component_inspected.connect(_on_component_inspected)


## À appeler une fois la scène dans l'arbre. `feedback` doit survivre à l'écran : le son de
## réussite se joue au moment où l'écran est remplacé.
func setup(repair_session: RepairSession, feedback: Feedback) -> void:
	session = repair_session
	_feedback = feedback
	_complaint.text = "\"%s\"" % session.job.complaint
	_device_view.setup(session.state)
	session.state.component_removed.connect(_refresh_tray.unbind(1))
	session.state.component_installed.connect(_refresh_tray.unbind(1))
	session.state.component_replaced.connect(_refresh_tray.unbind(2))
	session.state.component_broken.connect(_refresh_tray.unbind(2))
	session.deadline_exceeded.connect(_update_timer)
	_update_flip_label()
	_refresh_tray()
	_update_timer()
	_set_status("Find the fault. Flip the device, use the loupe, run the tests.")


func _process(_delta: float) -> void:
	if session != null:
		_update_timer()


# --- Gestes ---

func _on_gesture_started(component_id: String) -> void:
	var prediction: DisassemblyResult = session.state.query_remove(component_id)
	if prediction.outcome == Outcome.FORCED:
		_resisting_id = component_id
		_device_view.set_resisting(true)
		_set_status("%s is held by: %s. Finish the gesture to force it." % [UiFormat.label(component_id), UiFormat.labels(prediction.blockers)])
		_feedback.pulse(&"creak", VIBRATE_STRAIN_MS)
	else:
		_resisting_id = ""
		_set_status("%s…" % _gesture_hint(session.state.device.get_component(component_id)))


func _on_gesture_step(component_id: String, _step: int, _step_count: int) -> void:
	if component_id == _resisting_id:
		_feedback.pulse(&"creak", VIBRATE_STRAIN_MS)
		return
	match session.state.device.get_component(component_id).gesture:
		"hold":
			_feedback.pulse(&"sizzle", VIBRATE_STEP_MS)
		_:
			_feedback.pulse(&"screw_tick", VIBRATE_STEP_MS)


func _on_gesture_completed(component_id: String) -> void:
	_resisting_id = ""
	var result: DisassemblyResult = session.state.commit_remove(component_id)
	match result.outcome:
		Outcome.REMOVED:
			_set_status("Removed %s." % UiFormat.label(component_id))
			_feedback.pulse(&"pop", VIBRATE_REMOVED_MS)
		Outcome.FORCED:
			if result.broken.is_empty():
				_set_status("Still held by: %s." % UiFormat.labels(result.blockers))
				_feedback.pulse(&"creak", VIBRATE_STRAIN_MS)
			else:
				_set_status("Forced it! Broke: %s." % UiFormat.labels(result.broken))
				_feedback.pulse(&"crack", VIBRATE_BREAK_MS)


func _on_gesture_cancelled(_component_id: String) -> void:
	_resisting_id = ""
	_set_status("")


func _on_component_inspected(component_id: String) -> void:
	var role: String = session.state.device.get_component(component_id).role
	var findings: PackedStringArray = PackedStringArray()
	for clue: FaultDefinition.Clue in session.diagnosis.visible_clues():
		if clue.role == role:
			findings.append(clue.clue_id.capitalize().to_lower())
	if findings.is_empty():
		_set_status("Loupe: nothing unusual on %s." % UiFormat.label(component_id))
	else:
		_set_status("Loupe: %s on %s." % [", ".join(findings), UiFormat.label(component_id)])


# --- Outils ---

func _on_flip_pressed() -> void:
	var faces: PackedStringArray = session.state.device.faces
	_device_view.face = faces[(faces.find(_device_view.face) + 1) % faces.size()]
	_update_flip_label()


func _on_loupe_toggled(enabled: bool) -> void:
	_device_view.loupe_mode = enabled
	_update_clue_markers()
	_set_status("Loupe on: tap a part to inspect it." if enabled else "")


func _on_tests_pressed() -> void:
	var lines: PackedStringArray = PackedStringArray(["Software tests"])
	var results: Dictionary[String, TestStatus] = session.diagnosis.software_test_results()
	for test_id: String in results:
		lines.append("%s: %s" % [test_id.capitalize(), TestStatus.keys()[results[test_id]].capitalize()])
	_show_info("\n".join(lines))


func _on_final_test_pressed() -> void:
	var result: FinalTestResult = session.run_final_test()
	match result.outcome:
		FinalTestResult.Outcome.NOT_ASSEMBLED:
			_set_status("Reassemble the device before the final test.")
		FinalTestResult.Outcome.FAILED:
			var lines: PackedStringArray = PackedStringArray(["Final test failed."])
			if not result.failing_tests.is_empty():
				lines.append("Not working: %s." % UiFormat.labels(result.failing_tests))
			if not result.broken_ids.is_empty():
				lines.append("Broken parts: %s." % UiFormat.labels(result.broken_ids))
			lines.append("Reopen the device and keep looking.")
			_show_info("\n".join(lines))
			_feedback.pulse(&"failure", VIBRATE_BREAK_MS)
		FinalTestResult.Outcome.PASSED:
			_set_status("Repaired!")
			_feedback.pulse(&"success", VIBRATE_REMOVED_MS)


# --- Bac à pièces ---

func _refresh_tray() -> void:
	for child: Node in _tray.get_children():
		child.queue_free()
	if not session.state.is_removed(_selected_tray_id):
		_selected_tray_id = ""
	for component_id: String in session.state.removed_ids():
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(48, 48)
		button.toggle_mode = true
		button.button_pressed = component_id == _selected_tray_id
		button.text = UiFormat.label(component_id) + (" (broken)" if session.state.is_broken(component_id) else "")
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_on_tray_item_pressed.bind(component_id))
		_tray.add_child(button)
	_update_tray_actions()
	_update_clue_markers()


func _on_tray_item_pressed(component_id: String) -> void:
	_selected_tray_id = "" if component_id == _selected_tray_id else component_id
	_refresh_tray()


func _update_tray_actions() -> void:
	var selected: bool = _selected_tray_id != ""
	_reinstall_button.disabled = not selected
	_replace_button.disabled = not selected or not session.state.device.get_component(_selected_tray_id).replaceable


func _on_reinstall_pressed() -> void:
	var component_id: String = _selected_tray_id
	var result: DisassemblyResult = session.state.commit_install(component_id)
	if result.outcome == Outcome.INSTALL_BLOCKED:
		_set_status("Reinstall first: %s." % UiFormat.labels(result.blockers))
	elif result.outcome == Outcome.INSTALLED:
		_set_status("Reinstalled %s." % UiFormat.label(component_id))
		_feedback.pulse(&"click", VIBRATE_CLICK_MS)


func _on_replace_pressed() -> void:
	var component_id: String = _selected_tray_id
	var result: DisassemblyResult = session.state.replace(component_id)
	if result.outcome == Outcome.NOT_DETACHED:
		_set_status("Disconnect first: %s." % UiFormat.labels(result.blockers))
	elif result.is_success():
		_set_status("Swapped %s for a new part." % UiFormat.label(component_id))
		_feedback.pulse(&"click", VIBRATE_CLICK_MS)


# --- Affichage ---

func _update_timer() -> void:
	_timer.text = "%s / %s" % [UiFormat.time(session.elapsed_s), UiFormat.time(session.job.deadline_s)]
	_timer.add_theme_color_override("font_color", TIMER_LATE_COLOR if session.is_deadline_exceeded() else TIMER_COLOR)


func _update_flip_label() -> void:
	_flip_button.text = "Flip (%s)" % _device_view.face.capitalize()


func _update_clue_markers() -> void:
	var ids: PackedStringArray = PackedStringArray()
	for clue: FaultDefinition.Clue in session.diagnosis.visible_clues():
		var component: ComponentDefinition = session.state.device.component_for_role(clue.role)
		if component != null:
			ids.append(component.id)
	_device_view.clue_component_ids = ids


func _show_info(text: String) -> void:
	_info_text.text = text
	_info_panel.visible = true
	_device_view.input_enabled = false


func _close_info() -> void:
	_info_panel.visible = false
	_device_view.input_enabled = true


func _set_status(text: String) -> void:
	_status.text = text


static func _gesture_hint(component: ComponentDefinition) -> String:
	match component.gesture:
		"rotate":
			return "Turn in circles to unscrew %s" % UiFormat.label(component.id)
		"pull":
			return "Pull %s away" % UiFormat.label(component.id)
		"hold":
			return "Keep holding to heat %s" % UiFormat.label(component.id)
		"pry":
			return "Slide along the edge to pry %s" % UiFormat.label(component.id)
	return UiFormat.label(component.id)
