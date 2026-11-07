extends EdAppTestCase
## Milestones 2 and 3 in the real editor scene: the palette, drag and drop,
## the structure commands, canvas gestures, nudge and preview. Input goes
## through the window (Viewport.push_input) where the test can do so.


# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------

func test_palette_lists_every_element_and_searches() -> void:
	var m := await editor()
	eq(m.palette.element_indices().size(), EdElementCatalog.entries().size(), "every catalog element is listed")
	m._on_shell_value("palette-search", "slider")
	await frames()
	var names: Array = m.palette.element_indices().map(func(i): return m.palette.entry_at(i)["name"])
	eq(names, ["Slider", "SliderInt", "MinMaxSlider"])
	m._on_shell_value("palette-search", "")
	await frames()
	eq(m.palette.element_indices().size(), EdElementCatalog.entries().size())


func test_palette_choose_inserts_at_the_selection() -> void:
	var m := await editor()
	var before := m.state.workspace.text(MENU)
	m.state.select_node(node_named(m, "menu-title"), "test")
	await frames()
	var idx := -1
	for i in m.palette.element_indices():
		if m.palette.entry_at(i)["name"] == "Toggle":
			idx = i
	m._on_items_chosen("palette-tree", [idx])
	await frames()
	var after := m.state.workspace.text(MENU)
	eq(after, before.replace("<ui:Label name=\"menu-title\" text=\"Main Menu\" />\r\n", "<ui:Label name=\"menu-title\" text=\"Main Menu\" />\r\n    <ui:Toggle label=\"Toggle\" />\r\n"), "after the selected leaf, CRLF")
	eq(m.state.selected_node().local, "Toggle", "the new element is selected")
	ok(m.canvas.host.control_of(m.state.selected_node().id) != null, "and rendered")
	eq(m.state.workspace.history.undo_depth(), 1)
	# An editor element binds its namespace in the same step.
	m.state.select_node(node_named(m, "menu-root"), "test")
	for i in m.palette.element_indices():
		if m.palette.entry_at(i)["name"] == "ToolbarButton":
			idx = i
	m._on_items_chosen("palette-tree", [idx])
	await frames()
	ok(m.state.workspace.text(MENU).contains("<ui:UXML xmlns:ui='UnityEngine.UIElements' xmlns:uie='UnityEditor.UIElements'>"), "xmlns:uie with the root's quote style")
	eq(m.state.workspace.history.undo_depth(), 2)
	m._undo()
	m._undo()
	await frames()
	eq(m.state.workspace.text(MENU), before)


func test_drag_from_palette_to_hierarchy_and_canvas() -> void:
	var m := await editor()
	var label_idx := -1
	for i in m.palette.element_indices():
		if m.palette.entry_at(i)["name"] == "Label":
			label_idx = i
	var src_rect := await row_rect(m, "palette-tree", label_idx)
	ok(src_rect.has_area(), "the palette row is on screen")
	# Drop on the bottom quarter of the title row: after the title.
	var title := node_named(m, "menu-title")
	var dst_rect := await row_rect(m, "hierarchy-tree", tree_index(m, "hierarchy-tree", title.id))
	ok(dst_rect.has_area(), "the hierarchy row is on screen")
	await drag(m, src_rect.get_center(), Vector2(dst_rect.get_center().x, dst_rect.end.y - 2))
	var root := node_named(m, "menu-root")
	eq(root.children.map(func(c): return c.local), ["Label", "Label", "Button", "Button"], "inserted after the title")
	eq(root.children[1].get_attribute("text"), "Label")
	eq(m.state.selected_node(), root.children[1])
	# Drop on the canvas in the left padding of menu-root, level with the
	# lower half of the quit button: the end of menu-root.
	var quit := node_named(m, "quit-button")
	var qr := m.canvas.host.rect_of(quit.id)
	var rr := m.canvas.host.rect_of(node_named(m, "menu-root").id)
	var below := m.canvas.screen_to_global(Vector2(rr.position.x + 6, qr.end.y - 2))
	src_rect = await row_rect(m, "palette-tree", label_idx)
	await drag(m, src_rect.get_center(), below)
	root = node_named(m, "menu-root")
	eq(root.children.size(), 5)
	eq(root.children[4].local, "Label", "dropped after the last child along the column")
	eq(m.state.workspace.history.undo_depth(), 2, "one step per drop")
	eq(m.canvas.drop_hint, {}, "the hint clears")


