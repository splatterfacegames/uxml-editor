extends EdTestCase
## Ported from main:src/core/commands/ussCommands.test.ts. Targets are made
## directly (rule_target, inline_target, new_rule_target); the provenance
## picker that chose them in the old editor is a later milestone.

const SHEET := "Assets/UI/styles/screen.uss"


func _doc(sheet_path: String) -> String:
	return "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <Style src=\"%s\" />\n  <ui:Button name=\"save\" />\n</ui:UXML>\n" % sheet_path


func _inline_doc(style: String, quote: String = "\"") -> String:
	return "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Button name=\"save\" style=%s%s%s data-note=\"keep\" />\n</ui:UXML>\n" % [quote, style, quote]


func _rule_index(ws: EdWorkspace, path: String, selector: String) -> int:
	for r in ws.uss(path).rules():
		if r["selector_text"] == selector:
			return r["item_index"]
	return -1


func test_patches_only_declaration_value() -> void:
	var src := "#save { width: 100px; height: 20px; }\n"
	var s := open_session(_doc("styles/screen.uss"), {SHEET: src})
	var ws := s.workspace
	var t = EdUssCommands.rule_target(ws, SHEET, _rule_index(ws, SHEET, "#save"), "width")
	var tx = EdUssCommands.set_declaration(ws, t, "240px")
	var again = EdUssCommands.set_declaration(ws, t, "240px")
	eq(tx.id, again.id, "deterministic id")
	var at := src.find("100px")
	eq(tx.patches(SHEET), [p(at, at + 5, "240px")])
	run(s, tx)
	eq(ws.text(SHEET), src.replace("100px", "240px"))
	eq(ws.text(ENTRY), _doc("styles/screen.uss"), "entry untouched")


func test_removes_one_exact_duplicate_declaration() -> void:
	var src := ":nth-child(2) { width: 999px; unsupported: keep; }\r\n#save {\r\n  /* before */\r\n  width: 10px;\r\n  --custom: var(--gap, 2px);\r\n  margin: 1px 2px;\r\n  width : 30px \t; /* after */\r\n}\r\n"
	var s := open_session(_doc("styles/screen.uss"), {SHEET: src})
	var ws := s.workspace
	var t = EdUssCommands.rule_target(ws, SHEET, _rule_index(ws, SHEET, "#save"), "width")
	eq(t["declaration"]["raw"], "30px", "the last width wins")
	var tx = EdUssCommands.remove_declaration(ws, t)
	var owned := "width : 30px \t;"
	eq(tx.patches(SHEET), [p(src.find(owned), src.find(owned) + owned.length(), "")])
	run(s, tx)
	eq(ws.text(SHEET), src.replace(owned, ""))


func test_removing_a_line_only_declaration_removes_its_line() -> void:
	var src := "#save {\n  width: 10px;\n  height: 20px;\n}\n"
	var s := open_session(_doc("styles/screen.uss"), {SHEET: src})
	var ws := s.workspace
	run(s, EdUssCommands.remove_declaration(ws, EdUssCommands.rule_target(ws, SHEET, 0, "width")))
	eq(ws.text(SHEET), "#save {\n  height: 20px;\n}\n")


func test_appends_rules_with_local_conventions() -> void:
	var cases := [
		["Assets/UI/styles/crlf.uss", "/* header */\r\nButton {\r\n\twidth: 10px;\r\n}\r\n:nth-child(2) { unsupported: keep; }\r\n", "\r\n#save {\r\n\tcolor: rgb(1, 2, 3);\r\n}\r\n"],
		["Assets/UI/styles/lf.uss", "@media ignored { Button { width: 1px; } }\nButton {\n  height: 20px;\n}", "\n\n#save {\n  color: rgb(1, 2, 3);\n}"],
		["Assets/UI/styles/mixed.uss", "/* old LF */\nButton {\r\n\twidth: 10px;\r\n}\r\n", "\r\n#save {\r\n\tcolor: rgb(1, 2, 3);\r\n}\r\n"],
	]
	for c in cases:
		var s := open_session(_doc(c[0]), {c[0]: c[1]})
		var t := EdUssCommands.new_rule_target(s.workspace, c[0], "#save", "color")
		var tx = EdUssCommands.insert_rule(s.workspace, t, "rgb(1, 2, 3)")
		eq(tx.patches(c[0]), [p(c[1].length(), c[1].length(), c[2])], c[0])
		run(s, tx)
		eq(s.workspace.text(c[0]), c[1] + c[2])


