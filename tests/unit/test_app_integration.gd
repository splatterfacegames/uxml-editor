extends EdTestCase
## The editor scene end to end, headless: every view edits through the one
## history, and every view follows every edit.

const MENU := "Assets/UI/Menu.uxml"
const MENU_USS := "Assets/UI/Menu.uss"

var _dir := ""


func _copy_fixture(name: String) -> String:
	_dir = ProjectSettings.globalize_path("user://test-app-%d" % Time.get_ticks_usec())
	_copy_tree(ProjectSettings.globalize_path("res://fixtures/projects/" + name), _dir)
	return _dir


static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from + "/" + f, to + "/" + f)
	for d in DirAccess.get_directories_at(from):
		_copy_tree(from + "/" + d, to + "/" + d)


static func _rm(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_rm(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func teardown() -> void:
	await super()
	if not _dir.is_empty():
		_rm(_dir)


func _editor() -> EdMain:
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(m)
	return m


func _frames(n: int = 3) -> void:
	for i in n:
		await tree.process_frame


func _node_named(m: EdMain, authored: String) -> EdUxmlNode:
	for n in m.state.session.root().walk():
		if n.get_attribute("name") == authored:
			return n
	return null


func test_open_project_lists_files_and_renders() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	eq(m.state.files, [MENU_USS, MENU])
	eq(m.state.session.entry_path, MENU, "the first UXML document opens")
	var host := m.canvas.host
	ok(host.element_for_node.size() >= 5, "authored elements map to rendered elements (%d)" % host.element_for_node.size())
	eq(host.diagnostics, [], "the menu fixture renders without diagnostics")
	eq(m.source.text, EdNewlineMap.make(m.state.workspace.text(MENU)).display, "the source view shows the document")


func test_canvas_hit_test_selects_and_syncs_views() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var play := _node_named(m, "play-button")
	var r := m.canvas.host.rect_of(play.id)
	ok(r.has_area(), "the button has a rectangle")
	var id := m.canvas.host.hit_test(r.get_center())
	eq(id, play.id, "hit-test finds the deepest authored element")
	m.canvas.picked.emit(id, false)
	await _frames()
	eq(m.state.selected_node(), play)
	eq(m.canvas.selected_id, play.id, "canvas overlay follows")
	var sel: Array = m.shell.get_selected_indices("hierarchy-tree")
	eq(sel.size(), 1, "hierarchy follows")
	eq(int(m.shell.get_tree_item("hierarchy-tree", sel[0])["id"]), play.id)
	eq(m.inspector._node, play, "inspector follows")
	var src := m.state.workspace.text(MENU)
	eq(m.source.get_selected_text(), EdNewlineMap.make(src.substr(play.open_start, play.open_end - play.open_start)).display, "source view marks the open tag")
	eq(m.canvas.host.hit_test(Vector2(-5, -5)), -1)


func test_inspector_edit_is_a_patch_and_one_undo_step() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var before := m.state.workspace.text(MENU)
	m.state.select_node(_node_named(m, "quit-button"), "test")
	await _frames()
	var field := ""
	for f in m.inspector._fields:
		if m.inspector._fields[f]["kind"] == "attr" and m.inspector._fields[f]["name"] == "text" and not f.begins_with("remove-"):
			field = f
	ok(not field.is_empty(), "the inspector has a text field")
	m.inspector._on_value_changed(field, "Leave & Save")
	await _frames()
	var after := m.state.workspace.text(MENU)
	eq(after, before.replace("text='Quit &#x26; Save'", "text='Leave &amp; Save'"), "only the value span changed, quote style kept")
	eq(m.state.workspace.history.undo_depth(), 1)
	eq(m.source.text, EdNewlineMap.make(after).display, "source view follows")
	var quit := _node_named(m, "quit-button")
	eq(m.canvas.host.element_for_node[quit.id].get_attribute("text"), "Leave & Save", "canvas re-rendered")
	eq(m.state.selected_node(), quit, "selection survives the re-parse")
	m._undo()
	await _frames()
	eq(m.state.workspace.text(MENU), before, "undo restores the exact text")
	m._redo()
	await _frames()
	eq(m.state.workspace.text(MENU), after)


func test_inline_style_from_inspector() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	m.state.select_node(_node_named(m, "menu-title"), "test")
	await _frames()
	var field := ""
	for f in m.inspector._fields:
		if m.inspector._fields[f]["kind"] == "style" and m.inspector._fields[f]["name"] == "font-size" and not f.begins_with("remove-"):
			field = f
	m.inspector._on_value_changed(field, "32px")
	await _frames()
	ok(m.state.workspace.text(MENU).contains("<ui:Label name=\"menu-title\" text=\"Main Menu\" style=\"font-size: 32px;\" />"), "inline style attribute added")
	var title := _node_named(m, "menu-title")
	eq(m.canvas.host.computed_style(title.id).get("font-size", {}).get("value"), "32px", "the render uses the new inline style")


func test_source_edit_shares_the_history_and_keeps_crlf() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var before := m.state.workspace.text(MENU)
	ok(before.contains("\r\n"), "CRLF fixture")
	m.source._replace_changed(m.source.text, m.source.text.replace("Main Menu", "Main Menu!"))
	await _frames(1)
	ok(m.source.has_pending_edit(), "typed text is pending")
	m.source.flush()
	await _frames()
	var after := m.state.workspace.text(MENU)
	eq(after, before.replace("Main Menu", "Main Menu!"), "one patch; every CRLF kept")
	m.source._replace_changed(m.source.text, m.source.text.replace("<ui:Label name=\"menu-title\" text=\"Main Menu!\" />", "<ui:Label name=\"menu-title\" text=\"Main Menu!\" />\n    <ui:Label text=\"New\" />"))
	await _frames(1)
	ok(m.source.has_pending_edit(), "typed text is pending")
	m.source.flush()
	await _frames()
	ok(m.state.workspace.text(MENU).contains("/>\r\n    <ui:Label text=\"New\" />"), "a typed line break is written as CRLF")
	eq(m.state.workspace.history.undo_depth(), 1, "typing coalesces into one step")
	m._undo()
	await _frames()
	eq(m.state.workspace.text(MENU), before)
	eq(m.source.text, EdNewlineMap.make(before).display, "source view follows undo")


func test_a_typing_pause_commits_the_source_edit() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var before := m.state.workspace.text(MENU)
	m.source._replace_changed(m.source.text, m.source.text.replace("Main Menu", "Main Menu?"))
	await _frames(1)
	ok(m.source.has_pending_edit(), "pending after typing")
	eq(m.state.workspace.text(MENU), before, "no patch before the pause")
	var t0 := Time.get_ticks_msec()
	while m.source.has_pending_edit() and Time.get_ticks_msec() - t0 < 3000:
		await tree.process_frame
	ok(not m.source.has_pending_edit(), "the pause timer commits")
	eq(m.state.workspace.text(MENU), before.replace("Main Menu", "Main Menu?"), "one patch after the pause")
	eq(m.state.workspace.history.undo_depth(), 1)
	# A programmatic reload is not an edit.
	m.source.reload_from_buffer(true)
	await _frames(1)
	ok(not m.source.has_pending_edit(), "a reload is not pending")


func test_stylesheet_edit_rerenders_from_the_buffer() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var uss := m.state.workspace.text(MENU_USS)
	var tx := m.state.workspace.replace_text_transaction(MENU_USS, uss + "\r\n#menu-title { font-size: 40px; }\r\n", "Edit USS")
	m.state.execute(tx, "test")
	await _frames()
	var title := _node_named(m, "menu-title")
	eq(m.canvas.host.computed_style(title.id).get("font-size", {}).get("value"), "40px", "unsaved USS text is rendered")
	eq(FileAccess.get_file_as_string(_dir + "/" + MENU_USS), uss, "disk unchanged before save")


func test_save_with_revision_check() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var original := FileAccess.get_file_as_bytes(_dir + "/" + MENU)
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(_node_named(m, "play-button")), "tooltip", "Go"), "test")
	await _frames()
	eq(m.state.workspace.dirty_paths(), [MENU])
	eq(m.state.save([MENU]), 1)
	eq(m.state.workspace.dirty_paths(), [])
	var saved := FileAccess.get_file_as_bytes(_dir + "/" + MENU)
	eq(saved, m.state.workspace.buffer(MENU).to_bytes(), "disk has the buffer bytes")
	ok(saved != original)
	# An external change makes the next save refuse.
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(_node_named(m, "play-button")), "tooltip", "Go!"), "test")
	var f := FileAccess.open(_dir + "/" + MENU, FileAccess.WRITE)
	f.store_buffer(original)
	f.close()
	eq(m.state.save([MENU]), 0, "stale revision refused")
	eq(FileAccess.get_file_as_bytes(_dir + "/" + MENU), original, "external change kept")
	var ext := m.state.check_external_changes()
	eq(ext["conflicts"], [MENU])


