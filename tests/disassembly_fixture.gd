class_name DisassemblyFixture
extends RefCounted
## Charge l'appareil de test partagé par les suites de démontage.

const TEST_PHONE_PATH: String = "res://tests/fixtures/devices/test_phone.json"


static func load_test_phone() -> DeviceDefinition:
	var errors: Array[String] = []
	var device: DeviceDefinition = DeviceLoader.load_device(TEST_PHONE_PATH, errors)
	if device == null:
		push_error("test_phone.json invalide :\n%s" % "\n".join(PackedStringArray(errors)))
	return device
