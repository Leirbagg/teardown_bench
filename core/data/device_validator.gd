class_name DeviceValidator
extends RefCounted
## Valide les dictionnaires issus des JSON d'appareils et de pannes (docs/data_schema.md).
## Ne plante jamais sur une entrée malformée : renvoie des messages préfixés par un code
## entre crochets, ex. « [cycle] requires : a -> b -> a ». Liste vide = valide.

const SCHEMA_VERSION: int = 1


static func validate_device(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_check_schema_version(data, errors)
	_check_string(data, "id", "", errors)
	_check_string(data, "name", "", errors)
	_check_positive_int(data, "tier", "", errors)
	var faces: PackedStringArray = _check_string_array(data, "faces", "", errors, true, false)
	for face: String in faces:
		if face not in DeviceDefinition.FACES:
			errors.append("[bad_value] faces : '%s' n'est pas dans %s" % [face, DeviceDefinition.FACES])

	if not data.has("components"):
		errors.append("[missing_field] components")
		return errors
	if typeof(data["components"]) != TYPE_ARRAY or (data["components"] as Array).is_empty():
		errors.append("[bad_type] components doit être un tableau non vide")
		return errors

	var components: Dictionary[String, Dictionary] = _check_components(data["components"], faces, errors)
	_check_graph(components, errors)
	_check_software_tests(data, components, errors)
	return errors


static func validate_fault(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	_check_schema_version(data, errors)
	_check_string(data, "id", "", errors)
	_check_positive_int(data, "tier", "", errors)
	_check_string(data, "target_role", "", errors)
	_check_string_array(data, "complaints", "", errors, true, false)
	_check_positive_number(data, "target_time_s", "", errors)

	if not data.has("clues"):
		errors.append("[missing_field] clues")
		return errors
	if typeof(data["clues"]) != TYPE_ARRAY:
		errors.append("[bad_type] clues doit être un tableau")
		return errors
	var clues: Array = data["clues"]
	for i: int in clues.size():
		var path: String = "clues[%d]" % i
		if typeof(clues[i]) != TYPE_DICTIONARY:
			errors.append("[bad_type] %s doit être un objet" % path)
			continue
		var clue: Dictionary = clues[i]
		_check_enum(clue, "tool", FaultDefinition.CLUE_TOOLS, path, errors)
		_check_string(clue, "role", path, errors)
		_check_string(clue, "clue", path, errors)
		_check_enum(clue, "visible", FaultDefinition.CLUE_VISIBILITIES, path, errors)
	return errors


# --- Appareil ---

## Vérifie la forme de chaque composant et renvoie les champs utiles au graphe, indexés par id.
static func _check_components(raw_components: Array, faces: PackedStringArray, errors: Array[String]) -> Dictionary[String, Dictionary]:
	var components: Dictionary[String, Dictionary] = {}
	for i: int in raw_components.size():
		var path: String = "components[%d]" % i
		if typeof(raw_components[i]) != TYPE_DICTIONARY:
			errors.append("[bad_type] %s doit être un objet" % path)
			continue
		var raw: Dictionary = raw_components[i]
		var id: String = _check_string(raw, "id", path, errors)
		if id.is_empty():
			continue
		path = "components[%d](%s)" % [i, id]
		if components.has(id):
			errors.append("[duplicate_id] %s : id déjà utilisé" % path)
			continue
		_check_enum(raw, "kind", ComponentDefinition.KINDS, path, errors)
		_check_enum(raw, "face", faces, path, errors)
		_check_enum(raw, "gesture", ComponentDefinition.GESTURES, path, errors)
		_check_dictionary(raw, "gesture_params", path, errors)
		_check_visual(raw, path, errors)
		var requires: PackedStringArray = _check_string_array(raw, "requires", path, errors)
		var covered_by: PackedStringArray = _check_string_array(raw, "covered_by", path, errors)
		var force_breaks: PackedStringArray = _check_string_array(raw, "force_breaks", path, errors, false)
		var replace_requires: PackedStringArray = _check_string_array(raw, "replace_requires", path, errors, false)
		if id in replace_requires:
			errors.append("[bad_value] %s.replace_requires : un composant ne peut pas se requérir lui-même" % path)
		components[id] = {
			"path": path,
			"requires": requires,
			"covered_by": covered_by,
			"force_breaks": ComponentDefinition.resolve_force_breaks(id, force_breaks),
			"replace_requires": replace_requires,
			"role": _check_string(raw, "role", path, errors, false),
			"replaceable": _check_bool(raw, "replaceable", path, errors),
		}
	return components


static func _check_graph(components: Dictionary[String, Dictionary], errors: Array[String]) -> void:
	var edges: Dictionary = {}
	var required_ids: Dictionary = {}
	var role_owners: Dictionary = {}
	var has_root: bool = false

	for id: String in components:
		var component: Dictionary = components[id]
		var path: String = component["path"]
		var requires: PackedStringArray = component["requires"]
		var covered_by: PackedStringArray = component["covered_by"]
		edges[id] = requires
		has_root = has_root or requires.is_empty()

		for field: String in ["requires", "covered_by", "force_breaks", "replace_requires"]:
			for target: String in component[field]:
				if not components.has(target):
					errors.append("[unknown_ref] %s.%s : '%s' n'existe pas" % [path, field, target])
		for target: String in requires + (component["replace_requires"] as PackedStringArray):
			required_ids[target] = true
		for target: String in covered_by:
			if target not in requires:
				errors.append("[covered_not_required] %s.covered_by : '%s' absent de requires" % [path, target])

		if ComponentDefinition.is_forceable(requires, covered_by):
			for target: String in component["force_breaks"]:
				if components.has(target) and not components[target]["replaceable"]:
					errors.append("[breaks_irreplaceable] %s : le forcer casserait '%s', qui n'est pas replaceable" % [path, target])

		if not (component["replace_requires"] as PackedStringArray).is_empty() and not component["replaceable"]:
			errors.append("[replace_requires_irreplaceable] %s : replace_requires sur un composant non replaceable" % path)

		var role: String = component["role"]
		if role.is_empty():
			continue
		if role_owners.has(role):
			errors.append("[duplicate_role] %s.role : '%s' déjà porté par '%s'" % [path, role, role_owners[role]])
		else:
			role_owners[role] = id
		if not component["replaceable"]:
			errors.append("[role_not_replaceable] %s : un composant avec rôle doit être replaceable" % path)

	if not has_root:
		errors.append("[no_root] aucun composant sans requires")
	var cycle: PackedStringArray = Dag.find_cycle(edges)
	if not cycle.is_empty():
		errors.append("[cycle] requires : %s" % " -> ".join(cycle))

	for id: String in components:
		var component: Dictionary = components[id]
		if not required_ids.has(id) and not component["replaceable"] and (component["role"] as String).is_empty():
			errors.append("[orphan] %s : rien ne le requiert, il n'est pas replaceable et n'a pas de rôle" % component["path"])


static func _check_software_tests(data: Dictionary, components: Dictionary[String, Dictionary], errors: Array[String]) -> void:
	if not data.has("software_tests"):
		errors.append("[missing_field] software_tests")
		return
	if typeof(data["software_tests"]) != TYPE_ARRAY:
		errors.append("[bad_type] software_tests doit être un tableau")
		return

	var roles: Dictionary = {}
	for id: String in components:
		var role: String = components[id]["role"]
		if not role.is_empty():
			roles[role] = true

	var tests: Array = data["software_tests"]
	var edges: Dictionary = {}
	var paths: Dictionary = {}
	for i: int in tests.size():
		var path: String = "software_tests[%d]" % i
		if typeof(tests[i]) != TYPE_DICTIONARY:
			errors.append("[bad_type] %s doit être un objet" % path)
			continue
		var raw: Dictionary = tests[i]
		var id: String = _check_string(raw, "id", path, errors)
		if id.is_empty():
			continue
		path = "software_tests[%d](%s)" % [i, id]
		if edges.has(id):
			errors.append("[duplicate_id] %s : id déjà utilisé" % path)
			continue
		for role: String in _check_string_array(raw, "roles", path, errors, true, false):
			if not roles.has(role):
				errors.append("[unknown_ref] %s.roles : aucun composant ne porte le rôle '%s'" % [path, role])
		edges[id] = _check_string_array(raw, "after", path, errors)
		paths[id] = path

	for id: String in edges:
		for target: String in edges[id]:
			if not edges.has(target):
				errors.append("[unknown_ref] %s.after : '%s' n'existe pas" % [paths[id], target])
	var cycle: PackedStringArray = Dag.find_cycle(edges)
	if not cycle.is_empty():
		errors.append("[cycle] software_tests.after : %s" % " -> ".join(cycle))


## Facultatif. Si présent, `rect` vaut [x, y, largeur, hauteur] avec largeur et hauteur > 0.
static func _check_visual(component: Dictionary, path: String, errors: Array[String]) -> void:
	_check_dictionary(component, "visual", path, errors)
	if typeof(component.get("visual")) != TYPE_DICTIONARY or not (component["visual"] as Dictionary).has("rect"):
		return
	var rect: Variant = component["visual"]["rect"]
	var valid: bool = typeof(rect) == TYPE_ARRAY and (rect as Array).size() == 4
	if valid:
		for value: Variant in rect:
			valid = valid and _is_number(value)
	if not valid or float(rect[2]) <= 0.0 or float(rect[3]) <= 0.0:
		errors.append("[bad_value] %s : doit valoir [x, y, largeur, hauteur], dimensions > 0" % _field(path, "visual.rect"))


# --- Champs ---

## Version publique de la vérification d'un tableau de chaînes, pour les autres chargeurs.
static func check_string_array(data: Dictionary, key: String, path: String, errors: Array[String]) -> PackedStringArray:
	return _check_string_array(data, key, path, errors)


static func _field(path: String, key: String) -> String:
	return key if path.is_empty() else "%s.%s" % [path, key]


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _check_schema_version(data: Dictionary, errors: Array[String]) -> void:
	if not data.has("schema_version"):
		errors.append("[missing_field] schema_version")
	elif not _is_number(data["schema_version"]) or data["schema_version"] != SCHEMA_VERSION:
		errors.append("[bad_value] schema_version doit valoir %d" % SCHEMA_VERSION)


## Champ obligatoire non vide, ou facultatif (chaîne vide acceptée). Renvoie "" si invalide.
static func _check_string(data: Dictionary, key: String, path: String, errors: Array[String], required: bool = true) -> String:
	var field: String = _field(path, key)
	if not data.has(key):
		if required:
			errors.append("[missing_field] %s" % field)
		return ""
	if typeof(data[key]) != TYPE_STRING:
		errors.append("[bad_type] %s doit être une chaîne" % field)
		return ""
	var value: String = data[key]
	if required and value.is_empty():
		errors.append("[bad_value] %s ne peut pas être vide" % field)
	return value


## Chaîne obligatoire appartenant à `allowed`. Si `allowed` est vide, seule la présence est vérifiée.
static func _check_enum(data: Dictionary, key: String, allowed: PackedStringArray, path: String, errors: Array[String]) -> String:
	var value: String = _check_string(data, key, path, errors)
	if not value.is_empty() and not allowed.is_empty() and value not in allowed:
		errors.append("[bad_value] %s : '%s' n'est pas dans %s" % [_field(path, key), value, allowed])
	return value


static func _check_string_array(data: Dictionary, key: String, path: String, errors: Array[String], required: bool = true, allow_empty: bool = true) -> PackedStringArray:
	var field: String = _field(path, key)
	if not data.has(key):
		if required:
			errors.append("[missing_field] %s" % field)
		return PackedStringArray()
	if typeof(data[key]) != TYPE_ARRAY:
		errors.append("[bad_type] %s doit être un tableau de chaînes" % field)
		return PackedStringArray()
	var result: PackedStringArray = PackedStringArray()
	for item: Variant in data[key]:
		if typeof(item) != TYPE_STRING or (item as String).is_empty():
			errors.append("[bad_type] %s doit contenir uniquement des chaînes non vides" % field)
			return PackedStringArray()
		result.append(item)
	if not allow_empty and result.is_empty():
		errors.append("[bad_value] %s ne peut pas être vide" % field)
	return result


static func _check_positive_int(data: Dictionary, key: String, path: String, errors: Array[String]) -> int:
	var field: String = _field(path, key)
	if not data.has(key):
		errors.append("[missing_field] %s" % field)
		return 0
	var value: Variant = data[key]
	if not _is_number(value) or float(value) != floorf(float(value)) or float(value) < 1.0:
		errors.append("[bad_value] %s doit être un entier ≥ 1" % field)
		return 0
	return int(value)


static func _check_positive_number(data: Dictionary, key: String, path: String, errors: Array[String]) -> float:
	var field: String = _field(path, key)
	if not data.has(key):
		errors.append("[missing_field] %s" % field)
		return 0.0
	if not _is_number(data[key]) or float(data[key]) <= 0.0:
		errors.append("[bad_value] %s doit être un nombre > 0" % field)
		return 0.0
	return float(data[key])


## Facultatif, faux par défaut.
static func _check_bool(data: Dictionary, key: String, path: String, errors: Array[String]) -> bool:
	if not data.has(key):
		return false
	if typeof(data[key]) != TYPE_BOOL:
		errors.append("[bad_type] %s doit être un booléen" % _field(path, key))
		return false
	return data[key]


## Facultatif.
static func _check_dictionary(data: Dictionary, key: String, path: String, errors: Array[String]) -> void:
	if data.has(key) and typeof(data[key]) != TYPE_DICTIONARY:
		errors.append("[bad_type] %s doit être un objet" % _field(path, key))
