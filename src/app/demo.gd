class_name EdDemo
extends RefCounted
## Staged editor states for the documentation screenshots
## (`--demo=<name> --screenshot=<png>`). Each stage uses the same calls as
## the user input paths: the palette, the drag controller, the layout
## controller and preview mode.
##
##   palette         the library filtered by a search, an element inserted
##   drag-canvas     a palette element dragged over the canvas (drop hint)
##   drag-hierarchy  a hierarchy row dragged over another row (drop line)
##   resize          a resize gesture with a snap guide, mid-drag
##   multi           two elements selected, the Edit menu commands
##   preview         preview mode with a focused text field
##   diagnostics     a diagnostic chosen in the list: the range in the
##                   source view, the element in the canvas and hierarchy
##   tabs            two documents in tabs, one with unsaved edits
##   recovery        the recovery question after an unsaved session
##   conflict        the question for a file changed on disk and in the
##                   editor
##   context-menu    the hierarchy context menu
##   provenance      the declarations of background-color: the winning
##                   rule, the theme value it overrides, the source range
##   picker          the write-target picker of a min-width edit
##   states          the :hover state forced on a button, its rule wins
##   classes         the class editor with the rules of each class
##   timeline        a :hover toggle played on the canvas, paused in the
##                   middle; the easing curve in the inspector
##   timeline-classes  a run from one class to another, document scope
##   easing          the easing picker of the timing function
##   canvas-picker   the write-target picker at the end of a canvas drag
##   narrow          a narrow inspector: long texts elide
##   states-node     the state-machine panel: the hover state forced, its
##                   rules in the declaration list
##   states-edge     the state-machine panel: normal to hover plays on the
##                   timeline, paused in the middle
## The stages tabs, recovery, conflict and the timeline stages work on a
## copy of the menu fixture in user://demo-* (they write files).


