class_name EdRenderHost
extends SubViewport
## The live godot-uxml render of one document, built from the editor's
## source buffers.
##
## render() reloads the whole document from the current buffer text (a
## partial reload is godot-uxml request R4). After each render the host maps
## every authored element of the entry file to its rendered control by the
## open tag offset, which the editor parser and the godot-uxml parser agree
## on (tests/unit/test_source_parsers.gd).

signal rendered

const THEMES := ["auto", "runtime", "editor-dark", "editor-light"]

var doc: UxmlDocument = null
## editor node id -> UxmlElement (authored elements of the entry file)
var element_for_node: Dictionary = {}
## UxmlElement -> editor node id
var node_for_element: Dictionary = {}
## Diagnostics of the last render (UxmlDiagnostic dictionaries).
var diagnostics: Array = []
var theme_mode: String = "auto"
var last_render_ms: float = 0.0
var entry_path: String = ""
var _root: String = ""
## EdBufferResolver.key(absolute path) -> workspace path, for every buffer.
var _paths_by_key: Dictionary = {}


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


## The document fills the viewport through its anchors.
func set_screen_size(s: Vector2i) -> void:
	size = s


## Render `entry` (a workspace path) of `ws` from project directory
## `root_abs`. Buffers of open .uss/.uxml files override the disk files.
func render(ws: EdWorkspace, entry: String, root_abs: String) -> void:
	var t0 := Time.get_ticks_usec()
	entry_path = entry
	_root = root_abs
	if doc == null:
		_make_doc()
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
	var resolver := EdBufferResolver.new(root_abs)
	_paths_by_key.clear()
	for p in ws.buffers:
		resolver.set_override(root_abs + "/" + p, ws.text(p))
		_paths_by_key[EdBufferResolver.key(root_abs + "/" + p)] = p
	_load_source(ws.text(entry), root_abs + "/" + entry, resolver)
	_map(ws.uxml(entry))
	last_render_ms = (Time.get_ticks_usec() - t0) / 1000.0
	rendered.emit()


## UxmlDocument.load_source() with our resolver. Mirrors the godot-uxml
## method of the pinned commit; request R1 replaces it.
func _load_source(uxml: String, virtual_path: String, resolver: UxmlResourceResolver) -> void:
	if doc._doc != null:
		doc._attrs.capture_view_data()
	doc._clear()
	doc._resolver = resolver
	doc._doc = UxmlLoader.load_source(uxml, virtual_path, resolver)
	doc._effective_root = resolver.project_root
	UxmlTheme.attach(doc._doc, doc.theme_path, doc.editor_theme, doc.editor_skin)
	doc._index()
	doc._restyle_now()
	doc._attrs.restore_view_data()
	diagnostics = doc.diagnostics.duplicate()
	doc.loaded.emit(true)


func _map(tree: EdUxmlSource) -> void:
	element_for_node.clear()
	node_for_element.clear()
	if doc._doc == null or doc._doc.root == null or tree == null:
		return
	var by_offset := {}
	for el in doc._doc.root.walk():
		if el.part_of != null or doc._doc.element_paths.has(el):
			continue
		by_offset[el.open_tag_start] = el
	for n in tree.nodes:
		var el = by_offset.get(n.open_start)
		if el != null and el.tag() == n.name:
			element_for_node[n.id] = el
			node_for_element[el] = n.id


## The control that draws editor node `id`, or null (non-visual, hidden,
## or not rendered).
func control_of(id: int) -> Control:
	var el = element_for_node.get(id)
	if el == null:
		return null
	var c = doc._controls.get(el)
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		return null
	return c


## The rectangle of editor node `id` in screen (viewport) pixels.
func rect_of(id: int) -> Rect2:
	var c := control_of(id)
	if c == null or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()


