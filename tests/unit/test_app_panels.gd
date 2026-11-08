extends EdAppTestCase
## The panel layout: pane sizes per user, a wide inspector, texts that
## elide with a tooltip, a Classes section of the height of its content,
## and the write-target picker of canvas drags.

const LONG := ".menu-button, .menu-button.primary, .menu-root > .menu-button {\n  max-width: 400px;\n}\n"


func _select(m: EdMain, authored: String) -> EdUxmlNode:
	var n := node_named(m, authored)
	m.state.select_node(n, "test")
	await frames()
	m.inspector.flush()
	return n


func _append_uss(m: EdMain, text: String) -> void:
	var at := m.state.workspace.text(MENU_USS).length()
	m.state.execute(EdTransaction.make("test", "Append", MENU_USS, [{"start": at, "end": at, "replacement": text}]), "test")
	await frames()


func _center(m: EdMain, n: EdUxmlNode) -> Vector2:
	return m.canvas.screen_to_global(m.canvas.host.rect_of(n.id).get_center())


# ---------------------------------------------------------------------------
# Panes
# ---------------------------------------------------------------------------

func test_pane_sizes_are_kept_per_user() -> void:
	var saved := EdSettings.default_path
	EdSettings.default_path = "user://test-panes-%d.cfg" % Time.get_ticks_usec()
	var path := EdSettings.default_path
	var m := await editor()
	eq(m.shell.get_split_dimension("right-split"), 440.0, "a wide inspector by default")
	ok(m.shell.get_native("inspector-host") == null or m.inspector.size.x >= 400.0, "the inspector has the width: %f" % m.inspector.size.x)
	# Each pane: set, then the end of a split line drag (godot-uxml
	# split_changed), read.
	var sizes := {"main-split": 300.0, "left-split": 120.0, "hier-split": 260.0, "right-split": 500.0, "center-split": 380.0, "lower-split": 170.0, "source-split": 400.0}
	for sp in sizes:
		m.shell.set_split_dimension(sp, sizes[sp])
	m.shell.split_changed.emit("main-split", 300.0)
	await frames()
	var f := EdSettings.new(path)
	for sp in sizes:
		eq(f.get_value("layout", sp), sizes[sp], sp + " is saved")
	eq(EdMain.SPLITS.size(), sizes.size(), "every split view of the window")
	# A new window has the sizes.
	var w2: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(w2)
	await frames()
	for sp in sizes:
		eq(w2.shell.get_split_dimension(sp), sizes[sp], sp + " is restored")
	EdSettings.default_path = saved
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_drag_of_a_split_line_is_kept() -> void:
	var saved := EdSettings.default_path
	EdSettings.default_path = "user://test-panes-%d.cfg" % Time.get_ticks_usec()
	var path := EdSettings.default_path
	var m := await editor()
	await frames(3)
	# The split line of right-split is at the left edge of the inspector.
	var left: float = m.inspector.get_global_rect().position.x
	var y := 300.0
	var before: float = m.shell.get_split_dimension("right-split")
	var a := Vector2(left - 1.0, y)
	await drag(m, a, a + Vector2(-60, 0), 4)
	await frames()
	var after: float = m.shell.get_split_dimension("right-split")
	ok(absf(after - before - 60.0) < 8.0, "the line moved: %f -> %f" % [before, after])
	eq(EdSettings.new(path).get_value("layout", "right-split"), snappedf(after, 1.0), "the drag is saved")
	# A release of the mouse without a drag of a line writes nothing.
	m.shell.set_split_dimension("right-split", after + 30.0)
	mouse_button(m, Vector2(800, 12), false)
	await frames()
	eq(EdSettings.new(path).get_value("layout", "right-split"), snappedf(after, 1.0), "only split_changed saves")
	EdSettings.default_path = saved
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_broken_setting_is_ignored() -> void:
	var saved := EdSettings.default_path
	EdSettings.default_path = "user://test-panes-%d.cfg" % Time.get_ticks_usec()
	var path := EdSettings.default_path
	var s := EdSettings.new(path)
	s.set_value("layout", "right-split", "wide")
	s.set_value("layout", "main-split", -5.0)
	s.save()
	var m := await editor()
	eq(m.shell.get_split_dimension("right-split"), 440.0, "not a number: the default")
	ok(m.shell.get_split_dimension("main-split") >= 40.0, "a size is at least 40 px")
	EdSettings.default_path = saved
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_a_run_never_uses_the_settings_of_the_user() -> void:
	ok(EdSettings.default_path != "user://settings.cfg", "the runner points at a test file")


