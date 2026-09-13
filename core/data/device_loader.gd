class_name DeviceLoader
extends RefCounted
## Lit un fichier JSON de data/, le valide et construit sa définition.
## En cas d'échec, renvoie null et ajoute les erreurs à `errors`.


static func load_device(path: String, errors: Array[String]) -> DeviceDefinition:
	var data: Dictionary = _read_json(path, errors)
	if data.is_empty() or not _append_errors(DeviceValidator.validate_device(data), path, errors):
		return null
	return DeviceDefinition.from_dict(data)


static func load_fault(path: String, errors: Array[String]) -> FaultDefinition:
	var data: Dictionary = _read_json(path, errors)
	if data.is_empty() or not _append_errors(DeviceValidator.validate_fault(data), path, errors):
		return null
	return FaultDefinition.from_dict(data)


## Renvoie un dictionnaire vide et ajoute une erreur si le fichier est absent ou illisible.
static func _read_json(path: String, errors: Array[String]) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("[file] %s : fichier introuvable" % path)
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("[json] %s:%d : %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if typeof(json.data) != TYPE_DICTIONARY or (json.data as Dictionary).is_empty():
		errors.append("[json] %s : la racine doit être un objet non vide" % path)
		return {}
	return json.data


## Ajoute les erreurs de validation en précisant le fichier. Renvoie vrai s'il n'y en a aucune.
static func _append_errors(validation_errors: Array[String], path: String, errors: Array[String]) -> bool:
	for error: String in validation_errors:
		errors.append("%s (%s)" % [error, path])
	return validation_errors.is_empty()