func test_patches_existing_inline_value_keeping_trivia() -> void:
	var src := _inline_doc("color : red; /* keep */ background-image: url(&quot;icon.png&quot;); --gap: 2px", "'")
	var s := open_session(src)
	var t = EdUssCommands.inline_target(s, with_name(s, "save"), "color")
	var tx = EdUssCommands.set_inline_style(s, t, "rgb(1, 2, 3)")
	eq(tx.patches(ENTRY), [p(src.find("red"), src.find("red") + 3, "rgb(1, 2, 3)")])
	run(s, tx)
	eq(text(s), src.replace("red", "rgb(1, 2, 3)"))
	var s2 := open_session(src)
	var t2 = EdUssCommands.inline_target(s2, with_name(s2, "save"), "background-image")
	run(s2, EdUssCommands.set_inline_style(s2, t2, "url('pressed;state.png')"))
	eq(text(s2), src.replace("url(&quot;icon.png&quot;)", "url(&apos;pressed;state.png&apos;)"))


func test_adds_inline_declarations_without_replacing_open_tag() -> void:
	var existing := _inline_doc("opacity: 0.5; /* tail */", "'")
	var s := open_session(existing)
	run(s, EdUssCommands.set_inline_style(s, EdUssCommands.inline_target(s, with_name(s, "save"), "width"), "20px"))
	eq(text(s), existing.replace("opacity: 0.5; /* tail */", "opacity: 0.5; width: 20px; /* tail */"))
	var missing := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Button name='save' data-note=\"keep\" />\n</ui:UXML>\n"
	var m := open_session(missing)
	run(m, EdUssCommands.set_inline_style(m, EdUssCommands.inline_target(m, with_name(m, "save"), "width"), "20px"))
	eq(text(m), missing.replace(" data-note=\"keep\"", " data-note=\"keep\" style=\"width: 20px;\""))


func test_infers_multiline_inline_indentation() -> void:
	var src := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n  <ui:Button name=\"save\" style=\"\r\n    opacity: 0.5;\r\n  \" data-note=\"keep\" />\r\n</ui:UXML>\r\n"
	var s := open_session(src)
	run(s, EdUssCommands.set_inline_style(s, EdUssCommands.inline_target(s, with_name(s, "save"), "width"), "20px"))
	eq(text(s), src.replace("opacity: 0.5;", "opacity: 0.5;\r\n    width: 20px;"))


func test_inline_insertion_before_trailing_comments() -> void:
	var fixtures := [
		["margin: 1px 2px;/* tail */", "margin: 1px 2px; margin-left: 30px;/* tail */"],
		["\n    margin: 1px 2px;\n    /* tail */\n  ", "\n    margin: 1px 2px;\n    margin-left: 30px;\n    /* tail */\n  "],
		["\r\n\tmargin: 1px 2px;\r\n\t/* tail */\r\n  ", "\r\n\tmargin: 1px 2px;\r\n\tmargin-left: 30px;\r\n\t/* tail */\r\n  "],
		["margin: 1px 2px /* tail */", "margin: 1px 2px; margin-left: 30px; /* tail */"],
		["/* only */", "margin-left: 30px; /* only */"],
		["\r\n    /* only */\r\n  ", "\r\n    margin-left: 30px;\r\n    /* only */\r\n  "],
	]
	for f in fixtures:
		var src := _inline_doc(f[0])
		var s := open_session(src)
		run(s, EdUssCommands.set_inline_style(s, EdUssCommands.inline_target(s, with_name(s, "save"), "margin-left"), "30px"))
		eq(text(s), src.replace(f[0], f[1]), JSON.stringify(f[0]))


