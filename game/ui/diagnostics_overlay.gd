class_name DiagnosticsOverlay
extends PanelContainer
## Ce que l'appareil dit de lui-même : taille de vue, zone sûre, marges, densité. Sert à régler
## les problèmes d'affichage sur un téléphone, sans avoir à les décrire.

signal closed

@onready var _text: Label = %DiagnosticsText
@onready var _close_button: Button = %DiagnosticsCloseButton


func _ready() -> void:
	_close_button.pressed.connect(func() -> void:
		closed.emit()
		queue_free())


func show_report(viewport: Vector2, insets: Vector4i, save_path: String) -> void:
	_text.text = report(viewport, DisplayServer.window_get_size(), DisplayServer.get_display_safe_area(), insets, save_path)


## Version du jeu, telle que gravée à la construction (scripts/build_android.sh).
static func app_version() -> String:
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	return version if not version.is_empty() else "dev"


## Rapport lisible ; séparé de l'affichage pour être testable.
static func report(viewport: Vector2, window: Vector2i, safe: Rect2i, insets: Vector4i, save_path: String) -> String:
	var lines: PackedStringArray = PackedStringArray([
		"Teardown Bench %s" % app_version(),
		"Godot %s · %s" % [Engine.get_version_info()["string"], OS.get_name()],
		"Model: %s" % OS.get_model_name(),
		"Viewport: %d × %d" % [viewport.x, viewport.y],
		"Window: %d × %d" % [window.x, window.y],
		"Safe area: %d, %d → %d × %d" % [safe.position.x, safe.position.y, safe.size.x, safe.size.y],
		"Margins: left %d, top %d, right %d, bottom %d" % [insets.x, insets.y, insets.z, insets.w],
		"Screen: %d dpi · %.0f Hz" % [DisplayServer.screen_get_dpi(), DisplayServer.screen_get_refresh_rate()],
		"FPS: %d · draw calls: %d" % [Engine.get_frames_per_second(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)],
		"Mobile build: %s" % ("yes" if OS.has_feature("mobile") else "no"),
		"Save: %s (%s)" % [save_path, "found" if FileAccess.file_exists(save_path) else "none"],
	])
	return "\n".join(lines)
