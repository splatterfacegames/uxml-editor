class_name EdEasingPicker
extends Popup
## The easing picker of `transition-timing-function`: every Unity easing
## keyword (godot-uxml UssProperties.EASING_MODES) as a cell with its curve.
## A click on a cell chooses the keyword.
##
## The content is a godot-uxml document (generated once, editor dark
## skin); the curves are IMGUIContainer elements drawn with EdEasingCurve.
## The popup window is a native Godot Popup, as UxmlPopupMenu is.

const COLUMNS := 5
const CELL := Vector2(104, 70)

var doc: UxmlDocument
var _keywords: Array = []
var _extra := ""
var _then: Callable
var _current := ""
## The keyword chosen last (tests).
var last_choice := ""


func _init() -> void:
	transparent_bg = false
	borderless = true
	wrap_controls = false


func _ensure(extra: String) -> void:
	if doc != null and extra == _extra:
		return
	_extra = extra
	if doc != null:
		doc.queue_free()
	_keywords = Array(UssProperties.EASING_MODES)
	var out := PackedStringArray()
	out.append("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">")
	out.append("<Style src=\"res://src/app/ui/easing_picker.uss\" />")
	out.append("<ui:VisualElement name=\"grid\" class=\"grid\">")
	for i in _keywords.size():
		out.append("<ui:VisualElement name=\"cell-%d\" class=\"cell\">" % i)
		out.append("<ui:IMGUIContainer name=\"curve-%d\" class=\"curve\" />" % i)
		out.append("<ui:Button name=\"ease-%d\" class=\"name\" text=\"%s\" />" % [i, _keywords[i]])
		out.append("</ui:VisualElement>")
	out.append("</ui:VisualElement>")
	if not extra.is_empty():
		out.append("<ui:Button name=\"extra\" class=\"extra\" text=\"%s\" />" % String(extra).xml_escape(true))
	out.append("</ui:UXML>")
	doc = UxmlDocument.new()
	doc.auto_load = false
	doc.editor_theme = "always"
	doc.editor_skin = "dark"
	add_child(doc)
	doc.set_anchors_preset(Control.PRESET_FULL_RECT)
	doc.load_source("".join(out), "res://src/app/ui/__easing_picker__.uxml", "res://src/app/ui")
	doc.button_pressed.connect(_on_button)
	for i in _keywords.size():
		doc.set_imgui_handler("curve-%d" % i, _draw_curve.bind(i), _on_curve_input.bind(i))


## Open under `anchor` with keyword `current` marked. `then(keyword)` runs
## with the choice; `extra` adds a last entry (the remove entry of the
## inspector) that passes its own text.
func open_at(anchor: Control, current: String, then: Callable, extra: String = "") -> void:
	_ensure(extra)
	_then = then
	_current = current.strip_edges().to_lower()
	for i in _keywords.size():
		doc.set_class("cell-%d" % i, "cell current" if _keywords[i] == _current else "cell")
		var c := doc.get_element("curve-%d" % i)
		if c != null:
			c.queue_redraw()
	var rows := int(ceil(float(_keywords.size()) / COLUMNS))
	var sz := Vector2i(int(COLUMNS * CELL.x + 12), int(rows * CELL.y + 12 + (26 if not extra.is_empty() else 0)))
	var vp := anchor.get_viewport()
	var pos := anchor.get_global_transform_with_canvas().origin + Vector2(0, anchor.size.y)
	if vp != null and vp.gui_embed_subwindows:
		var b := vp.get_visible_rect()
		pos.x = clampf(pos.x, b.position.x, maxf(b.position.x, b.end.x - sz.x))
		if pos.y + sz.y > b.end.y:
			pos.y = maxf(b.position.y, anchor.get_global_transform_with_canvas().origin.y - sz.y)
	else:
		pos = anchor.get_screen_position() + Vector2(0, anchor.size.y)
	size = sz
	doc.size = Vector2(sz)
	popup(Rect2i(Vector2i(pos), sz))


## Choose keyword `kw` (a click on a cell; tests).
func choose(kw: String) -> void:
	last_choice = kw
	hide()
	if _then.is_valid():
		_then.call(kw)


func _on_button(element_name: String) -> void:
	if element_name == "extra":
		choose(_extra)
	elif element_name.begins_with("ease-"):
		choose(_keywords[int(element_name.substr(5))])


func _on_curve_input(_box: Control, ev: InputEvent, i: int) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		choose(_keywords[i])


func _draw_curve(box: Control, rect: Rect2, i: int) -> void:
	var on: bool = _keywords[i] == _current
	EdEasingCurve.draw(box, rect.grow(-4), _keywords[i], Color(1.0, 0.85, 0.4) if on else Color(0.55, 0.8, 1.0))