func test_hierarchy_drag_reorders_and_reparents() -> void:
	var m := await editor()
	var quit := node_named(m, "quit-button")
	var play := node_named(m, "play-button")
	var qr := await row_rect(m, "hierarchy-tree", tree_index(m, "hierarchy-tree", quit.id))
	var pr := await row_rect(m, "hierarchy-tree", tree_index(m, "hierarchy-tree", play.id))
	await drag(m, qr.get_center(), Vector2(pr.get_center().x, pr.position.y + 2))
	var root := node_named(m, "menu-root")
	eq(root.children.map(func(c): return c.get_attribute("name")), ["menu-title", "quit-button", "play-button"], "dropped before play")
	ok(m.state.workspace.text(MENU).contains("<!-- keep-between-buttons -->"), "comments stay")
	eq(m.state.selected_node(), node_named(m, "quit-button"), "the moved element stays selected")
	# Drop the title into the middle of a container row: reparent into it.
	m.state.execute(EdStructureCommands.insert_new_element(m.state.session, EdLocator.create(node_named(m, "menu-root")), 3, "VisualElement", EdElementCatalog.RUNTIME, [["name", "box"]]), "test")
	await frames()
	var box := node_named(m, "box")
	var title := node_named(m, "menu-title")
	var br := await row_rect(m, "hierarchy-tree", tree_index(m, "hierarchy-tree", box.id))
	var tr := await row_rect(m, "hierarchy-tree", tree_index(m, "hierarchy-tree", title.id))
	await drag(m, tr.get_center(), br.get_center())
	box = node_named(m, "box")
	eq(box.children.map(func(c): return c.get_attribute("name")), ["menu-title"], "reparented into the box")
	eq(m.state.workspace.history.undo_depth(), 3)


# ---------------------------------------------------------------------------
# Structure commands
# ---------------------------------------------------------------------------

func test_copy_paste_cut_duplicate_wrap_unwrap() -> void:
	var m := await editor()
	var before := m.state.workspace.text(MENU)
	m.state.select_node(node_named(m, "play-button"), "test")
	ok(m.run_command("copy"), "copy")
	m.state.select_node(node_named(m, "menu-root"), "test")
	ok(m.run_command("paste"), "paste into the container")
	await frames()
	var root := node_named(m, "menu-root")
	eq(root.children[-1].get_attribute("name"), "play-button-copy", "a pasted name stays unique")
	ok(m.state.workspace.text(MENU).contains("<ui:Button name = 'play-button-copy' class='menu-button primary' text=\"Play &amp; Go\" tooltip='Press &quot;Enter&quot;' />"), "exact bytes, the name quote kept")
	m.state.select_node(node_named(m, "menu-title"), "test")
	ok(m.run_command("duplicate"))
	await frames()
	eq(node_named(m, "menu-title-copy").index_in_parent, 1)
	m.state.select_nodes([node_named(m, "menu-title"), node_named(m, "menu-title-copy")], "test")
	ok(m.run_command("wrap"))
	await frames()
	var wrapper := m.state.selected_node()
	eq(wrapper.name, "ui:VisualElement", "the wrapper is selected")
	eq(wrapper.children.map(func(c): return c.get_attribute("name")), ["menu-title", "menu-title-copy"])
	ok(m.run_command("unwrap"))
	await frames()
	eq(m.state.selected_nodes().map(func(n): return n.get_attribute("name")), ["menu-title", "menu-title-copy"], "unwrap selects the children")
	m.state.select_node(node_named(m, "menu-title-copy"), "test")
	ok(m.run_command("cut"))
	await frames()
	eq(node_named(m, "menu-title-copy"), null, "cut removes")
	m.state.select_node(node_named(m, "quit-button"), "test")
	ok(m.run_command("paste"), "paste after a leaf")
	await frames()
	eq(node_named(m, "menu-title-copy").index_in_parent, node_named(m, "quit-button").index_in_parent + 1, "pasted after the selected leaf; a cut name is free again")
	ok(m.run_command("move-up"))
	await frames()
	eq(m.state.selected_node().index_in_parent, node_named(m, "quit-button").index_in_parent - 1)
	ok(m.run_command("delete"))
	await frames()
	eq(node_named(m, "menu-title-copy"), null)
	var depth := m.state.workspace.history.undo_depth()
	eq(depth, 8, "each command is one undo step")
	for i in depth:
		m._undo()
	await frames()
	eq(m.state.workspace.text(MENU), before, "every step undoes to the exact bytes")


