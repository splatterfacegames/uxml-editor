extends EdAppTestCase
## Milestone 8: the project host of the web export (EdWebHost), on the
## desktop with a fake of web_host.js. The fake keeps a "disk": path ->
## {data: PackedByteArray, mtime, size}, as the File System Access API
## shows it.

var _disk: Dictionary = {}
var _fs := true
var _calls: Array = []
## Writes that the fake answers with a disk change first: path -> new text.
var _race: Dictionary = {}
var _fail_write := false
var _recovery := ""


func _fake(method: String, json: String, answer: Callable) -> Variant:
	_calls.append(method)
	match method:
		"hasFsAccess":
			return _fs
		"pickDirectory":
			var files: Array = []
			for p in _disk:
				files.append({"path": p, "data": Marshalls.raw_to_base64(_disk[p]["data"]), "mtime": _disk[p]["mtime"], "size": _disk[p]["size"]})
			answer.call(JSON.stringify({"ok": true, "mode": "fs", "name": "menu", "files": files}))
		"fetchSample":
			if json != "sample":
				answer.call(JSON.stringify({"ok": false, "error": "HTTP 404"}))
				return null
			answer.call(JSON.stringify({"ok": true, "mode": "zip", "name": "sample.zip", "data": Marshalls.raw_to_base64(_sample_zip())}))
		"stat":
			var req = JSON.parse_string(json)
			var out: Array = []
			for f in req["files"]:
				var p := String(f["path"])
				if not _disk.has(p):
					out.append({"path": p, "exists": false, "mtime": 0, "size": 0})
					continue
				var d: Dictionary = _disk[p]
				var e := {"path": p, "exists": true, "mtime": d["mtime"], "size": d["size"]}
				if int(f["mtime"]) != int(d["mtime"]) or int(f["size"]) != int(d["size"]):
					e["data"] = Marshalls.raw_to_base64(d["data"])
				out.append(e)
			answer.call(JSON.stringify({"ok": true, "files": out}))
		"write":
			var req = JSON.parse_string(json)
			var p := String(req["path"])
			if _race.has(p):
				_set_disk(p, String(_race[p]))
				_race.erase(p)
			if _fail_write:
				answer.call(JSON.stringify({"ok": false, "conflict": false, "path": p, "error": "NotAllowedError"}))
				return null
			var d: Dictionary = _disk.get(p, {})
			if not bool(req["force"]) and not d.is_empty() and (int(d["mtime"]) != int(req["mtime"]) or int(d["size"]) != int(req["size"])):
				answer.call(JSON.stringify({"ok": false, "conflict": true, "path": p, "mtime": d["mtime"], "size": d["size"], "data": Marshalls.raw_to_base64(d["data"])}))
				return null
			var bytes := Marshalls.base64_to_raw(String(req["data"]))
			_disk[p] = {"data": bytes, "mtime": int(d.get("mtime", 1000)) + 1000, "size": bytes.size()}
			answer.call(JSON.stringify({"ok": true, "path": p, "mtime": _disk[p]["mtime"], "size": bytes.size()}))
	return null


func _set_disk(p: String, text: String) -> void:
	var bytes := text.to_utf8_buffer()
	var old: Dictionary = _disk.get(p, {"mtime": 1000})
	_disk[p] = {"data": bytes, "mtime": int(old["mtime"]) + 7, "size": bytes.size()}


func _disk_text(p: String) -> String:
	return (_disk[p]["data"] as PackedByteArray).get_string_from_utf8()


func _load_disk() -> void:
	var src := ProjectSettings.globalize_path("res://fixtures/projects/menu")
	for rel in [MENU, MENU_USS]:
		var bytes := FileAccess.get_file_as_bytes(src + "/" + rel)
		_disk[rel] = {"data": bytes, "mtime": 1000, "size": bytes.size()}


## The editor with a web host on the fake.
func _web_editor() -> EdMain:
	tree.root.size = Vector2i(1600, 1000)
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(m)
	await frames()
	# A journal of its own: the copy has the same path in each test.
	_recovery = ProjectSettings.globalize_path("user://test-web-recovery-%d" % Time.get_ticks_usec())
	m.state.recovery_base = _recovery
	var w := EdWebHost.new(m)
	w.use_bridge(_fake)
	m.add_child(w)
	m.web = w
	_load_disk()
	return m


func _duplicate_quit(m: EdMain) -> void:
	m.state.select_node(node_named(m, "quit-button"), "test")
	m.run_command("duplicate")
	await frames()


