extends EdAppTestCase
## Milestone 5 in the editor: the diagnostics panel, document tabs with one
## history, the disk watch timer, and the hierarchy context menu.

const SECOND := "Assets/UI/Second.uxml"


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ---------------------------------------------------------------------------
# Diagnostics
# ---------------------------------------------------------------------------

func test_diagnostics_filter_by_severity_file_and_source() -> void:
	var m := await editor("unsupported")
	var all := m.diagnostics_all
	ok(all.size() >= 4, "godot-uxml diagnostics: %d" % all.size())
	ok(all.all(func(e): return e["source"] == "godot-uxml"), "the unknown element is reported once (godot-uxml)")
	var uxml := "Assets/UI/Unsupported.uxml"
	m._set_diag_filter("file", uxml, "diag-file-menu", uxml)
	await frames(1)
	ok(m._diagnostics.size() > 0 and m._diagnostics.all(func(e): return e["file"] == uxml), "file filter")
	m._set_diag_filter("file", "", "diag-file-menu", "All files")
	m._set_diag_filter("severity", "error", "diag-severity-menu", "Errors")
	eq(m._diagnostics.size(), 0, "no errors")
	m._set_diag_filter("severity", "", "diag-severity-menu", "All severities")
	m._set_diag_filter("source", "editor", "diag-source-menu", "Editor")
	eq(m._diagnostics.size(), 0, "no editor entries")
	# An editor refusal joins the list as an editor entry.
	m.state.execute(EdError.make("test", "a refused edit"), "test")
	await frames(1)
	eq(m._diagnostics.size(), 1, "the refusal")
	ok(m._diagnostics[0]["message"].contains("a refused edit"))
	ok(m.shell.get_native("diagnostics-header").text.contains("1/"), "the header counts shown/all")
	m._set_diag_filter("source", "", "diag-source-menu", "All sources")
	eq(m._diagnostics.size(), all.size() + 1)


func test_editor_parse_problems_and_the_jump_to_a_range() -> void:
	var m := await editor("malformed")
	var path := "Assets/UI/Malformed.uxml"
	var mine := m.diagnostics_all.filter(func(e): return e["source"] == "editor" and e["severity"] == "error")
	ok(not mine.is_empty(), "the editor parse problem is an error")
	# Jump to a godot-uxml diagnostic with an element at its offset.
	var e: Dictionary = {}
	for x in m.diagnostics_all:
		if x["file"] == path and x["start"] >= 0 and m.state.session.tree().element_at_offset(x["start"]) != null and m.state.session.tree().element_at_offset(x["start"]).parent != null:
			e = x
			break
	ok(not e.is_empty(), "a diagnostic inside an element")
	if e.is_empty():
		return
	m.jump_to_diagnostic(e)
	await frames()
	var n := m.state.selected_node()
	ok(n != null and n.open_start <= e["start"] and e["start"] < maxi(n.open_end, n.inner_end), "the element at the range is selected")
	eq(m.canvas.selected_ids, [n.id], "in the canvas")
	var item := m.shell.get_tree_item("hierarchy-tree", m.shell.get_selected_indices("hierarchy-tree")[0])
	eq(int(item["id"]), n.id, "in the hierarchy")
	eq(m.source.path, path)
	var a: int = m.source._map.to_buffer(m.source._offset_of(m.source.get_selection_from_line(), m.source.get_selection_from_column()))
	var b: int = m.source._map.to_buffer(m.source._offset_of(m.source.get_selection_to_line(), m.source.get_selection_to_column()))
	eq([a, b], [e["start"], e["end"]], "the source selects the range")
	ok(e["end"] > e["start"], "a range, not a point")


func test_a_list_click_jumps() -> void:
	var m := await editor("unsupported")
	var i := -1
	for k in m._diagnostics.size():
		if m._diagnostics[k]["file"].ends_with(".uss"):
			i = k
			break
	ok(i >= 0, "a stylesheet diagnostic")
	m.shell.set_selection("diagnostics-list", [i])
	await frames()
	eq(m.source.path, m._diagnostics[i]["file"], "the source view shows the stylesheet")
	ok(m.source.has_selection(), "the range is selected")


