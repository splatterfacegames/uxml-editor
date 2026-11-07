class_name EdDragController
extends Control
## Drag and drop between the views: a library element to the canvas or the
## hierarchy (insert), and hierarchy elements to the canvas or the
## hierarchy (move: reorder or reparent).
##
## godot-uxml runs the drag (request R12): the library and the hierarchy
## TreeViews get Unity's four drag-and-drop callbacks
## (UxmlDocument.set_drag_and_drop). A drag starts after 5 pixels; the
## pressed row keeps the mouse until the release. Over the hierarchy,
## godot-uxml gives the drop arguments: the 5-pixel bands at the top and
## the bottom of a row drop between items (the parent and the child index
## come from the tree), the rest of a row drops over the item. Over a
## container the drop goes into the container, at the end. Over an element
## that takes no children the drop goes before the row (the upper half) or
## after it (the lower half). Outside every collection, items_drag_updated
## and items_drag_ended give an empty target and "outside": the canvas
## takes the drop at the deepest container under the pointer, at the
## child index along its flex direction.
##
## Native Godot control: this full-window Control draws the drag title and
## the drop line of a before/after drop over a leaf row over the
## godot-uxml shell. godot-uxml draws the drop indicator of a collection
## (a bar between items, an outline over an item) but not the title at the
## pointer. It ignores the mouse.

signal dropped(payload: Dictionary, target: Dictionary)

const DROP := Color(1.0, 0.7, 0.2)
const PALETTE := "palette-tree"
const HIERARCHY := "hierarchy-tree"

var shell: UxmlDocument
var canvas: EdCanvasView
var state: EdEditorState
var palette: EdPaletteView

## {kind: "palette", entry, label} or {kind: "nodes", locs, label}
var payload: Dictionary = {}
## {where: "canvas"|"hierarchy", parent: EdUxmlNode, index: int,
##  line: [Vector2, Vector2] (global), rect: Rect2 (global)}
var target: Dictionary = {}
## The result of the last drag ("dropped", "rejected", "outside",
## "canceled"; tests).
var last_result := ""
var _mouse := Vector2.ZERO
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


## Give the library and the hierarchy their callbacks and connect the drag
## signals of the shell. After each load of the shell.
func attach() -> void:
	shell.set_drag_and_drop(PALETTE, {
		"can_start_drag": func(a): return not palette.entry_at(int(a["index"])).is_empty(),
		"setup_drag_and_drop": _setup,
		"drag_and_drop_update": func(_a): return UxmlDocument.DragVisualMode.REJECTED,
	})
	shell.set_drag_and_drop(HIERARCHY, {
		"can_start_drag": _can_start_hierarchy,
		"setup_drag_and_drop": _setup,
		"drag_and_drop_update": _hierarchy_update,
		"handle_drop": _hierarchy_drop,
	})
	if not shell.items_drag_started.is_connected(_on_started):
		shell.items_drag_started.connect(_on_started)
		shell.items_drag_updated.connect(_on_updated)
		shell.items_drag_ended.connect(_on_ended)


func is_dragging() -> bool:
	return not payload.is_empty()


## Escape cancels a drag (godot-uxml also cancels on Escape in the focused
## list). Returns true when the event was used.
func handle_input(ev: InputEvent) -> bool:
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE and is_dragging():
		shell.cancel_drag()
		return true
	return false


func cancel() -> void:
	if not shell.get_drag().is_empty():
		shell.cancel_drag()
	_clear()


func _clear() -> void:
	payload = {}
	target = {}
	canvas.drop_hint = {}
	queue_redraw()


# ---------------------------------------------------------------------------
# Sources (Unity canStartDrag, setupDragAndDrop)
# ---------------------------------------------------------------------------

## What a drag of `args` (the godot-uxml drag arguments) takes.
func payload_for(list: String, args: Dictionary) -> Dictionary:
	if state.session == null:
		return {}
	if list == PALETTE:
		var e := palette.entry_at(int(args["index"]))
		if e.is_empty():
			return {}
		return {"kind": "palette", "entry": e, "label": "+ " + String(e["name"])}
	var t := state.session.tree()
	var nodes: Array = []
	for id in args.get("ids", []):
		var i := int(id)
		if i >= 0 and i < t.nodes.size() and t.nodes[i].parent != null:
			nodes.append(t.nodes[i])
	nodes = EdStructureCommands.top_level(nodes)
	if nodes.is_empty():
		return {}
	var locs: Array = nodes.map(func(n): return EdLocator.create(n))
	return {"kind": "nodes", "locs": locs, "label": "Move %s" % nodes[0].local if nodes.size() == 1 else "Move %d elements" % nodes.size()}


