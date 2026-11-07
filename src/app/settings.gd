class_name EdSettings
extends RefCounted
## Per-user editor settings in a ConfigFile (default
## `user://settings.cfg`): the sizes of the window panes, the timeline
## options and the state of the panels. `user://` is a directory of the operating system user, so each
## user keeps their own layout.
##
## The test runner and the benchmark point `default_path` at a test file,
## so a test run never reads or changes the settings of the user.

static var default_path := "user://settings.cfg"

var path: String
var _cfg := ConfigFile.new()


func _init(p: String = "") -> void:
	path = default_path if p.is_empty() else p
	if FileAccess.file_exists(path):
		_cfg.load(path)


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	if not _cfg.has_section_key(section, key):
		return fallback
	return _cfg.get_value(section, key)


## Set a value; returns true when it changed.
func set_value(section: String, key: String, value: Variant) -> bool:
	if _cfg.has_section_key(section, key) and _cfg.get_value(section, key) == value:
		return false
	_cfg.set_value(section, key, value)
	return true


func save() -> int:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	return _cfg.save(path)


func clear() -> void:
	_cfg.clear()
