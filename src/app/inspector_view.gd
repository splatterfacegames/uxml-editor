class_name EdInspectorView
extends Control
## The inspector: attributes and inline styles of the selected element.
##
## The inspector is a godot-uxml document (dogfooding the addon). The editor
## generates its UXML once: a fixed skeleton with pools of field rows. A
## selection change or a render then changes the skeleton in place
## (attribute values, labels, classes that hide unused rows) through the
## godot-uxml element model, so godot-uxml restyles only what changed. A
## new skeleton is generated only when the selection needs more rows than
## the pools hold. Building the document costs about 300 ms on the native
## path (godot-uxml request R15); an in-place update costs a few ms.
##
## Fields commit on Enter or focus loss (is-delayed). Each commit is an
## attribute or inline style command, so it is one patch and one undo step.
## Computed values from the godot-uxml cascade show as placeholders of
## unset style fields.

signal command(result: Variant, origin: String)

const COMMON_ATTRIBUTES := ["name", "class", "text", "tooltip", "picking-mode", "focusable", "tabindex", "view-data-key"]
const TEXT_ELEMENTS := ["Label", "Button", "Toggle", "Foldout", "RadioButton", "GroupBox", "Tab", "ToolbarButton", "ToolbarToggle", "ToolbarMenu", "HelpBox"]
const COMMON_STYLES := [
	"width", "height", "min-width", "min-height", "max-width", "max-height",
	"flex-direction", "flex-grow", "flex-shrink", "flex-basis", "flex-wrap",
	"align-items", "align-self", "justify-content",
	"position", "left", "top", "right", "bottom",
	"margin", "padding", "border-width", "border-radius", "border-color",
	"background-color", "background-image", "color", "opacity",
	"font-size", "-unity-font-style", "-unity-text-align", "white-space",
	"display", "visibility", "overflow", "rotate", "scale", "translate",
	"transition-property", "transition-duration",
]
## Extra rows (attributes and declarations outside the common lists) come
## in blocks of this size. Unused rows of a shown block are invisible, so
## most selection changes need no layout.
const POOL_STEP := 2

var doc: UxmlDocument
var _session: EdDocumentSession = null
var _node: EdUxmlNode = null
## field name -> {kind: "attr"|"style"|"tag", name: String} for the rows
## in use.
var _fields: Dictionary = {}
var _host: EdRenderHost = null
var _pending := false
var _count := 1
var _focus_type := false
## Extra rows in the current skeleton (-1: no skeleton yet).
var _attr_pool := -1
var _style_pool := -1
## Number of skeleton loads (tests and the benchmark read it).
var builds := 0
## element name -> {attribute: value} as last written, and label texts.
var _written: Dictionary = {}
var _applying := false


func _init() -> void:
	doc = UxmlDocument.new()
	doc.auto_load = false
	doc.editor_theme = "always"
	doc.editor_skin = "dark"
	doc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(doc)
	doc.value_changed.connect(_on_value_changed)
	doc.button_pressed.connect(_on_button)


func show_selection(session: EdDocumentSession, node: EdUxmlNode, host: EdRenderHost, count: int = 1) -> void:
	_session = session
	_node = node
	_host = host
	_count = count
	if not _pending:
		_pending = true
		_rebuild.call_deferred()


## Bring the document up to date now (tests; normally deferred to the end
## of the frame, so several changes in one frame make one update).
func flush() -> void:
	if _pending:
		_rebuild()


func _rebuild() -> void:
	_pending = false
	var v := _view()
	var need_a := _round(v["attrs"].size() - COMMON_ATTRIBUTES.size())
	var need_s := _round(v["styles"].size() - COMMON_STYLES.size())
	if _attr_pool < need_a or _style_pool < need_s:
		_build_skeleton(maxi(need_a, _attr_pool), maxi(need_s, _style_pool))
	_apply(v)
	if _focus_type:
		_focus_type = false
		focus_type_field()


## Extra rows: at least POOL_STEP, in steps of POOL_STEP.
static func _round(n: int) -> int:
	return maxi(POOL_STEP, int(ceil(float(n) / POOL_STEP)) * POOL_STEP)