# ---------------------------------------------------------------------------
# Long texts
# ---------------------------------------------------------------------------

func test_long_texts_elide_with_a_tooltip() -> void:
	var m := await editor()
	await _append_uss(m, LONG)
	await _select(m, "quit-button")
	m.inspector.show_property("min-width")
	m.inspector.flush()
	await frames()
	var doc := m.inspector.doc
	# The inspector at the default width: the common texts fit.
	var field := "style-%d" % EdInspectorView.COMMON_STYLES.find("min-width")
	var line := doc.get_native(field) as LineEdit
	ok(line.placeholder_text.contains("← Menu.uss"), "the origin fits at the default width: " + line.placeholder_text)
	eq(line.tooltip_text, m.inspector.placeholder_of(field), "the tooltip has the whole text")
	# Narrow: every long text ends in the ellipsis, and the tooltip has it all.
	m.shell.set_split_dimension("right-split", 250.0)
	await frames(4)
	m.inspector.flush()
	await frames(2)
	ok(line.placeholder_text.ends_with("...") or line.placeholder_text.ends_with("…"), "the origin elides: " + line.placeholder_text)
	ok(m.inspector.placeholder_of(field).contains("← Menu.uss"), "the whole text stays")
	ok(line.tooltip_text.contains("← Menu.uss"), "in the tooltip")
	_check_fits(line.get_theme_font("font"), line.get_theme_font_size("font_size"), line.placeholder_text, line.size.x)
	for el_name in ["class-rules-0", "prov-0"]:
		var c := doc.get_native(el_name)
		var shown := String(c.get("text"))
		var full := EdUi.full_text(doc, el_name)
		ok(full.length() > shown.length(), "%s elides: %s" % [el_name, shown])
		ok(shown.ends_with("...") or shown.ends_with("…"), "%s: %s" % [el_name, shown])
		eq(c.tooltip_text, full, el_name + ": the tooltip is the whole text")
		_check_fits(c.get_theme_font("font"), c.get_theme_font_size("font_size"), shown, c.size.x)
	# Wide again: the whole text, and the authored tooltip is back.
	m.shell.set_split_dimension("right-split", 900.0)
	await frames(4)
	m.inspector.flush()
	await frames(2)
	ok(line.placeholder_text.contains("← Menu.uss"), "the whole text again: " + line.placeholder_text)


func _check_fits(font: Font, fs: int, text: String, width: float) -> void:
	ok(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= width + 1.0, "\"%s\" fits in %f" % [text, width])


func test_a_label_that_changes_while_narrow_elides() -> void:
	var m := await editor()
	m.shell.set_split_dimension("right-split", 240.0)
	await frames(4)
	await _select(m, "play-button")
	m.inspector.show_property("background-color")
	m.inspector.flush()
	await frames(2)
	var doc := m.inspector.doc
	var c := doc.get_native("prov-0")
	var shown := String(c.get("text"))
	ok(EdUi.full_text(doc, "prov-0").contains("Menu.uss:"), EdUi.full_text(doc, "prov-0"))
	ok(shown.ends_with("...") or shown.ends_with("…"), shown)
	m.inspector.show_property("min-width")
	m.inspector.flush()
	await frames(2)
	ok(EdUi.full_text(doc, "prov-0").contains("Menu.uss:13"), "the new text: " + EdUi.full_text(doc, "prov-0"))
	ok(String(c.get("text")) != shown, "the control shows the new text")


func test_window_labels_elide() -> void:
	var m := await editor()
	await frames()
	var long_text := "A long status text ".repeat(40)
	EdUi.set_label(m.shell, "status-label", long_text)
	await frames(2)
	var c := m.shell.get_native("status-label")
	ok(String(c.get("text")).length() < long_text.length(), "elided")
	eq(c.tooltip_text, long_text, "the tooltip")
	eq(EdUi.full_text(m.shell, "status-label"), long_text)
	EdUi.set_label(m.shell, "status-label", "Short")
	await frames(2)
	eq(String(c.get("text")), "Short")
	ok(c.tooltip_text != long_text, "the tooltip goes away")


