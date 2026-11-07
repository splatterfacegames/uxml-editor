class_name EdInspectorView
extends Control
## The inspector: attributes and inline styles of the selected element.
##
## The inspector is a godot-uxml document that the editor generates as UXML
## text for each selection (dogfooding the addon). Fields commit on Enter
## or focus loss (is-delayed). Each commit is an attribute or inline style
## command, so it is one patch and one undo step. Computed values from the
## godot-uxml cascade show as placeholders of unset style fields.

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

var doc: UxmlDocument
var _session: EdDocumentSession = null
var _node: EdUxmlNode = null
## field name -> {kind: "attr"|"style", name: String}
var _fields: Dictionary = {}
var _host: EdRenderHost = null
var _pending := false
var _count := 1
var _focus_type := false


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


func _rebuild() -> void:
	_pending = false
	var offset := Vector2.ZERO
	if doc._doc != null and doc.get_element("scroll") != null:
		offset = doc.get_scroll_offset("scroll")
	_fields.clear()
	doc.load_source(_generate(), "res://src/app/ui/__inspector__.uxml", "res://src/app/ui")
	if offset != Vector2.ZERO:
		doc.set_scroll_offset("scroll", offset)
	if _focus_type:
		_focus_type = false
		focus_type_field()


## Put the keyboard focus in the element type field (F2: rename).
func focus_type_field() -> void:
	if _pending:
		_focus_type = true
		return
	var c := doc.get_native("element-type")
	if c != null:
		c.grab_focus()
		if c is LineEdit:
			(c as LineEdit).select_all()


