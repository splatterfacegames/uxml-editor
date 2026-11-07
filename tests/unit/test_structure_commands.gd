extends EdTestCase
## Milestone 2 structure commands: palette insertion, unwrap, remove and
## move of several elements, the clipboard, and the step composer.

const DOC := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n" \
	+ "  <ui:VisualElement name=\"panel\">\r\n" \
	+ "    <ui:Label name=\"title\" text='Hi &amp; bye' />\r\n" \
	+ "    <!-- keep -->\r\n" \
	+ "    <ui:Button name=\"go\" text=\"Go\" />\r\n" \
	+ "  </ui:VisualElement>\r\n" \
	+ "</ui:UXML>\r\n"


# ---------------------------------------------------------------------------
# Catalog
# ---------------------------------------------------------------------------

func test_catalog_matches_the_tags_godot_uxml_knows() -> void:
	var known: Dictionary = UssControls.IMPLICIT_CLASSES
	for e in EdElementCatalog.entries():
		ok(known.has(e["name"]), "godot-uxml knows palette element %s" % e["name"])
	for tag in known:
		ok(not EdElementCatalog.find(tag).is_empty() or EdElementCatalog.NOT_IN_PALETTE.has(tag),
			"godot-uxml tag %s is in the palette or listed as not authored" % tag)
	eq(EdElementCatalog.find("ColorField")["uri"], EdElementCatalog.EDITOR)
	eq(EdElementCatalog.find("Button")["uri"], EdElementCatalog.RUNTIME)
	var groups := {}
	for e in EdElementCatalog.entries():
		groups[e["group"]] = true
	eq(groups.keys().size(), EdElementCatalog.GROUPS.size(), "every group has elements")


func test_catalog_search() -> void:
	var names := EdElementCatalog.search("toolbar but").map(func(e): return e["name"])
	eq(names, ["ToolbarButton"])
	ok(EdElementCatalog.search("FIELD").size() > 20, "case-insensitive")
	ok(EdElementCatalog.search("editor").all(func(e): return e["uri"] == EdElementCatalog.EDITOR))
	eq(EdElementCatalog.search("").size(), EdElementCatalog.entries().size())


func test_every_palette_element_renders_without_unsupported_control() -> void:
	var body := ""
	for e in EdElementCatalog.entries():
		var pfx := "ui" if e["uri"] == EdElementCatalog.RUNTIME else "uie"
		body += "<%s:%s />" % [pfx, e["name"]]
	var src := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:uie=\"UnityEditor.UIElements\">%s</ui:UXML>" % body
	var doc := UxmlDocument.new()
	doc.auto_load = false
	add_node(doc)
	doc.load_source(src)
	var bad: Array = []
	for d in doc.diagnostics:
		if d.get("kind") == "unsupported-control" or d.get("kind") == "malformed":
			bad.append(UxmlDiagnostic.format(d))
	eq(bad, [], "every palette element renders")


# ---------------------------------------------------------------------------
# Insert from the palette
# ---------------------------------------------------------------------------

func test_insertion_point_follows_the_selection() -> void:
	var s := open_session(DOC)
	var panel := s.resolve(with_name(s, "panel"))
	var title := s.resolve(with_name(s, "title"))
	var ip := EdStructureCommands.insertion_point(s, panel)
	eq([ip["parent"], ip["index"]], [panel, 2], "a container gets a last child")
	ip = EdStructureCommands.insertion_point(s, title)
	eq([ip["parent"], ip["index"]], [panel, 1], "a leaf gets a next sibling")
	ip = EdStructureCommands.insertion_point(s, null)
	eq([ip["parent"], ip["index"]], [s.root(), 1], "no selection: end of the root")


func test_insert_new_element_uses_the_bound_prefix() -> void:
	var s := open_session(DOC)
	var tx = EdStructureCommands.insert_new_element(s, with_name(s, "panel"), 2, "Toggle", EdElementCatalog.RUNTIME, [["label", "On & off"]])
	if not is_tx(tx):
		return
	eq(tx.label, "Insert Toggle")
	run(s, tx)
	eq(text(s), DOC.replace("<ui:Button name=\"go\" text=\"Go\" />", "<ui:Button name=\"go\" text=\"Go\" />\r\n    <ui:Toggle label=\"On &amp; off\" />"))
	eq(s.resolve(tx.selection_after[0]).local, "Toggle", "the new element is selected")