# ---------------------------------------------------------------------------
# Classes section
# ---------------------------------------------------------------------------

## The shown height of the Classes section: down to the Attributes section,
## with the `translate` of the sections (the unused rows stay in the layout).
func _section_height(m: EdMain) -> float:
	await frames(3)
	var d := m.inspector.doc
	return d.get_element_rect(d.get_element_model("attr-section")).position.y - d.get_element_rect(d.get_element_model("class-section")).position.y


func test_the_classes_section_has_the_height_of_its_content() -> void:
	var m := await editor()
	await _select(m, "menu-title")
	var none: float = await _section_height(m)
	await _select(m, "quit-button")
	var one: float = await _section_height(m)
	await _select(m, "play-button")
	var two: float = await _section_height(m)
	ok(one > none, "one class row: %f > %f" % [one, none])
	ok(two > one, "two class rows: %f > %f" % [two, one])
	ok(absf((two - one) - (one - none)) < 1.0, "each class adds one row")
	ok(none < 60.0, "without classes only the header and the add row: %f" % none)
	# More classes than the skeleton has.
	var n := node_named(m, "quit-button")
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(n), "class", "menu-button a b c d e"), "test")
	await frames()
	await _select(m, "quit-button")
	var six: float = await _section_height(m)
	ok(absf(six - (none + 6 * (one - none))) < 1.5, "six rows: %f" % six)
	ok(String(m.inspector.doc.get_native("class-name-5").get("text")) == ".e", "the last class")
	# The add row follows the last row in use, and a row that is not in use
	# takes no input.
	await _select(m, "menu-title")
	await frames(3)
	var d := m.inspector.doc
	var add := d.get_element_rect(d.get_element_model("class-add-row"))
	var top := d.get_element_rect(d.get_element_model("class-section"))
	ok(add.position.y - top.position.y < 40.0, "the add row moves up: %f" % (add.position.y - top.position.y))
	ok(not d.get_element("block-class-0").is_visible_in_tree(), "the unused rows are invisible")
	var line := d.get_native("new-class") as LineEdit
	var at := line.get_global_rect().get_center()
	var hit := d.element_at(d.get_global_transform().affine_inverse() * at)
	ok(hit != null and hit.get_attribute("name") != "block-class-0", "the moved row gets the mouse")
	# A closed section moves nothing.
	var lay: int = d.layout_count
	await _select(m, "quit-button")
	await frames(3)
	eq(d.layout_count, lay, "a change of the number of classes needs no layout")


func test_a_closed_section_does_not_move_what_follows() -> void:
	var m := await editor()
	await _select(m, "menu-title")
	await frames(3)
	var d := m.inspector.doc
	var open_at := d.get_element_rect(d.get_element_model("attr-section")).position.y
	# A click on the header of the section.
	var head := d.get_element_rect(d.get_element_model("class-section")).position + Vector2(12, 9)
	var at := d.get_global_transform() * head
	mouse_button(m, at, true)
	mouse_button(m, at, false)
	await frames(3)
	eq(str(d.get_element_model("class-section").get_attribute("value")), "false", "the section closed")
	var closed_at := d.get_element_rect(d.get_element_model("attr-section")).position.y
	ok(closed_at <= open_at + 1.0, "closed: %f, open: %f" % [closed_at, open_at])
	eq(String(d.get_element_model("below-classes").get_attribute("style")), "", "no shift")


# ---------------------------------------------------------------------------
# The write-target picker of canvas drags
# ---------------------------------------------------------------------------

func test_a_canvas_drag_asks_for_the_target_and_remembers() -> void:
	var m := await editor()
	var n := await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU)
	var uss := m.state.workspace.text(MENU_USS)
	var c := _center(m, n)
	await drag(m, c, c + Vector2(40, 0), 4)
	await frames()
	ok(not m.inspector.pending.is_empty(), "more than one target: the picker asks")
	var labels: Array = m.inspector.pending_labels()
	ok(labels.has("Inline style"), str(labels))
	ok(labels.any(func(l): return String(l).begins_with("New rule #quit-button")), str(labels))
	ok(m.state.workspace.text(MENU) != src, "the drag shows on the canvas with the default target")
	eq(m.state.workspace.history.undo_depth(), 1, "one undo step")
	# The default is the target of the drag: no second write.
	ok(m.inspector.choose_id("inline"))
	await frames()
	eq(m.state.workspace.history.undo_depth(), 1)
	n = node_named(m, "quit-button")
	ok(String(n.get_attribute("style")).contains("margin-left"), str(n.get_attribute("style")))
	eq(m.state.workspace.text(MENU_USS), uss, "no stylesheet edit")
	# The next drag of this selection does not ask.
	eq(m.inspector.remembered_choice("margin-left"), "inline", "the same memory as the fields")
	c = _center(m, n)
	await drag(m, c, c + Vector2(20, 0), 3)
	await frames()
	ok(m.inspector.pending.is_empty(), "no question")
	eq(m.state.workspace.history.undo_depth(), 2)


