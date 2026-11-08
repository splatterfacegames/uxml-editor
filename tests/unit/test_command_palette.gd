extends EdAppTestCase
## Milestone 8: the command registry, the command palette and the shortcut map.


func _key_event(keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	e.alt_pressed = alt
	return e


## Type `text` as key events (the field with the focus gets them).
func _type(m: EdMain, text: String) -> void:
	for ch in text:
		for pressed in [true, false]:
			var e := InputEventKey.new()
			e.keycode = OS.find_keycode_from_string(ch.to_upper())
			e.unicode = ch.unicode_at(0)
			e.pressed = pressed
			m.get_viewport().push_input(e)
		await frames(1)


# ---------------------------------------------------------------------------
# Registry
# ---------------------------------------------------------------------------

func test_shortcut_text_parses() -> void:
	eq(EdCommandRegistry.parse("Ctrl+Shift+P"), {"keycode": KEY_P, "ctrl": true, "shift": true, "alt": false})
	eq(EdCommandRegistry.parse("Alt+Up"), {"keycode": KEY_UP, "ctrl": false, "shift": false, "alt": true})
	eq(EdCommandRegistry.parse("Del")["keycode"], KEY_DELETE)
	eq(EdCommandRegistry.parse("F2")["keycode"], KEY_F2)
	eq(EdCommandRegistry.parse("Ctrl++")["keycode"], KEY_PLUS, "the last + is the key")
	eq(EdCommandRegistry.parse("Ctrl+/")["keycode"], KEY_SLASH)
	eq(EdCommandRegistry.parse("Cmd+S")["ctrl"], true, "Cmd is the command key")
	eq(EdCommandRegistry.parse("Hyper+S"), {}, "an unknown modifier")
	eq(EdCommandRegistry.parse("Ctrl+"), {}, "no key")
	eq(EdCommandRegistry.parse("F13"), {})
	eq(EdCommandRegistry.parse(""), {})


func test_every_default_binding_parses_and_is_unique() -> void:
	var r := EdCommandRegistry.new()
	var seen := {}
	for c in r.commands:
		for k in c["keys"]:
			var spec := EdCommandRegistry.parse(String(k))
			ok(not spec.is_empty(), "%s: %s parses" % [c["id"], k])
			var key := "%s|%s" % [c["scope"], str(spec)]
			ok(not seen.has(key), "%s is bound once (also %s)" % [k, seen.get(key, "")])
			seen[key] = c["id"]
	ok(r.has("palette") and r.has("shortcuts"))
	ok(not r.has("download-zip"), "a web command is not a desktop command")
	ok(EdCommandRegistry.new("web").has("download-zip"))


func test_a_key_event_finds_its_command_in_its_scope() -> void:
	var r := EdCommandRegistry.new()
	eq(r.command_for(_key_event(KEY_S, true), "global"), "save")
	eq(r.command_for(_key_event(KEY_S, true, true), "global"), "save-all", "the modifiers must match")
	eq(r.command_for(_key_event(KEY_Y, true), "global"), "redo", "the second binding")
	eq(r.command_for(_key_event(KEY_D, true), "global"), "", "duplicate is a structure key")
	eq(r.command_for(_key_event(KEY_D, true), "structure"), "duplicate")
	eq(r.command_for(_key_event(KEY_UP, false, false, true), "structure"), "move-up")
	eq(r.command_for(_key_event(KEY_Q, true), "global"), "")


func test_overrides_change_the_bindings() -> void:
	var r := EdCommandRegistry.new()
	var dropped := r.apply_overrides({"duplicate": "Ctrl+Shift+D", "save": ["Ctrl+S", "F5"], "fit": "Ctrl+0", "wrap": "", "rename": "Nope+X"})
	eq(r.command_for(_key_event(KEY_D, true), "structure"), "", "the old binding is gone")
	eq(r.command_for(_key_event(KEY_D, true, true), "structure"), "duplicate")
	eq(r.command_for(_key_event(KEY_F5), "global"), "save")
	eq(r.command_for(_key_event(KEY_0, true), "global"), "fit")
	eq(r.keys_of("wrap"), [], "an empty text unbinds")
	eq(dropped, ["Nope+X"], "a text that does not parse is reported")
	eq(r.keys_of("rename"), [], "and not bound")
	eq(r.key_text("save"), "Ctrl+S")


func test_fuzzy_search_ranks_the_best_match_first() -> void:
	var r := EdCommandRegistry.new()
	eq(r.search("dup")[0]["id"], "duplicate")
	eq(r.search("save all")[0]["id"], "save-all")
	eq(r.search("tsp")[0]["id"], "states-panel", "the starts of words: Toggle the State-machine Panel")
	eq(r.search("zoom")[0]["category"], "View")
	eq(r.search("qqqq"), [], "no match")
	eq(r.search("").size(), r.commands.size(), "an empty query lists every command")
	ok(EdCommandRegistry.fuzzy_score("du", "Undo") < 0, "the order of the characters counts")
	ok(EdCommandRegistry.fuzzy_score("un", "Undo") > EdCommandRegistry.fuzzy_score("un", "Edit: Unwrap"), "an earlier match is better")
	ok(EdCommandRegistry.fuzzy_score("FIT", "fit the document") >= 0, "the case does not count")


func test_the_shortcut_map_lists_commands_and_fixed_keys() -> void:
	var r := EdCommandRegistry.new()
	var rows := r.shortcut_rows()
	var titles: Array = rows.map(func(x): return x["title"])
	ok(titles.has("Duplicate"))
	ok(titles.has("Cancel a drag"), "a fixed key")
	ok(not titles.has("Fit the document in the canvas"), "a command without a key is not in the map")
	# Rows of one category stay together.
	var cats: Array = []
	for x in rows:
		if cats.is_empty() or cats[-1] != x["category"]:
			ok(not cats.has(x["category"]), "%s once" % x["category"])
			cats.append(x["category"])
	eq(r.shortcut_rows("escape").map(func(x): return x["title"]).has("Cancel a drag"), true, "the keys are searched too")


# ---------------------------------------------------------------------------
# Palette in the editor
# ---------------------------------------------------------------------------

func test_the_palette_costs_nothing_until_it_opens() -> void:
	var m := await editor()
	eq(m.command_palette.loads, 0, "not loaded")
	ok(not m.command_palette.visible)
	key(m, KEY_P, true, true)
	await frames()
	ok(m.command_palette.is_open(), "Ctrl+Shift+P opens it")
	eq(m.command_palette.loads, 1)
	eq(m.command_palette.rows.size(), m.commands.commands.size(), "every command")
	ok(m.command_palette.doc.get_native("cp-search").has_focus(), "the search has the focus")
	key(m, KEY_ESCAPE)
	await frames()
	ok(not m.command_palette.is_open(), "Escape closes it")
	ok(not m.canvas.preview, "Ctrl+Shift+P is not Ctrl+P")


func test_typing_filters_and_enter_runs_the_command() -> void:
	var m := await editor()
	m.state.select_node(node_named(m, "quit-button"), "test")
	await frames()
	var before: int = m.state.session.root().walk().size()
	m.execute("palette")
	await frames()
	await _type(m, "dupl")
	await frames()
	eq(m.command_palette.query, "dupl")
	eq(m.command_palette.rows[0]["id"], "duplicate")
	eq(m.command_palette.row_texts(0), ["Edit", "Duplicate", "Ctrl+D"])
	key(m, KEY_ENTER)
	await frames(4)
	ok(not m.command_palette.is_open(), "closed")
	eq(m.state.session.root().walk().size(), before + 1, "the element is duplicated")
	eq(m.state.workspace.history.undo_label(), "Duplicate Button", "one undo step")


func test_arrow_keys_choose_a_row() -> void:
	var m := await editor()
	m.execute("palette")
	await frames()
	eq(m.command_palette.index, 0)
	key(m, KEY_DOWN)
	key(m, KEY_DOWN)
	await frames()
	eq(m.command_palette.index, 2)
	eq(m.command_palette.doc.get_selected_indices("cp-list"), [2], "the list shows the choice")
	key(m, KEY_UP)
	await frames()
	eq(m.command_palette.index, 1)
	m.command_palette.close()


func test_a_click_outside_the_panel_closes_it() -> void:
	var m := await editor()
	m.execute("palette")
	await frames()
	mouse_button(m, Vector2(20, 980), true)
	await frames()
	ok(not m.command_palette.is_open())


func test_the_shortcut_map_shows_the_current_bindings() -> void:
	var saved := EdSettings.default_path
	EdSettings.default_path = "user://test-keys-%d.cfg" % Time.get_ticks_usec()
	var s := EdSettings.new()
	s.set_value("shortcuts", "duplicate", "Ctrl+Shift+D")
	s.save()
	var m := await editor()
	key(m, KEY_SLASH, true)
	await frames()
	ok(m.command_palette.is_open())
	eq(m.command_palette.mode, "shortcuts")
	var found := false
	for i in m.command_palette.rows.size():
		var t := m.command_palette.row_texts(i)
		if t[1] == "Duplicate":
			found = true
			eq(t[2], "Ctrl+Shift+D", "the binding of the settings")
	ok(found, "Duplicate is in the map")
	ok(String(m.edit_menu_labels()[3]).ends_with("Ctrl+Shift+D"), "the Edit menu shows it too: %s" % m.edit_menu_labels()[3])
	m.command_palette.close()
	# The new binding works; the old one does nothing.
	m.state.select_node(node_named(m, "quit-button"), "test")
	await frames()
	var before: int = m.state.session.root().walk().size()
	key(m, KEY_D, true)
	await frames()
	eq(m.state.session.root().walk().size(), before, "Ctrl+D is free")
	key(m, KEY_D, true, true)
	await frames()
	eq(m.state.session.root().walk().size(), before + 1, "Ctrl+Shift+D duplicates")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EdSettings.default_path))
	EdSettings.default_path = saved


