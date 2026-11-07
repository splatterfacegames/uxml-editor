class_name EdInspectorView
extends Control
## The provenance inspector: the element type, the pseudo-state preview,
## the classes, the attributes and the style of the selected element, and
## every declaration of the focused style property.
##
## The inspector is a godot-uxml document (dogfooding the addon). The editor
## generates its UXML once: a fixed skeleton with pools of rows. A
## selection change or a render then changes the skeleton in place (field
## values, labels, classes that hide unused rows), so godot-uxml restyles
## only what changed. A new skeleton is generated only when the selection
## needs more rows than the pools hold (request R15 has the build cost).
##
## Style writes follow ADR 0004: the valid write targets come from the
## cascade candidates of godot-uxml (explain_style, request R5) through
## EdStyleTargets. One valid target commits at once; more than one opens a
## picker menu. The choice stays for that property until the selection or
## the state preview changes. A target freezes its source; a choice after
## a change of that source is refused.
##
## Fields commit on Enter or focus loss (is-delayed). Each commit is one
## command, one patch set and one undo step; a colour picker drag is one
## coalesced step.

signal command(result: Variant, origin: String)
## Show a source range: a declaration of the provenance list or a rule of
## a class.
signal jump_requested(path: String, start: int, end: int)
## Select another element (the parent of an inherited value).
signal select_requested(id: int)
## The pseudo-states of the state preview changed for editor node `id`.
signal states_changed(id: int, states: Array)

const COMMON_ATTRIBUTES := ["name", "class", "text", "tooltip", "picking-mode", "focusable", "tabindex", "view-data-key"]
const COMMON_STYLES := [
	"width", "height", "min-width", "min-height", "max-width", "max-height",
	"flex-direction", "flex-grow", "flex-shrink", "flex-basis", "flex-wrap",
	"align-items", "align-self", "justify-content",
	"position", "left", "top", "right", "bottom",
	"margin", "padding", "border-width", "border-radius", "border-color",
	"background-color", "background-image", "color", "opacity",
	"font-size", "-unity-font-style", "-unity-text-align", "white-space",
	"display", "visibility", "overflow", "rotate", "scale", "translate", "transform-origin",
	"transition-property", "transition-duration", "transition-delay", "transition-timing-function",
]
## The states of the state preview (godot-uxml set_forced_states, R6).
const STATES := ["hover", "active", "focus", "checked", "selected", "disabled"]
## Extra rows (attributes and declarations outside the common lists, and
## classes) come in blocks of this size. A block that is not in use is
## not displayed.
const POOL_STEP := 2
## Rows of the declaration list.
const PROV_ROWS := 8
const REMOVE_LABEL := "(remove the declaration)"

var doc: UxmlDocument
var _session: EdDocumentSession = null
var _node: EdUxmlNode = null
## field name -> {kind: "attr"|"style"|"tag"|..., name: String} for the
## rows in use.
var _fields: Dictionary = {}
var _host: EdRenderHost = null
var _pending := false
var _count := 1
var _focus_type := false
## Extra rows in the current skeleton (-1: no skeleton yet).
var _attr_pool := -1
var _style_pool := -1
var _class_pool := -1
## Number of skeleton loads (tests and the benchmark read it).
var builds := 0
## element name -> {attribute: value} as last written, and label texts.
var _written: Dictionary = {}
var _applying := false
## The property of the declaration list ("" none).
var focused_property := ""
## The rows of the declaration list (EdProvenance rows).
var provenance: Array = []
## The write targets of the focused property (EdStyleTargets choices).
var targets: Array = []
## The classes of the selection: [{name, rules: [class rule + matches]}].
var classes: Array = []
## The open target question: {property, value, choices, coalesce, then}.
var pending: Dictionary = {}
var picker: UxmlPopupMenu = null
## property -> choice id the user picked for this selection and states.
var _sticky: Dictionary = {}
var _sticky_key := ""
## Lists project assets: (extensions: Array) -> Array of project paths.
var asset_lister: Callable
var _color_popup: PopupPanel = null
var _coalesce := 0


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
	var key := _selection_key()
	if key != _sticky_key:
		_sticky.clear()
		_sticky_key = key
	var v := _view()
	var need_a := _round(v["attrs"].size() - COMMON_ATTRIBUTES.size())
	var need_s := _round(v["styles"].size() - COMMON_STYLES.size())
	var need_c := _round(v["classes"].size())
	if _attr_pool < need_a or _style_pool < need_s or _class_pool < need_c:
		_build_skeleton(maxi(need_a, _attr_pool), maxi(need_s, _style_pool), maxi(need_c, _class_pool))
	_apply(v)
	if _focus_type:
		_focus_type = false
		focus_type_field()