func test_a_new_rule_chosen_after_a_drag_gets_the_end_of_the_drag() -> void:
	var m := await editor()
	var n := await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU)
	var c := _center(m, n)
	await drag(m, c, c + Vector2(40, 8), 4)
	await frames()
	ok(m.inspector.choose_id("new:%s:#quit-button" % MENU_USS), str(m.inspector.pending_labels()))
	await frames()
	eq(m.state.workspace.text(MENU), src, "the inline write is gone")
	var uss := m.state.workspace.text(MENU_USS)
	eq(uss.count("#quit-button"), 1, "one rule: " + uss)
	ok(uss.contains("margin-left") and uss.contains("margin-top"), uss)
	eq(m.state.workspace.history.undo_depth(), 1, "one undo step")
	# The memory names the rule: the next drag writes to it, without a question.
	n = node_named(m, "quit-button")
	c = _center(m, n)
	await drag(m, c, c + Vector2(16, 0), 3)
	await frames()
	ok(m.inspector.pending.is_empty(), "no question")
	uss = m.state.workspace.text(MENU_USS)
	eq(uss.count("#quit-button"), 1, "still one rule: " + uss)
	eq(m.state.workspace.history.undo_depth(), 2)
	m.state.undo()
	await frames()
	m.state.undo()
	await frames()
	eq(m.state.workspace.text(MENU), src)
	ok(not m.state.workspace.text(MENU_USS).contains("#quit-button"), "undo removes the rule")


func test_the_picker_is_a_context_menu_of_the_inspector() -> void:
	var m := await editor()
	var n := await _select(m, "quit-button")
	var c := _center(m, n)
	await drag(m, c, c + Vector2(40, 0), 3)
	await frames()
	var menu := m.inspector.doc.get_context_menu()
	ok(menu != null, "show_context_menu of the inspector document")
	eq(menu, m.inspector.picker)
	eq(menu.document().editor_theme, "always", "the look of the inspector")
	ok(menu.document().get_element("item-%d" % m.inspector.pending_labels().size()) == null, "a separator before Cancel")
	# A close without a choice cancels, as a click outside the menu.
	var src := m.state.workspace.text(MENU)
	ok(src != "")
	m.inspector.doc.close_context_menu()
	await frames(3)
	ok(m.inspector.pending.is_empty(), "the question ended")
	eq(m.state.workspace.history.undo_depth(), 0, "the drag is undone")
	# A field helper menu too.
	m.state.select_node(null, "test")
	n = await _select(m, "quit-button")
	var i := EdInspectorView.COMMON_STYLES.find("display")
	m.inspector._on_button("pick-style-%d" % i)
	await frames()
	ok(m.inspector.doc.get_context_menu() != null, "a keyword menu")
	m.inspector.doc.close_context_menu()
	await frames()


func test_cancel_undoes_the_drag() -> void:
	var m := await editor()
	var n := await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU)
	var c := _center(m, n)
	await drag(m, c, c + Vector2(40, 0), 3)
	await frames()
	ok(not m.inspector.choose(99), "Cancel")
	await frames()
	eq(m.state.workspace.text(MENU), src, "the drag is undone")
	eq(m.state.workspace.history.undo_depth(), 0)


