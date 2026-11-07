class_name EdRenderHost
extends SubViewport
## The live godot-uxml render of one document, built from the editor's
## source buffers.
##
## render() loads the whole document through an EdBufferResolver
## (UxmlDocument.load_source with a resolver, request R1). update() brings
## the render up to date after an edit without a full load where
## godot-uxml can: reload_stylesheet() for a USS buffer, replace_source()
## for the entry buffer (in place when only `class` and `style` changed,
## request R4). After each render or update the host maps every authored
## element of the entry file to its UxmlElement by the open tag offset,
## which the editor parser and the godot-uxml parser agree on (request R3;
## tests/unit/test_source_parsers.gd).
##
## Every lookup goes through the public editor APIs of godot-uxml: element
## handles (R2), provenance (R5), forced states (R6), the hit test (R8),
## template instances (R10) and element rectangles (R14).

signal rendered

const THEMES := ["auto", "runtime", "editor-dark", "editor-light"]
## The pseudo-states that the state preview can force (R6).
const FORCEABLE := ["hover", "active", "focus", "checked", "selected", "disabled", "enabled"]

var doc: UxmlDocument = null
## editor node id -> UxmlElement (authored elements of the entry file)
var element_for_node: Dictionary = {}
## UxmlElement -> editor node id
var node_for_element: Dictionary = {}
## Diagnostics of the last render (UxmlDiagnostic dictionaries).
var diagnostics: Array = []
var theme_mode: String = "auto"
var last_render_ms: float = 0.0
## Number of full loads and of partial updates (in-place source replaces
## and stylesheet reloads; tests and the benchmark).
var renders := 0
var patches := 0
## The last update kept the controls (an in-place replace or a stylesheet
## reload only).
var last_was_patch := false
var entry_path: String = ""
var _root: String = ""
var _theme_loaded := ""
var _resolver: EdBufferResolver = null
## EdBufferResolver.key(absolute path) -> workspace path, for every buffer.
var _paths_by_key: Dictionary = {}
## workspace path -> text given to the render (to find the changed buffers).
var _texts: Dictionary = {}
## node id -> forced states, applied again after a full load.
var forced: Dictionary = {}


func _init() -> void:
	transparent_bg = false
	disable_3d = true
	gui_snap_controls_to_pixels = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	handle_input_locally = true
	size = Vector2i(1280, 720)


func _ready() -> void:
	_make_doc()


func _make_doc() -> void:
	if doc != null:
		doc.queue_free()
	doc = UxmlDocument.new()
	doc.auto_load = false
	doc.name = "Document"
	doc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(doc)


## Show nothing (the last tab closed).
func clear() -> void:
	_make_doc()
	element_for_node.clear()
	node_for_element.clear()
	diagnostics = []
	entry_path = ""
	_texts.clear()
	forced.clear()


func is_loaded() -> bool:
	return doc != null and doc.get_document_model() != null


## The document fills the viewport through its anchors.
func set_screen_size(s: Vector2i) -> void:
	size = s


func _apply_theme() -> void:
	match theme_mode:
		"editor-dark":
			doc.editor_theme = "always"
			doc.editor_skin = "dark"
		"editor-light":
			doc.editor_theme = "always"
			doc.editor_skin = "light"
		"runtime":
			doc.editor_theme = "never"
			doc.editor_skin = "dark"
		_:
			# Unity's choice: the editor look for documents with editor
			# (uie:) controls, the runtime theme for the rest.
			doc.editor_theme = "auto"
			doc.editor_skin = "dark"


## Render `entry` (a workspace path) of `ws` from project directory
## `root_abs`. Buffers of open .uss/.uxml files override the disk files.
func render(ws: EdWorkspace, entry: String, root_abs: String) -> void:
	var t0 := Time.get_ticks_usec()
	if entry != entry_path:
		forced.clear()
	entry_path = entry
	_root = root_abs
	if doc == null:
		_make_doc()
	_apply_theme()
	_theme_loaded = theme_mode
	_resolver = EdBufferResolver.new(root_abs)
	_paths_by_key.clear()
	_texts.clear()
	for p in ws.buffers:
		var text := ws.text(p)
		_resolver.set_override(root_abs + "/" + p, text)
		_paths_by_key[EdBufferResolver.key(root_abs + "/" + p)] = p
		_texts[p] = text
	doc.load_source(ws.text(entry), root_abs + "/" + entry, "", _resolver)
	_after_load(ws, entry, false)
	renders += 1
	last_render_ms = (Time.get_ticks_usec() - t0) / 1000.0
	rendered.emit()