func _selection_key() -> String:
	if _node == null or _session == null:
		return ""
	return "%s|%s|%s" % [_session.entry_path, JSON.stringify(EdLocator.create(_node)), ",".join(states())]


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


## The forced pseudo-states of the selection (the state preview).
func states() -> Array:
	if _host == null or _node == null:
		return []
	return _host.forced_of(_node.id)


func _states_dict() -> Dictionary:
	var d := {}
	for s in states():
		d[s] = true
	return d


# ---------------------------------------------------------------------------
# What to show
# ---------------------------------------------------------------------------

## The inspector content for the current selection, as plain data.
func _view() -> Dictionary:
	var v := {"empty": _node == null, "attrs": [], "styles": [], "classes": []}
	if _node == null:
		provenance = []
		targets = []
		classes = []
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
	v["rendered"] = _host != null and _host.element_for_node.has(n.id)
	v["states"] = states()

	# Fixed rows (the common names, always in the same rows, so a new
	# selection changes values, not labels), then the other authored
	# attributes and declarations.
	var used := {}
	for common in COMMON_ATTRIBUTES:
		var value = n.get_attribute(common)
		if value != null:
			used[common] = true
		v["attrs"].append({"label": common, "value": "" if value == null else String(value),
			"placeholder": "" if value != null else attribute_hint(n.local, common), "removable": value != null})
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
		v["styles"].append(inline.get(prop, {"label": prop, "value": "",
			"placeholder": _computed_text(computed, EdProvenance.longhand_of(prop)), "removable": false}))
	v["styles"].append_array(extra_styles)
	v["colors"] = {}
	for prop in COMMON_STYLES:
		if EdStyleTypes.kind_of(prop) == "color":
			var cv = computed.get(EdProvenance.longhand_of(prop), {})
			var c = EdStyleTypes.parse_color(String(cv.get("value", "")) if cv is Dictionary else "")
			v["colors"][prop] = Color(0, 0, 0, 0) if c == null else c

	classes = []
	var cls = n.get_attribute("class")
	if cls != null:
		for c in String(cls).split(" ", false):
			classes.append({"name": c, "rules": _class_rules(n, c)})
	v["classes"] = classes

	_refresh_provenance()
	v["provenance"] = provenance
	v["targets"] = targets

	v["layout"] = null
	if _host != null:
		var r := _host.rect_of(n.id)
		if r.size == Vector2.ZERO and _host.control_of(n.id) == null:
			v["layout"] = "Not drawn (non-visual or hidden)."
		else:
			v["layout"] = "x %d   y %d   width %d   height %d" % [int(r.position.x), int(r.position.y), int(round(r.size.x)), int(round(r.size.y))]
	return v


## The rules of the document that name class `cls`, each with `matches`:
## the rule applies to the element now (with the previewed states).
func _class_rules(n: EdUxmlNode, cls: String) -> Array:
	var out: Array = []
	for r in EdProvenance.class_rules(_session.workspace, _session.style_paths(), cls):
		var m := false
		if _host != null and not (r["properties"] as Array).is_empty():
			var prop := EdProvenance.longhand_of(String(r["properties"][0]))
			for e in _host.explain(n.id, prop, _states_dict()):
				var o: Dictionary = e["origin"]
				if o.get("kind") == "rule" and o.get("path") == r["path"] and int(o.get("item", -1)) == int(r["item"]):
					m = true
					break
		r["matches"] = m
		out.append(r)
	return out


## The declaration list and the write targets of the focused property.
func _refresh_provenance() -> void:
	provenance = []
	targets = []
	if focused_property.is_empty() or _node == null or _host == null:
		return
	var entries := _host.explain(_node.id, EdProvenance.longhand_of(focused_property), _states_dict())
	provenance = EdProvenance.rows(_session, _node, entries)
	targets = EdStyleTargets.choices(_session, _node, focused_property, entries, states())


## Show the declarations of style property `property`.
func show_property(property: String) -> void:
	if property == focused_property:
		return
	focused_property = property
	if not _pending:
		_pending = true
		_rebuild.call_deferred()


## The value hint of an unset attribute: the enum choices or the default
## from the godot-uxml catalog (request R9).
static func attribute_hint(local: String, attr: String) -> String:
	var a := EdElementCatalog.attribute(local, attr)
	if a.is_empty():
		return ""
	if a.has("choices"):
		return " | ".join(Array(a["choices"]))
	var d := String(a.get("default", ""))
	return "" if d.is_empty() else "default: " + d


# ---------------------------------------------------------------------------
# The skeleton and in-place updates
# ---------------------------------------------------------------------------