func teardown() -> void:
	await super()
	EdWebHost._rm(ProjectSettings.globalize_path(EdWebHost.BASE))
	if not _recovery.is_empty():
		EdWebHost._rm(_recovery)


func test_a_directory_opens_as_a_copy() -> void:
	var m := await _web_editor()
	m.execute("open-project")
	await frames()
	eq(m.web.mode, "fs")
	ok(m.state.has_project(), "the project is open")
	eq(m.state.store.root, m.web.root, "the store reads the copy")
	eq(m.state.files, [MENU_USS, MENU])
	eq(m.state.workspace.text(MENU), _disk_text(MENU), "byte for byte")
	m.state.open_document(MENU)
	await frames()
	ok(m.canvas.host.is_loaded(), "the canvas renders the copy")


func test_a_save_writes_the_disk() -> void:
	var m := await _web_editor()
	m.execute("open-project")
	m.state.open_document(MENU)
	await frames()
	await _duplicate_quit(m)
	ok(m.state.workspace.is_dirty(MENU))
	m.execute("save")
	await frames()
	ok(not m.state.workspace.is_dirty(MENU), "saved")
	ok(_disk_text(MENU).contains("quit-button-copy"), "the disk has the edit")
	eq(FileAccess.get_file_as_bytes(m.web.root + "/" + MENU), _disk[MENU]["data"], "the copy and the disk agree")
	ok(_calls.has("stat") and _calls.has("write"), "read again, then written: %s" % [_calls])


func test_a_disk_change_before_a_save_is_refused_as_on_the_desktop() -> void:
	var m := await _web_editor()
	m.execute("open-project")
	m.state.open_document(MENU)
	await frames()
	await _duplicate_quit(m)
	_set_disk(MENU, "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label text=\"other\" /></ui:UXML>")
	m.execute("save")
	await frames()
	ok(m.state.workspace.is_dirty(MENU), "not saved")
	ok(_disk_text(MENU).contains("other"), "the disk keeps the other change")
	ok(m._confirm.visible, "the editor asks before an overwrite")
	m._confirm.confirmed.emit()
	m._confirm.hide()
	await frames()
	ok(not m.state.workspace.is_dirty(MENU), "overwritten")
	ok(_disk_text(MENU).contains("quit-button-copy"), "with the editor text")


func test_a_disk_change_during_a_save_keeps_the_edit_unsaved() -> void:
	var m := await _web_editor()
	m.execute("open-project")
	m.state.open_document(MENU)
	await frames()
	await _duplicate_quit(m)
	var edited := m.state.workspace.text(MENU)
	_race[MENU] = "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label text=\"race\" /></ui:UXML>"
	m.execute("save")
	await frames()
	ok(_disk_text(MENU).contains("race"), "nothing written over the change")
	ok(m.state.workspace.is_dirty(MENU), "the edit is unsaved again")
	eq(m.state.workspace.text(MENU), edited, "and kept")
	ok(m.web.last_push[0].get("conflict", false))
	ok(FileAccess.get_file_as_string(m.web.root + "/" + MENU).contains("race"), "the copy has the disk bytes")


func test_a_failed_write_keeps_the_edit_unsaved() -> void:
	var m := await _web_editor()
	m.execute("open-project")
	m.state.open_document(MENU)
	await frames()
	await _duplicate_quit(m)
	_fail_write = true
	m.execute("save")
	await frames()
	ok(m.state.workspace.is_dirty(MENU), "unsaved")
	ok(not _disk_text(MENU).contains("quit-button-copy"))


func test_the_watch_timer_sees_a_disk_change() -> void:
	var m := await _web_editor()
	m.execute("open-project")
	m.state.open_document(MENU)
	await frames()
	_set_disk(MENU_USS, ".menu-root { background-color: #102030; }\n")
	ok(m.state.pending_recovery.is_empty() and m._asking == null, "no question waits")
	m._on_watch_timer()
	await frames()
	eq(m.state.workspace.text(MENU_USS), ".menu-root { background-color: #102030; }\n", "a clean file reloads")


