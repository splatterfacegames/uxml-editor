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
			var e := EdElementCatalog.find("Toggle")
			m.drag.begin({"kind": "palette", "entry": e, "label": "+ Toggle"})
			var title := _node(m, "menu-title")
			var r := m.canvas.host.rect_of(title.id)
			var root_r := m.canvas.host.rect_of(_node(m, "menu-root").id)
			m.drag._update_target(m.canvas.screen_to_global(Vector2(root_r.position.x + 300, r.end.y + 4)))
		"drag-hierarchy":
			await _frames(tree, 2)
			var quit := _node(m, "quit-button")
			_select(m, "quit-button")
			await _frames(tree, 2)
			var play := _node(m, "play-button")
			m.drag.begin({"kind": "nodes", "locs": [EdLocator.create(quit)], "label": "Move Button"})
			var idx := -1
			for i in 50:
				var it := m.shell.get_tree_item("hierarchy-tree", i)
				if not it.is_empty() and int(it["id"]) == play.id:
					idx = i
			for row in m.shell.get_list_rows("hierarchy-tree"):
				if row.index == idx:
					var rr: Rect2 = row.get_element().get_global_rect()
					m.drag._update_target(Vector2(rr.get_center().x, rr.position.y + 3))
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
	await _frames(tree, 6)


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
