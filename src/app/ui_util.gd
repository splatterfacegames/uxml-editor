class_name EdUi
extends RefCounted
## Small helpers for the godot-uxml documents that the editor owns (the
## window and the inspector).
##
## Text goes through UxmlDocument.set_text(). godot-uxml lays out only when
## the text can move an element, and it elides the text and sets the
## tooltip (request R15). A Label whose size does not depend on its text
## costs no layout.


## Set the text of Label or Button `element_name` of `doc`. A set_text()
## with the same text still queues a restyle, so an equal text stops here.
## Returns false when the text did not change.
static func set_label(doc: UxmlDocument, element_name: String, text: String) -> bool:
	if doc.get_native(element_name) == null or full_text(doc, element_name) == text:
		return false
	doc.set_text(element_name, text)
	return true


## The text of placeholder `full` at the width of field `c`: `full`, or
## its start and "..." when it does not fit. Glyphs are at most about one
## em wide, so most texts need no measure (the inspector has about 70
## fields per selection).
static func elided_placeholder(c: LineEdit, full: String) -> String:
	var fs: int = c.get_theme_font_size("font_size")
	var sb: StyleBox = c.get_theme_stylebox("normal")
	var width: float = c.size.x - (sb.get_minimum_size().x if sb != null else 0.0)
	if c.size.x <= 0.0 or full.length() * fs <= width:
		return full
	var font: Font = c.get_theme_font("font")
	if font == null:
		return full
	return UxmlStyleApplier.elide_text(full, width, "end", font, fs)


## The LineEdit of text field `element_name` (the native control, or the
## LineEdit inside it), or null.
static func line_edit(doc: UxmlDocument, element_name: String) -> LineEdit:
	var c := doc.get_native(element_name)
	if c is LineEdit:
		return c
	var outer := doc.get_element(element_name)
	if outer == null:
		return null
	for x in outer.find_children("*", "LineEdit", true, false):
		return x as LineEdit
	return null


## Live text of a search field: `on_text` gets every change as the user
## types. godot-uxml puts the caret of a TextField that is not `is-delayed`
## at the start at each change (request R27). The caret before the key
## (gui_input comes before the LineEdit handles the key) and the change of
## the length give the caret after the change; it goes back at the next
## frame, after the restyle of the change.
static func live_text(doc: UxmlDocument, element_name: String, on_text: Callable) -> void:
	var le := line_edit(doc, element_name)
	if le == null:
		return
	var before := {"text": le.text, "col": le.caret_column}
	le.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventKey and ev.pressed:
			before["text"] = le.text
			before["col"] = le.caret_column)
	le.text_changed.connect(func(t: String) -> void:
		var col := clampi(int(before["col"]) + t.length() - String(before["text"]).length(), 0, t.length())
		before["text"] = t
		before["col"] = col
		le.caret_column = col
		le.get_tree().process_frame.connect(_keep_caret.bind(le, t, col), CONNECT_ONE_SHOT)
		on_text.call(t))


static func _keep_caret(le: LineEdit, t: String, col: int) -> void:
	if is_instance_valid(le) and le.text == t and le.caret_column != col:
		le.caret_column = col


## The full text of a label (also while it is elided).
static func full_text(doc: UxmlDocument, element_name: String) -> String:
	var c := doc.get_native(element_name)
	if c == null:
		return ""
	if c.has_meta("uxml_full_text") and String(c.get("text")) == String(c.get_meta("uxml_elided")):
		return String(c.get_meta("uxml_full_text"))
	return String(c.get("text"))


## Set a model attribute without the change notification.
static func set_silent(doc: UxmlDocument, element_name: String, attr: String, value: String) -> void:
	var el := doc.get_element_model(element_name)
	if el == null:
		return
	for a in el.attributes:
		if a["name"] == attr:
			a["value"] = value
			return
	el.attributes.append({"name": attr, "value": value, "offset": 0})