func _build_skeleton(attr_pool: int, style_pool: int, class_pool: int) -> void:
	_attr_pool = attr_pool
	_style_pool = style_pool
	_class_pool = class_pool
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
	# State preview (forced pseudo-states, R6).
	out.append("<ui:VisualElement name=\"state-row\" class=\"state-row\">")
	out.append("<ui:Label class=\"row-label\" text=\"State preview\" tooltip=\"%s\" />" % _x("Force pseudo-states on the element. The canvas and the inspector show the state rules."))
	for s in STATES:
		out.append("<ui:Toggle name=\"state-%s\" class=\"state-toggle\" text=\":%s\" value=\"false\" />" % [s, s])
	out.append("</ui:VisualElement>")
	# Classes.
	out.append("<ui:Foldout name=\"class-section\" text=\"Classes\" value=\"true\" class=\"section\">")
	out.append("<ui:Label name=\"class-none\" class=\"hint\" text=\"No classes.\" />")
	for b in class_pool / POOL_STEP:
		out.append("<ui:VisualElement name=\"block-class-%d\" class=\"block hidden\">" % b)
		for j in POOL_STEP:
			var i := b * POOL_STEP + j
			out.append("<ui:VisualElement name=\"row-class-%d\" class=\"row invisible\">" % i)
			out.append("<ui:Label name=\"class-name-%d\" class=\"row-label class-name\" text=\" \" />" % i)
			out.append("<ui:Button name=\"class-rules-%d\" class=\"link class-rules\" text=\" \" tooltip=\"%s\" />" % [i, _x("The rules that name the class (✓: applies now). Click to show the first rule.")])
			out.append("<ui:Button name=\"remove-class-%d\" class=\"remove\" text=\"×\" tooltip=\"Remove the class\" />" % i)
			out.append("</ui:VisualElement>")
		out.append("</ui:VisualElement>")
	out.append("<ui:VisualElement class=\"add-row\">")
	out.append("<ui:TextField name=\"new-class\" class=\"add-value\" placeholder-text=\"class\" />")
	out.append("<ui:Button name=\"add-class\" class=\"add-button\" text=\"Add\" />")
	out.append("</ui:VisualElement>")
	out.append("</ui:Foldout>")
	# Attributes.
	out.append("<ui:Foldout name=\"attr-section\" text=\"Attributes\" value=\"true\" class=\"section\">")
	_rows_xml(out, "attr", COMMON_ATTRIBUTES.size(), attr_pool)
	out.append("<ui:VisualElement class=\"add-row\">")
	out.append("<ui:Button name=\"pick-attr\" class=\"helper\" text=\"▾\" tooltip=\"%s\" />" % _x("The attributes of this element (godot-uxml catalog)."))
	out.append("<ui:TextField name=\"new-attr-name\" class=\"add-name\" placeholder-text=\"attribute\" />")
	out.append("<ui:TextField name=\"new-attr-value\" class=\"add-value\" placeholder-text=\"value\" />")
	out.append("<ui:Button name=\"add-attr\" class=\"add-button\" text=\"Add\" />")
	out.append("</ui:VisualElement>")
	out.append("</ui:Foldout>")
	# Style.
	out.append("<ui:Foldout name=\"style-section\" text=\"Style\" value=\"true\" class=\"section\">")
	out.append("<ui:HelpBox name=\"warn-style\" class=\"hidden\" message-type=\"Warning\" text=\"%s\" />" % _x("The style attribute occurs more than once. Edit it in the source view."))
	out.append("<ui:Label class=\"hint\" text=\"%s\" />" % _x("Unset properties show the computed value. A field with the focus lists its declarations below."))
	_rows_xml(out, "style", COMMON_STYLES.size(), style_pool)
	out.append("<ui:VisualElement class=\"add-row\">")
	out.append("<ui:TextField name=\"new-style-name\" class=\"add-name\" placeholder-text=\"property\" />")
	out.append("<ui:TextField name=\"new-style-value\" class=\"add-value\" placeholder-text=\"value\" />")
	out.append("<ui:Button name=\"add-style\" class=\"add-button\" text=\"Add\" />")
	out.append("</ui:VisualElement>")
	out.append("</ui:Foldout>")
	# Declarations of the focused property (provenance).
	out.append("<ui:Foldout name=\"prov-section\" text=\"Declarations\" value=\"true\" class=\"section\">")
	out.append("<ui:Label name=\"prov-title\" class=\"readout\" text=\" \" />")
	for i in PROV_ROWS:
		out.append("<ui:Button name=\"prov-%d\" class=\"link prov hidden\" text=\" \" tooltip=\"%s\" />" % [i, _x("Click to show the declaration in the source view.")])
	out.append("<ui:Label name=\"prov-targets\" class=\"readout targets\" text=\" \" />")
	out.append("</ui:Foldout>")
	out.append("<ui:Foldout name=\"layout-section\" text=\"Layout\" value=\"true\" class=\"section\">")
	out.append("<ui:Label name=\"layout-readout\" class=\"readout\" text=\" \" />")
	out.append("</ui:Foldout>")
	out.append("</ui:VisualElement>")
	out.append("</ui:ScrollView></ui:UXML>")
	var offset := Vector2.ZERO
	if doc.get_document_model() != null and doc.get_element("scroll") != null:
		offset = doc.get_scroll_offset("scroll")
	doc.load_source("".join(out), "res://src/app/ui/__inspector__.uxml", "res://src/app/ui")
	if offset != Vector2.ZERO:
		doc.set_scroll_offset("scroll", offset)
	# A style field with the focus lists its declarations.
	for i in COMMON_STYLES.size() + style_pool:
		var c := doc.get_native("style-%d" % i)
		if c != null:
			c.focus_entered.connect(_on_style_focus.bind("style-%d" % i))