func _can_start_hierarchy(a: Dictionary) -> bool:
	return not payload_for(HIERARCHY, a).is_empty()


func _setup(a: Dictionary) -> Dictionary:
	var p := payload_for(String(a["element_name"]), a)
	return {"title": p.get("label", ""), "data": p}


func _on_started(_list: String, _indices: Array, at: Vector2) -> void:
	var d := shell.get_drag()
	payload = d.get("data", {}) if d.get("data") is Dictionary else {}
	_mouse = at
	queue_redraw()


# ---------------------------------------------------------------------------
# Targets (Unity dragAndDropUpdate, handleDrop)
# ---------------------------------------------------------------------------

func _hierarchy_update(a: Dictionary) -> int:
	if payload.is_empty() and a.get("data") is Dictionary:
		payload = a["data"]
	var t := hierarchy_target(a)
	if t.is_empty() or not _valid(t):
		return UxmlDocument.DragVisualMode.REJECTED
	return UxmlDocument.DragVisualMode.COPY if payload_kind(a) == "palette" else UxmlDocument.DragVisualMode.MOVE


func _hierarchy_drop(a: Dictionary) -> int:
	var t := hierarchy_target(a)
	if t.is_empty() or not _valid(t):
		return UxmlDocument.DragVisualMode.REJECTED
	var p: Dictionary = a.get("data", {}) if a.get("data") is Dictionary else payload
	dropped.emit(p, t)
	return UxmlDocument.DragVisualMode.COPY if p.get("kind") == "palette" else UxmlDocument.DragVisualMode.MOVE


static func payload_kind(a: Dictionary) -> String:
	var d = a.get("data")
	return String(d.get("kind", "")) if d is Dictionary else ""


func _on_updated(_list: String, at: Vector2, drop: Dictionary) -> void:
	_mouse = at
	if drop.is_empty():
		target = canvas_target(at)
		if not target.is_empty() and not _valid(target):
			target = {}
	elif String(drop.get("element_name", "")) == HIERARCHY and int(drop.get("visual_mode", 0)) != UxmlDocument.DragVisualMode.REJECTED:
		target = hierarchy_target(drop)
	else:
		target = {}
	if not target.is_empty() and target["where"] == "canvas":
		canvas.drop_hint = {"rect": target["doc_rect"], "line": target["doc_line"]}
	else:
		canvas.drop_hint = {}
	queue_redraw()


func _on_ended(_list: String, at: Vector2, result: String) -> void:
	last_result = result
	if result == "outside" and not payload.is_empty():
		var t := canvas_target(at)
		if not t.is_empty() and _valid(t):
			dropped.emit(payload, t)
	_clear()


## A move may not go into a moved element or below it.
func _valid(t: Dictionary) -> bool:
	if payload.get("kind") != "nodes":
		return true
	var parent: EdUxmlNode = t["parent"]
	for l in payload["locs"]:
		var n := state.session.resolve(l)
		if n == null or n.contains(parent):
			return false
	return true


func _tree_node(index: int) -> EdUxmlNode:
	var item := shell.get_tree_item(HIERARCHY, index)
	if item.is_empty() or state.session == null:
		return null
	return _node_by_id(int(item["id"]))


func _node_by_id(id: int) -> EdUxmlNode:
	var t := state.session.tree()
	return t.nodes[id] if id >= 0 and id < t.nodes.size() else null