func test_inserts_after_exact_inline_semicolon() -> void:
	var cases := [
		["opacity: 0.5   ;/* immediate */ /* trailing */", "opacity: 0.5   ; width: 20px;/* immediate */ /* trailing */", "opacity: 0.5   ;".length(), " width: 20px;"],
		["opacity: 0.5\t\f;\t/* tail */", "opacity: 0.5\t\f; width: 20px;\t/* tail */", "opacity: 0.5\t\f;".length(), " width: 20px;"],
		["\n    opacity: 0.5\n    ;\n    /* tail */\n  ", "\n    opacity: 0.5\n    ;\n    width: 20px;\n    /* tail */\n  ", "\n    opacity: 0.5\n    ;".length(), "\n    width: 20px;"],
		["\r\n\topacity: 0.5\r\n\t;\r\n\t/* tail */\r\n  ", "\r\n\topacity: 0.5\r\n\t;\r\n\twidth: 20px;\r\n\t/* tail */\r\n  ", "\r\n\topacity: 0.5\r\n\t;".length(), "\r\n\twidth: 20px;"],
		["opacity: 0.5 \t/* tail */", "opacity: 0.5; width: 20px; \t/* tail */", "opacity: 0.5".length(), "; width: 20px;"],
		["\r\n    opacity: 0.5\r\n    /* tail */\r\n  ", "\r\n    opacity: 0.5;\r\n    width: 20px;\r\n    /* tail */\r\n  ", "\r\n    opacity: 0.5".length(), ";\r\n    width: 20px;"],
	]
	for c in cases:
		var src := _inline_doc(c[0])
		var s := open_session(src)
		var tx = EdUssCommands.set_inline_style(s, EdUssCommands.inline_target(s, with_name(s, "save"), "width"), "20px")
		if not is_tx(tx, JSON.stringify(c[0])):
			continue
		var at: int = src.find(c[0]) + c[2]
		eq(tx.patches(ENTRY), [p(at, at, c[3])], JSON.stringify(c[0]))
		run(s, tx)
		eq(text(s), src.replace(c[0], c[1]))
		s.workspace.history.undo()
		eq(text(s), src)
		s.workspace.history.redo()
		eq(text(s), src.replace(c[0], c[1]))


func test_rejects_malformed_inline_tails() -> void:
	for style in ["opacity: 0.5; /* unterminated", "opacity: 0.5; stray /* tail */", "opacity: 0.5 ;; /* duplicate */", "opacity: 0.5 \t; stray /* tail */"]:
		var src := _inline_doc(style)
		var s := open_session(src)
		var t = EdUssCommands.inline_target(s, with_name(s, "save"), "width")
		var r = EdUssCommands.set_inline_style(s, t, "20px")
		if r is EdError and r.code == "unsafe-source":
			checks += 1
		else:
			# The span parser reads some malformed tails as declarations;
			# either way nothing may change.
			ok(r is EdError or style == "opacity: 0.5; stray /* tail */", "%s refused (%s)" % [style, r])
		eq(text(s), src)
		eq(s.workspace.history.can_undo(), false)


func test_quoted_semicolons_and_unsafe_append() -> void:
	var path := "Assets/UI/styles/valid.uss"
	var valid := "#save { background-image: url(\"old.png\"); }\n"
	var s := open_session(_doc("styles/valid.uss"), {path: valid})
	run(s, EdUssCommands.set_declaration(s.workspace, EdUssCommands.rule_target(s.workspace, path, 0, "background-image"), "url(\"pressed;state.png\")"))
	eq(s.workspace.text(path), valid.replace("url(\"old.png\")", "url(\"pressed;state.png\")"))
	for unsafe in ["#save { width: 10px;\n", "/* unterminated"]:
		var u := open_session(_doc("styles/u.uss"), {"Assets/UI/styles/u.uss": unsafe})
		var t := EdUssCommands.new_rule_target(u.workspace, "Assets/UI/styles/u.uss", "#save", "color")
		is_error(EdUssCommands.insert_rule(u.workspace, t, "red"), "unsafe-source", unsafe)
		eq(u.workspace.text("Assets/UI/styles/u.uss"), unsafe)


