extends EdTestCase
## Project enumeration, reads and revision-checked saves.

var _dir := ""


func _project() -> String:
	_dir = ProjectSettings.globalize_path("user://test-store-%d" % Time.get_ticks_usec())
	for d in ["Assets/UI/nested", "Library/cache", ".git", "Packages/p"]:
		DirAccess.make_dir_recursive_absolute(_dir + "/" + d)
	_write("Assets/UI/a.uxml", "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" />\n")
	_write("Assets/UI/nested/b.uss", "Label { color: red; }\n")
	_write("Assets/UI/readme.txt", "not ui")
	_write("Library/cache/c.uss", "skipped")
	_write(".git/d.uxml", "skipped")
	_write("Packages/p/e.USS", ".x {}")
	return _dir


func _write(rel: String, s: String) -> void:
	var f := FileAccess.open(_dir + "/" + rel, FileAccess.WRITE)
	f.store_buffer(s.to_utf8_buffer())
	f.close()


func teardown() -> void:
	if not _dir.is_empty():
		_rm(_dir)
	await super()


static func _rm(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_rm(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func test_lists_uxml_and_uss_skipping_caches() -> void:
	var store := EdProjectStore.new(_project())
	eq(store.list_files(), ["Assets/UI/a.uxml", "Assets/UI/nested/b.uss", "Packages/p/e.USS"])


func test_save_writes_when_revision_matches() -> void:
	var store := EdProjectStore.new(_project())
	var r = store.read("Assets/UI/nested/b.uss")
	var b: EdSourceBuffer = r["buffer"]
	var edited := b.with_text("Label { color: blue; }\n")
	var rev = store.save("Assets/UI/nested/b.uss", edited, r["revision"])
	ok(rev is Dictionary, "saved")
	eq(FileAccess.get_file_as_string(_dir + "/Assets/UI/nested/b.uss"), "Label { color: blue; }\n")
	ok(not FileAccess.file_exists(_dir + "/Assets/UI/nested/b.uss" + EdProjectStore.TEMP_SUFFIX), "temp file gone")
	eq(store.revision("Assets/UI/nested/b.uss")["sha256"], rev["sha256"])


func test_save_refuses_after_external_change() -> void:
	var store := EdProjectStore.new(_project())
	var r = store.read("Assets/UI/a.uxml")
	_write("Assets/UI/a.uxml", "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label /></ui:UXML>\n")
	var res = store.save("Assets/UI/a.uxml", r["buffer"], r["revision"])
	is_error(res, "stale-revision")
	eq(FileAccess.get_file_as_string(_dir + "/Assets/UI/a.uxml"), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label /></ui:UXML>\n", "external change kept")
	var forced = store.save("Assets/UI/a.uxml", r["buffer"], r["revision"], true)
	ok(forced is Dictionary, "overwrite on request")


func test_save_refuses_after_external_delete() -> void:
	var store := EdProjectStore.new(_project())
	var r = store.read("Assets/UI/a.uxml")
	DirAccess.remove_absolute(_dir + "/Assets/UI/a.uxml")
	is_error(store.save("Assets/UI/a.uxml", r["buffer"], r["revision"]), "stale-revision")


func test_missing_file() -> void:
	var store := EdProjectStore.new(_project())
	is_error(store.read("Assets/UI/none.uxml"), "missing-file")


func test_project_paths() -> void:
	eq(EdProjectPaths.resolve("styles/a.uss", "Assets/UI/screen.uxml"), "Assets/UI/styles/a.uss")
	eq(EdProjectPaths.resolve("../b.uss", "Assets/UI/screen.uxml"), "Assets/b.uss")
	eq(EdProjectPaths.resolve("/Assets/x.uss", "Assets/UI/screen.uxml"), "Assets/x.uss")
	eq(EdProjectPaths.resolve("project://database/Assets/x.uss?fileID=1&guid=2#x", "Assets/UI/screen.uxml"), "Assets/x.uss")
	eq(EdProjectPaths.resolve("../../../x.uss", "Assets/UI/screen.uxml"), null)
	eq(EdProjectPaths.resolve("https://example.com/x.uss", "Assets/UI/screen.uxml"), null)