## Put the keyboard focus in the element type field (F2: rename).
func focus_type_field() -> void:
	if _pending:
		_focus_type = true
		return
	var c := doc.get_native("element-type")
	if c != null and c.is_visible_in_tree():
		c.grab_focus()
		if c is LineEdit:
			(c as LineEdit).select_all()


# ---------------------------------------------------------------------------
# What to show
# ---------------------------------------------------------------------------

## The inspector content for the current selection, as plain data.
func _view() -> Dictionary:
	var v := {"empty": _node == null, "attrs": [], "styles": []}
	if _node == null:
		return v
	var n := _node
	var src := _session.source()
	var authored = n.get_attribute("name")
	v["title"] = n.local + ("" if authored == null else "   #" + String(authored))
	var sub := "%s  ·  %s  ·  line %d" % [n.name, _session.entry_path.get_file(), src.substr(0, n.open_start).count("\n") + 1]
	if _count > 1:
		sub += "  ·  +%d more selected" % (_count - 1)
	v["subtitle"] = sub
	v["type"] = n.name if n.parent != null else null
	v["unknown"] = n.parent != null and not EdElementCatalog.is_known(n.local)
	v["inexact"] = not _session.workspace.buffer(_session.entry_path).exact

	# Fixed rows (the common names, always in the same rows, so a new
	# selection changes values, not labels), then the other authored
	# attributes and declarations.
	var used := {}
	for common in COMMON_ATTRIBUTES:
		var value = n.get_attribute(common)
		if value != null:
			used[common] = true
		v["attrs"].append({"label": common, "value": "" if value == null else String(value), "placeholder": "",
			"removable": value != null})
	var seen := {}
	for a in n.attributes:
		if a["name"] == "style":
			continue
		if used.has(a["name"]) and not seen.has(a["name"]):
			seen[a["name"]] = true
			continue
		v["attrs"].append({"label": a["name"], "value": a["value"], "placeholder": "", "removable": true})

	var computed: Dictionary = _host.computed_style(n.id) if _host != null else {}
	var styles := n.attributes_named("style")
	var inline := {}
	var extra_styles: Array = []
	v["multi_style"] = styles.size() > 1
	if styles.size() == 1:
		var a: Dictionary = styles[0]
		for d in EdUssSource.parse_declarations(src, a["value_start"], a["value_end"]):
			var row := {"label": d["property"], "value": EdUxmlSource.decode_entities(d["raw"]), "placeholder": "", "removable": true}
			if COMMON_STYLES.has(d["property"]) and not inline.has(d["property"]):
				inline[d["property"]] = row
			else:
				extra_styles.append(row)
	for prop in COMMON_STYLES:
		v["styles"].append(inline.get(prop, {"label": prop, "value": "", "placeholder": _computed_text(computed, prop), "removable": false}))
	v["styles"].append_array(extra_styles)

	v["layout"] = null
	if _host != null:
		var r := _host.rect_of(n.id)
		if r.size == Vector2.ZERO and _host.control_of(n.id) == null:
			v["layout"] = "Not drawn (non-visual or hidden)."
		else:
			v["layout"] = "x %d   y %d   width %d   height %d" % [int(r.position.x), int(r.position.y), int(round(r.size.x)), int(round(r.size.y))]
	return v


# ---------------------------------------------------------------------------
# The skeleton and in-place updates
# ---------------------------------------------------------------------------

