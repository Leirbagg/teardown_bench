class_name PartPainter
extends RefCounted
## Dessin des pièces et du décor, partagé par l'appareil (DeviceView) et le tapis (MatMap) : une
## même pièce a le même aspect partout. Une instance par vue (cache de styles).

const OUTLINE_COLOR: Color = Color("0d1014")
const SHADOW_COLOR: Color = Color(0, 0, 0, 0.35)
const BROKEN_COLOR: Color = Color("e5484d")
const LABEL_COLOR: Color = Color(1, 1, 1, 0.85)
const DECORATION_LABEL_COLOR: Color = Color(1, 1, 1, 0.35)
const LABEL_FONT_SIZE: int = 11
const KIND_COLORS: Dictionary[String, Color] = {
	"screw": Color("9aa4ad"),
	"cover": Color("3b4754"),
	"connector": Color("d4a72c"),
	"adhesive": Color("e8dcc0"),
	"module": Color("2f7f86"),
}
const DECORATION_COLORS: Dictionary[String, Color] = {
	"frame": Color("2b3139"),
	"board": Color("1d4a3a"),
	"chip": Color("15191d"),
	"camera": Color("1a1e23"),
	"lens": Color("07090b"),
	"glass": Color("39424d"),
	"notch": Color("050607"),
}
const CORNER_RADIUS: Dictionary[String, int] = {
	"cover": 12,
	"module": 6,
	"connector": 3,
	"adhesive": 2,
	"body": 24,
	"frame": 20,
	"glass": 22,
	"board": 4,
	"chip": 2,
	"camera": 14,
	"notch": 8,
	"frame_seal": 3,
	"socket": 3,
}
## Styles sans bordure : fonds et décors.
const BORDERLESS: PackedStringArray = ["bubble", "body", "mat", "frame", "frame_seal", "socket", "board", "chip", "camera", "lens", "glass", "notch"]

var _styles: Dictionary[String, StyleBoxFlat] = {}


static func kind_color(kind: String) -> Color:
	return KIND_COLORS.get(kind, Color.MAGENTA)


## Style arrondi mis en cache par clé ; sa couleur est réglée à chaque appel.
func style(key: String, color: Color) -> StyleBoxFlat:
	if not _styles.has(key):
		var created: StyleBoxFlat = StyleBoxFlat.new()
		created.set_corner_radius_all(CORNER_RADIUS.get(key, 8))
		created.border_color = OUTLINE_COLOR
		created.set_border_width_all(0 if key in BORDERLESS else 1)
		created.anti_aliasing = true
		_styles[key] = created
	var cached: StyleBoxFlat = _styles[key]
	cached.bg_color = color
	return cached


## Une pièce : vis ronde avec sa tête, joint en cadre, ou boîte arrondie selon son kind.
func draw_part(canvas: CanvasItem, component: ComponentDefinition, rect: Rect2, color: Color,
		angle: float = 0.0, lift: float = 1.0) -> void:
	if component.kind == "screw":
		draw_screw(canvas, rect, color, component.screw_type, angle, lift)
		return
	var thickness: float = frame_thickness(component, rect)
	if thickness > 0.0:
		draw_frame(canvas, rect, thickness, color)
		return
	canvas.draw_style_box(style(component.kind, color), rect)


## Joint qui entoure une pièce : quatre bandes, pas un rectangle plein.
func draw_frame(canvas: CanvasItem, rect: Rect2, thickness: float, color: Color) -> void:
	var inner: Rect2 = rect.grow(-thickness)
	for band: Rect2 in [
		Rect2(rect.position, Vector2(rect.size.x, thickness)),
		Rect2(Vector2(rect.position.x, inner.end.y), Vector2(rect.size.x, thickness)),
		Rect2(Vector2(rect.position.x, inner.position.y), Vector2(thickness, inner.size.y)),
		Rect2(Vector2(inner.end.x, inner.position.y), Vector2(thickness, inner.size.y)),
	]:
		canvas.draw_style_box(style("frame_seal", color), band)


## Épaisseur du cadre dans le repère de `rect` (0 si la pièce n'est pas un cadre).
static func frame_thickness(component: ComponentDefinition, rect: Rect2) -> float:
	var declared: float = float(component.visual.get("frame_thickness", 0.0))
	if declared <= 0.0:
		return 0.0
	var device_rect: Array = component.visual.get("rect", [0, 0, 1, 1])
	var scale: float = rect.size.x / maxf(float(device_rect[2]), 0.001)
	return minf(declared * scale, minf(rect.size.x, rect.size.y) / 2.0 - 1.0)