func _generate() -> String:
	var out := PackedStringArray()
	out.append("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\" xmlns:uie=\"UnityEditor.UIElements\">")
	out.append("<Style src=\"res://src/app/ui/inspector.uss\" />")
	out.append("<ui:ScrollView name=\"scroll\" class=\"inspector\">")
	if _node == null:
		out.append("<ui:Label class=\"empty\" text=\"%s\" />" % _x("Select an element in the canvas or the hierarchy."))
		out.append("</ui:ScrollView></ui:UXML>")
		return "".join(out)
	var n := _node
	out.append("<ui:VisualElement class=\"title-row\">")
	out.append("<ui:Label class=\"title\" text=\"%s\" />" % _x(n.local))
	if not n.prefix.is_empty():
		out.append("<ui:Label class=\"title-prefix\" text=\"%s\" />" % _x(n.prefix + ":"))
	var authored = n.get_attribute("name")
	if authored != null:
		out.append("<ui:Label class=\"title-name\" text=\"%s\" />" % _x("#" + String(authored)))
	out.append("</ui:VisualElement>")
	var src := _session.source()
	var sub := "%s  ·  line %d" % [_session.entry_path.get_file(), src.substr(0, n.open_start).count("\n") + 1]
	if _count > 1:
		sub += "  ·  +%d more selected" % (_count - 1)
	out.append("<ui:Label class=\"subtitle\" text=\"%s\" />" % _x(sub))
	if n.parent != null:
		_fields["element-type"] = {"kind": "tag", "name": ""}
		out.append("<ui:TextField name=\"element-type\" label=\"Element\" value=\"%s\" is-delayed=\"true\" class=\"field type-field\" tooltip=\"%s\" />" % [
			_x(n.name), _x("The element type (F2). Enter renames the open and close tags.")])
	if n.parent != null and not EdElementCatalog.is_known(n.local):
		out.append("<ui:HelpBox message-type=\"Warning\" text=\"%s\" />" % _x("godot-uxml does not know <%s>. The element stays in the document and renders as a plain box." % n.name))
	if not _session.workspace.buffer(_session.entry_path).exact:
		out.append("<ui:HelpBox message-type=\"Warning\" text=\"%s\" />" % _x("This file does not decode to its exact bytes. The editor shows it but does not change it."))

	# Attributes
	out.append("<ui:Foldout text=\"Attributes\" value=\"true\" class=\"section\">")
	var shown := {}
	var i := 0
	for a in n.attributes:
		if a["name"] == "style":
			continue
		shown[a["name"]] = true
		_row(out, "attr-%d" % i, a["name"], a["value"], "", "attr", a["name"], true)
		i += 1
	for common in COMMON_ATTRIBUTES:
		if shown.has(common) or (common == "text" and not TEXT_ELEMENTS.has(n.local)):
			continue
		_row(out, "attr-%d" % i, common, "", "", "attr", common, false)
		i += 1
	out.append("<ui:VisualElement class=\"add-row\">")
	out.append("<ui:TextField name=\"new-attr-name\" class=\"add-name\" placeholder-text=\"attribute\" />")
	out.append("<ui:TextField name=\"new-attr-value\" class=\"add-value\" placeholder-text=\"value\" />")
	out.append("<ui:Button name=\"add-attr\" class=\"add-button\" text=\"Add\" />")
	out.append("</ui:VisualElement>")
	out.append("</ui:Foldout>")

	# Inline style
	var computed: Dictionary = _host.computed_style(n.id) if _host != null else {}
	out.append("<ui:Foldout text=\"Inline style\" value=\"true\" class=\"section\">")
	var styles := n.attributes_named("style")
	var inline_props := {}
	if styles.size() == 1:
		var a: Dictionary = styles[0]
		var k := 0
		for d in EdUssSource.parse_declarations(src, a["value_start"], a["value_end"]):
			inline_props[d["property"]] = true
			_row(out, "style-%d" % k, d["property"], EdUxmlSource.decode_entities(d["raw"]), "", "style", d["property"], true)
			k += 1
	elif styles.size() > 1:
		out.append("<ui:HelpBox message-type=\"Warning\" text=\"%s\" />" % _x("The style attribute occurs more than once. Edit it in the source view."))
	out.append("<ui:Label class=\"hint\" text=\"%s\" />" % _x("Unset properties show the computed value."))
	var k2 := 0
	for prop in COMMON_STYLES:
		if inline_props.has(prop):
			continue
		_row(out, "unset-%d" % k2, prop, "", _computed_text(computed, prop), "style", prop, false)
		k2 += 1
	out.append("<ui:VisualElement class=\"add-row\">")
	out.append("<ui:TextField name=\"new-style-name\" class=\"add-name\" placeholder-text=\"property\" />")
	out.append("<ui:TextField name=\"new-style-value\" class=\"add-value\" placeholder-text=\"value\" />")
	out.append("<ui:Button name=\"add-style\" class=\"add-button\" text=\"Add\" />")
	out.append("</ui:VisualElement>")
	out.append("</ui:Foldout>")

	# Layout (read only)
	if _host != null:
		var r := _host.rect_of(n.id)
		out.append("<ui:Foldout text=\"Layout\" value=\"true\" class=\"section\">")
		if r.size == Vector2.ZERO and _host.control_of(n.id) == null:
			out.append("<ui:Label class=\"hint\" text=\"Not drawn (non-visual or hidden).\" />")
		else:
			out.append("<ui:Label class=\"readout\" text=\"%s\" />" % _x("x %d   y %d   width %d   height %d" % [int(r.position.x), int(r.position.y), int(round(r.size.x)), int(round(r.size.y))]))
		out.append("</ui:Foldout>")
	out.append("</ui:ScrollView></ui:UXML>")
	return "".join(out)


func _row(out: PackedStringArray, field: String, label: String, value: String, placeholder: String, kind: String, key: String, removable: bool) -> void:
	_fields[field] = {"kind": kind, "name": key}
	out.append("<ui:VisualElement class=\"row\">")
	out.append("<ui:TextField name=\"%s\" label=\"%s\" value=\"%s\" placeholder-text=\"%s\" is-delayed=\"true\" class=\"field%s\" />" % [
		field, _x(label), _x(value), _x(placeholder), "" if removable else " unset"])
	if removable:
		_fields["remove-" + field] = {"kind": kind, "name": key}
		out.append("<ui:Button name=\"remove-%s\" class=\"remove\" text=\"×\" tooltip=\"Remove\" />" % field)
	out.append("</ui:VisualElement>")


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
	if _node == null or not _fields.has(field):
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
		var nm := _text("new-attr-name").strip_edges()
		if not nm.is_empty():
			command.emit(EdUxmlCommands.set_attribute(_session, _locator(), nm, _text("new-attr-value")), "inspector")
		return
	if button == "add-style":
		var prop := _text("new-style-name").strip_edges()
		var val := _text("new-style-value").strip_edges()
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


func _text(field: String) -> String:
	var c := doc.get_native(field)
	if c is LineEdit:
		return (c as LineEdit).text
	if c is TextEdit:
		return (c as TextEdit).text
	return ""