func test_a_choice_of_the_inspector_applies_to_the_drag() -> void:
	var m := await editor()
	var n := await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU)
	var i := EdInspectorView.COMMON_STYLES.find("margin-left")
	if i < 0:
		m.inspector.remember_choice("margin-left", "new:%s:.menu-button" % MENU_USS)
	else:
		m.inspector.write_style("margin-left", "3px", m.inspector.doc.get_native("style-%d" % i))
		ok(m.inspector.choose_id("new:%s:.menu-button" % MENU_USS), str(m.inspector.pending_labels()))
		await frames()
	m.inspector.remember_choice("margin-top", "new:%s:.menu-button" % MENU_USS)
	var depth := m.state.workspace.history.undo_depth()
	n = node_named(m, "quit-button")
	var c := _center(m, n)
	await drag(m, c, c + Vector2(30, 0), 3)
	await frames()
	ok(m.inspector.pending.is_empty(), "no question")
	eq(m.state.workspace.text(MENU), src, "no inline style")
	ok(m.state.workspace.text(MENU_USS).contains("margin-left"), m.state.workspace.text(MENU_USS))
	eq(m.state.workspace.history.undo_depth(), depth + 1)


func test_one_valid_target_needs_no_question() -> void:
	# A nameless, classless element with a rule target only by inline.
	var m := await editor()
	var n := await _select(m, "menu-title")
	m.state.execute(EdUxmlCommands.remove_attribute(m.state.session, EdLocator.create(n), "name"), "test")
	await frames()
	var t: EdUxmlNode = null
	for x in m.state.session.root().walk():
		if x.local == "Label":
			t = x
	m.state.select_node(t, "test")
	await frames()
	m.inspector.flush()
	eq(m.inspector.choices_for("margin-left").size(), 1, "inline only")
	var c := _center(m, t)
	await drag(m, c, c + Vector2(24, 0), 3)
	await frames()
	ok(m.inspector.pending.is_empty(), "no question")
	ok(m.state.workspace.text(MENU).contains("margin-left"), m.state.workspace.text(MENU))


func test_a_new_rule_of_a_state_is_one_rule_for_a_whole_drag() -> void:
	var m := await editor()
	var n := await _select(m, "quit-button")
	m.inspector.set_state("hover", true)
	await frames()
	m.inspector.flush()
	m.timeline.stop()
	await frames()
	var c := _center(m, n)
	await drag(m, c, c + Vector2(40, 0), 6)
	await frames()
	var uss := m.state.workspace.text(MENU_USS)
	eq(uss.count(":hover"), 1, "one rule over all steps: " + uss)
	eq(m.state.workspace.history.undo_depth(), 1, "one undo step")