func _build_skeleton(attr_pool: int, style_pool: int) -> void:
	_attr_pool = attr_pool
	_style_pool = style_pool
	_written.clear()
	builds += 1
	var out := PackedStringArray()
	out.append("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:uie=\"UnityEditor.UIElements\">")
	out.append("<Style src=\"res://src/app/ui/inspector.uss\" />")
	out.append("<ui:ScrollView name=\"scroll\" class=\"inspector\">")
	out.append("<ui:Label name=\"empty\" class=\"empty\" text=\"%s\" />" % _x("Select an element in the canvas or the hierarchy."))
	out.append("<ui:VisualElement name=\"content\" class=\"invisible\">")
	out.append("<ui:Label name=\"title\" class=\"title\" text=\" \" />")
	out.append("<ui:Label name=\"subtitle\" class=\"subtitle\" text=\" \" />")
	out.append("<ui:TextField name=\"element-type\" label=\"Element\" value=\"\" is-delayed=\"true\" class=\"field type-field\" tooltip=\"%s\" />" % _x("The element type (F2). Enter renames the open and close tags."))
	out.append("<ui:HelpBox name=\"warn-unknown\" class=\"hidden\" message-type=\"Warning\" text=\"%s\" />" % _x("godot-uxml does not know this element. The element stays in the document and renders as a plain box."))
	out.append("<ui:HelpBox name=\"warn-inexact\" class=\"hidden\" message-type=\"Warning\" text=\"%s\" />" % _x("This file does not decode to its exact bytes. The editor shows it but does not change it."))
	out.append("<ui:Foldout name=\"attr-section\" text=\"Attributes\" value=\"true\" class=\"section\">")
	_rows_xml(out, "attr", COMMON_ATTRIBUTES.size(), attr_pool)
	out.append("<ui:VisualElement class=\"add-row\">")
	out.append("<ui:TextField name=\"new-attr-name\" class=\"add-name\" placeholder-text=\"attribute\" />")
	out.append("<ui:TextField name=\"new-attr-value\" class=\"add-value\" placeholder-text=\"value\" />")
	out.append("<ui:Button name=\"add-attr\" class=\"add-button\" text=\"Add\" />")
	out.append("</ui:VisualElement>")
	out.append("</ui:Foldout>")
	out.append("<ui:Foldout name=\"style-section\" text=\"Inline style\" value=\"true\" class=\"section\">")
	out.append("<ui:HelpBox name=\"warn-style\" class=\"hidden\" message-type=\"Warning\" text=\"%s\" />" % _x("The style attribute occurs more than once. Edit it in the source view."))
	out.append("<ui:Label class=\"hint\" text=\"%s\" />" % _x("Unset properties show the computed value."))
	_rows_xml(out, "style", COMMON_STYLES.size(), style_pool)
	out.append("<ui:VisualElement class=\"add-row\">")
	out.append("<ui:TextField name=\"new-style-name\" class=\"add-name\" placeholder-text=\"property\" />")
	out.append("<ui:TextField name=\"new-style-value\" class=\"add-value\" placeholder-text=\"value\" />")
	out.append("<ui:Button name=\"add-style\" class=\"add-button\" text=\"Add\" />")
	out.append("</ui:VisualElement>")
	out.append("</ui:Foldout>")
	out.append("<ui:Foldout name=\"layout-section\" text=\"Layout\" value=\"true\" class=\"section\">")
	out.append("<ui:Label name=\"layout-readout\" class=\"readout\" text=\" \" />")
	out.append("</ui:Foldout>")
	out.append("</ui:VisualElement>")
	out.append("</ui:ScrollView></ui:UXML>")
	var offset := Vector2.ZERO
	if doc._doc != null and doc.get_element("scroll") != null:
		offset = doc.get_scroll_offset("scroll")
	doc.load_source("".join(out), "res://src/app/ui/__inspector__.uxml", "res://src/app/ui")
	if offset != Vector2.ZERO:
		doc.set_scroll_offset("scroll", offset)


## The fixed rows, then the extra rows in blocks. Block 0 is always shown.
func _rows_xml(out: PackedStringArray, kind: String, fixed: int, extra: int) -> void:
	for i in fixed:
		_row(out, "%s-%d" % [kind, i], "row")
	for b in extra / POOL_STEP:
		out.append("<ui:VisualElement name=\"block-%s-%d\" class=\"%s\">" % [kind, b, "block" if b == 0 else "block hidden"])
		for j in POOL_STEP:
			_row(out, "%s-%d" % [kind, fixed + b * POOL_STEP + j], "row invisible")
		out.append("</ui:VisualElement>")


## A row: a fixed-width name label, the value field and the remove button.
## The name is a Label of fixed size, so a new name needs no layout.
func _row(out: PackedStringArray, field: String, row_class: String) -> void:
	out.append("<ui:VisualElement name=\"row-%s\" class=\"%s\">" % [field, row_class])
	out.append("<ui:Label name=\"label-%s\" class=\"row-label\" text=\" \" />" % field)
	out.append("<ui:TextField name=\"%s\" value=\"\" placeholder-text=\"\" is-delayed=\"true\" class=\"field\" />" % field)
	out.append("<ui:Button name=\"remove-%s\" class=\"remove invisible\" text=\"×\" tooltip=\"Remove\" />" % field)
	out.append("</ui:VisualElement>")


