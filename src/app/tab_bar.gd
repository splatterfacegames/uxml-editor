class_name EdTabBar
extends Control
## The document tabs over the canvas: one tab per open UXML document, with
## a close button. A godot-uxml document of its own, generated when the
## tabs, the active tab or an unsaved mark change (a few controls, so a
## new document costs little; the window document has no API to add
## elements, request R12 notes the general case).

signal tab_chosen(path: String)
signal tab_closed(path: String)

var doc: UxmlDocument
var _tabs: Array = []
var _key: Variant = null


func _init() -> void:
	doc = UxmlDocument.new()
	doc.auto_load = false
	doc.editor_theme = "always"
	doc.editor_skin = "dark"
	doc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(doc)
	doc.button_pressed.connect(_on_button)


## Show `tabs` (entry paths) with `active` selected; `dirty` holds the
## paths with unsaved edits.
func show_tabs(tabs: Array, active: String, dirty: Dictionary) -> void:
	var marks: Array = tabs.map(func(t): return dirty.has(t))
	var key := [tabs.duplicate(), active, marks]
	if key == _key:
		return
	_key = key
	_tabs = tabs.duplicate()
	var out := PackedStringArray()
	out.append("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">")
	out.append("<Style src=\"res://src/app/ui/tab_bar.uss\" />")
	out.append("<ui:VisualElement name=\"bar\" class=\"tab-bar\">")
	if tabs.is_empty():
		out.append("<ui:Label class=\"tab-empty\" text=\"No document open. Choose a UXML file in the project list.\" />")
	for i in tabs.size():
		var path: String = tabs[i]
		var label := ("● " if marks[i] else "") + path.get_file()
		out.append("<ui:VisualElement name=\"tab-row-%d\" class=\"tab%s\">" % [i, " active" if path == active else ""])
		out.append("<ui:Button name=\"tab-%d\" class=\"tab-button\" text=\"%s\" tooltip=\"%s\" />" % [i, _x(label), _x(path)])
		out.append("<ui:Button name=\"close-%d\" class=\"tab-close\" text=\"×\" tooltip=\"%s\" />" % [i, _x("Close " + path + " (Ctrl+W)")])
		out.append("</ui:VisualElement>")
	out.append("</ui:VisualElement></ui:UXML>")
	doc.load_source("".join(out), "res://src/app/ui/__tabs__.uxml", "res://src/app/ui")


## The global rectangle of the tab of `path` (tests).
func tab_rect(path: String) -> Rect2:
	var c := doc.get_element("tab-%d" % _tabs.find(path))
	return Rect2() if c == null else c.get_global_rect()


func close_rect(path: String) -> Rect2:
	var c := doc.get_element("close-%d" % _tabs.find(path))
	return Rect2() if c == null else c.get_global_rect()


func _on_button(button: String) -> void:
	var dash := button.rfind("-")
	if dash < 0:
		return
	var i := int(button.substr(dash + 1))
	if i < 0 or i >= _tabs.size():
		return
	if button.begins_with("tab-"):
		tab_chosen.emit(_tabs[i])
	elif button.begins_with("close-"):
		tab_closed.emit(_tabs[i])


static func _x(s: String) -> String:
	var e = EdXml.escape_attribute_value(s, "\"")
	return "" if e == null else e