## The deepest authored element under `point` (viewport pixels), or -1.
## Elements with picking-mode="Ignore" still hit: the editor selects what
## the author wrote, not what the game would pick.
## Workaround for request R8: the point is tested in the local space of
## each control (so rotate, scale and translate apply, as godot-uxml sets
## them on the Control transform) and of every clipping ancestor.
func hit_test(point: Vector2) -> int:
	var best := -1
	var best_depth := -1
	for id in element_for_node:
		var c := control_of(id)
		if c == null or not c.is_visible_in_tree():
			continue
		if not _hits(c, point):
			continue
		var depth := _depth(element_for_node[id])
		if depth > best_depth or (depth == best_depth and id > best):
			best = id
			best_depth = depth
	return best


## True when `point` is inside `c` and inside every clipping ancestor
## (ScrollView viewports, overflow: hidden), transforms applied.
func _hits(c: Control, point: Vector2) -> bool:
	if not _local_has(c, point):
		return false
	var p := c.get_parent()
	while p != null and p != doc and p is Control:
		var pc := p as Control
		if pc.clip_contents and not _local_has(pc, point):
			return false
		p = p.get_parent()
	return true


static func _local_has(c: Control, point: Vector2) -> bool:
	var local := c.get_global_transform().affine_inverse() * point
	return Rect2(Vector2.ZERO, c.size).has_point(local)


func _depth(el: UxmlElement) -> int:
	var d := 0
	var p = doc._parents.get(el)
	while p != null:
		d += 1
		p = doc._parents.get(p)
	return d


## The computed style of editor node `id` (godot-uxml cascade output).
## Workaround: godot-uxml looks up computed styles by name only (request R2).
func computed_style(id: int) -> Dictionary:
	var el = element_for_node.get(id)
	if el == null:
		return {}
	return doc._styles.get(el, {})


## The editor node id of the authored parent of `id` (-1 for the root or
## an unmapped parent).
func parent_id(id: int) -> int:
	var el = element_for_node.get(id)
	if el == null:
		return -1
	var p = doc._parents.get(el)
	while p != null:
		if node_for_element.has(p):
			return node_for_element[p]
		p = doc._parents.get(p)
	return -1


## The computed style of `id` for EdLayoutCommands: property ->
## {value: String, origin}. Origins are normalized: a rule of a project
## stylesheet becomes {kind: "rule", path: <workspace path>, item,
## decl_index, states}; a rule of a godot-uxml theme becomes
## {kind: "theme"}; inline and inherited keep their shape.
## Seam for requests R2 and R5: the cascade output is read from the
## document internals today.
func style_facts(id: int) -> Dictionary:
	var out := {}
	var cs := computed_style(id)
	for prop in cs:
		var e = cs[prop]
		if typeof(e) != TYPE_DICTIONARY:
			out[prop] = {"value": str(e), "origin": {"kind": "default"}}
			continue
		out[prop] = {"value": str(e.get("value", "")), "origin": _normalize_origin(e.get("origin", {}))}
	return out


func _normalize_origin(o: Variant) -> Dictionary:
	if typeof(o) != TYPE_DICTIONARY:
		return {"kind": "default"}
	match String(o.get("kind", "")):
		"rule":
			var path := workspace_path(String(o.get("file", "")))
			if path.is_empty():
				return {"kind": "theme"}
			var r := {"kind": "rule", "path": path, "item": int(o.get("item", -1)), "decl_index": int(o.get("decl_index", -1))}
			if o.has("states"):
				r["states"] = (o["states"] as Array).duplicate()
			return r
		"inline":
			return {"kind": "inline", "decl_index": int(o.get("decl_index", -1))}
		"inherited":
			return {"kind": "inherited", "origin": _normalize_origin(o.get("origin", {}))}
	return {"kind": "default"}


## The workspace path of a file that the render read, or "" when the file
## is not in the project (a godot-uxml theme).
func workspace_path(file: String) -> String:
	if file.is_empty():
		return ""
	return _paths_by_key.get(EdBufferResolver.key(file), "")


## The border widths (left, top) of `id` in px.
func border_start(id: int) -> Vector2:
	var cs := computed_style(id)
	return Vector2(float(EdLayoutCommands.px(cs.get("border-left-width")) if EdLayoutCommands.px(cs.get("border-left-width")) != null else 0.0),
		float(EdLayoutCommands.px(cs.get("border-top-width")) if EdLayoutCommands.px(cs.get("border-top-width")) != null else 0.0))


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
