extends EdTestCase
## Ported from main:src/core/commands/uxmlCommands.attributes.test.ts.


func test_changes_only_value_span_and_keeps_quote_style() -> void:
	var original := "<?xml version=\"1.0\"?>\r\n" \
		+ "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n" \
		+ "  <ui:Button text='Back &amp; forth' />\r\n" \
		+ "</ui:UXML>\r\n"
	var s := open_session(original)
	var value_start := original.find("Back &amp; forth")
	var tx = EdUxmlCommands.set_attribute(s, named(s, "ui:Button"), "text", "Continue & \"Next\" 'now' <")
	if not is_tx(tx):
		return
	var repl := "Continue &amp; \"Next\" &apos;now&apos; &lt;"
	eq(tx.patches(ENTRY), [p(value_start, value_start + "Back &amp; forth".length(), repl)])
	run(s, tx)
	eq(text(s), original.substr(0, value_start) + repl + original.substr(value_start + "Back &amp; forth".length()))


func test_inserts_attribute_without_rewriting_self_closing_tag() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Button text=\"Go\" />\n</ui:UXML>\n"
	var s := open_session(original)
	var at := original.find("\" />") + 1
	var tx = EdUxmlCommands.set_attribute(s, named(s, "ui:Button"), "tooltip", "Choose \"Go\" & 'continue'")
	var repl := " tooltip=\"Choose &quot;Go&quot; &amp; 'continue'\""
	eq(tx.patches(ENTRY), [p(at, at, repl)])
	run(s, tx)
	eq(text(s), original.substr(0, at) + repl + original.substr(at))


func test_matches_multiline_attribute_spacing() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\r\n  <ui:Button\r\n      text='Go'\r\n    >Body</ui:Button>\r\n</ui:UXML>\r\n"
	var s := open_session(original)
	var at := original.find("'\r\n    >") + 1
	var tx = EdUxmlCommands.set_attribute(s, named(s, "ui:Button"), "tooltip", "More")
	eq(tx.patches(ENTRY), [p(at, at, "\r\n      tooltip='More'")])


func test_reuses_delimiter_spacing_without_attributes() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button   ></ui:Button></ui:UXML>"
	var s := open_session(original)
	var at := original.find("   >")
	var tx = EdUxmlCommands.set_attribute(s, named(s, "ui:Button"), "enabled", "true")
	eq(tx.patches(ENTRY), [p(at, at, "   enabled=\"true\"")])


func test_removes_attribute_and_leading_separator() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Button  name='play'\ttext = \"Go\"   class='primary' />\n</ui:UXML>\n"
	var s := open_session(original)
	var rs := original.find("\ttext")
	var re := rs + "\ttext = \"Go\"".length()
	var tx = EdUxmlCommands.remove_attribute(s, named(s, "ui:Button"), "text")
	eq(tx.patches(ENTRY), [p(rs, re, "")])
	run(s, tx)
	eq(text(s), original.substr(0, rs) + original.substr(re))


func test_non_xml_whitespace_is_not_a_separator() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button name=\"target\" foo=\"1\" bar=\"2\" /></ui:UXML>"
	var s := open_session(original)
	# The scanner does not treat U+00A0 as whitespace, so "bar" is not a
	# separate attribute: removing it is refused, nothing changes.
	var r = EdUxmlCommands.remove_attribute(s, with_name(s, "target"), "bar")
	ok(r is EdError, "refused")
	eq(text(s), original)


func test_lexes_exact_attribute_spans() -> void:
	for lex in ["text = \"Go\"", "text\f=\f\"Go\"", "text = \"one\"two\"", "text = 'one'two'"]:
		eq(EdXml.read_attribute_lexeme(lex, 0, lex.length()), null, JSON.stringify(lex))
	var dq := "text\t=\r\n\"one'two &quot; three\""
	eq(EdXml.read_attribute_lexeme(dq, 0, dq.length()), {"name": "text", "quote": "\"", "value_start": dq.find("\"") + 1, "value_end": dq.length() - 1})
	var sq := "text = 'one\"two &apos; three'"
	eq(EdXml.read_attribute_lexeme(sq, 0, sq.length()), {"name": "text", "quote": "'", "value_start": sq.find("'") + 1, "value_end": sq.length() - 1})


func test_escapes_xml_whitespace_and_rejects_unrepresentable() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button text=\"Go\" /></ui:UXML>")
	var b := named(s, "ui:Button")
	var tx = EdUxmlCommands.set_attribute(s, b, "text", "line 1\n\tline 2\r😀")
	eq(tx.patches(ENTRY)[0]["replacement"], "line 1&#xA;&#x9;line 2&#xD;😀")
	is_error(EdUxmlCommands.set_attribute(s, b, "text", "bad" + char(0x1) + "value"), "invalid-value")
	is_error(EdUxmlCommands.set_attribute(s, b, "text", "bad" + char(0xFFFE) + "value"), "invalid-value")


func test_invalid_names() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button text=\"Go\" /></ui:UXML>")
	var b := named(s, "ui:Button")
	for bad in ["", "bad name", "a:b:c", "1x"]:
		is_error(EdUxmlCommands.set_attribute(s, b, bad, "v"), "invalid-name", bad)


func test_duplicate_attributes_and_unresolved_locators() -> void:
	var original := "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button text=\"First\" text=\"Second\" /></ui:UXML>"
	var s := open_session(original)
	var b := named(s, "ui:Button")
	is_error(EdUxmlCommands.set_attribute(s, b, "text", "Third"), "ambiguous-source")
	is_error(EdUxmlCommands.remove_attribute(s, b, "text"), "ambiguous-source")
	var missing := b.duplicate(true)
	missing["authored_name"] = "missing"
	missing["child_path"] = [99]
	missing["qualified_tag"] = "ui:Missing"
	missing["attribute_hints"] = []
	is_error(EdUxmlCommands.set_attribute(s, missing, "text", "Third"), "unresolved-locator")
	eq(text(s), original)


func test_missing_attribute_removal() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button /></ui:UXML>")
	is_error(EdUxmlCommands.remove_attribute(s, named(s, "ui:Button"), "text"), "missing-attribute")


func test_unbound_attribute_prefix_is_refused() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Button /></ui:UXML>")
	is_error(EdUxmlCommands.set_attribute(s, named(s, "ui:Button"), "x:data", "1"), "illegal-hierarchy")


func test_inexact_buffer_is_never_patched() -> void:
	var ws := EdWorkspace.new()
	var b := EdSourceBuffer.from_bytes(ENTRY, PackedByteArray([0x3C, 0x61, 0x20, 0x62, 0x3D, 0x22, 0xFF, 0x22, 0x2F, 0x3E]))
	eq(b.exact, false)
	ws.set_buffer(ENTRY, b)
	var s := EdDocumentSession.new(ws, ENTRY)
	is_error(EdUxmlCommands.set_attribute(s, EdLocator.create(s.root()), "b", "x"), "inexact-source")
