extends EdTestCase
## Open and save every fixture: the saved bytes equal the original bytes.
## Covers fixtures/projects (CRLF, LF, malformed) and the godot-uxml parity
## cases in tests/fixtures/godot-uxml-parity.

var _scratch := ""


func _scratch_dir() -> String:
	if _scratch.is_empty():
		_scratch = ProjectSettings.globalize_path("user://test-roundtrip-%d" % Time.get_ticks_usec())
		DirAccess.make_dir_recursive_absolute(_scratch)
	return _scratch


func teardown() -> void:
	if not _scratch.is_empty():
		_remove_tree(_scratch)
	await super()


static func _remove_tree(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_remove_tree(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func test_every_fixture_saves_byte_identical() -> void:
	var files := fixture_files(["uxml", "uss"])
	ok(files.size() >= 190, "fixtures found (%d)" % files.size())
	var dir := _scratch_dir()
	var store := EdProjectStore.new(dir)
	var failed: Array = []
	var inexact: Array = []
	for i in files.size():
		var original := read_file(files[i])
		var rel := "f%03d.%s" % [i, files[i].get_extension()]
		var f := FileAccess.open(dir + "/" + rel, FileAccess.WRITE)
		f.store_buffer(original)
		f.close()
		var r = store.read(rel)
		if r is EdError:
			failed.append(files[i])
			continue
		var b: EdSourceBuffer = r["buffer"]
		if not b.exact:
			inexact.append(files[i])
			continue
		# Parse it as the editor would; parsing must not change the text.
		if rel.ends_with(".uxml"):
			EdUxmlSource.parse(b.text)
		else:
			EdUssSource.parse(b.text)
		var saved = store.save(rel, b, r["revision"])
		if saved is EdError or read_file(dir + "/" + rel) != original:
			failed.append(files[i])
	eq(failed, [], "not byte-identical after open and save")
	eq(inexact, [], "fixtures that do not decode exactly")


func test_crlf_fixture_keeps_crlf_after_an_edit() -> void:
	var path := ProjectSettings.globalize_path("res://fixtures/projects/menu/Assets/UI/Menu.uxml")
	var original := read_file(path)
	var b := EdSourceBuffer.from_bytes("Menu.uxml", original)
	eq(b.newline_style, "crlf")
	var ws := EdWorkspace.new()
	ws.set_buffer("Assets/UI/Menu.uxml", b)
	var s := EdDocumentSession.new(ws, "Assets/UI/Menu.uxml")
	var el: EdUxmlNode = s.root().children[-1]
	var tx = EdUxmlCommands.set_attribute(s, EdLocator.create(el), "tooltip", "Hi")
	ok(tx is EdTransaction)
	ws.history.execute(tx)
	var after := ws.text("Assets/UI/Menu.uxml")
	eq(after.count("\r\n"), b.text.count("\r\n"), "no newline added or converted")
	eq(after.replace("\r\n", "").count("\n"), 0, "no bare LF")
	ws.history.undo()
	eq(ws.buffer("Assets/UI/Menu.uxml").to_bytes(), original)