## The fixed rows, then the extra rows in blocks; a block in use is shown.
func _rows_xml(out: PackedStringArray, kind: String, fixed: int, extra: int) -> void:
	for i in fixed:
		_row(out, kind, i, "row")
	for b in extra / POOL_STEP:
		out.append("<ui:VisualElement name=\"block-%s-%d\" class=\"block hidden\">" % [kind, b])
		for j in POOL_STEP:
			_row(out, kind, fixed + b * POOL_STEP + j, "row invisible")
		out.append("</ui:VisualElement>")


## A row: a fixed-width name label, a typed helper (fixed style rows),
## the value field and the remove button. The name is a Label of fixed
## size, so a new name needs no layout.
func _row(out: PackedStringArray, kind: String, i: int, row_class: String) -> void:
	var field := "%s-%d" % [kind, i]
	out.append("<ui:VisualElement name=\"row-%s\" class=\"%s\">" % [field, row_class])
	out.append("<ui:Label name=\"label-%s\" class=\"row-label\" text=\" \" />" % field)
	if kind == "style":
		var h := helper_kind(COMMON_STYLES[i]) if i < COMMON_STYLES.size() else ""
		match h:
			"color":
				out.append("<ui:Button name=\"pick-%s\" class=\"helper swatch\" text=\" \" tooltip=\"Pick a colour\" />" % field)
			"menu":
				out.append("<ui:Button name=\"pick-%s\" class=\"helper\" text=\"▾\" tooltip=\"Choose a value\" />" % field)
			"unit":
				out.append("<ui:Button name=\"pick-%s\" class=\"helper\" text=\"u\" tooltip=\"Choose a unit\" />" % field)
			"asset":
				out.append("<ui:Button name=\"pick-%s\" class=\"helper\" text=\"…\" tooltip=\"Choose a project asset\" />" % field)
			_:
				out.append("<ui:VisualElement class=\"helper-space\" />")
	out.append("<ui:TextField name=\"%s\" value=\"\" placeholder-text=\"\" is-delayed=\"true\" class=\"field\" />" % field)
	out.append("<ui:Button name=\"remove-%s\" class=\"remove invisible\" text=\"×\" tooltip=\"Remove\" />" % field)
	out.append("</ui:VisualElement>")


## The typed helper of a style property: "color" (a picker), "menu" (the
## keywords), "unit", "asset" or "".
static func helper_kind(property: String) -> String:
	match EdStyleTypes.kind_of(property):
		"enum", "easing", "property-list":
			return "menu"
		"length", "rotate", "time", "translate":
			return "unit"
		"color":
			return "color"
		"asset":
			return "asset"
	return ""


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
		_hide("state-row", "state-row", not v["rendered"])
		for s in STATES:
			_fields["state-" + s] = {"kind": "state", "name": s}
			_toggle("state-" + s, (v["states"] as Array).has(s))
		_class_rows(v["classes"])
		_rows("attr", v["attrs"], COMMON_ATTRIBUTES.size(), _attr_pool)
		_rows("style", v["styles"], COMMON_STYLES.size(), _style_pool)
		for i in COMMON_STYLES.size():
			var prop: String = COMMON_STYLES[i]
			var h := helper_kind(prop)
			if not h.is_empty():
				_fields["pick-style-%d" % i] = {"kind": "pick", "name": prop, "helper": h}
			if h == "color":
				var sw := doc.get_native("pick-style-%d" % i)
				if sw != null:
					# The swatch: the button tinted with the computed colour
					# (a modulate of the control, no restyle).
					var c: Color = v["colors"].get(prop, Color(0, 0, 0, 0))
					sw.self_modulate = Color(c.r, c.g, c.b, maxf(c.a, 0.15))
		_provenance_rows(v["provenance"], v["targets"])
		_hide("layout-section", "section", v["layout"] == null)
		if v["layout"] != null:
			_text("layout-readout", v["layout"])
	_applying = false