func test_range_end() -> void:
	var ws := EdWorkspace.new()
	ws.set_buffer("a.uxml", EdSourceBuffer.new("a.uxml", "<ui:UXML><ui:Label text=\"x\" bad=\"1\" /></ui:UXML>"))
	ws.set_buffer("a.uss", EdSourceBuffer.new("a.uss", ".a { color: red; }"))
	eq(EdDiagnostics.range_end(ws, "a.uxml", 9), "<ui:UXML><ui:Label text=\"x\" bad=\"1\" />".length(), "an open tag")
	eq(EdDiagnostics.range_end(ws, "a.uxml", 28), 35, "an attribute")
	eq(EdDiagnostics.range_end(ws, "a.uss", 5), 11, "a token")


# ---------------------------------------------------------------------------
# Tabs and the one history
# ---------------------------------------------------------------------------

func test_tabs_share_one_history() -> void:
	var dir := copy_fixture("menu")
	_write(dir + "/" + SECOND, "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Label name=\"second\" text=\"B\" />\n</ui:UXML>\n")
	tree.root.size = Vector2i(1600, 1000)
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(m)
	await frames()
	m.state.open_project(dir)
	await frames()
	m.state.open_document(MENU)
	m.state.open_document(SECOND)
	await frames()
	eq(m.state.tabs, [MENU, SECOND], "two tabs")
	ok(m.tabs.tab_rect(SECOND).has_area() and m.tabs.tab_rect(MENU).has_area(), "the tab bar shows both")
	# An edit in each tab.
	m.state.open_document(MENU)
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(node_named(m, "play-button")), "text", "A1"), "test")
	await frames()
	m.state.open_document(SECOND)
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(node_named(m, "second")), "text", "B1"), "test")
	await frames()
	eq(m.state.workspace.history.undo_depth(), 2, "one history")
	ok(m.tabs.doc.get_native("tab-0").text.begins_with("● "), "the unsaved mark")
	m._undo()
	await frames()
	eq(m.state.session.entry_path, SECOND, "the newest step is in this tab")
	ok(not m.state.workspace.text(SECOND).contains("B1"))
	m._undo()
	await frames()
	eq(m.state.session.entry_path, MENU, "undo shows the tab of the step")
	ok(not m.state.workspace.text(MENU).contains("A1"))
	m._redo()
	await frames()
	ok(m.state.workspace.text(MENU).contains("A1"), "redo")
	# Click a tab, then close it with its button.
	mouse_button(m, m.tabs.tab_rect(SECOND).get_center(), true)
	mouse_button(m, m.tabs.tab_rect(SECOND).get_center(), false)
	await frames()
	eq(m.state.session.entry_path, SECOND, "a click shows the tab")
	var close := m.tabs.close_rect(SECOND).get_center()
	mouse_button(m, close, true)
	mouse_button(m, close, false)
	await frames()
	eq(m.state.tabs, [MENU], "closed")
	eq(m.state.session.entry_path, MENU, "the next tab is active")
	ok(m.state.workspace.is_dirty(MENU), "edits stay in the workspace")
	# The selection of a tab comes back.
	m.state.select_node(node_named(m, "quit-button"), "test")
	m.state.open_document(SECOND)
	m.state.open_document(MENU)
	eq(m.state.selected_node().get_attribute("name"), "quit-button", "per-tab selection")
	key(m, KEY_W, true)
	await frames()
	eq(m.state.tabs, [SECOND], "Ctrl+W closes the active tab")
	m.state.close_document(SECOND)
	await frames()
	eq(m.state.session, null, "no tab")
	eq(m.canvas.host.element_for_node.size(), 0, "an empty canvas")


# ---------------------------------------------------------------------------
# External changes on a timer
# ---------------------------------------------------------------------------

