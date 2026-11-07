extends EdTestCase
## Source buffers, the workspace commit and the one undo history.


func test_bom_and_newlines_round_trip() -> void:
	var bytes := PackedByteArray([0xEF, 0xBB, 0xBF]) + "<a>\r\n</a>\r\n".to_utf8_buffer()
	var b := EdSourceBuffer.from_bytes("x.uxml", bytes)
	eq(b.bom, true)
	eq(b.exact, true)
	eq(b.text, "<a>\r\n</a>\r\n")
	eq(b.newline_style, "crlf")
	eq(b.to_bytes(), bytes)
	var edited := b.apply([p(1, 2, "b")])
	eq(edited.to_bytes(), PackedByteArray([0xEF, 0xBB, 0xBF]) + "<b>\r\n</a>\r\n".to_utf8_buffer(), "BOM kept after an edit")


func test_newline_styles() -> void:
	eq(EdSourceBuffer.observe_newline_style("a"), "none")
	eq(EdSourceBuffer.observe_newline_style("a\nb\n"), "lf")
	eq(EdSourceBuffer.observe_newline_style("a\r\nb"), "crlf")
	eq(EdSourceBuffer.observe_newline_style("a\rb"), "cr")
	eq(EdSourceBuffer.observe_newline_style("a\nb\r\n"), "mixed")
	eq(EdSourceBuffer.new("m", "a\nb\r\nc").newline(), "\r\n", "mixed uses the last newline")


func test_invalid_utf8_is_inexact_and_refused() -> void:
	var b := EdSourceBuffer.from_bytes("x.uss", PackedByteArray([0x61, 0xC3, 0x28]))
	eq(b.exact, false)
	var ws := EdWorkspace.new()
	ws.set_buffer("x.uss", b)
	var tx := EdTransaction.make("t", "Edit", "x.uss", [p(0, 1, "b")])
	is_error(ws.history.execute(tx), "inexact-source")
	eq(ws.history.can_undo(), false)


func test_commit_is_all_or_nothing_across_files() -> void:
	var ws := EdWorkspace.new()
	ws.set_buffer("a.uxml", EdSourceBuffer.new("a.uxml", "aaaa"))
	ws.set_buffer("b.uss", EdSourceBuffer.new("b.uss", "bbbb"))
	var tx := EdTransaction.multi("t", "Both", {"a.uxml": [p(0, 1, "A")], "b.uss": [p(0, 9, "B")]})
	is_error(ws.history.execute(tx), "invalid-patch")
	eq(ws.text("a.uxml"), "aaaa", "first file untouched")
	var good := EdTransaction.multi("t", "Both", {"a.uxml": [p(0, 1, "A")], "b.uss": [p(3, 4, "B")]})
	ws.history.execute(good)
	eq([ws.text("a.uxml"), ws.text("b.uss")], ["Aaaa", "bbbB"])
	ws.history.undo()
	eq([ws.text("a.uxml"), ws.text("b.uss")], ["aaaa", "bbbb"])
	ws.history.redo()
	eq([ws.text("a.uxml"), ws.text("b.uss")], ["Aaaa", "bbbB"])


func test_coalescing_merges_typing_until_undo() -> void:
	var ws := EdWorkspace.new()
	ws.set_buffer("a.uss", EdSourceBuffer.new("a.uss", ""))
	for ch in ["a", "b", "c"]:
		var tx := ws.replace_text_transaction("a.uss", ws.text("a.uss") + ch, "Type")
		tx.coalesce_key = "source:a.uss"
		ws.history.execute(tx)
	eq(ws.history.undo_depth(), 1, "three keystrokes, one step")
	ws.history.undo()
	eq(ws.text("a.uss"), "")
	ws.history.redo()
	eq(ws.text("a.uss"), "abc")
	var tx2 := ws.replace_text_transaction("a.uss", "abcd", "Type")
	tx2.coalesce_key = "source:a.uss"
	ws.history.execute(tx2)
	eq(ws.history.undo_depth(), 2, "a redo closes the coalescing step")


func test_new_edit_clears_redo() -> void:
	var ws := EdWorkspace.new()
	ws.set_buffer("a.uss", EdSourceBuffer.new("a.uss", "x"))
	ws.history.execute(ws.replace_text_transaction("a.uss", "y", "One"))
	ws.history.undo()
	eq(ws.history.can_redo(), true)
	ws.history.execute(ws.replace_text_transaction("a.uss", "z", "Two"))
	eq(ws.history.can_redo(), false)
	eq(ws.history.undo_label(), "Two")


func test_replace_text_transaction_is_minimal() -> void:
	var ws := EdWorkspace.new()
	ws.set_buffer("a.uss", EdSourceBuffer.new("a.uss", "#a { width: 10px; }"))
	var tx := ws.replace_text_transaction("a.uss", "#a { width: 120px; }", "Edit")
	eq(tx.patches("a.uss"), [p(13, 13, "2")])
	eq(ws.replace_text_transaction("a.uss", "#a { width: 10px; }", "Edit"), null)


func test_undo_restores_selection_before() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label name=\"a\" /><ui:Label name=\"b\" /></ui:UXML>")
	var sel := [with_name(s, "b")]
	var tx: EdTransaction = EdUxmlCommands.remove_element(s, with_name(s, "b"))
	tx.selection_before = sel
	s.workspace.history.execute(tx)
	var r = s.workspace.history.undo()
	var last: EdTransaction = r["entry"]["inverse"][-1]
	eq(last.selection_after, sel)


func test_dirty_tracking() -> void:
	var ws := EdWorkspace.new()
	ws.set_buffer("a.uss", EdSourceBuffer.new("a.uss", "x"))
	eq(ws.is_dirty("a.uss"), false)
	ws.history.execute(ws.replace_text_transaction("a.uss", "y", "Edit"))
	eq(ws.dirty_paths(), ["a.uss"])
	ws.history.undo()
	eq(ws.is_dirty("a.uss"), false, "undo back to the saved text is clean")


func test_locator_survives_reparse_and_reorders() -> void:
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label name=\"a\" /><ui:Button /><ui:Label name=\"b\" /></ui:UXML>")
	var loc := named(s, "ui:Button")
	run(s, EdUxmlCommands.move_element(s, loc, EdLocator.create(s.root()), 0))
	var n := s.resolve(loc)
	ok(n != null and n.name == "ui:Button", "unique structural match still resolves")
	eq(n.child_path(), [0])


func test_reload_from_disk_forgets_only_unsafe_steps() -> void:
	var ws := EdWorkspace.new()
	ws.set_buffer("a.uss", EdSourceBuffer.new("a.uss", "a"))
	ws.set_buffer("b.uss", EdSourceBuffer.new("b.uss", "b"))
	ws.history.execute(ws.replace_text_transaction("b.uss", "b1", "B1"))
	ws.history.execute(ws.replace_text_transaction("a.uss", "a1", "A1"))
	ws.history.execute(ws.replace_text_transaction("b.uss", "b2", "B2"))
	ws.set_buffer("a.uss", EdSourceBuffer.new("a.uss", "from disk"), {}, "reload")
	eq(ws.history.undo_depth(), 1, "only the step after the last a.uss step stays")
	ws.history.undo()
	eq([ws.text("a.uss"), ws.text("b.uss")], ["from disk", "b1"])
	eq(ws.history.can_undo(), false)