func _class_rows(rows: Array) -> void:
	_hide("class-none", "hint", not rows.is_empty())
	var blocks := int(ceil(float(rows.size()) / POOL_STEP))
	for b in _class_pool / POOL_STEP:
		_hide("block-class-%d" % b, "block", b >= blocks)
	for i in _class_pool:
		var used: bool = i < rows.size()
		_hide("row-class-%d" % i, "row", false, "" if used else "invisible")
		if not used:
			continue
		var r: Dictionary = rows[i]
		_text("class-name-%d" % i, "." + String(r["name"]))
		var parts: Array = []
		for rule in r["rules"]:
			parts.append("%s%s:%d %s" % ["✓ " if rule["matches"] else "", String(rule["path"]).get_file(), int(rule["line"]), rule["selector"]])
		_text("class-rules-%d" % i, "no rule names this class" if parts.is_empty() else "   ".join(parts))
		_fields["class-rules-%d" % i] = {"kind": "class-rules", "name": r["name"]}
		_fields["remove-class-%d" % i] = {"kind": "class", "name": r["name"]}


func _provenance_rows(rows: Array, choices: Array) -> void:
	if focused_property.is_empty():
		_text("prov-title", "A style field with the focus lists its declarations here.")
	else:
		var lh := EdProvenance.longhand_of(focused_property)
		_text("prov-title", "%s%s  ·  %d declaration%s%s" % [focused_property, "" if lh == focused_property else " (" + lh + ")",
			rows.size(), "" if rows.size() == 1 else "s", "" if states().is_empty() else "  ·  :" + ":".join(states())])
	for i in PROV_ROWS:
		var used: bool = i < rows.size()
		var r: Dictionary = rows[i] if used else {}
		var status := String(r.get("status", ""))
		_hide("prov-%d" % i, "link prov", not used, "status-" + status if used else "")
		if used:
			var t := EdProvenance.line(r)
			if i == PROV_ROWS - 1 and rows.size() > PROV_ROWS:
				t = "… and %d more" % (rows.size() - PROV_ROWS + 1)
			_text("prov-%d" % i, t)
			_fields["prov-%d" % i] = {"kind": "prov", "name": str(i)}
	var labels: Array = choices.map(func(c): return String(c["label"]))
	var sticky = _sticky.get(focused_property)
	var picked := ""
	for c in choices:
		if c["id"] == sticky:
			picked = c["label"]
	_text("prov-targets", "" if focused_property.is_empty() else
		("Writes to: " + picked if not picked.is_empty() else "Write targets: " + ("none" if labels.is_empty() else "; ".join(labels))))


func _rows(kind: String, rows: Array, fixed: int, extra: int) -> void:
	var blocks := int(ceil(float(rows.size() - fixed) / POOL_STEP))
	for b in extra / POOL_STEP:
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


## A Toggle value (a model change: the toggle restyles).
func _toggle(field: String, on: bool) -> void:
	var w: Dictionary = _written.get(field, {})
	var v := "true" if on else "false"
	if w.get("value") == v:
		return
	w["value"] = v
	_written[field] = w
	var el := doc.get_element_model(field)
	if el != null and str(el.get_attribute("value")) != v:
		el.set_attribute("value", v)


func _silent(el_name: String, attr: String, value: String) -> void:
	EdUi.set_silent(doc, el_name, attr, value)


## A label or button text. The labels that change per selection have a
## fixed size (inspector.uss), so EdUi.set_label() needs no restyle and no
## layout.
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


# ---------------------------------------------------------------------------
# Style writes (ADR 0004)
# ---------------------------------------------------------------------------

## Write `value` to style `property` of the selection: at once when one
## target is valid (or the user picked one for this property), else after
## the picker. An empty value removes a declaration. `anchor`: the control
## under which the picker opens.
func write_style(property: String, value: String, anchor: Control = null, coalesce: String = "") -> void:
	if _node == null or _session == null:
		return
	var v := value.strip_edges()
	if not v.is_empty():
		var bad = EdStyleTypes.check(property, v)
		if bad is EdError:
			command.emit(bad, "inspector")
			return
	_with_target(property, v.is_empty(), anchor, func(choice): _commit(property, v, choice, coalesce))