func test_keyboard_shortcuts_and_rename() -> void:
	var m := await editor()
	m.state.select_node(node_named(m, "menu-title"), "test")
	await frames()
	m.canvas.grab_focus()
	key(m, KEY_D, true)
	await frames()
	ok(node_named(m, "menu-title-copy") != null, "Ctrl+D duplicates")
	key(m, KEY_DELETE)
	await frames()
	eq(node_named(m, "menu-title-copy"), null, "Delete removes the selection")
	m.state.select_node(node_named(m, "menu-title"), "test")
	await frames()
	key(m, KEY_F2)
	await frames()
	var f := m.inspector.doc.get_native("element-type")
	ok(f != null and f.has_focus(), "F2 focuses the element type field")
	key(m, KEY_C, true)
	await frames()
	eq(m.state.workspace.history.undo_depth(), 2, "Ctrl+C in a text field does not run a structure command")
	m.inspector._on_value_changed("element-type", "ui:Button")
	await frames()
	var t := node_named(m, "menu-title")
	eq(t.name, "ui:Button", "renamed")
	ok(m.state.workspace.text(MENU).contains("<ui:Button name=\"menu-title\" text=\"Main Menu\" />"))
	m.inspector._on_value_changed("element-type", "x:Bad")
	await frames()
	eq(node_named(m, "menu-title").name, "ui:Button", "an unbound prefix is refused")


# ---------------------------------------------------------------------------
# Canvas gestures
# ---------------------------------------------------------------------------

func _make_absolute(m: EdMain, authored: String) -> void:
	var t = EdUssCommands.inline_target(m.state.session, EdLocator.create(node_named(m, authored)), "position")
	m.state.execute(EdUssCommands.set_inline_style(m.state.session, t, "absolute"), "test")
	await frames()


func test_resize_handle_drag_is_one_undo_step() -> void:
	var m := await editor()
	var before := m.state.workspace.text(MENU)
	var play := node_named(m, "play-button")
	m.state.select_node(play, "test")
	await frames()
	m.layout.snap_enabled = false
	var r := m.canvas.host.rect_of(play.id)
	var se := m.canvas.screen_to_global(r.end)
	var zoom := m.canvas.zoom
	await drag(m, se, se + Vector2(40, 20) * zoom, 6)
	var after := m.state.workspace.text(MENU)
	var w := int(round(r.size.x)) + 40
	var h := int(round(r.size.y)) + 20
	ok(after.contains("tooltip='Press &quot;Enter&quot;' style='width: %dpx; height: %dpx;' />" % [w, h]), "inline width and height, in the quote style of the tag: " + after)
	eq(m.state.workspace.history.undo_depth(), 1, "the whole drag is one undo step")
	var r2 := m.canvas.host.rect_of(node_named(m, "play-button").id)
	ok(absf(r2.size.x - w) < 1.5 and absf(r2.size.y - h) < 1.5, "the render follows (%s)" % r2)
	m._undo()
	await frames()
	eq(m.state.workspace.text(MENU), before, "one undo restores the bytes")


func test_move_writes_left_and_top_and_snaps() -> void:
	var m := await editor()
	await _make_absolute(m, "quit-button")
	var quit := node_named(m, "quit-button")
	m.state.select_node(quit, "test")
	await frames()
	var r := m.canvas.host.rect_of(quit.id)
	var play_r := m.canvas.host.rect_of(node_named(m, "play-button").id)
	# Drag so the left edge lands 2 px right of the play button's left edge.
	var d := Vector2(play_r.position.x + 2 - r.position.x, 30.0)
	var a := m.canvas.screen_to_global(r.get_center())
	m.layout.grid = 1
	mouse_button(m, a, true)
	await frames(1)
	mouse_move(m, a + d * m.canvas.zoom * 0.5)
	await frames(1)
	mouse_move(m, a + d * m.canvas.zoom)
	await frames(1)
	ok(m.canvas.guides.get("x", []).has(play_r.position.x), "a guide shows the snap (%s)" % m.canvas.guides)
	mouse_button(m, a + d * m.canvas.zoom, false)
	await frames()
	var q2 := m.canvas.host.rect_of(node_named(m, "quit-button").id)
	ok(absf(q2.position.x - play_r.position.x) < 0.6, "the left edge snapped to the sibling (%s vs %s)" % [q2.position.x, play_r.position.x])
	ok(m.state.workspace.text(MENU).contains("left: "), "left written")
	ok(m.state.workspace.text(MENU).contains("top: "), "top written")
	eq(m.state.workspace.history.undo_depth(), 2, "style setup + one gesture")
	eq(m.canvas.guides, {}, "guides clear after the gesture")