func test_every_command_runs_from_the_palette() -> void:
	var m := await editor()
	m.state.select_node(node_named(m, "quit-button"), "test")
	await frames()
	for c in m.commands.commands:
		var id := String(c["id"])
		if id == "open-project" or id == "close-tab":
			continue
		ok(m.execute(id), "%s runs" % id)
		await frames(1)
		m.command_palette.close()
		if m.canvas.preview:
			m.set_preview(false)
	eq(m.execute("no-such-command"), false)
	await frames()


func test_typing_in_the_library_search_keeps_the_order() -> void:
	# The search is a live TextField (not is-delayed). godot-uxml keeps its
	# caret at each change (request R27, pin f4ffe6e); value_changed gives
	# the text as the user types.
	var m := await editor()
	var le := EdUi.line_edit(m.shell, "palette-search")
	ok(le != null)
	le.grab_focus()
	await frames()
	await _type(m, "slid")
	await frames()
	eq(le.text, "slid")
	eq(le.caret_column, 4)
	eq(m.palette.query, "slid", "the library filters as the user types")


func test_typing_in_the_command_palette_keeps_the_order() -> void:
	var m := await editor()
	m.command_palette.open()
	await frames()
	var le := EdUi.line_edit(m.command_palette.doc, "cp-search")
	ok(le != null)
	ok(le.has_focus(), "the search has the focus")
	await _type(m, "dupl")
	await frames()
	eq(le.text, "dupl")
	eq(le.caret_column, 4)
	eq(m.command_palette.query, "dupl", "the palette filters as the user types")
	ok(m.command_palette.rows.size() > 0, "a command matches")
	m.command_palette.close()
	await frames()