static func stage(m: EdMain, demo: String) -> void:
	var tree := m.get_tree()
	match demo:
		"palette":
			_select(m, "menu-root")
			_set_search(m, "button")
			await _frames(tree, 4)
			for i in m.palette.element_indices():
				if m.palette.entry_at(i)["name"] == "RepeatButton":
					m.insert_entry(m.palette.entry_at(i))
					m.shell.set_selection("palette-tree", [i])
		"drag-canvas":
			await _frames(tree, 2)
			var title := _node(m, "menu-title")
			var r := m.canvas.host.rect_of(title.id)
			var root_r := m.canvas.host.rect_of(_node(m, "menu-root").id)
			var from := await _row_center(m, "palette-tree", _palette_index(m, "Toggle"))
			await _drag_to(m, from, m.canvas.screen_to_global(Vector2(root_r.position.x + 300, r.end.y + 4)))
		"drag-hierarchy":
			await _frames(tree, 2)
			var quit := _node(m, "quit-button")
			_select(m, "quit-button")
			await _frames(tree, 2)
			var play := _node(m, "play-button")
			var from := await _row_center(m, "hierarchy-tree", _tree_index(m, quit.id))
			var to_r := m.shell.get_item_rect("hierarchy-tree", _tree_index(m, play.id))
			await _drag_to(m, from, Vector2(to_r.get_center().x, to_r.position.y + 2))
		"resize":
			_select(m, "play-button")
			await _frames(tree, 3)
			var play := _node(m, "play-button")
			var r := m.canvas.host.rect_of(play.id)
			var quit_r := m.canvas.host.rect_of(_node(m, "quit-button").id)
			m.layout.begin("se")
			# Width to 60 % and the bottom edge 3 px short of the quit
			# button's top edge: the snap pulls it there and draws a guide.
			m.layout.update("se", Vector2(r.size.x * -0.4, quit_r.position.y - r.end.y - 3), false, false)
			await _frames(tree, 4)
		"multi":
			m.state.select_nodes([_node(m, "play-button"), _node(m, "quit-button")], "demo")
			await _frames(tree, 2)
			m.run_command("duplicate")
		"preview":
			await _frames(tree, 2)
			m.set_preview(true)
			await _frames(tree, 2)
			var field := m.canvas.host.doc.get_native("profile-name") as LineEdit
			if field != null:
				field.grab_focus()
				field.text = "Runner 2"
				field.caret_column = field.text.length()
		"diagnostics":
			await _frames(tree, 4)
			for i in m._diagnostics.size():
				var e: Dictionary = m._diagnostics[i]
				if e["file"].ends_with(".uxml") and e["start"] >= 0:
					var n := m.state.session.tree().element_at_offset(e["start"])
					if n != null and n.parent != null:
						m.shell.set_selection("diagnostics-list", [i])
						break
		"tabs":
			var dir := _copy_menu("demo-tabs")
			var f := FileAccess.open(dir + "/Assets/UI/Settings.uxml", FileAccess.WRITE)
			f.store_string(SETTINGS)
			f.close()
			m.state.open_project(dir)
			m.state.open_document("Assets/UI/Settings.uxml")
			m.state.open_document("Assets/UI/Menu.uxml")
			await _frames(tree, 3)
			m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(_node(m, "play-button")), "text", "Play"), "demo")
			_select(m, "play-button")
		"recovery":
			var dir := _copy_menu("demo-recovery")
			var rdir := ProjectSettings.globalize_path("user://demo-recovery-journal")
			var a := EdEditorState.new()
			a.recovery_base = rdir
			a.open_project(dir)
			a.open_document("Assets/UI/Menu.uxml")
			for n in a.session.root().walk():
				if n.get_attribute("name") == "play-button":
					a.execute(EdUxmlCommands.set_attribute(a.session, EdLocator.create(n), "text", "Unsaved edit"), "demo")
			a.journal.close()
			m.state.recovery_base = rdir
			m.state.open_project(dir)
		"conflict":
			var dir := _copy_menu("demo-conflict")
			m.state.open_project(dir)
			m.state.open_document("Assets/UI/Menu.uxml")
			await _frames(tree, 3)
			m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(_node(m, "play-button")), "text", "Mine"), "demo")
			var path := dir + "/Assets/UI/Menu.uxml"
			var text := FileAccess.get_file_as_string(path).replace("Main Menu", "Changed by another program")
			var f := FileAccess.open(path, FileAccess.WRITE)
			f.store_string(text)
			f.close()
			m.state.check_external_changes()
		"context-menu":
			await _frames(tree, 3)
			var quit := _node(m, "quit-button")
			var at: Vector2 = await _row_center(m, "hierarchy-tree", _tree_index(m, quit.id))
			m.state.select_node(quit, "demo")
			m.shell.show_context_menu(at, m._context_items({"position": at}))
		"provenance":
			_select(m, "play-button")
			await _frames(tree, 3)
			m.inspector.show_property("background-color")
			m.inspector.flush()
			m.inspector.open_provenance(0)
			await _frames(tree, 2)
			m.inspector.doc.scroll_to("scroll", "prov-section")
		"picker":
			_select(m, "play-button")
			await _frames(tree, 3)
			m.inspector.flush()
			var i := EdInspectorView.COMMON_STYLES.find("min-width")
			m.inspector.doc.scroll_to("scroll", "row-style-%d" % i)
			await _frames(tree, 3)
			m.inspector.show_property("min-width")
			m.inspector.flush()
			m.inspector.write_style("min-width", "200px", m.inspector.doc.get_native("style-%d" % i))
		"states":
			var t = EdUssCommands.new_rule_target(m.state.workspace, "Assets/UI/Menu.uss", ".menu-button:hover", "background-color")
			m.state.execute(EdUssCommands.insert_rule(m.state.workspace, t, "#c0392b"), "demo")
			await _frames(tree, 3)
			_select(m, "quit-button")
			await _frames(tree, 3)
			m.inspector.flush()
			m.inspector.set_state("hover", true)
			m.inspector.show_property("background-color")
			await _frames(tree, 3)
			m.inspector.flush()
			m.inspector.doc.scroll_to("scroll", "prov-section")
		"classes":
			_select(m, "play-button")
			await _frames(tree, 3)
			m.inspector.flush()
		"timeline":
			_open_transitions(m, "demo-timeline")
			await _frames(tree, 3)
			_select(m, "quit-button")
			await _frames(tree, 3)
			m.inspector.flush()
			m.inspector.set_state("hover", true)
			m.timeline.seek_to(0.6)
			m.inspector.show_property("transition-timing-function")
			await _frames(tree, 3)
			m.inspector.flush()
			m.inspector.doc.scroll_to("scroll", "easing-row")
		"timeline-classes":
			_open_transitions(m, "demo-timeline")
			await _frames(tree, 3)
			_select(m, "quit-button")
			await _frames(tree, 3)
			m.timeline.set_scope("document")
			m.timeline.set_state_text("from", ".menu-button")
			m.timeline.set_state_text("to", ".menu-button.alt")
			m.timeline.seek_to(0.3)
		"easing":
			_open_transitions(m, "demo-timeline")
			await _frames(tree, 3)
			_select(m, "quit-button")
			await _frames(tree, 3)
			m.inspector.flush()
			m.inspector.doc.scroll_to("scroll", "easing-row")
			await _frames(tree, 3)
			m.inspector.open_easing_picker("transition-timing-function", m.inspector.doc.get_element("easing-curve"))
		"canvas-picker":
			_select(m, "quit-button")
			await _frames(tree, 3)
			m.inspector.flush()
			m.layout.begin("move")
			m.layout.update("move", Vector2(40, 12), false, true)
			await _frames(tree, 3)
			m.layout.finish(false)
		"states-node":
			_open_transitions(m, "demo-states")
			await _frames(tree, 3)
			_select(m, "quit-button")
			m.states.set_open(true)
			await _frames(tree, 4)
			m.states.select_node("hover")
			# The transitions of the state end.
			await tree.create_timer(1.6).timeout
		"states-edge":
			_open_transitions(m, "demo-states")
			await _frames(tree, 3)
			_select(m, "quit-button")
			m.states.set_open(true)
			await _frames(tree, 4)
			m.states.select_edge("normal>hover")
			m.timeline.seek_to(0.6)
			await _frames(tree, 3)
		"narrow":
			m.shell.set_split_dimension("right-split", 300.0)
			var long_rule := ".menu-button, .menu-button.primary, .menu-root > .menu-button {\n  max-width: 400px;\n}\n"
			var path := "Assets/UI/Menu.uss"
			var ws := m.state.workspace
			var end := ws.text(path).length()
			m.state.execute(EdTransaction.make("demo", "A long rule", path, [{"start": end, "end": end, "replacement": long_rule}]), "demo")
			await _frames(tree, 3)
			_select(m, "quit-button")
			await _frames(tree, 3)
			m.inspector.show_property("min-width")
			await _frames(tree, 3)
			m.inspector.flush()
	await _frames(tree, 6)