## Vrai si le point touche la pièce : pour un joint, sa bande, jamais le trou. `touch_band` élargit
## la zone sensible d'un joint dessiné fin, sans l'épaissir à l'écran.
static func contains_point(component: ComponentDefinition, rect: Rect2, point: Vector2, touch_band: float = 0.0) -> bool:
	if not rect.has_point(point):
		return false
	var thickness: float = frame_thickness(component, rect)
	if thickness <= 0.0:
		return true
	return not rect.grow(-maxf(thickness, touch_band)).has_point(point)


## Socle d'un connecteur débranché : creux, à la place exacte de la nappe.
func draw_socket(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	canvas.draw_style_box(style("socket", Color(0.06, 0.08, 0.09, 1.0)), rect)
	canvas.draw_rect(rect, Color(color, 0.45), false, 2.0)


## Vis vue de dessus : ombre, corps, et empreinte selon la tête (cruciforme par défaut).
func draw_screw(canvas: CanvasItem, rect: Rect2, color: Color, head_type: String, angle: float = 0.0, lift: float = 1.0) -> void:
	var center: Vector2 = rect.get_center()
	var radius: float = minf(rect.size.x, rect.size.y) / 2.0 * lift
	canvas.draw_circle(center + Vector2(1.5, 1.5) * lift, radius, SHADOW_COLOR)
	canvas.draw_circle(center, radius, color)
	canvas.draw_arc(center, radius, 0.0, TAU, 24, OUTLINE_COLOR, 1.0)
	var width: float = maxf(1.0, radius * 0.18)
	match head_type:
		"pentalobe":
			for i: int in 5:
				canvas.draw_circle(center + Vector2.from_angle(angle + TAU * i / 5.0) * radius * 0.45, radius * 0.16, OUTLINE_COLOR)
			canvas.draw_circle(center, radius * 0.2, OUTLINE_COLOR)
		"tri_point":
			for i: int in 3:
				canvas.draw_line(center, center + Vector2.from_angle(angle - PI / 2.0 + TAU * i / 3.0) * radius * 0.7, OUTLINE_COLOR, width)
		_:
			var slot: Vector2 = Vector2.from_angle(angle) * radius * 0.7
			canvas.draw_line(center - slot, center + slot, OUTLINE_COLOR, width)
			canvas.draw_line(center - slot.orthogonal(), center + slot.orthogonal(), OUTLINE_COLOR, width)


func draw_broken(canvas: CanvasItem, rect: Rect2) -> void:
	canvas.draw_line(rect.position, rect.end, BROKEN_COLOR, 3.0)
	canvas.draw_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), BROKEN_COLOR, 3.0)


## Nom centré dans la pièce, si elle est assez grande pour le contenir. Rien sur un joint en
## cadre : son centre appartient à la pièce qu'il entoure.
func draw_label(canvas: CanvasItem, font: Font, text: String, rect: Rect2, min_width: float = 56.0,
		component: ComponentDefinition = null) -> void:
	if component != null and frame_thickness(component, rect) > 0.0:
		return
	if rect.size.x >= min_width and rect.size.y >= LABEL_FONT_SIZE + 6:
		canvas.draw_string(font, Vector2(rect.position.x, rect.get_center().y + LABEL_FONT_SIZE / 2.0),
			text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, LABEL_FONT_SIZE, LABEL_COLOR)


func draw_decoration(canvas: CanvasItem, font: Font, decoration: DeviceDefinition.Decoration, rect: Rect2) -> void:
	var color: Color = DECORATION_COLORS.get(decoration.kind, Color.MAGENTA)
	if decoration.kind == "lens":
		var radius: float = minf(rect.size.x, rect.size.y) / 2.0
		canvas.draw_circle(rect.get_center(), radius, color)
		canvas.draw_arc(rect.get_center(), radius, 0.0, TAU, 32, Color(1, 1, 1, 0.15), 2.0)
		canvas.draw_circle(rect.get_center() - Vector2(radius, radius) * 0.3, radius * 0.18, Color(1, 1, 1, 0.12))
	else:
		canvas.draw_style_box(style(decoration.kind, color), rect)
	if not decoration.label.is_empty() and rect.size.y >= LABEL_FONT_SIZE + 6:
		# En bas du décor : le haut d'une carte mère est souvent couvert de caches.
		canvas.draw_string(font, Vector2(rect.position.x, rect.end.y - 6),
			decoration.label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, LABEL_FONT_SIZE, DECORATION_LABEL_COLOR)
