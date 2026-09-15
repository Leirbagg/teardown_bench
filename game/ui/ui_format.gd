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


## Pour une ligne d'état courte : nomme jusqu'à `max_names` pièces, résume le reste.
## ["battery_tab_top_right", …×4] → "Battery Tab Top Right and 3 more"
static func labels_brief(ids: PackedStringArray, max_names: int = 1) -> String:
	if ids.size() <= max_names:
		return labels(ids)
	return "%s and %d more" % [labels(ids.slice(0, max_names)), ids.size() - max_names]