func test_insert_new_element_declares_a_missing_namespace_on_the_root() -> void:
	var s := open_session(DOC)
	var tx = EdStructureCommands.insert_new_element(s, with_name(s, "panel"), 0, "ColorField", EdElementCatalog.EDITOR)
	if not is_tx(tx):
		return
	eq(tx.patches(ENTRY).size(), 2, "one transaction, two patches")
	run(s, tx)
	var t := text(s)
	ok(t.begins_with("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:uie=\"UnityEditor.UIElements\">\r\n"), "xmlns:uie added to the root")
	ok(t.contains("<ui:VisualElement name=\"panel\">\r\n    <uie:ColorField />\r\n    <ui:Label"), "element inserted with the new prefix")
	eq(s.resolve(tx.selection_after[0]).name, "uie:ColorField")
	eq(s.workspace.history.undo_depth(), 1)
	s.workspace.history.undo()
	eq(text(s), DOC, "one undo restores the bytes")


func test_insert_new_element_picks_a_free_prefix_and_default_namespace() -> void:
	var taken := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:uie=\"Other\"><ui:VisualElement /></ui:UXML>"
	var s := open_session(taken)
	var tx = EdStructureCommands.insert_new_element(s, named(s, "ui:VisualElement"), 0, "Toolbar", EdElementCatalog.EDITOR)
	run(s, tx)
	ok(text(s).contains("xmlns:uie2=\"UnityEditor.UIElements\""), "a free prefix")
	ok(text(s).contains("<uie2:Toolbar />"))
	var plain := "<UXML xmlns=\"UnityEngine.UIElements\"><VisualElement /></UXML>"
	var s2 := open_session(plain)
	run(s2, EdStructureCommands.insert_new_element(s2, named(s2, "VisualElement"), 0, "Label", EdElementCatalog.RUNTIME))
	eq(text(s2), "<UXML xmlns=\"UnityEngine.UIElements\"><VisualElement><Label /></VisualElement></UXML>", "the default namespace needs no prefix; the space before /> goes")


# ---------------------------------------------------------------------------
# Remove, move
# ---------------------------------------------------------------------------

func test_remove_elements_in_one_step() -> void:
	var s := open_session(DOC)
	var tx = EdStructureCommands.remove_elements(s, [with_name(s, "go"), with_name(s, "title"), with_name(s, "panel")])
	if not is_tx(tx):
		return
	eq(tx.label, "Remove VisualElement", "a contained element goes with its parent")
	var s2 := open_session(DOC)
	var tx2 = EdStructureCommands.remove_elements(s2, [with_name(s2, "go"), with_name(s2, "title")])
	eq(tx2.label, "Remove 2 elements")
	run(s2, tx2)
	var s3 := open_session(DOC)
	run(s3, EdUxmlCommands.remove_element(s3, with_name(s3, "title")))
	run(s3, EdUxmlCommands.remove_element(s3, with_name(s3, "go")))
	eq(text(s2), text(s3), "the same bytes as two single removals")
	ok(text(s2).contains("<!-- keep -->"), "comment kept")
	eq(s2.workspace.history.undo_depth(), 1)
	is_error(EdStructureCommands.remove_elements(s2, [EdLocator.create(s2.root())]), "illegal-root")


func test_move_to_a_drop_position() -> void:
	var s := open_session(DOC)
	# Drop the label after the button: drop index 2 counts the label itself.
	var tx = EdStructureCommands.move_to(s, [with_name(s, "title")], with_name(s, "panel"), 2)
	if not is_tx(tx):
		return
	run(s, tx)
	var panel := s.resolve(with_name(s, "panel"))
	eq(panel.children.map(func(c): return c.get_attribute("name")), ["go", "title"])
	eq(s.resolve(tx.selection_after[0]).get_attribute("name"), "title", "the selection follows")
	ok(text(s).contains("<!-- keep -->"))
	# Reparent to the root, before the panel.
	var tx2 = EdStructureCommands.move_to(s, [with_name(s, "go")], EdLocator.create(s.root()), 0)
	run(s, tx2)
	eq(s.root().children[0].get_attribute("name"), "go")
	eq(s.resolve(tx2.selection_after[0]), s.root().children[0])
	is_error(EdStructureCommands.move_to(s, [with_name(s, "panel")], with_name(s, "title"), 0), "illegal-hierarchy", "into its own child")


