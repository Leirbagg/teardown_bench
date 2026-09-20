class_name ModelCatalog
extends RefCounted
## Fiches des modèles de la gamme : ce qu'un réparateur reconnaît d'un téléphone avant même de
## l'ouvrir (année, taille, dalle, façon dont il s'ouvre, connecteur), et le démontage qui lui
## correspond. Un modèle dont le démontage n'est pas encore construit se consulte mais ne se
## joue pas : la gamme est visible en entier, elle devient jouable par lots.

const PATH: String = "res://data/models.json"


class Family:
	extends RefCounted
	var id: String
	var label: String
	## "screen" (tout passe par l'écran) ou "screen_or_back" (le dos se retire aussi).
	var opens_from: String
	var note: String


class Model:
	extends RefCounted
	var id: String
	var name: String
	var year: int
	var screen_inches: float
	## "oled" ou "lcd".
	var screen_tech: String
	var family: String
	var family_label: String
	var opens_from: String
	## "lightning" ou "usb_c".
	var port: String
	## Identifiant de l'appareil démontable, vide tant qu'il n'est pas construit.
	var teardown: String
	## Faux quand la fiche repose sur une connaissance incomplète, à confirmer sur un guide.
	var verified: bool
	## Guide public sur lequel le démontage a été recoupé ("" tant qu'il ne l'a pas été).
	var source: String
	var note: String

	func is_playable() -> bool:
		return not teardown.is_empty()


var families: Array[Family] = []
var models: Array[Model] = []


## Renvoie null et remplit `errors` si le fichier est illisible ou incohérent.
static func load_from(path: String, errors: Array[String]) -> ModelCatalog:
	var errors_before: int = errors.size()
	var data: Dictionary = DeviceLoader.read_json(path, errors)
	if data.is_empty():
		return null
	var catalog: ModelCatalog = ModelCatalog.new()
	var family_ids: PackedStringArray = PackedStringArray()
	for raw: Variant in data.get("families", []):
		var family: Family = Family.new()
		var entry: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
		family.id = str(entry.get("id", ""))
		family.label = str(entry.get("label", ""))
		family.opens_from = str(entry.get("opens_from", ""))
		family.note = str(entry.get("note", ""))
		if family.id.is_empty() or family.id in family_ids:
			errors.append("[bad_value] %s : famille sans id ou en double" % path)
			continue
		family_ids.append(family.id)
		catalog.families.append(family)
	var model_ids: PackedStringArray = PackedStringArray()
	for raw: Variant in data.get("models", []):
		var entry: Dictionary = raw if typeof(raw) == TYPE_DICTIONARY else {}
		var model: Model = Model.new()
		model.id = str(entry.get("id", ""))
		model.name = str(entry.get("name", ""))
		model.year = int(entry.get("year", 0))
		model.screen_inches = float(entry.get("screen_inches", 0.0))
		model.screen_tech = str(entry.get("screen_tech", ""))
		model.family = str(entry.get("family", ""))
		model.family_label = str(entry.get("family_label", ""))
		model.opens_from = str(entry.get("opens_from", ""))
		model.port = str(entry.get("port", ""))
		model.teardown = str(entry.get("teardown", ""))
		model.verified = bool(entry.get("verified", false))
		model.source = str(entry.get("source", ""))
		model.note = str(entry.get("note", ""))
		if model.id.is_empty() or model.id in model_ids:
			errors.append("[bad_value] %s : modèle sans id ou en double ('%s')" % [path, model.id])
			continue
		if model.name.is_empty():
			errors.append("[bad_value] %s : modèle '%s' sans nom affichable" % [path, model.id])
		if model.family not in family_ids:
			errors.append("[unknown_ref] %s : modèle '%s' rattaché à la famille inconnue '%s'" % [path, model.id, model.family])
		model_ids.append(model.id)
		catalog.models.append(model)
	if catalog.models.is_empty():
		errors.append("[bad_value] %s : aucune fiche de modèle" % path)
	return catalog if errors.size() == errors_before else null


## Vérifie que chaque `teardown` désigne un appareil chargé.
func check_teardowns(devices: Array[DeviceDefinition], errors: Array[String]) -> void:
	var device_ids: PackedStringArray = PackedStringArray()
	for device: DeviceDefinition in devices:
		device_ids.append(device.id)
	for model: Model in models:
		if model.is_playable() and model.teardown not in device_ids:
			errors.append("[unknown_ref] modèle '%s' : démontage '%s' introuvable" % [model.id, model.teardown])


## null si l'identifiant est inconnu.
func find(model_id: String) -> Model:
	for model: Model in models:
		if model.id == model_id:
			return model
	return null


## Modèle correspondant à un appareil démontable, null s'il n'y en a pas.
func for_teardown(device_id: String) -> Model:
	for model: Model in models:
		if model.teardown == device_id:
			return model
	return null


## Modèles réellement jouables aujourd'hui, dans l'ordre de la gamme.
func playable() -> Array[Model]:
	return models.filter(func(model: Model) -> bool: return model.is_playable())