func test_gesture_writes_to_the_winning_rule() -> void:
	var m := await editor()
	var root := node_named(m, "menu-root")
	m.state.select_node(root, "test")
	await frames()
	m.layout.snap_enabled = false
	var r := m.canvas.host.rect_of(root.id)
	# .menu-root has no width; a resize writes inline. padding-left comes
	# from the rule; a move of a relative element writes margins inline.
	var e := m.canvas.screen_to_global(Vector2(r.end.x, r.get_center().y))
	await drag(m, e, e + Vector2(-100, 0) * m.canvas.zoom)
	ok(m.state.workspace.text(MENU).contains("class=\"menu-root\" style=\"width: %dpx;\"" % int(round(r.size.x - 100))), "width inline")
	eq(m.state.workspace.text(MENU_USS), FileAccess.get_file_as_string(_dir + "/" + MENU_USS), "the sheet is unchanged")
	# A rule winner: put left in the rule, then move.
	var uss := m.state.workspace.text(MENU_USS)
	m.state.execute(m.state.workspace.replace_text_transaction(MENU_USS, uss.replace("  padding-top: 16px;\r\n", "  padding-top: 16px;\r\n  position: absolute;\r\n  left: 10px;\r\n  top: 12px;\r\n"), "setup"), "test")
	await frames()
	var r2 := m.canvas.host.rect_of(node_named(m, "menu-root").id)
	var c := m.canvas.screen_to_global(r2.position + Vector2(30, 30))
	await drag(m, c, c + Vector2(15, 5) * m.canvas.zoom)
	var sheet := m.state.workspace.text(MENU_USS)
	ok(sheet.contains("  left: 25px;\r\n  top: 17px;\r\n"), "left and top written in their rule: " + sheet)
	ok(not m.state.workspace.text(MENU).contains("left:"), "not inline")


func test_nudge_coalesces_a_run_of_keys() -> void:
	var m := await editor()
	await _make_absolute(m, "quit-button")
	m.state.select_node(node_named(m, "quit-button"), "test")
	await frames()
	m.canvas.grab_focus()
	var depth := m.state.workspace.history.undo_depth()
	key(m, KEY_RIGHT)
	await frames(1)
	key(m, KEY_RIGHT)
	await frames(1)
	key(m, KEY_DOWN, false, true)
	await frames()
	var t := m.state.workspace.text(MENU)
	ok(t.contains("left: ") and t.contains("top: "), "nudge writes left and top")
	eq(m.state.workspace.history.undo_depth(), depth + 1, "a run of arrow keys is one step")
	var base = EdLayoutCommands.gesture_base(node_named(m, "quit-button"), m.canvas.host.style_facts(node_named(m, "quit-button").id), Rect2(), Rect2(), Vector2.ZERO)
	ok(base["left"] != null and base["top"] != null)
	m._undo()
	await frames()
	ok(not m.state.workspace.text(MENU).contains("left: "), "undo removes the whole run")


# ---------------------------------------------------------------------------
# Preview
# ---------------------------------------------------------------------------

func test_preview_sends_clicks_and_text_to_the_document() -> void:
	var m := await editor("options")
	var doc := m.canvas.host.doc
	var field := doc.get_native("profile-name") as LineEdit
	ok(field != null, "the text field renders a LineEdit")
	var fr := field.get_global_rect()
	var before := m.state.workspace.text("Assets/UI/Options.uxml")
	m.set_preview(true)
	await frames()
	ok(m.canvas.preview)
	var at := m.canvas.screen_to_global(fr.get_center())
	mouse_move(m, at, false)
	await frames(1)
	mouse_button(m, at, true)
	mouse_button(m, at, false)
	await frames()
	ok(field.has_focus(), "a click focuses the field in the document")
	eq(m.state.selection, [], "no selection in preview")
	field.select_all()
	for k in [KEY_A, KEY_B]:
		key(m, k)
	var e := InputEventKey.new()
	e.keycode = KEY_X
	e.unicode = "x".unicode_at(0)
	e.pressed = true
	m.get_viewport().push_input(e)
	await frames()
	ok(field.text.ends_with("x"), "typed text reaches the field (%s)" % field.text)
	var fs := doc.get_element_model("fullscreen")
	var tg := m.canvas.screen_to_global(doc.get_element("fullscreen").get_global_rect().get_center())
	var was := str(fs.get_attribute("value"))
	mouse_button(m, tg, true)
	mouse_button(m, tg, false)
	await frames()
	ok(str(fs.get_attribute("value")) != was, "a click toggles the toggle (%s -> %s)" % [was, fs.get_attribute("value")])
	eq(m.state.workspace.text("Assets/UI/Options.uxml"), before, "preview input does not edit the source")
	m.set_preview(false)
	await frames()
	ok(not m.canvas.preview)
	eq((m.canvas.host.doc.get_native("profile-name") as LineEdit).text, "Runner", "leaving preview renders from the source again")