## The valid targets of `property` now (fresh: a target freezes the
## current source). `removal`: only the targets with a declaration.
func choices_for(property: String, removal: bool = false) -> Array:
	if _node == null or _host == null:
		return []
	var entries := _host.explain(_node.id, EdProvenance.longhand_of(property), _states_dict())
	var out := EdStyleTargets.choices(_session, _node, property, entries, states())
	if removal:
		out = out.filter(func(c): return c["kind"] != "new-rule" and c["target"].get("declaration") != null)
	return out


## Call `then(choice)` with the target of `property`: the sticky choice,
## the only valid target, or the target the user picks (the picker opens).
func _with_target(property: String, removal: bool, anchor: Control, then: Callable) -> void:
	var cs := choices_for(property, removal)
	if cs.is_empty():
		command.emit(EdError.make("invalid-target", ("%s has no declaration to remove." if removal else "%s has no write target (a pseudo-state needs a rule).") % property), "inspector")
		return
	var sticky = _sticky.get(property)
	for c in cs:
		if c["id"] == sticky:
			then.call(c)
			return
	if cs.size() == 1:
		then.call(cs[0])
		return
	_open_picker(property, cs, anchor, then)


func _open_picker(property: String, cs: Array, anchor: Control, then: Callable) -> void:
	_close_picker()
	pending = {"property": property, "choices": cs, "then": then}
	var labels := PackedStringArray(cs.map(func(c): return String(c["label"])))
	labels.append("Cancel")
	var at: Control = anchor if anchor != null and anchor.is_inside_tree() else doc
	picker = UxmlPopupMenu.open(at, labels, -1, doc.theme_path, doc)
	picker.chosen.connect(choose)
	picker.popup_hide.connect(_on_picker_hidden, CONNECT_DEFERRED)


## The picker closed without a choice (a click outside): no write.
func _on_picker_hidden() -> void:
	pending = {}
	_close_picker()


func _close_picker() -> void:
	if picker != null and is_instance_valid(picker):
		picker.queue_free()
	picker = null


## The labels of the open target question ([] when none; tests).
func pending_labels() -> Array:
	return [] if pending.is_empty() else pending["choices"].map(func(c): return String(c["label"]))


## Answer the target question with choice `index` (an index past the
## choices cancels). The choice stays for the property. Returns true when
## a target was chosen.
func choose(index: int) -> bool:
	if pending.is_empty():
		return false
	var p := pending
	pending = {}
	_close_picker()
	if index < 0 or index >= p["choices"].size():
		return false
	var c: Dictionary = p["choices"][index]
	_sticky[p["property"]] = c["id"]
	(p["then"] as Callable).call(c)
	return true


## Pick the choice whose id is `id` (tests: "inline", "rule:<path>:<item>",
## "new:<path>:<selector>").
func choose_id(id: String) -> bool:
	if pending.is_empty():
		return false
	for i in pending["choices"].size():
		if pending["choices"][i]["id"] == id:
			return choose(i)
	return false


func _commit(property: String, value: String, choice: Dictionary, coalesce: String) -> void:
	if _node == null:
		return
	var r = EdStyleTargets.commit(_session, choice, value)
	if r is EdTransaction:
		var asset = _check_asset(property, value, choice)
		if asset is EdError:
			command.emit(asset, "inspector")
			return
		if not coalesce.is_empty():
			(r as EdTransaction).coalesce_key = coalesce
	command.emit(r, "inspector")
	# A new rule is now a rule: later writes of the property go to it.
	if r is EdTransaction and choice["kind"] == "new-rule":
		var sheet := _session.workspace.uss(choice["path"])
		if sheet != null:
			_sticky[property] = "rule:%s:%d" % [choice["path"], sheet.items.size() - 1]


## A url() of an asset property must name a file of the project.
func _check_asset(property: String, value: String, choice: Dictionary) -> Variant:
	if EdStyleTypes.kind_of(property) != "asset" or _session == null:
		return null
	var p := EdStyleTypes.url_path(value)
	if p.is_empty() or p.begins_with("project://") or p.begins_with("res://"):
		return null
	var resolved = EdProjectPaths.resolve(p, String(choice["path"]))
	if resolved == null:
		return EdError.make("invalid-value", "%s is outside the project." % p)
	if asset_lister.is_valid():
		var all: Array = asset_lister.call(EdStyleTypes.asset_extensions(property))
		if not all.has(resolved):
			return EdError.make("missing-file", "%s is not a file of the project (from %s)." % [p, choice["path"]])
	return null


# ---------------------------------------------------------------------------
# Helpers: menus, units, colours, assets
# ---------------------------------------------------------------------------