# ---------------------------------------------------------------------------
# Unwrap
# ---------------------------------------------------------------------------

func test_unwrap_keeps_children_comments_and_crlf() -> void:
	var s := open_session(DOC)
	var tx = EdStructureCommands.unwrap_element(s, with_name(s, "panel"))
	if not is_tx(tx):
		return
	run(s, tx)
	eq(text(s), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n" \
		+ "  <ui:Label name=\"title\" text='Hi &amp; bye' />\r\n" \
		+ "  <!-- keep -->\r\n" \
		+ "  <ui:Button name=\"go\" text=\"Go\" />\r\n" \
		+ "</ui:UXML>\r\n")
	eq(tx.selection_after.size(), 2, "the children are selected")
	eq(s.resolve(tx.selection_after[1]).get_attribute("name"), "go")
	s.workspace.history.undo()
	eq(text(s), DOC)


func test_unwrap_does_not_touch_multiline_attribute_values() -> void:
	var src := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n\t<ui:VisualElement>\n\t\t<ui:Label\n\t\t\ttext=\"a\n\t\tb\" />\n\t</ui:VisualElement>\n</ui:UXML>\n"
	var s := open_session(src)
	run(s, EdStructureCommands.unwrap_element(s, named(s, "ui:VisualElement")))
	eq(text(s), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n\t<ui:Label\n\t\t\ttext=\"a\n\t\tb\" />\n</ui:UXML>\n",
		"only line starts outside open tags lose an indent")