func _apply(v: Dictionary) -> void:
	_applying = true
	_fields.clear()
	var empty: bool = v["empty"]
	# Visibility, not display: the content keeps its layout, so the first
	# selection needs no layout of the whole document.
	_hide("empty", "empty", false, "" if empty else "invisible")
	_hide("content", "", false, "invisible" if empty else "")
	if not empty:
		_text("title", v["title"])
		_text("subtitle", v["subtitle"])
		var has_type: bool = v["type"] != null
		_hide("element-type", "field type-field", not has_type)
		if has_type:
			_fields["element-type"] = {"kind": "tag", "name": ""}
			_value("element-type", v["type"])
		_hide("warn-unknown", "", not v["unknown"])
		_hide("warn-inexact", "", not v["inexact"])
		_hide("warn-style", "", not v["multi_style"])
		_rows("attr", v["attrs"], COMMON_ATTRIBUTES.size(), _attr_pool)
		_rows("style", v["styles"], COMMON_STYLES.size(), _style_pool)
		_hide("layout-section", "section", v["layout"] == null)
		if v["layout"] != null:
			_text("layout-readout", v["layout"])
	_applying = false


func _rows(kind: String, rows: Array, fixed: int, extra: int) -> void:
	var blocks := int(ceil(float(rows.size() - fixed) / POOL_STEP))
	for b in range(1, extra / POOL_STEP):
		_hide("block-%s-%d" % [kind, b], "block", b >= blocks)
	for i in fixed + extra:
		var field := "%s-%d" % [kind, i]
		var used: bool = i < rows.size()
		if i >= fixed:
			_hide("row-" + field, "row", false, "" if used else "invisible")
		if not used:
			continue
		var r: Dictionary = rows[i]
		_fields[field] = {"kind": kind, "name": r["label"]}
		_text("label-" + field, r["label"])
		_value(field, r["value"], r["placeholder"])
		_hide("label-" + field, "row-label", false, "" if r["removable"] else "unset")
		_hide("remove-" + field, "remove", false, "" if r["removable"] else "invisible")
		if r["removable"]:
			_fields["remove-" + field] = {"kind": kind, "name": r["label"]}


## Write attribute `attr` of element `el_name` when it changed since the
## last write.
func _attr(el_name: String, attr: String, value: String) -> void:
	var w: Dictionary = _written.get(el_name, {})
	if w.get(attr) == value:
		return
	var el := doc.get_element_model(el_name)
	if el == null:
		return
	el.set_attribute(attr, value)
	w[attr] = value
	_written[el_name] = w


## The value and the placeholder of a text field. A field with the
## keyboard focus keeps what the user types.
## Fast path: neither changes the style or the size of the field, so the
## text goes straight to the LineEdit and the model attribute changes
## without a change notification (a godot-uxml restyle of the field costs
## more than the whole update). The model stays equal to the control, so a
## later full restyle of godot-uxml writes the same text.
func _value(field: String, value: String, placeholder: String = "") -> void:
	var c := doc.get_native(field) as LineEdit
	if c == null:
		return
	if c.placeholder_text != placeholder:
		c.placeholder_text = placeholder
		_silent(field, "placeholder-text", placeholder)
	if c.has_focus():
		return
	if c.text != value:
		c.text = value
	_silent(field, "value", value)
	var w: Dictionary = _written.get(field, {})
	w["value"] = value
	_written[field] = w


func _silent(el_name: String, attr: String, value: String) -> void:
	EdUi.set_silent(doc, el_name, attr, value)


## A label text. The labels that change per selection have a fixed size
## (inspector.uss), so EdUi.set_label() needs no restyle and no layout.
func _text(el_name: String, text: String) -> void:
	var w: Dictionary = _written.get(el_name, {})
	if w.get("text") == text:
		return
	w["text"] = text
	_written[el_name] = w
	EdUi.set_label(doc, el_name, text)