func _on_helper(field: String) -> void:
	var f: Dictionary = _fields[field]
	var prop: String = f["name"]
	var anchor := doc.get_native(field)
	match String(f["helper"]):
		"menu":
			var cs := EdStyleTypes.choices(prop)
			if prop == "transition-property":
				cs = ["all", "none"] + COMMON_STYLES.filter(func(p): return not p.begins_with("transition"))
			_menu(anchor, cs + [REMOVE_LABEL], _menu_value.bind(prop, anchor))
		"unit":
			_menu(anchor, EdStyleTypes.units(prop), _unit_value.bind(prop, anchor))
		"asset":
			var assets: Array = asset_lister.call(EdStyleTypes.asset_extensions(prop)) if asset_lister.is_valid() else []
			_menu(anchor, ["none"] + assets + [REMOVE_LABEL], _asset_value.bind(prop, anchor))
		"color":
			open_color_picker(prop, anchor)


func _menu_value(t: String, prop: String, anchor: Control) -> void:
	write_style(prop, "" if t == REMOVE_LABEL else t, anchor)


func _unit_value(u: String, prop: String, anchor: Control) -> void:
	write_style(prop, EdStyleTypes.with_unit(_field_text(prop), u, _computed_value(prop)), anchor)


## An asset of the menu: url() relative to the file of the target.
func _asset_value(a: String, prop: String, anchor: Control) -> void:
	if a == REMOVE_LABEL:
		write_style(prop, "", anchor)
	elif a == "none":
		write_style(prop, "none", anchor)
	else:
		_with_target(prop, false, anchor, _commit_asset.bind(prop, a))


func _commit_asset(choice: Dictionary, prop: String, asset: String) -> void:
	_commit(prop, EdStyleTypes.url_for(asset, String(choice["path"])), choice, "")


## The colour picker of `property` (godot-uxml UxmlEditorWidgets, the
## picker of ColorField). The target is chosen first; each change writes
## to it, and the changes of one picker are one undo step.
func open_color_picker(property: String, anchor: Control) -> void:
	_with_target(property, false, anchor, _open_color_for.bind(property, anchor))


func _open_color_for(choice: Dictionary, property: String, anchor: Control) -> void:
	_sticky[property] = choice["id"]
	_coalesce += 1
	var key := "color:%d" % _coalesce
	var start = EdStyleTypes.parse_color(_computed_value(property))
	if _color_popup != null and is_instance_valid(_color_popup):
		_color_popup.queue_free()
	_color_popup = UxmlEditorWidgets.open_color_picker(anchor if anchor != null else doc, Color.WHITE if start == null else start,
		true, false, _on_color.bind(property, key))


func _on_color(c: Color, property: String, key: String) -> void:
	color_changed(property, c, key)


## A colour picker change: write the colour to the chosen target.
func color_changed(property: String, c: Color, coalesce: String = "") -> void:
	var id = _sticky.get(property)
	for ch in choices_for(property):
		if id == null or ch["id"] == id:
			_sticky[property] = ch["id"]
			_commit(property, EdStyleTypes.color_text(c), ch, coalesce)
			return


func _menu(anchor: Control, items: Array, then: Callable) -> void:
	_close_picker()
	var labels := PackedStringArray(items.map(func(x): return String(x)))
	picker = UxmlPopupMenu.open(anchor if anchor != null else doc, labels, -1, doc.theme_path, doc)
	picker.chosen.connect(_on_menu_chosen.bind(labels, then))
	picker.popup_hide.connect(_on_menu_hidden, CONNECT_DEFERRED)


func _on_menu_chosen(i: int, labels: PackedStringArray, then: Callable) -> void:
	_close_picker()
	if i >= 0 and i < labels.size():
		then.call(labels[i])


func _on_menu_hidden() -> void:
	if pending.is_empty():
		_close_picker()


## The text in the field of style `property` (the inline value), or "".
func _field_text(property: String) -> String:
	var i := COMMON_STYLES.find(property)
	if i < 0:
		return ""
	var c := doc.get_native("style-%d" % i) as LineEdit
	return "" if c == null else c.text


func _computed_value(property: String) -> String:
	if _host == null or _node == null:
		return ""
	var v = _host.computed_style(_node.id).get(EdProvenance.longhand_of(property))
	return String(v.get("value", "")) if v is Dictionary else ("" if v == null else str(v))


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _on_style_focus(field: String) -> void:
	if _fields.has(field) and _fields[field]["kind"] == "style":
		show_property(_fields[field]["name"])