## The drop of godot-uxml drop arguments `a` over the hierarchy.
func hierarchy_target(a: Dictionary) -> Dictionary:
	if state.session == null:
		return {}
	var root := state.session.root()
	if root == null:
		return {}
	var whole := Rect2()
	var lc := shell.get_element(HIERARCHY)
	if lc != null:
		whole = lc.get_global_rect()
	match int(a.get("drop_position", UxmlDocument.DragPosition.OUTSIDE_ITEMS)):
		UxmlDocument.DragPosition.OVER_ITEM:
			var n := _tree_node(int(a["index"]))
			if n == null:
				return {}
			var rr := shell.get_item_rect(HIERARCHY, int(a["index"]))
			if n.parent == null or EdElementCatalog.accepts_children(n):
				return {"where": "hierarchy", "parent": n, "index": n.children.size(), "line": [], "rect": rr}
			var pos: Vector2 = a.get("position", rr.get_center())
			if pos.y < rr.get_center().y:
				return {"where": "hierarchy", "parent": n.parent, "index": n.index_in_parent,
					"line": [rr.position, Vector2(rr.end.x, rr.position.y)], "rect": Rect2()}
			return {"where": "hierarchy", "parent": n.parent, "index": n.index_in_parent + 1,
				"line": [Vector2(rr.position.x, rr.end.y), rr.end], "rect": Rect2()}
		UxmlDocument.DragPosition.BETWEEN_ITEMS:
			var pid = a.get("parent_id")
			var ci := int(a.get("child_index", -1))
			if pid == null:
				# Before or after the UXML root: the start or the end of the root.
				return {"where": "hierarchy", "parent": root, "index": 0 if ci == 0 else root.children.size(), "line": [], "rect": Rect2()}
			var p := _node_by_id(int(pid))
			if p == null:
				return {}
			return {"where": "hierarchy", "parent": p, "index": p.children.size() if ci < 0 else mini(ci, p.children.size()), "line": [], "rect": Rect2()}
	return {"where": "hierarchy", "parent": root, "index": root.children.size(), "line": [], "rect": whole}


func canvas_target(pos: Vector2) -> Dictionary:
	if not canvas.is_visible_in_tree() or not canvas.get_global_rect().has_point(pos) or state.session == null:
		return {}
	var root := state.session.root()
	if root == null:
		return {}
	var sp := canvas.global_to_screen(pos)
	var screen := Rect2(Vector2.ZERO, canvas.screen_size())
	if not screen.has_point(sp):
		return {}
	var id := canvas.hit(sp)
	var t := state.session.tree()
	var n: EdUxmlNode = t.nodes[id] if id >= 0 and id < t.nodes.size() else root
	while n != null and not EdElementCatalog.accepts_children(n):
		n = n.parent
	if payload.get("kind") == "nodes":
		for l in payload["locs"]:
			var moved := state.session.resolve(l)
			while moved != null and n != null and moved.contains(n):
				n = moved.parent
	if n == null:
		n = root
	var host := canvas.host
	var crect := host.rect_of(n.id) if n.parent != null else screen
	if crect.size == Vector2.ZERO:
		crect = screen
	var dir := "column"
	if n.parent != null:
		dir = String(host.computed_style(n.id).get("flex-direction", {}).get("value", "column"))
	var row := dir.begins_with("row")
	var reverse := dir.ends_with("reverse")
	var index := n.children.size()
	var line: Array = []
	var last_rect := Rect2()
	for c in n.children:
		var cr := host.rect_of(c.id)
		if cr.size == Vector2.ZERO:
			continue
		last_rect = cr
		var before: bool
		if row:
			before = (sp.x < cr.get_center().x) != reverse
		else:
			before = (sp.y < cr.get_center().y) != reverse
		if before:
			index = c.index_in_parent
			line = _edge_line(cr, row, reverse, true)
			break
	if line.is_empty():
		if last_rect.size != Vector2.ZERO:
			line = _edge_line(last_rect, row, reverse, false)
		else:
			line = _edge_line(crect.grow(-4), row, reverse, true)
	return {"where": "canvas", "parent": n, "index": index, "doc_rect": crect, "doc_line": line, "line": [], "rect": Rect2()}


## The leading (or trailing) edge of `r` along the flex direction.
static func _edge_line(r: Rect2, row: bool, reverse: bool, leading: bool) -> Array:
	var start_side := leading != reverse
	if row:
		var x := r.position.x if start_side else r.end.x
		return [Vector2(x, r.position.y), Vector2(x, r.end.y)]
	var y := r.position.y if start_side else r.end.y
	return [Vector2(r.position.x, y), Vector2(r.end.x, y)]


# ---------------------------------------------------------------------------

func _draw() -> void:
	if not is_dragging():
		return
	var inv := get_global_transform().affine_inverse()
	if not target.is_empty() and target["where"] == "hierarchy":
		var line: Array = target["line"]
		if line.size() == 2:
			draw_line(inv * line[0], inv * line[1], DROP, 2.0)
	var label: String = payload.get("label", "")
	if target.is_empty():
		label += "  (no drop here)"
	var fs := 12
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12
	var p := inv * _mouse + Vector2(14, 10)
	draw_rect(Rect2(p, Vector2(w, 18)), Color(0.15, 0.15, 0.15, 0.92))
	draw_rect(Rect2(p, Vector2(w, 18)), DROP if not target.is_empty() else Color(0.6, 0.6, 0.6), false, 1.0)
	draw_string(_font, p + Vector2(6, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
