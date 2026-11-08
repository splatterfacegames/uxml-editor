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


## The full text of a label (also while it is elided).
static func full_text(doc: UxmlDocument, element_name: String) -> String:
	var c := doc.get_native(element_name)
	if c == null:
		return ""
	if c.has_meta("uxml_full_text") and String(c.get("text")) == String(c.get_meta("uxml_elided")):
		return String(c.get_meta("uxml_full_text"))
	return String(c.get("text"))