func _on_value_changed(field: String, value: Variant) -> void:
	if _applying or _node == null or not _fields.has(field):
		return
	var f: Dictionary = _fields[field]
	match String(f["kind"]):
		"tag":
			var tag := String(value).strip_edges()
			if tag.is_empty() or tag == _node.name:
				return
			command.emit(EdUxmlCommands.rename_element(_session, _locator(), tag), "inspector")
		"attr":
			var v := String(value)
			var cur = _node.get_attribute(f["name"])
			if (cur == null and v.is_empty()) or (cur != null and String(cur) == v):
				return
			command.emit(EdUxmlCommands.set_attribute(_session, _locator(), f["name"], v), "inspector")
		"state":
			set_state(f["name"], bool(value))
		"style":
			var v := String(value).strip_edges()
			show_property(f["name"])
			var inline_value := ""
			for r in _node.attributes_named("style"):
				for d in EdUssSource.parse_declarations(_session.source(), r["value_start"], r["value_end"]):
					if d["property"] == f["name"]:
						inline_value = EdUxmlSource.decode_entities(d["raw"])
			if v == inline_value:
				return
			write_style(f["name"], v, doc.get_native(field))


## Force pseudo-state `state` on the selection, or release it.
func set_state(state: String, on: bool) -> void:
	if _node == null or _host == null:
		return
	var s := states()
	if on and not s.has(state):
		s.append(state)
	elif not on:
		s.erase(state)
	_host.set_forced(_node.id, s)
	states_changed.emit(_node.id, _host.forced_of(_node.id))
	if not _pending:
		_pending = true
		_rebuild.call_deferred()


func _on_button(button: String) -> void:
	if _node == null:
		return
	match button:
		"add-attr":
			var nm := _text_of("new-attr-name").strip_edges()
			if not nm.is_empty():
				command.emit(EdUxmlCommands.set_attribute(_session, _locator(), nm, _text_of("new-attr-value")), "inspector")
			return
		"pick-attr":
			var names: Array = []
			for a in EdElementCatalog.attributes_of(_node.local):
				if _node.get_attribute(a["name"]) == null and a["name"] != "style":
					names.append(a["name"])
			_menu(doc.get_native("pick-attr"), names, _pick_attr)
			return
		"add-style":
			var prop := _text_of("new-style-name").strip_edges()
			var val := _text_of("new-style-value").strip_edges()
			if not prop.is_empty() and not val.is_empty():
				show_property(prop)
				write_style(prop, val, doc.get_native("add-style"))
			return
		"add-class":
			var c := _text_of("new-class").strip_edges()
			if not c.is_empty():
				command.emit(EdProvenance.add_class(_session, _locator(), c), "inspector")
				_set_text_of("new-class", "")
			return
	if not _fields.has(button):
		return
	var f: Dictionary = _fields[button]
	match String(f["kind"]):
		"attr":
			command.emit(EdUxmlCommands.remove_attribute(_session, _locator(), f["name"]), "inspector")
		"style":
			show_property(f["name"])
			write_style(f["name"], "", doc.get_native(button))
		"class":
			command.emit(EdProvenance.remove_class(_session, _locator(), f["name"]), "inspector")
		"class-rules":
			for c in classes:
				if c["name"] == f["name"] and not c["rules"].is_empty():
					var r: Dictionary = c["rules"][0]
					jump_requested.emit(r["path"], r["start"], r["end"])
		"prov":
			open_provenance(int(f["name"]))
		"pick":
			_on_helper(button)


## Show the source of declaration row `i` of the list (or select the
## element an inherited value comes from).
func open_provenance(i: int) -> void:
	if i < 0 or i >= provenance.size():
		return
	var r: Dictionary = provenance[i]
	if int(r["select_id"]) >= 0:
		select_requested.emit(int(r["select_id"]))
	elif not String(r["path"]).is_empty() and int(r["start"]) >= 0:
		jump_requested.emit(r["path"], r["start"], r["end"])


## An attribute of the catalog menu: its name goes to the add row, its
## hint to the value field.
func _pick_attr(nm: String) -> void:
	_set_text_of("new-attr-name", nm)
	var hint := attribute_hint(_node.local, nm)
	var vc := doc.get_native("new-attr-value") as LineEdit
	if vc != null:
		vc.placeholder_text = "value" if hint.is_empty() else hint
		vc.grab_focus()


func _text_of(field: String) -> String:
	var c := doc.get_native(field)
	if c is LineEdit:
		return (c as LineEdit).text
	if c is TextEdit:
		return (c as TextEdit).text
	return ""


func _set_text_of(field: String, text: String) -> void:
	var c := doc.get_native(field) as LineEdit
	if c != null:
		c.text = text
	_silent(field, "value", text)
