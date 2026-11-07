extends EdTestCase
## Ported from main:src/core/commands/uxmlCommands.insertionRemoval.test.ts
## and uxmlCommands.moveWrap.test.ts.


func test_inserts_sibling_keeping_comments_and_mixed_indentation() -> void:
	var original := "<?xml version=\"1.0\"?>\r\n" \
		+ "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:vendor=\"Example\">\r\n" \
		+ "  <ui:VisualElement name=\"panel\">\r\n" \
		+ "    <ui:Label text=\"First\" />\r\n" \
		+ "    <!-- keep this -->\r\n" \
		+ "\t\t<vendor:Widget />loose text\r\n" \
		+ "  </ui:VisualElement>\r\n" \
		+ "</ui:UXML>\r\n"
	var s := open_session(original)
	var at := original.find("<vendor:Widget")
	var frag := "<ui:Button text=\"Options\" />"
	var tx = EdUxmlCommands.insert_element(s, named(s, "ui:VisualElement"), 1, frag)
	if not is_tx(tx):
		return
	eq(tx.patches(ENTRY), [p(at, at, frag + "\r\n\t\t")])
	run(s, tx)
	eq(text(s), original.substr(0, at) + frag + "\r\n\t\t" + original.substr(at))


func test_converts_self_closing_parent_with_crlf_indentation() -> void:
	var original := "<?xml version=\"1.0\"?>\r\n<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n  <ui:VisualElement name=\"empty\" />\r\n</ui:UXML>\r\n"
	var s := open_session(original)
	# The space before `/>` goes: `<ui:VisualElement name="empty">`.
	var slash := original.find(" />", original.find("name=\"empty\""))
	var frag := "<ui:Label text=\"New\" />"
	var repl := ">\r\n    " + frag + "\r\n  </ui:VisualElement>"
	var tx = EdUxmlCommands.insert_element(s, named(s, "ui:VisualElement"), 0, frag)
	eq(tx.patches(ENTRY), [p(slash, slash + 3, repl)])
	run(s, tx)
	eq(text(s), original.substr(0, slash) + repl + original.substr(slash + 3))
	ok(text(s).contains("<ui:VisualElement name=\"empty\">\r\n"), "no space before >")


func test_self_closing_parent_with_a_line_break_before_the_slash() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement\n    name=\"tall\"\n  />\n</ui:UXML>\n"
	var s := open_session(original)
	var tx = EdUxmlCommands.insert_element(s, named(s, "ui:VisualElement"), 0, "<ui:Label />")
	run(s, tx)
	ok(text(s).contains("name=\"tall\"\n  >"), "a line break before /> stays")


func test_inserts_into_empty_paired_parent_keeping_comment() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement>\n    <!-- only child trivia -->\n  </ui:VisualElement>\n</ui:UXML>\n"
	var s := open_session(original)
	var at := original.find("\n  </ui:VisualElement>")
	var tx = EdUxmlCommands.insert_element(s, named(s, "ui:VisualElement"), 0, "<ui:Label />")
	eq(tx.patches(ENTRY), [p(at, at, "\n    <ui:Label />")])


