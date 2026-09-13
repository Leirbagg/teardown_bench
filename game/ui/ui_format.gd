class_name UiFormat
extends RefCounted
## Mise en forme des textes affichés, partagée par les écrans.


## 83.4 → "1:23"
static func time(seconds: float) -> String:
	var total: int = int(seconds)
	return "%d:%02d" % [floori(total / 60.0), total % 60]


## "back_screw_l" → "Back Screw L"
static func label(id: String) -> String:
	return id.capitalize()


static func labels(ids: PackedStringArray) -> String:
	var names: PackedStringArray = PackedStringArray()
	for id: String in ids:
		names.append(label(id))
	return ", ".join(names)