func test_the_watch_timer_reloads_and_asks() -> void:
	var m := await editor("menu")
	m.watch_timer.stop()
	m.watch_timer.wait_time = 0.1
	m.watch_timer.start()
	# A clean file reloads without a question.
	var uss := FileAccess.get_file_as_string(_dir + "/" + MENU_USS)
	_write(_dir + "/" + MENU_USS, uss + "\n.extra { color: red; }\n")
	var t0 := Time.get_ticks_msec()
	while not m.state.workspace.text(MENU_USS).contains(".extra") and Time.get_ticks_msec() - t0 < 4000:
		await tree.process_frame
	ok(m.state.workspace.text(MENU_USS).contains(".extra"), "a clean file reloads on the timer")
	ok(m._asking == null, "no question for a clean file")
	# A dirty file that changes on disk asks.
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(node_named(m, "play-button")), "text", "Mine"), "test")
	var disk := FileAccess.get_file_as_string(_dir + "/" + MENU).replace("Main Menu", "Theirs")
	_write(_dir + "/" + MENU, disk)
	t0 = Time.get_ticks_msec()
	while m._asking == null and Time.get_ticks_msec() - t0 < 4000:
		await tree.process_frame
	ok(m._asking != null and m._asking.dialog_text.contains(MENU), "a conflict question")
	m.answer(false)
	await frames(10)
	ok(m.state.workspace.text(MENU).contains("Mine"), "keep: the editor text stays")
	ok(m._asking == null, "the same disk version is not asked again")
	_write(_dir + "/" + MENU, disk.replace("Theirs", "Theirs again"))
	t0 = Time.get_ticks_msec()
	while m._asking == null and Time.get_ticks_msec() - t0 < 4000:
		await tree.process_frame
	ok(m._asking != null, "a new disk version asks again")
	m.answer(true)
	await frames()
	ok(m.state.workspace.text(MENU).contains("Theirs again"), "reload: the disk text")
	ok(not m.state.workspace.is_dirty(MENU), "clean after the reload")


func test_the_quick_check_reads_no_unchanged_file() -> void:
	var store := EdProjectStore.new(copy_fixture("menu"))
	var rev := store.revision(MENU)
	# A file older than a few seconds with the same size and time.
	var old := rev.duplicate()
	ok(not store.may_differ(MENU, old) or int(Time.get_unix_time_from_system()) - int(rev["mtime"]) <= 3, "unchanged")
	var changed := rev.duplicate()
	changed["size"] = 1
	ok(store.may_differ(MENU, changed), "a size change")
	changed = rev.duplicate()
	changed["mtime"] = 5
	ok(store.may_differ(MENU, changed), "a time change")


# ---------------------------------------------------------------------------
# Hierarchy context menu
# ---------------------------------------------------------------------------

func test_the_hierarchy_context_menu_runs_edit_commands() -> void:
	var m := await editor("menu")
	var quit := node_named(m, "quit-button")
	var r := await row_rect(m, "hierarchy-tree", tree_index(m, "hierarchy-tree", quit.id))
	ok(r.has_area(), "the row of quit-button")
	mouse_button(m, r.get_center(), true, MOUSE_BUTTON_RIGHT)
	mouse_button(m, r.get_center(), false, MOUSE_BUTTON_RIGHT)
	await frames()
	var menu := m.shell.get_context_menu()
	ok(menu != null, "a right click opens the menu")
	eq(menu.document().editor_theme, "always", "the menu has the editor look of the window")
	eq(menu.document().editor_skin, "dark", "and the skin of the window")
	eq(m.state.selected_node().get_attribute("name"), "quit-button", "the row is selected")
	var dup := -1
	for i in EdMain.CONTEXT_MENU.size():
		if EdMain.CONTEXT_MENU[i][1] == "duplicate":
			dup = i
	menu.chosen.emit(dup)
	await frames()
	ok(m.state.workspace.text(MENU).contains("quit-button-copy"), "Duplicate from the menu")
	eq(m.state.workspace.history.undo_depth(), 1, "one undo step")