## A rule of the demos and the benchmark: transitions, a state rule and
## another class.
const TRANSITIONS := """
.menu-button {
  transition-property: background-color, min-width, opacity;
  transition-duration: 0.5s, 1s, 0.3s;
  transition-delay: 0s, 0.2s, 0.4s;
  transition-timing-function: ease-in-out, ease-out-bounce, linear;
}
.menu-button:hover {
  background-color: #c0392b;
  min-width: 320px;
  opacity: 0.6;
}
.alt {
  background-color: #2471a3;
  min-width: 260px;
}
"""


## Open a copy of the menu fixture with the rules of TRANSITIONS.
static func _open_transitions(m: EdMain, name: String) -> void:
	var dir := _copy_menu(name)
	var path := dir + "/Assets/UI/Menu.uss"
	var text := FileAccess.get_file_as_string(path) + TRANSITIONS
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	m.state.open_project(dir)
	m.state.open_document("Assets/UI/Menu.uxml")


const SETTINGS := """<ui:UXML xmlns:ui="UnityEngine.UIElements">
    <ui:VisualElement name="settings" style="padding: 12px;">
        <ui:Label name="settings-title" text="Settings" style="font-size: 20px;" />
        <ui:Toggle name="vsync" label="V-Sync" value="true" />
        <ui:Slider name="volume" label="Volume" low-value="0" high-value="1" value="0.8" />
    </ui:VisualElement>
</ui:UXML>
"""


## A fresh copy of the menu fixture in user://<name>.
static func _copy_menu(name: String) -> String:
	var dir := ProjectSettings.globalize_path("user://" + name)
	_copy(ProjectSettings.globalize_path("res://fixtures/projects/menu"), dir)
	var rdir := ProjectSettings.globalize_path("user://demo-recovery-journal")
	if name != "demo-recovery" or not DirAccess.dir_exists_absolute(rdir):
		return dir
	for d in DirAccess.get_directories_at(rdir):
		for f in DirAccess.get_files_at(rdir + "/" + d):
			DirAccess.remove_absolute(rdir + "/" + d + "/" + f)
	return dir


static func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from + "/" + f, to + "/" + f)
	for d in DirAccess.get_directories_at(from):
		_copy(from + "/" + d, to + "/" + d)


## Press at `from` and move to `to` with the button held (no release):
## the drag of godot-uxml (request R12) stays open for the screenshot.
static func _drag_to(m: EdMain, from: Vector2, to: Vector2) -> void:
	var tree := m.get_tree()
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = from
	e.global_position = from
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	m.get_viewport().push_input(e)
	await _frames(tree, 1)
	for i in range(1, 7):
		var mm := InputEventMouseMotion.new()
		mm.position = from.lerp(to, i / 6.0)
		mm.global_position = mm.position
		mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.get_viewport().push_input(mm)
		await _frames(tree, 1)


static func _palette_index(m: EdMain, element: String) -> int:
	for i in m.palette.element_indices():
		if m.palette.entry_at(i)["name"] == element:
			return i
	return -1


static func _tree_index(m: EdMain, id: int) -> int:
	for i in 200:
		var it := m.shell.get_tree_item("hierarchy-tree", i)
		if it.is_empty():
			return -1
		if int(it["id"]) == id:
			return i
	return -1


static func _row_center(m: EdMain, list: String, index: int) -> Vector2:
	m.shell.scroll_to_item(list, index)
	await _frames(m.get_tree(), 2)
	return m.shell.get_item_rect(list, index).get_center()


static func _frames(tree: SceneTree, n: int) -> void:
	for i in n:
		await tree.process_frame


static func _node(m: EdMain, authored: String) -> EdUxmlNode:
	if m.state.session == null:
		return null
	for n in m.state.session.root().walk():
		if n.get_attribute("name") == authored:
			return n
	return null


static func _select(m: EdMain, authored: String) -> void:
	m.state.select_node(_node(m, authored), "demo")


static func _set_search(m: EdMain, text: String) -> void:
	var el := m.shell.get_element_model("palette-search")
	if el != null:
		el.set_attribute("value", text)
	m.palette.set_query(text)