## Bring the render up to date with the buffers of `ws` without a full
## load where godot-uxml can (request R4):
##
## - a changed stylesheet of the document: reload_stylesheet() (restyle,
##   the controls stay);
## - a changed entry buffer, or a changed template: replace_source(). It
##   edits in place when the trees match and only `class` and `style`
##   changed, else it loads again and keeps the view state.
##
## Returns false when a full render() is needed (no document, another
## entry, another theme, a buffer added or removed).
func update(ws: EdWorkspace, entry: String) -> bool:
	if not is_loaded() or entry != entry_path or _resolver == null or _theme_loaded != theme_mode:
		return false
	if ws.buffers.size() != _texts.size():
		return false
	var changed: Array = []
	for p in ws.buffers:
		if not _texts.has(p):
			return false
		var text := ws.text(p)
		if text != _texts[p]:
			changed.append(p)
	if changed.is_empty():
		return true
	var t0 := Time.get_ticks_usec()
	for p in changed:
		_texts[p] = ws.text(p)
		_resolver.set_override(_root + "/" + p, _texts[p])
	var replace := false
	var kept := true
	for p in changed:
		if p == entry or p.to_lower().ends_with(".uxml"):
			replace = true
			continue
		if p.to_lower().ends_with(".uss"):
			var err := doc.reload_stylesheet(_root + "/" + p, _texts[p])
			# ERR_DOES_NOT_EXIST: the document does not use the sheet.
			if err != OK and err != ERR_DOES_NOT_EXIST:
				return false
	if replace:
		var err := doc.replace_source(_texts[entry])
		if err != OK:
			return false
		kept = doc.get_last_replace_mode() == "in-place"
	_after_load(ws, entry, kept)
	if kept:
		patches += 1
	else:
		renders += 1
	last_render_ms = (Time.get_ticks_usec() - t0) / 1000.0
	rendered.emit()
	return true


func _after_load(ws: EdWorkspace, entry: String, kept: bool) -> void:
	last_was_patch = kept
	var model := doc.get_document_model()
	diagnostics = doc.diagnostics.duplicate()
	var old_forced := {}
	for id in forced:
		var el = element_for_node.get(id)
		if el != null:
			old_forced[id] = forced[id]
	_map(ws.uxml(entry), model)
	# A full load drops the forced states of godot-uxml; replace_source()
	# moves them. The editor keeps them by node id (the same source
	# structure gives the same ids).
	forced = {}
	for id in old_forced:
		if element_for_node.has(id):
			forced[id] = old_forced[id]
			if not kept:
				doc.set_forced_states(element_for_node[id], PackedStringArray(old_forced[id]))


func _map(tree: EdUxmlSource, model: UxmlDocumentModel) -> void:
	element_for_node.clear()
	node_for_element.clear()
	if model == null or model.root == null or tree == null:
		return
	var by_offset := {}
	for el in model.root.walk():
		# Control parts carry the offsets of their control element and
		# template clones the offsets of the outermost <Instance> (R3);
		# neither is authored in the entry file.
		if el.part_of != null or model.instance_of(el) != null:
			continue
		by_offset[el.open_tag_start] = el
	for n in tree.nodes:
		var el = by_offset.get(n.open_start)
		# An <Instance> is a TemplateContainer in the godot-uxml model.
		if el != null and (el.tag() == n.name or (n.local == "Instance" and el.local == "TemplateContainer")):
			element_for_node[n.id] = el
			node_for_element[el] = n.id


## The element that the editor shows for a rendered element: a control
## part answers for its control element, a template clone for the
## outermost instance in the entry file (R10), anything else for its
## nearest mapped ancestor. -1 when none.
func node_of(el: UxmlElement) -> int:
	var model := doc.get_document_model() if doc != null else null
	while el != null:
		while el.part_of != null:
			el = el.part_of
		if node_for_element.has(el):
			return node_for_element[el]
		var inst: UxmlElement = model.instance_of(el) if model != null else null
		el = inst if inst != null else doc.get_parent_element(el)
	return -1


## The control that draws editor node `id`, or null (non-visual, hidden,
## or not rendered).
func control_of(id: int) -> Control:
	var el = element_for_node.get(id)
	if el == null:
		return null
	var c := doc.get_control_for(el)
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		return null
	return c


## The bounding box of a box of editor node `id` in screen (viewport)
## pixels, transforms applied (R14). `box`: "border", "padding" or
## "content". Rect2() when the element has no layout.
func rect_of(id: int, box: String = "border") -> Rect2:
	var el = element_for_node.get(id)
	if el == null:
		return Rect2()
	return doc.get_element_rect(el, null, box)


## The transform from the local space of `id` (the top-left corner of its
## border box) to screen pixels, and its local size: {transform, size}, or
## {} when the element has no layout.
func local_box_of(id: int) -> Dictionary:
	var el = element_for_node.get(id)
	if el == null:
		return {}
	var t := doc.get_element_transform(el)
	if t.x == Vector2.ZERO and t.y == Vector2.ZERO:
		return {}
	return {"transform": t, "size": doc.get_element_rect(el, el).size}


## The deepest authored element under `point` (viewport pixels), or -1
## (request R8). Elements with picking-mode="Ignore" still hit: the editor
## selects what the author wrote, not what the game would pick. A hit on
## template content selects the instance.
func hit_test(point: Vector2) -> int:
	if not is_loaded():
		return -1
	var el := doc.element_at(point, false, false)
	if el == null:
		return -1
	return node_of(el)


