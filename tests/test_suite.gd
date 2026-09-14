class_name TestSuite
extends RefCounted
## Base des suites de tests : exécute chaque méthode test_* et compte les échecs.
## Une suite vit dans tests/cases/ et est lancée par tests/run_tests.gd.
## Une erreur moteur ou GDScript pendant un test (qui interrompt la fonction sans exception)
## compte comme un échec.


class ErrorCounter:
	extends Logger
	var count: int = 0

	func _log_error(_function: String, _file: String, _line: int, _code: String, _rationale: String,
			_editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		count += 1


static var _error_counter: ErrorCounter = null

var _failures: int = 0
var _current_test: String = ""
var _expected_errors: int = 0


func run() -> int:
	if _error_counter == null:
		_error_counter = ErrorCounter.new()
		OS.add_logger(_error_counter)
	var suite_name: String = (get_script() as Script).resource_path.get_file()
	var test_count: int = 0
	for method: Dictionary in get_method_list():
		var method_name: String = method["name"]
		if not method_name.begins_with("test_"):
			continue
		_current_test = "%s::%s" % [suite_name, method_name]
		test_count += 1
		var errors_before: int = _error_counter.count
		_expected_errors = 0
		call(method_name)
		var logged: int = _error_counter.count - errors_before
		if logged != _expected_errors:
			_fail("%d erreur(s) moteur journalisée(s), %d attendue(s) : voir ci-dessus" % [logged, _expected_errors])
	print("%s : %d test(s), %d échec(s)" % [suite_name, test_count, _failures])
	return _failures


## Déclare que le test doit journaliser exactement `count` erreurs moteur (entrée volontairement
## invalide, par exemple). Sans cet appel, toute erreur journalisée fait échouer le test.
func expect_engine_errors(count: int) -> void:
	_expected_errors = count


func assert_true(condition: bool, message: String = "attendu vrai") -> void:
	if not condition:
		_fail(message)


func assert_false(condition: bool, message: String = "attendu faux") -> void:
	if condition:
		_fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		_fail("%sobtenu %s, attendu %s" % [_prefix(message), var_to_str(actual), var_to_str(expected)])


func assert_no_errors(errors: Array[String], message: String = "") -> void:
	if not errors.is_empty():
		_fail("%serreurs inattendues :\n  %s" % [_prefix(message), "\n  ".join(PackedStringArray(errors))])


func assert_has_code(errors: Array[String], code: String, message: String = "") -> void:
	var tag: String = "[%s]" % code
	for error: String in errors:
		if error.begins_with(tag):
			return
	_fail("%scode %s absent de : %s" % [_prefix(message), tag, errors])


func _prefix(message: String) -> String:
	return "" if message.is_empty() else message + " : "


func _fail(message: String) -> void:
	_failures += 1
	printerr("ÉCHEC %s : %s" % [_current_test, message])