## Show or hide element `el_name` (the `hidden` class: display none).
func _hide(el_name: String, base: String, hidden: bool, extra: String = "") -> void:
	var cls := base
	if not extra.is_empty():
		cls = (cls + " " + extra).strip_edges()
	if hidden:
		cls = (cls + " hidden").strip_edges()
	var w: Dictionary = _written.get(el_name, {})
	if w.get("class") == cls:
		return
	doc.set_class(el_name, cls)
	w["class"] = cls
	_written[el_name] = w


static func _computed_text(computed: Dictionary, prop: String) -> String:
	if computed.is_empty():
		return ""
	var v = computed.get(prop)
	if v == null:
		return ""
	if typeof(v) != TYPE_DICTIONARY:
		return str(v)
	return "%s   %s" % [str(v.get("value", "")), describe_origin(v.get("origin", {}))]


## A short description of a godot-uxml cascade origin:
## {kind: "rule", file, item, decl_index}, {kind: "inherited", origin}, ...
static func describe_origin(o: Variant) -> String:
	if typeof(o) != TYPE_DICTIONARY:
		return ""
	match String(o.get("kind", "")):
		"rule":
			var f := String(o.get("file", ""))
			if f.begins_with("res://addons/godot_uxml/themes/"):
				return "← theme"
			return "← %s" % f.get_file()
		"inherited":
			var inner := describe_origin(o.get("origin", {}))
			return "← inherited" + ("" if inner.is_empty() else " " + inner.substr(2))
		"inline":
			return "← inline"
		"":
			return ""
	return "← " + String(o.get("kind", ""))


static func _x(s: String) -> String:
	var e = EdXml.escape_attribute_value(s, "\"")
	return "" if e == null else e


func _locator() -> Dictionary:
	return EdLocator.create(_node)


func _on_value_changed(field: String, value: Variant) -> void:
	if _applying or _node == null or not _fields.has(field):
		return
	var f: Dictionary = _fields[field]
	var v := String(value)
	if f["kind"] == "tag":
		var tag := v.strip_edges()
		if tag.is_empty() or tag == _node.name:
			return
		command.emit(EdUxmlCommands.rename_element(_session, _locator(), tag), "inspector")
		return
	if f["kind"] == "attr":
		var cur = _node.get_attribute(f["name"])
		if (cur == null and v.is_empty()) or (cur != null and String(cur) == v):
			return
		command.emit(EdUxmlCommands.set_attribute(_session, _locator(), f["name"], v), "inspector")
	else:
		var t = EdUssCommands.inline_target(_session, _locator(), f["name"])
		if t is EdError:
			command.emit(t, "inspector")
			return
		if v.strip_edges().is_empty():
			if t["declaration"] != null:
				command.emit(EdUssCommands.remove_inline_style(_session, t), "inspector")
			return
		if t["declaration"] != null and EdUxmlSource.decode_entities(t["declaration"]["raw"]) == v.strip_edges():
			return
		command.emit(EdUssCommands.set_inline_style(_session, t, v.strip_edges()), "inspector")


func _on_button(button: String) -> void:
	if _node == null:
		return
	if button == "add-attr":
		var nm := _text_of("new-attr-name").strip_edges()
		if not nm.is_empty():
			command.emit(EdUxmlCommands.set_attribute(_session, _locator(), nm, _text_of("new-attr-value")), "inspector")
		return
	if button == "add-style":
		var prop := _text_of("new-style-name").strip_edges()
		var val := _text_of("new-style-value").strip_edges()
		if not prop.is_empty() and not val.is_empty():
			var t = EdUssCommands.inline_target(_session, _locator(), prop)
			command.emit(t if t is EdError else EdUssCommands.set_inline_style(_session, t, val), "inspector")
		return
	if _fields.has(button):
		var f: Dictionary = _fields[button]
		if f["kind"] == "attr":
			command.emit(EdUxmlCommands.remove_attribute(_session, _locator(), f["name"]), "inspector")
		else:
			var t = EdUssCommands.inline_target(_session, _locator(), f["name"])
			command.emit(t if t is EdError else EdUssCommands.remove_inline_style(_session, t), "inspector")


func _text_of(field: String) -> String:
	var c := doc.get_native(field)
	if c is LineEdit:
		return (c as LineEdit).text
	if c is TextEdit:
		return (c as TextEdit).text
	return ""
