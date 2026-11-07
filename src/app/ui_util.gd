class_name EdUi
extends RefCounted
## Cheap updates of the godot-uxml documents that the editor owns (the
## window and the inspector).
##
## UxmlDocument.set_text() lays out the whole document, and a model
## attribute change restyles the element. For a Label whose size does not
## depend on its text (a fixed width, or a width from the parent), the text
## can go straight to the Label control: no restyle and no layout. The
## model attribute changes too, without a change notification, so a later
## full restyle of godot-uxml writes the same text. godot-uxml does not
## apply a `text` change of the model to a Label (request R15).
##
## Elision. A label with `text-overflow: ellipsis` (and `overflow: hidden`,
## no wrap) shows "..." when the text is too wide, and the full text is its
## tooltip. godot-uxml elides after each layout; set_label() elides at
## once with the same function (UxmlStyleApplier.elide_text) and the same
## control metadata (`uxml_full_text`, `uxml_elided`), so the next layout
## of godot-uxml (a pane resize) elides the same text again. Request R15
## asks godot-uxml for a text update that elides by itself.


## Set the text of a fixed-size Label or Button `element_name` of `doc`.
## Returns false when the text did not change.
static func set_label(doc: UxmlDocument, element_name: String, text: String) -> bool:
	var c := doc.get_native(element_name)
	if not (c is Label or c is Button):
		return false
	var full := String(c.get_meta("uxml_full_text")) if c.has_meta("uxml_full_text") else String(c.get("text"))
	if full == text and (not c.has_meta("uxml_full_text") or String(c.get("text")) == String(c.get_meta("uxml_elided"))):
		return false
	set_silent(doc, element_name, "text", text)
	if c.has_meta("uxml_full_text"):
		c.remove_meta("uxml_full_text")
		c.remove_meta("uxml_elided")
	c.set("text", text)
	elide(doc, element_name, c)
	return true


## Elide control `c` of element `element_name` at its current width when
## its style asks for it (text-overflow: ellipsis).
static func elide(doc: UxmlDocument, element_name: String, c: Control) -> void:
	if not c.has_meta("ed_elide"):
		var st := doc.get_computed_style(element_name)
		var to = st.get("text-overflow")
		var ov = st.get("overflow")
		var pos = st.get("-unity-text-overflow-position")
		var on: bool = to is Dictionary and String(to.get("value", "")) == "ellipsis" \
			and ov is Dictionary and String(ov.get("value", "")) == "hidden"
		c.set_meta("ed_elide", "" if not on else (String(pos.get("value", "end")) if pos is Dictionary else "end"))
	var where := String(c.get_meta("ed_elide"))
	if where.is_empty() or c.size.x <= 0.0:
		return
	var full := String(c.get("text"))
	var font: Font = c.get_theme_font("font")
	if font == null:
		return
	var fs: int = c.get_theme_font_size("font_size")
	var sb: StyleBox = c.get_theme_stylebox("normal")
	var width: float = c.size.x - (sb.get_minimum_size().x if sb != null else 0.0)
	var shown := UxmlStyleApplier.elide_text(full, width, where, font, fs)
	if shown == full:
		_tooltip(c, false, full)
		return
	c.set_meta("uxml_full_text", full)
	c.set_meta("uxml_elided", shown)
	c.set("text", shown)
	_tooltip(c, true, full)


## The full text as the tooltip while the text is elided (as godot-uxml
## does, display-tooltip-when-elided); the authored tooltip returns after.
static func _tooltip(c: Control, on: bool, full: String) -> void:
	if on:
		if not c.has_meta("uxml_tip_saved"):
			c.set_meta("uxml_tip_saved", c.tooltip_text)
		c.tooltip_text = full
		if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			c.set_meta("uxml_tip_mouse", true)
			c.mouse_filter = Control.MOUSE_FILTER_PASS
	elif c.has_meta("uxml_tip_saved"):
		c.tooltip_text = c.get_meta("uxml_tip_saved")
		c.remove_meta("uxml_tip_saved")
		if c.has_meta("uxml_tip_mouse"):
			c.remove_meta("uxml_tip_mouse")
			if c.mouse_filter == Control.MOUSE_FILTER_PASS:
				c.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