func test_unwrap_inline_and_empty_and_refusals() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Box><ui:Label /><ui:Label /></ui:Box><ui:Box /></ui:UXML>")
	run(s, EdStructureCommands.unwrap_element(s, named(s, "ui:Box")))
	eq(text(s), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label /><ui:Label /><ui:Box /></ui:UXML>")
	run(s, EdStructureCommands.unwrap_element(s, named(s, "ui:Box")))
	eq(text(s), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label /><ui:Label /></ui:UXML>", "an empty element is removed")
	is_error(EdStructureCommands.unwrap_element(s, EdLocator.create(s.root())), "illegal-root")
	var ns := open_session("<UXML><x:Box xmlns:x=\"X\"><x:Label /></x:Box></UXML>")
	is_error(EdStructureCommands.unwrap_element(ns, named(ns, "x:Box")), "illegal-hierarchy", "a child would lose its namespace")


# ---------------------------------------------------------------------------
# Clipboard
# ---------------------------------------------------------------------------

func test_copy_takes_exact_source_and_namespaces() -> void:
	var s := open_session(DOC)
	var p = EdClipboard.copy(s, [with_name(s, "go"), with_name(s, "title")])
	if not ok(p is Dictionary, "copy gives a payload"):
		return
	eq(p["fragments"].map(func(f): return f["source"]), ["<ui:Label name=\"title\" text='Hi &amp; bye' />", "<ui:Button name=\"go\" text=\"Go\" />"], "document order, exact bytes")
	eq(p["fragments"][0]["namespaces"], [{"name": "xmlns:ui", "value": "UnityEngine.UIElements"}])
	eq(EdClipboard.plain_text(p), "<ui:Label name=\"title\" text='Hi &amp; bye' />\n<ui:Button name=\"go\" text=\"Go\" />")
	is_error(EdClipboard.copy(s, [with_name(s, "panel"), with_name(s, "go")]), "invalid-selection", "overlapping elements")
	is_error(EdClipboard.copy(s, [EdLocator.create(s.root())]), "illegal-root")


func test_paste_renames_taken_names_and_selects_the_copies() -> void:
	var s := open_session(DOC)
	var p = EdClipboard.copy(s, [with_name(s, "title"), with_name(s, "go")])
	var tx = EdClipboard.paste(s, EdLocator.create(s.root()), 1, p)
	if not is_tx(tx):
		return
	eq(tx.label, "Paste 2 elements")
	run(s, tx)
	ok(text(s).contains("  </ui:VisualElement>\r\n  <ui:Label name=\"title-copy\" text='Hi &amp; bye' />\r\n  <ui:Button name=\"go-copy\" text=\"Go\" />\r\n</ui:UXML>"), "pasted at the end of the root, quotes and entities kept: " + text(s))
	eq(tx.selection_after.map(func(l): return s.resolve(l).get_attribute("name")), ["title-copy", "go-copy"])
	var tx2 = EdClipboard.paste(s, EdLocator.create(s.root()), 0, p)
	run(s, tx2)
	ok(text(s).contains("name=\"title-copy-2\""), "a second copy gets -2")


func test_paste_adds_missing_namespaces_and_refuses_conflicts() -> void:
	var src := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:uie=\"UnityEditor.UIElements\"><uie:Toolbar><uie:ToolbarButton text=\"A\" /></uie:Toolbar></ui:UXML>"
	var s := open_session(src)
	var p = EdClipboard.copy(s, [named(s, "uie:ToolbarButton")])
	var dest := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:VisualElement /></ui:UXML>")
	var tx = EdClipboard.paste(dest, named(dest, "ui:VisualElement"), 0, p)
	if not is_tx(tx):
		return
	run(dest, tx)
	eq(text(dest), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:VisualElement><uie:ToolbarButton text=\"A\" xmlns:uie=\"UnityEditor.UIElements\" /></ui:VisualElement></ui:UXML>")
	var clash := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:uie=\"Other\"><ui:VisualElement /></ui:UXML>")
	is_error(EdClipboard.paste(clash, named(clash, "ui:VisualElement"), 0, p), "illegal-hierarchy")


func test_payload_from_plain_text() -> void:
	var s := open_session(DOC)
	var p = EdClipboard.payload_from_text("  <ui:Label text=\"x\" />\n<ui:Button />  ")
	if not ok(p is Dictionary):
		return
	eq(p["fragments"].size(), 2)
	run(s, EdClipboard.paste(s, with_name(s, "panel"), 0, p))
	ok(text(s).contains("<ui:VisualElement name=\"panel\">\r\n    <ui:Label text=\"x\" />\r\n    <ui:Button />\r\n    <ui:Label name=\"title\""))
	is_error(EdClipboard.payload_from_text("hello"), "invalid-fragment")
	is_error(EdClipboard.payload_from_text("<a></b>"), "invalid-fragment")
	var unbound = EdClipboard.payload_from_text("<x:Thing />")
	is_error(EdClipboard.paste(s, with_name(s, "panel"), 0, unbound), "invalid-fragment", "an unbound prefix")


func test_duplicate_through_the_clipboard() -> void:
	var s := open_session(DOC)
	var tx = EdClipboard.duplicate_elements(s, [with_name(s, "title")])
	if not is_tx(tx):
		return
	eq(tx.label, "Duplicate Label")
	run(s, tx)
	ok(text(s).contains("<!-- keep -->\r\n    <ui:Label name=\"title-copy\" text='Hi &amp; bye' />\r\n    <ui:Button"), "the copy goes before the next sibling: " + text(s))
	eq(s.resolve(tx.selection_after[0]).get_attribute("name"), "title-copy")


# ---------------------------------------------------------------------------
# Step composer
# ---------------------------------------------------------------------------

func test_step_composer_makes_one_patch_set() -> void:
	var s := open_session(DOC)
	var tx = EdStepComposer.compose(s, "test", "Two edits", [
		func(sh): return EdUxmlCommands.set_attribute(sh, with_name(sh, "go"), "text", "Run"),
		func(sh): return EdUxmlCommands.set_attribute(sh, with_name(sh, "go"), "tooltip", "Start"),
	])
	if not is_tx(tx):
		return
	eq(text(s), DOC, "planning does not change the buffer")
	run(s, tx)
	ok(text(s).contains("<ui:Button name=\"go\" text=\"Run\" tooltip=\"Start\" />"))
	eq(s.workspace.history.undo_depth(), 1)
	var bad = EdStepComposer.compose(s, "test", "Bad", [
		func(sh): return EdUxmlCommands.set_attribute(sh, with_name(sh, "go"), "text", "X"),
		func(sh): return EdError.make("nope", "stop"),
	])
	is_error(bad, "nope")
	ok(text(s).contains("text=\"Run\""), "a failed step changes nothing")
