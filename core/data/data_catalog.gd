class_name DataCatalog
extends RefCounted
## Appareils et pannes du jeu, chargés depuis data/preload_manifest.json.
## Le manifeste liste explicitement chaque fichier : ce qui n'est pas référencé n'est pas
## exporté dans l'APK (voir CLAUDE.md, « Pièges connus »).

const MANIFEST_PATH: String = "res://data/preload_manifest.json"

var devices: Array[DeviceDefinition] = []
var faults: Array[FaultDefinition] = []


## Renvoie null et remplit `errors` si le manifeste ou l'un des fichiers est invalide.
static func load_manifest(path: String, errors: Array[String]) -> DataCatalog:
	var errors_before: int = errors.size()
	var manifest: Dictionary = DeviceLoader.read_json(path, errors)
	if manifest.is_empty():
		return null
	var catalog: DataCatalog = DataCatalog.new()
	for device_path: String in _paths(manifest, "devices", path, errors):
		var device: DeviceDefinition = DeviceLoader.load_device(device_path, errors)
		if device != null:
			catalog.devices.append(device)
	for fault_path: String in _paths(manifest, "faults", path, errors):
		var fault: FaultDefinition = DeviceLoader.load_fault(fault_path, errors)
		if fault != null:
			catalog.faults.append(fault)
	return catalog if errors.size() == errors_before else null


## null si l'identifiant est inconnu.
func find_device(device_id: String) -> DeviceDefinition:
	for device: DeviceDefinition in devices:
		if device.id == device_id:
			return device
	return null


## null si l'identifiant est inconnu.
func find_fault(fault_id: String) -> FaultDefinition:
	for fault: FaultDefinition in faults:
		if fault.id == fault_id:
			return fault
	return null


## Tous les chemins listés, appareils puis pannes.
static func listed_paths(manifest: Dictionary) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for key: String in ["devices", "faults"]:
		if typeof(manifest.get(key)) == TYPE_ARRAY:
			for item: Variant in manifest[key]:
				paths.append(str(item))
	return paths


static func _paths(manifest: Dictionary, key: String, manifest_path: String, errors: Array[String]) -> PackedStringArray:
	var field_errors: Array[String] = []
	var paths: PackedStringArray = DeviceValidator.check_string_array(manifest, key, "", field_errors)
	for error: String in field_errors:
		errors.append("%s (%s)" % [error, manifest_path])
	return paths
