extends SceneTree
## Headless test runner.
##
##   godot --headless --path . -s res://tests/run_tests.gd [-- options]
##
## Options (after `--`):
##   --filter=<text>   run only test files or methods whose name contains it
##   --gdscript        disable the godot-uxml native core (GDScript path)
##
## Every tests/unit/test_*.gd file extends EdTestCase. Every method whose
## name starts with `test_` is one test. The exit code is the number of
## failed tests (capped at 255).

const UNIT_DIR := "res://tests/unit"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := ""
	for a in args:
		if a.begins_with("--filter="):
			filter = a.substr(9)
		elif a == "--gdscript":
			UxmlParser.use_native = false
			UssParser.use_native = false
			UssCascade.use_native = false
			UxmlDocument.use_native_layout = false
	# Journals of the test projects go to a directory of their own.
	EdEditorState.default_recovery_base = "user://test-recovery"
	var logger := ErrorCounter.new()
	OS.add_logger(logger)
	var broken := _compile_all("res://src")
	var native := ClassDB.class_exists("UxmlNativeParser") and UxmlParser.use_native
	print("godot-uxml core: %s" % ("native" if native else "GDScript"))
	var files: Array = []
	for f in DirAccess.get_files_at(UNIT_DIR):
		if f.begins_with("test_") and f.ends_with(".gd"):
			files.append(f)
	files.sort()
	var total := 0
	var failed := 0
	var checks := 0
	var failures: Array = []
	var started := Time.get_ticks_msec()
	for f in files:
		var script: GDScript = load(UNIT_DIR + "/" + f)
		if script == null:
			failures.append("%s: does not compile" % f)
			failed += 1
			continue
		var methods: Array = []
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if mname.begins_with("test_") and not methods.has(mname):
				if filter.is_empty() or f.contains(filter) or mname.contains(filter):
					methods.append(mname)
		if methods.is_empty():
			continue
		var file_failed := 0
		for mname in methods:
			var tc: EdTestCase = script.new()
			tc.tree = self
			tc.current = "%s::%s" % [f.get_basename(), mname]
			logger.reset()
			await tc.call(mname)
			await tc.teardown()
			for e in logger.take():
				tc.failures.append("script error: " + e)
			total += 1
			checks += tc.checks
			if not tc.failures.is_empty():
				failed += 1
				file_failed += 1
				for msg in tc.failures:
					failures.append("%s: %s" % [tc.current, msg])
		print("%-44s %3d tests  %s" % [f.get_basename(), methods.size(), "ok" if file_failed == 0 else "%d FAILED" % file_failed])
	for b in broken:
		failures.push_front("%s: does not compile" % b)
		failed += 1
	for msg in failures:
		printerr("FAIL " + msg)
	_rm(ProjectSettings.globalize_path("user://test-recovery"))
	print("%d tests, %d checks, %d failed (%.1f s)" % [total, checks, failed, (Time.get_ticks_msec() - started) / 1000.0])
	quit(mini(failed, 255))


static func _rm(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_rm(dir + "/" + d)
	DirAccess.remove_absolute(dir)


## Load every script under `dir`; return the paths that fail to compile.
func _compile_all(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			var sc = ResourceLoader.load(dir + "/" + f, "", ResourceLoader.CACHE_MODE_REUSE)
			if sc == null or not (sc as GDScript).can_instantiate():
				out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_compile_all(dir + "/" + d))
	return out


## Collects script errors so a test that stops on an error fails.
class ErrorCounter extends Logger:
	var _errors: Array = []
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_mutex.lock()
		_errors.append("%s (%s:%d %s)" % [rationale if not rationale.is_empty() else code, file, line, function])
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

	func reset() -> void:
		_mutex.lock()
		_errors.clear()
		_mutex.unlock()

	func take() -> Array:
		_mutex.lock()
		var out := _errors.duplicate()
		_errors.clear()
		_mutex.unlock()
		return out
