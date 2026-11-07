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


## Set the text of a fixed-size Label `element_name` of `doc`. Returns
## false when the text did not change.
static func set_label(doc: UxmlDocument, element_name: String, text: String) -> bool:
	var c := doc.get_native(element_name) as Label
	if c == null:
		return false
	if c.text == text and not c.has_meta("uxml_full_text"):
		return false
	set_silent(doc, element_name, "text", text)
	if c.has_meta("uxml_full_text"):
		c.remove_meta("uxml_full_text")
		c.remove_meta("uxml_elided")
	c.text = text
	return true


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
