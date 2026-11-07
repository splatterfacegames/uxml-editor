extends EdTestCase
## EdNewlineMap: the source view's "\n" copy maps back to exact buffer
## offsets, and an edit keeps every untouched line break.


func test_display_and_offsets() -> void:
	var src := "a\r\nb\rc\nd\r\n"
	var m := EdNewlineMap.make(src)
	eq(m.display, "a\nb\nc\nd\n")
	for d in m.display.length() + 1:
		var b := m.to_buffer(d)
		eq(m.to_display(b), d, "display %d -> buffer %d -> display" % [d, b])
	eq(m.to_buffer(1), 1, "before the first break")
	eq(m.to_buffer(2), 3, "after the CRLF")
	eq(m.to_buffer(4), 5, "after the lone CR")


func test_edit_keeps_untouched_breaks_and_uses_buffer_style() -> void:
	var src := "<a>\r\n  <b/>\r\n</a>\r\n"
	var m := EdNewlineMap.make(src)
	var edited := m.display.replace("<b/>", "<b/>\n  <c/>")
	var patch = m.to_buffer_patch(edited)
	eq(EdSourcePatch.apply(src, [patch]), "<a>\r\n  <b/>\r\n  <c/>\r\n</a>\r\n")


func test_mixed_breaks_survive_unrelated_edits() -> void:
	var src := "x\ny\r\nz\rw"
	var m := EdNewlineMap.make(src)
	var patch = m.to_buffer_patch(m.display.replace("z", "Z"))
	eq(EdSourcePatch.apply(src, [patch]), "x\ny\r\nZ\rw")
	var del = m.to_buffer_patch(m.display.replace("y\n", ""))
	eq(EdSourcePatch.apply(src, [del]), "x\nz\rw", "deleting a line removes its whole CRLF")


func test_no_change_is_null() -> void:
	var m := EdNewlineMap.make("a\r\n")
	eq(m.to_buffer_patch("a\n"), null)