## The computed style of editor node `id` (godot-uxml cascade output,
## property -> {value, origin}).
func computed_style(id: int) -> Dictionary:
	var el = element_for_node.get(id)
	if el == null:
		return {}
	return doc.get_computed_style_for(el)


## The editor node id of the authored parent of `id` (-1 for the root or
## an unmapped parent).
func parent_id(id: int) -> int:
	var el = element_for_node.get(id)
	if el == null:
		return -1
	var p := doc.get_parent_element(el)
	while p != null:
		if node_for_element.has(p):
			return node_for_element[p]
		p = doc.get_parent_element(p)
	return -1


## The computed style of `id` for EdLayoutCommands: property ->
## {value: String, origin}. Origins are normalized (normalize_origin()).
func style_facts(id: int) -> Dictionary:
	var out := {}
	var cs := computed_style(id)
	for prop in cs:
		var e = cs[prop]
		if typeof(e) != TYPE_DICTIONARY:
			out[prop] = {"value": str(e), "origin": {"kind": "default"}}
			continue
		out[prop] = {"value": str(e.get("value", "")), "origin": normalize_origin(e.get("origin", {}))}
	return out


## Every declaration of the longhand `property` that applies to `id`,
## winner first (UxmlDocument.explain_style, request R5), with normalized
## origins. `states`: pseudo-states for the query ({"hover": true}).
## Entry: {value, property, declared, status, rank, specificity, order,
## origin, raw_origin}.
func explain(id: int, property: String, states: Dictionary = {}) -> Array:
	var el = element_for_node.get(id)
	if el == null:
		return []
	var out: Array = []
	for e in doc.explain_style(el, property, states):
		var d: Dictionary = (e as Dictionary).duplicate()
		d["raw_origin"] = e.get("origin", {})
		d["origin"] = normalize_origin(e.get("origin", {}))
		if d["origin"]["kind"] == "inherited":
			var from = (e.get("origin", {}) as Dictionary).get("from")
			d["origin"]["from_id"] = node_of(from) if from is UxmlElement else -1
		out.append(d)
	return out


## A godot-uxml cascade origin in editor terms: a rule of a project
## stylesheet becomes {kind: "rule", path: <workspace path>, item,
## decl_index, states}; a rule of a godot-uxml theme becomes {kind:
## "theme", file, item}; inline, inherited and default keep their shape.
func normalize_origin(o: Variant) -> Dictionary:
	if typeof(o) != TYPE_DICTIONARY:
		return {"kind": "default"}
	match String(o.get("kind", "")):
		"rule":
			var path := workspace_path(String(o.get("file", "")))
			var states: Array = (o["states"] as Array).duplicate() if o.has("states") else []
			if path.is_empty():
				return {"kind": "theme", "file": String(o.get("file", "")), "item": int(o.get("item", -1)), "states": states}
			return {"kind": "rule", "path": path, "item": int(o.get("item", -1)), "decl_index": int(o.get("decl_index", -1)), "states": states}
		"inline":
			return {"kind": "inline", "decl_index": int(o.get("decl_index", -1))}
		"inherited":
			return {"kind": "inherited", "origin": normalize_origin(o.get("origin", {}))}
	return {"kind": "default"}


## The workspace path of a file that the render read, or "" when the file
## is not in the project (a godot-uxml theme).
func workspace_path(file: String) -> String:
	if file.is_empty():
		return ""
	return _paths_by_key.get(EdBufferResolver.key(file), "")


## The border widths (left, top) of `id` in px: the padding box in the
## element's own space (R14).
func border_start(id: int) -> Vector2:
	var el = element_for_node.get(id)
	if el == null:
		return Vector2.ZERO
	return doc.get_element_rect(el, el, "padding").position


## The rectangles of the rendered authored siblings of `id`.
func sibling_rects(id: int) -> Array:
	var pid := parent_id(id)
	var out: Array = []
	for other in element_for_node:
		if other == id or parent_id(other) != pid:
			continue
		var r := rect_of(other)
		if r.has_area():
			out.append(r)
	return out


# ---------------------------------------------------------------------------
# Forced pseudo-states (state preview, request R6)
# ---------------------------------------------------------------------------

## Keep `states` on editor node `id` until cleared (an empty Array removes
## them). The canvas render shows the states.
func set_forced(id: int, states: Array) -> void:
	var el = element_for_node.get(id)
	if el == null:
		return
	var kept: Array = []
	for s in FORCEABLE:
		if states.has(s):
			kept.append(s)
	if kept.is_empty():
		forced.erase(id)
	else:
		forced[id] = kept
	doc.set_forced_states(el, PackedStringArray(kept))


func forced_of(id: int) -> Array:
	return (forced.get(id, []) as Array).duplicate()


func clear_forced() -> void:
	forced.clear()
	if is_loaded():
		doc.clear_forced_states()