func test_inner_crlf_for_empty_first_line_root() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n</ui:UXML>\r\n"
	var s := open_session(original)
	var tx = EdUxmlCommands.insert_element(s, EdLocator.create(s.root()), 0, "<ui:Label />")
	var at := original.find("\r\n")
	eq(tx.patches(ENTRY), [p(at, at, "\r\n  <ui:Label />")])
	run(s, tx)
	eq(text(s), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n  <ui:Label />\r\n</ui:UXML>\r\n")
	eq(tx.selection_after[0]["child_path"], [0], "selects the inserted element")


func test_rejects_unsafe_fragments() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:VisualElement /></ui:UXML>"
	var s := open_session(original)
	var parent := named(s, "ui:VisualElement")
	for frag in [" <ui:Label />", "<ui:Label /><ui:Button />", "<ui:Label text=\"bad & value\" />",
			"<ui:Label><ui:Button /></ui:Wrong>", "<?xml version=\"1.0\"?><ui:Label />",
			"<ui:Label text=\"" + char(1) + "\" />", "<x:Label />", "<ui:Label text=\"a<b\" />"]:
		is_error(EdUxmlCommands.insert_element(s, parent, 0, frag), "invalid-fragment", JSON.stringify(frag))
	eq(text(s), original)


func test_removes_exact_outer_span_keeping_comments_and_tail_text() -> void:
	var original := "<?xml version=\"1.0\"?>\r\n" \
		+ "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:vendor=\"Example\">\r\n" \
		+ "  <ui:VisualElement>\r\n" \
		+ "    <ui:Label />\r\n" \
		+ "    <!-- keep before unsupported -->\r\n" \
		+ "\t<vendor:Widget><Odd-Child /></vendor:Widget>loose tail\r\n" \
		+ "    <ui:Button />\r\n" \
		+ "  </ui:VisualElement>\r\n" \
		+ "</ui:UXML>\r\n"
	var s := open_session(original)
	var rs := original.find("<vendor:Widget>")
	var re := rs + "<vendor:Widget><Odd-Child /></vendor:Widget>".length()
	var tx = EdUxmlCommands.remove_element(s, named(s, "vendor:Widget"))
	eq(tx.patches(ENTRY), [p(rs, re, "")])
	run(s, tx)
	ok(text(s).contains("<!-- keep before unsupported -->"))
	ok(text(s).contains("loose tail"))


func test_remove_takes_leading_whitespace_only() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Label name=\"a\" />\n  <ui:Label name=\"b\" />\n</ui:UXML>\n"
	var s := open_session(original)
	run(s, EdUxmlCommands.remove_element(s, with_name(s, "b")))
	eq(text(s), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Label name=\"a\" />\n</ui:UXML>\n")


func test_duplicates_subtree_with_sibling_separator() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:x=\"Example\">\r\n" \
		+ "  <ui:VisualElement>\r\n" \
		+ "    <x:Panel name=\"copy\">\r\n" \
		+ "      <!-- internal -->\r\n" \
		+ "      <Unknown-Control value=\"&amp;\" />\r\n" \
		+ "    </x:Panel>\r\n" \
		+ "  </ui:VisualElement>\r\n" \
		+ "</ui:UXML>\r\n"
	var s := open_session(original)
	var fs := original.find("<x:Panel")
	var fe := original.find("</x:Panel>") + "</x:Panel>".length()
	var frag := original.substr(fs, fe - fs)
	var tx = EdUxmlCommands.duplicate_element(s, named(s, "x:Panel"))
	eq(tx.patches(ENTRY), [p(fe, fe, "\r\n    " + frag)])


func test_validates_locator_fields() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button name=\"target\" text=\"Go\" /></ui:UXML>"
	var s := open_session(original)
	var valid := with_name(s, "target")
	var bad: Array = []
	for k in 4:
		bad.append(valid.duplicate(true))
	bad[0]["child_path"] = [-1]
	bad[1]["qualified_tag"] = "ui:Button:Again"
	bad[2]["ancestor_tags"] = "nope"
	bad[3]["authored_name"] = 5
	for loc in bad:
		is_error(EdUxmlCommands.set_attribute(s, loc, "text", "Stop"), "invalid-locator", str(loc))
	eq(text(s), original)


func test_rejects_structural_edits_of_the_root() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:VisualElement /></ui:UXML>"
	var s := open_session(original)
	var root := EdLocator.create(s.root())
	var child := named(s, "ui:VisualElement")
	is_error(EdUxmlCommands.remove_element(s, root), "illegal-root")
	is_error(EdUxmlCommands.duplicate_element(s, root), "illegal-root")
	is_error(EdUxmlCommands.move_element(s, root, child, 0), "illegal-root")
	is_error(EdUxmlCommands.wrap_elements(s, [root], "ui:VisualElement"), "illegal-root")
	is_error(EdUxmlCommands.rename_element(s, root, "ui:VisualElement"), "illegal-root")
	eq(text(s), original)


func test_transactions_are_deterministic_and_replay() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button name=\"target\" text=\"Go\" /></ui:UXML>"
	var s := open_session(original)
	var loc := with_name(s, "target")
	var tx: EdTransaction = EdUxmlCommands.set_attribute(s, loc, "text", "Stop")
	var other: EdTransaction = EdUxmlCommands.set_attribute(open_session(original), loc, "text", "Stop")
	eq(tx.id, other.id)
	eq(tx.patches_by_file, other.patches_by_file)
	run(s, tx)
	var edited := text(s)
	s.workspace.history.undo()
	eq(text(s), original)
	s.workspace.history.redo()
	eq(text(s), edited)
	var replay := open_session(original)
	replay.workspace.history.execute(tx.copy())
	eq(text(replay), edited)


func test_rename_changes_open_and_close_names() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement name=\"box\">\n    <ui:Label />\n  </ui:VisualElement >\n</ui:UXML>\n"
	var s := open_session(original)
	run(s, EdUxmlCommands.rename_element(s, with_name(s, "box"), "ui:ScrollView"))
	eq(text(s), original.replace("ui:VisualElement", "ui:ScrollView"))


func test_rename_refuses_unbound_prefix() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label /></ui:UXML>")
	is_error(EdUxmlCommands.rename_element(s, named(s, "ui:Label"), "uie:ColorField"), "illegal-hierarchy")


# ---------------------------------------------------------------------------
# Move and wrap
# ---------------------------------------------------------------------------

func test_moves_subtree_across_parents_keeping_trivia() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:x=\"Example\">\r\n" \
		+ "  <ui:VisualElement name=\"from\">\r\n" \
		+ "    <!-- source comment -->\r\n" \
		+ "\t<x:Widget name=\"move\"><Odd-Child /><!-- inside --></x:Widget>loose source\r\n" \
		+ "  </ui:VisualElement>\r\n" \
		+ "  <ui:VisualElement name=\"to\">\r\n" \
		+ "    <ui:Label />\r\n" \
		+ "    <!-- destination comment -->\r\n" \
		+ "  </ui:VisualElement>\r\n" \
		+ "</ui:UXML>\r\n"
	var s := open_session(original)
	var fs := original.find("<x:Widget")
	var fe := original.find("</x:Widget>") + "</x:Widget>".length()
	var frag := original.substr(fs, fe - fs)
	var dst := original.find("<ui:Label") + "<ui:Label />".length()
	var tx = EdUxmlCommands.move_element(s, with_name(s, "move"), with_name(s, "to"), 1)
	eq(tx.patches(ENTRY), [p(fs, fe, ""), p(dst, dst, "\r\n    " + frag)])
	run(s, tx)
	var moved := original.substr(0, fs) + original.substr(fe, dst - fe) + "\r\n    " + frag + original.substr(dst)
	eq(text(s), moved)
	s.workspace.history.undo()
	eq(text(s), original)
	s.workspace.history.redo()
	eq(text(s), moved)


func test_reorders_with_final_index() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement name=\"parent\">\n    <ui:Label name=\"a\" />\n    <!-- between a and b -->\n    <ui:Label name=\"b\" />\n    <ui:Label name=\"c\" />\n  </ui:VisualElement>\n</ui:UXML>\n"
	var s := open_session(original)
	var fs := original.find("<ui:Label name=\"c\"")
	var fe := fs + "<ui:Label name=\"c\" />".length()
	var at := original.find("<ui:Label name=\"a\"")
	var tx = EdUxmlCommands.move_element(s, with_name(s, "c"), with_name(s, "parent"), 0)
	eq(tx.patches(ENTRY), [p(at, at, "<ui:Label name=\"c\" />\n    "), p(fs, fe, "")])
	run(s, tx)
	ok(text(s).contains("<!-- between a and b -->"))
	var names: Array = []
	for c in s.root().children[0].children:
		names.append(c.get_attribute("name"))
	eq(names, ["c", "a", "b"])
	s.workspace.history.undo()
	eq(text(s), original)


func test_moves_into_self_closing_destination() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement name=\"from\">\n    <ui:Label name=\"move\" />\n  </ui:VisualElement>\n  <ui:VisualElement name=\"to\" />\n</ui:UXML>\n"
	var s := open_session(original)
	var cs := original.find("<ui:Label")
	var ce := cs + "<ui:Label name=\"move\" />".length()
	var slash := original.find(" />", original.find("name=\"to\""))
	var repl := ">\n    <ui:Label name=\"move\" />\n  </ui:VisualElement>"
	var tx = EdUxmlCommands.move_element(s, with_name(s, "move"), with_name(s, "to"), 0)
	eq(tx.patches(ENTRY), [p(cs, ce, ""), p(slash, slash + 3, repl)])
	run(s, tx)
	eq(s.root().children[1].children[0].name, "ui:Label")


func test_moves_contiguous_group_with_trivia() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement name=\"from\">\n    <ui:Label name=\"a\" />\n    <!-- moves with group -->\n\t<ui:Button name=\"b\" />\n  </ui:VisualElement>\n  <ui:VisualElement name=\"to\">\n    <ui:Label name=\"existing\" />\n  </ui:VisualElement>\n</ui:UXML>\n"
	var s := open_session(original)
	var gs := original.find("<ui:Label name=\"a\"")
	var ge := original.find("<ui:Button name=\"b\"") + "<ui:Button name=\"b\" />".length()
	var group := original.substr(gs, ge - gs)
	var at := original.find("<ui:Label name=\"existing\"") + "<ui:Label name=\"existing\" />".length()
	var tx = EdUxmlCommands.move_elements(s, [with_name(s, "a"), with_name(s, "b")], with_name(s, "to"), 1)
	eq(tx.patches(ENTRY), [p(gs, ge, ""), p(at, at, "\n    " + group)])
	run(s, tx)
	var names: Array = []
	for c in s.root().children[1].children:
		names.append(c.get_attribute("name"))
	eq(names, ["existing", "a", "b"])


func test_wraps_siblings_keeping_bytes() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n  <ui:VisualElement name=\"parent\">\r\n    <ui:Label name=\"a\" />\r\n\t<!-- keep between -->\r\n\t<ui:Button name=\"b\" />\r\n  </ui:VisualElement>\r\n</ui:UXML>\r\n"
	var s := open_session(original)
	var fs := original.find("<ui:Label")
	var se := original.find("<ui:Button") + "<ui:Button name=\"b\" />".length()
	var tx = EdUxmlCommands.wrap_elements(s, [with_name(s, "a"), with_name(s, "b")], "ui:VisualElement")
	eq(tx.patches(ENTRY), [p(fs, fs, "<ui:VisualElement>\r\n      "), p(se, se, "\r\n    </ui:VisualElement>")])
	run(s, tx)
	var wrapper: EdUxmlNode = s.root().children[0].children[0]
	eq(wrapper.name, "ui:VisualElement")
	eq(wrapper.children.map(func(c): return c.name), ["ui:Label", "ui:Button"])
	ok(text(s).contains("<!-- keep between -->"))


func test_rejects_unsafe_indices_cycles_and_selections() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement name=\"parent\">\n    <ui:Label name=\"a\"><ui:Button name=\"nested\" /></ui:Label>\n    <ui:Label name=\"b\" />\n    <ui:Label name=\"c\" />\n  </ui:VisualElement>\n</ui:UXML>\n"
	var s := open_session(original)
	var parent := with_name(s, "parent")
	var a := with_name(s, "a")
	var b := with_name(s, "b")
	var c := with_name(s, "c")
	var nested := with_name(s, "nested")
	is_error(EdUxmlCommands.insert_element(s, parent, -1, "<ui:Label />"), "invalid-index")
	is_error(EdUxmlCommands.insert_element(s, parent, 4, "<ui:Label />"), "invalid-index")
	is_error(EdUxmlCommands.move_element(s, b, parent, 1), "illegal-hierarchy")
	is_error(EdUxmlCommands.move_element(s, parent, nested, 0), "illegal-hierarchy")
	is_error(EdUxmlCommands.move_elements(s, [], parent, 0), "invalid-selection")
	is_error(EdUxmlCommands.move_elements(s, [a, a], parent, 0), "invalid-selection")
	is_error(EdUxmlCommands.move_elements(s, [a, c], parent, 0), "invalid-selection")
	is_error(EdUxmlCommands.wrap_elements(s, [], "ui:VisualElement"), "invalid-selection")
	is_error(EdUxmlCommands.wrap_elements(s, [a, a], "ui:VisualElement"), "invalid-selection")
	is_error(EdUxmlCommands.wrap_elements(s, [a, c], "ui:VisualElement"), "invalid-selection")
	is_error(EdUxmlCommands.wrap_elements(s, [a, nested], "ui:VisualElement"), "invalid-selection")
	eq(text(s), original)


func test_refuses_edits_of_unterminated_elements() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:VisualElement name=\"open\">\n    <ui:Label />\n"
	var s := open_session(original)
	is_error(EdUxmlCommands.remove_element(s, with_name(s, "open")), "ambiguous-source")
	is_error(EdUxmlCommands.insert_element(s, with_name(s, "open"), 0, "<ui:Label />"), "ambiguous-source")