func test_a_zip_opens_and_a_save_downloads_the_zip() -> void:
	var m := await _web_editor()
	_fs = false
	# A zip with one top folder, as a download of a folder gives.
	var tmp := ProjectSettings.globalize_path("user://test-web-%d.zip" % Time.get_ticks_usec())
	var z := ZIPPacker.new()
	z.open(tmp)
	for rel in [MENU, MENU_USS]:
		z.start_file("MenuProject/" + rel)
		z.write_file(_disk[rel]["data"])
		z.close_file()
	z.close()
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	m.execute("open-project")
	ok(_calls.has("pickZip"), "without the API: the zip input")
	eq(m.web.open_zip_bytes("MenuProject.zip", bytes), OK)
	await frames()
	eq(m.web.mode, "zip")
	eq(m.web.project_name, "MenuProject", "the top folder")
	eq(m.state.files, [MENU_USS, MENU])
	m.state.open_document(MENU)
	await frames()
	await _duplicate_quit(m)
	m.execute("save")
	await frames()
	ok(not m.state.workspace.is_dirty(MENU), "saved to the copy")
	eq(m.web.downloads, 1, "and downloaded")
	# The zip has the edit.
	var out := ProjectSettings.globalize_path("user://test-web-out.zip")
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_buffer(m.web.last_zip)
	f.close()
	var r := ZIPReader.new()
	eq(r.open(out), OK)
	ok(r.get_files().has("MenuProject/" + MENU), "the paths of the project: %s" % [r.get_files()])
	ok(r.read_file("MenuProject/" + MENU).get_string_from_utf8().contains("quit-button-copy"), "the zip has the edit")
	r.close()
	DirAccess.remove_absolute(out)


## A zip of the menu fixture under one top folder, as the site bundles it.
func _sample_zip() -> PackedByteArray:
	var tmp := ProjectSettings.globalize_path("user://test-web-sample-%d.zip" % Time.get_ticks_usec())
	var z := ZIPPacker.new()
	z.open(tmp)
	for rel in [MENU, MENU_USS]:
		z.start_file("sample/" + rel)
		z.write_file(_disk[rel]["data"])
		z.close_file()
	z.close()
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return bytes


func test_a_sample_from_the_site_opens_as_a_zip() -> void:
	var m := await _web_editor()
	m.web.open_sample("sample")
	await frames()
	ok(_calls.has("fetchSample"), "the host fetches the sample")
	eq(m.web.mode, "zip")
	eq(m.web.project_name, "sample", "the top folder")
	eq(m.state.files, [MENU_USS, MENU])
	ok(m.state.session != null, "the first document is open")
	await _duplicate_quit(m)
	m.execute("save")
	await frames()
	eq(m.web.downloads, 1, "a save downloads the project as a zip")


func test_a_missing_sample_opens_nothing() -> void:
	var m := await _web_editor()
	m.web.open_sample("nope")
	await frames()
	ok(not m.state.has_project(), "no project")


func test_a_broken_zip_opens_nothing() -> void:
	var m := await _web_editor()
	_fs = false
	ok(m.web.open_zip_bytes("x.zip", "not a zip".to_utf8_buffer()) != OK)
	ok(not m.state.has_project())


func test_names_are_safe_folder_names() -> void:
	eq(EdWebHost._safe("My Project (2)"), "My_Project__2_")
	eq(EdWebHost._safe("../x"), "project")
	eq(EdWebHost._safe(""), "project")
	eq(EdWebHost._common_folder(PackedStringArray(["a/x.uxml", "a/b/y.uss"])), "a/")
	eq(EdWebHost._common_folder(PackedStringArray(["a/x.uxml", "y.uss"])), "")


## A browser has no system fonts: every symbol that the editor draws is in
## Inter or in the symbol fallback (src/app/fonts).
func test_every_editor_glyph_has_a_font_without_system_fonts() -> void:
	await _web_editor()
	var inter := UxmlTheme.default_font()
	var symbols := load(EdMain.SYMBOL_FONT) as Font
	ok(inter.fallbacks.has(symbols), "the symbol font is a fallback of the default font")
	EdMain.add_symbol_fallback()
	eq(inter.fallbacks.count(symbols), 1, "added once")
	var missing := []
	for ch in "·×—…←→−∿▲▶▾◀○●⚠✓❚":
		var code := ch.unicode_at(0)
		if not symbols.has_char(code) and not (load(UxmlTheme.DEFAULT_FONT) as FontFile).get_supported_chars().contains(ch):
			missing.append("U+%04X" % code)
	eq(missing, [], "glyphs without a font")
	ok(symbols.has_char(0x25B6) and symbols.has_char(0x25BE) and symbols.has_char(0x223F) and symbols.has_char(0x275A), "the symbols that Inter lacks")