func test_a_selection_outside_the_hierarchy_view_scrolls_once_without_a_layout() -> void:
	var dir := copy_fixture("menu")
	var u := PackedStringArray(["<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">"])
	for i in 80:
		u.append("  <ui:Label name=\"l%d\" text=\"%d\" />" % [i, i])
	u.append("</ui:UXML>")
	var f := FileAccess.open(dir + "/Assets/UI/Long.uxml", FileAccess.WRITE)
	f.store_string("
".join(u) + "
")
	f.close()
	tree.root.size = Vector2i(1600, 1000)
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(m)
	await frames()
	m.state.open_project(dir)
	m.state.open_document("Assets/UI/Long.uxml")
	await frames(8)
	# The first selections lay out the window once (the inspector and the
	# status show a selection); the rows are in view, so no scroll.
	for i in [1, 2, 3]:
		m.state.select_node(node_named(m, "l%d" % i), "canvas")
		await frames(2)
	# A selection outside the view scrolls after a frame without another
	# selection. godot-uxml lays out only the rows (R29): the window layout
	# count stays, the row layout count rises.
	var layouts: int = m.shell.layout_count
	var rows0: int = m.shell.local_layout_count
	for i in [70, 75, 79, 10, 60]:
		m.state.select_node(node_named(m, "l%d" % i), "canvas")
		await frames(4)
		var row := tree_index(m, "hierarchy-tree", node_named(m, "l%d" % i).id)
		ok(m._row_in_view("hierarchy-tree", row), "l%d is in view: row %d, %s in %s" % [i, row, m.shell.get_item_rect("hierarchy-tree", row), m.shell.get_element("hierarchy-tree").get_global_rect()])
	eq(m.shell.layout_count, layouts, "the scrolls lay out no window")
	ok(m.shell.local_layout_count > rows0, "the rows are laid out alone: %d -> %d" % [rows0, m.shell.local_layout_count])
	# A run of selections, one per frame: one scroll at the end of the run.
	for i in [20, 25, 30]:
		m.state.select_node(node_named(m, "l%d" % i), "canvas")
		await tree.process_frame
		eq(m._scroll_row >= 0, true, "l%d: the scroll waits" % i)
	await frames(4)
	eq(m._scroll_row, -1, "scrolled")
	ok(m._row_in_view("hierarchy-tree", tree_index(m, "hierarchy-tree", node_named(m, "l30").id)), "the last selection is in view")
	# A selection inside the view does not scroll.
	var offset := m.shell.get_scroll_offset("hierarchy-tree")
	var rows1: int = m.shell.local_layout_count
	m.state.select_node(node_named(m, "l31"), "canvas")
	await frames()
	eq(m.shell.get_scroll_offset("hierarchy-tree"), offset, "a row in view: no scroll")
	eq(m.shell.layout_count, layouts, "and no layout")
	ok(m.shell.local_layout_count - rows1 <= 2, "at most the rows of the old and the new selection")


func test_the_toolbar_shows_the_project_folder_name() -> void:
	var m := await editor()
	eq(EdUi.full_text(m.shell, "document-label"), m.state.store.root.get_file(), "the folder name, not the path")
	ok(not EdUi.full_text(m.shell, "document-label").contains("/"), "no path")
	eq(m.shell.get_native("document-label").tooltip_text, m.state.store.root, "the tooltip has the path")
	eq(EdMain.project_label("C:/work/game/"), "game")
	eq(EdMain.project_label("C:\\work\\game"), "game")
	eq(EdMain.project_label("/"), "")


func test_a_small_window_keeps_room_for_the_source_view() -> void:
	var saved := EdSettings.default_path
	EdSettings.default_path = "user://test-panes-%d.cfg" % Time.get_ticks_usec()
	var path := EdSettings.default_path
	var m := await editor()
	# The size of the editor embedded in the project site.
	tree.root.size = Vector2i(1240, 698)
	await frames(4)
	var w := 1240.0
	var center := w - m.shell.get_split_dimension("main-split") - m.shell.get_split_dimension("right-split")
	ok(center >= w * 0.5 - 1.0, "the center column has half of the width: %f" % center)
	var source := center - m.shell.get_split_dimension("source-split")
	ok(source >= 339.0, "the source view has room: %f" % source)
	ok(m.shell.get_split_dimension("center-split") <= 349.0, "the canvas keeps half of the height")
	ok(m.source.size.x >= 300.0, "the source control is wide: %f" % m.source.size.x)
	# A save keeps the wanted sizes, not the sizes of the small window.
	m.save_splits()
	eq(EdSettings.new(path).get_value("layout", "right-split"), 440.0, "the wanted inspector width is saved")
	eq(EdSettings.new(path).get_value("layout", "source-split"), 440.0)
	# A large window again: the wanted sizes.
	tree.root.size = Vector2i(1600, 1000)
	await frames(4)
	eq(m.shell.get_split_dimension("right-split"), 440.0, "the inspector is wide again")
	eq(m.shell.get_split_dimension("source-split"), 440.0)
	EdSettings.default_path = saved
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_forcing_states_lays_out_no_inspector() -> void:
	# A row of the declaration list changes its status class, and the winner
	# row is bold. The row has a fixed size, so godot-uxml lays out only the
	# row for the font change (R31), not the whole inspector.
	var m := await editor()
	m.state.select_node(node_named(m, "play-button"), "canvas")
	m.states.set_open(true)
	await frames(6)
	m.states.select_node("hover")
	await frames(3)
	var d := m.inspector.doc
	var lay: int = d.layout_count
	var bold := 0
	for id in ["active", "focus", "checked", "disabled", "normal", "hover"]:
		m.states.select_node(id)
		await frames(2)
		for i in EdInspectorView.PROV_ROWS:
			var el := d.get_element_model("prov-%d" % i)
			if el != null and str(el.get_attribute("class")).split(" ").has("status-winner"):
				var fs = d.get_computed_style("prov-%d" % i).get("-unity-font-style", {})
				eq(str(fs.get("value", "") if fs is Dictionary else fs), "bold", "the winner row is bold")
				bold += 1
	eq(d.layout_count, lay, "no layout of the inspector for six forced states")
	ok(bold > 0, "a winner row in the declaration list (%d)" % bold)
	m.states.clear()
	m.states.set_open(false)
	await frames()