func test_external_change_reloads_clean_files() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var f := FileAccess.open(_dir + "/" + MENU_USS, FileAccess.WRITE)
	f.store_string("Label { color: red; }\n")
	f.close()
	var ext := m.state.check_external_changes()
	eq(ext["reloaded"], [MENU_USS])
	eq(m.state.workspace.text(MENU_USS), "Label { color: red; }\n")


func test_hierarchy_selection_and_delete() -> void:
	var m := _editor()
	await _frames()
	m.state.open_project(_copy_fixture("menu"))
	await _frames()
	var quit := _node_named(m, "quit-button")
	var idx := -1
	for i in 20:
		var it := m.shell.get_tree_item("hierarchy-tree", i)
		if not it.is_empty() and int(it["id"]) == quit.id:
			idx = i
	ok(idx >= 0, "the tree lists the button")
	m._on_list_selection("hierarchy-tree", [idx])
	await _frames()
	eq(m.state.selected_node(), quit)
	m.state.execute(EdUxmlCommands.remove_element(m.state.session, m.state.selection[0]), "hierarchy")
	await _frames()
	eq(_node_named(m, "quit-button"), null)
	ok(m.state.workspace.text(MENU).contains("<!-- keep-between-buttons -->"), "comment kept")
	eq(m.state.selected_node().get_attribute("name"), "menu-root", "selection moves to the parent")