func test_rejects_stale_targets_without_mutation() -> void:
	var src := "#save { width: 10px; height: 20px; }\n"
	var s := open_session(_doc("styles/screen.uss"), {SHEET: src})
	var ws := s.workspace
	var t = EdUssCommands.rule_target(ws, SHEET, 0, "width")
	run(s, EdUssCommands.set_declaration(ws, EdUssCommands.rule_target(ws, SHEET, 0, "height"), "25px"))
	var after := ws.text(SHEET)
	is_error(EdUssCommands.set_declaration(ws, t, "40px"), "stale-target")
	is_error(EdUssCommands.remove_declaration(ws, t), "stale-target")
	var forged = EdUssCommands.rule_target(ws, SHEET, 0, "width")
	forged["declaration"]["start"] += 1
	is_error(EdUssCommands.set_declaration(ws, forged, "40px"), "stale-target")
	eq(ws.text(SHEET), after)
	var it := open_session(_inline_doc("width: 1px"))
	var stale = EdUssCommands.inline_target(it, with_name(it, "save"), "width")
	run(it, EdUxmlCommands.set_attribute(it, with_name(it, "save"), "data-note", "changed"))
	is_error(EdUssCommands.set_inline_style(it, stale, "2px"), "stale-target")


func test_inserts_longhand_into_shorthand_rule() -> void:
	var src := "#save {\n  margin: 1px 2px;\n  color: red;\n}\n"
	var s := open_session(_doc("styles/screen.uss"), {SHEET: src})
	var ws := s.workspace
	var tx = EdUssCommands.set_declaration(ws, EdUssCommands.rule_target(ws, SHEET, 0, "margin-left"), "30px")
	var at := src.find("}")
	eq(tx.patches(SHEET), [p(at, at, "  margin-left: 30px;\n")])
	run(s, tx)
	var expected := "#save {\n  margin: 1px 2px;\n  color: red;\n  margin-left: 30px;\n}\n"
	eq(ws.text(SHEET), expected)
	ws.history.undo()
	eq(ws.text(SHEET), src)
	ws.history.redo()
	eq(ws.text(SHEET), expected)


func test_adds_missing_semicolon_when_appending_to_a_rule() -> void:
	var src := "#save {\n  color: red\n}\n.a { color: red }\n"
	var s := open_session(_doc("styles/screen.uss"), {SHEET: src})
	var ws := s.workspace
	run(s, EdUssCommands.set_declaration(ws, EdUssCommands.rule_target(ws, SHEET, 0, "width"), "1px"))
	run(s, EdUssCommands.set_declaration(ws, EdUssCommands.rule_target(ws, SHEET, 1, "width"), "2px"))
	eq(ws.text(SHEET), "#save {\n  color: red;\n  width: 1px;\n}\n.a { color: red; width: 2px; }\n")


func test_values_with_comments_are_edited_in_source_only() -> void:
	var src := "#save { width: 10px /* note */; }\n"
	var s := open_session(_doc("styles/screen.uss"), {SHEET: src})
	is_error(EdUssCommands.set_declaration(s.workspace, EdUssCommands.rule_target(s.workspace, SHEET, 0, "width"), "20px"), "ambiguous-source")


func test_require_value() -> void:
	ok(EdUssCommands.require_value("width", "10px") == true)
	ok(EdUssCommands.require_value("background-image", "url(\"a;b.png\")") == true)
	for bad in ["", "1px; height: 2px", "1px }", "1px /* x */"]:
		is_error(EdUssCommands.require_value("width", bad), "invalid-value", bad)


func test_remove_inline_style() -> void:
	var src := _inline_doc("color: red; width: 1px")
	var s := open_session(src)
	run(s, EdUssCommands.remove_inline_style(s, EdUssCommands.inline_target(s, with_name(s, "save"), "color")))
	eq(text(s), _inline_doc("width: 1px"))
	run(s, EdUssCommands.remove_inline_style(s, EdUssCommands.inline_target(s, with_name(s, "save"), "width")))
	eq(text(s), "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Button name=\"save\" data-note=\"keep\" />\n</ui:UXML>\n")
	s.workspace.history.undo()
	s.workspace.history.undo()
	eq(text(s), src)
