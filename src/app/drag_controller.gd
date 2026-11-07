class_name EdDragController
extends Control
## Drag and drop between the views: a palette element to the canvas or the
## hierarchy (insert), and hierarchy elements to the canvas or the
## hierarchy (move: reorder or reparent).
##
## The controller watches the raw mouse events of the window (EdMain
## forwards them from _input) and never takes the press, so the lists
## still select. A drag starts after DRAG_START pixels. The drop position
## comes from the row under the pointer (hierarchy: the top quarter drops
## before, the bottom quarter after, the middle into a container) or from
## the element under the pointer (canvas: the deepest container, and the
## child index along its flex direction).
##
## Native Godot control: this full-window Control draws the drag label and
## the hierarchy drop line over the godot-uxml shell (godot-uxml has no
## drag-and-drop API; request R12). It ignores the mouse.

signal dropped(payload: Dictionary, target: Dictionary)

const DRAG_START := 6.0
const DROP := Color(1.0, 0.7, 0.2)

var shell: UxmlDocument
var canvas: EdCanvasView
var state: EdEditorState
var palette: EdPaletteView

## {kind: "palette", entry, label} or {kind: "nodes", locs, label}
var payload: Dictionary = {}
## {where: "canvas"|"hierarchy", parent: EdUxmlNode, index: int,
##  line: [Vector2, Vector2] (global), rect: Rect2 (global)}
var target: Dictionary = {}
var _press: Dictionary = {}
var _mouse := Vector2.ZERO
var _font: Font


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func is_dragging() -> bool:
	return not payload.is_empty()


## Returns true when the event was used (the drop release).
func handle_input(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return false
		if mb.pressed:
			_press = {}
			var p := payload_at(mb.global_position)
			if not p.is_empty():
				_press = {"pos": mb.global_position, "payload": p}
			return false
		var was := is_dragging()
		if was:
			_update_target(mb.global_position)
			if not target.is_empty():
				dropped.emit(payload, target)
		cancel()
		return was
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_mouse = mm.global_position
		if not is_dragging() and not _press.is_empty() and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
				and mm.global_position.distance_to(_press["pos"]) >= DRAG_START:
			begin(_press["payload"])
		if is_dragging():
			_update_target(mm.global_position)
			return true
		return false
	if ev is InputEventKey and (ev as InputEventKey).pressed and (ev as InputEventKey).keycode == KEY_ESCAPE and is_dragging():
		cancel()
		return true
	return false


func begin(p: Dictionary) -> void:
	payload = p
	_press = {}
	queue_redraw()


func cancel() -> void:
	payload = {}
	target = {}
	_press = {}
	canvas.drop_hint = {}
	queue_redraw()


# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------

## What a press at `pos` would drag: a palette element, the hierarchy
## selection (when the press is on a selected row) or the pressed row.
func payload_at(pos: Vector2) -> Dictionary:
	if state.session == null:
		return {}
	var r := row_at("palette-tree", pos)
	if not r.is_empty():
		var e := palette.entry_at(r["index"])
		if not e.is_empty():
			return {"kind": "palette", "entry": e, "label": "+ " + String(e["name"])}
		return {}
	r = row_at("hierarchy-tree", pos)
	if not r.is_empty():
		var n := _tree_node(r["index"])
		if n == null or n.parent == null:
			return {}
		var locs: Array = [EdLocator.create(n)]
		for l in state.selection:
			if state.session.resolve(l) == n:
				locs = state.selection.duplicate(true)
				break
		return {"kind": "nodes", "locs": locs, "label": "Move %s" % n.local if locs.size() == 1 else "Move %d elements" % locs.size()}
	return {}


## {index, rect} of the bound row of collection `list` at global `pos`.
## Uses only public godot-uxml calls: get_list_rows() and
## UxmlListRow.get_element().
func row_at(list: String, pos: Vector2) -> Dictionary:
	var lc := shell.get_element(list)
	if lc == null or not lc.is_visible_in_tree() or not lc.get_global_rect().has_point(pos):
		return {}
	for row in shell.get_list_rows(list):
		var ur := row as UxmlListRow
		if ur == null or ur.index < 0:
			continue
		var c := ur.get_element()
		if c == null or not c.is_visible_in_tree():
			continue
		var rr := c.get_global_rect()
		if rr.has_point(pos):
			return {"index": ur.index, "rect": rr}
	return {}


func _tree_node(index: int) -> EdUxmlNode:
	var item := shell.get_tree_item("hierarchy-tree", index)
	if item.is_empty() or state.session == null:
		return null
	var t := state.session.tree()
	var id := int(item["id"])
	return t.nodes[id] if id >= 0 and id < t.nodes.size() else null


# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

func _update_target(pos: Vector2) -> void:
	_mouse = pos
	target = hierarchy_target(pos)
	if target.is_empty():
		target = canvas_target(pos)
	if not target.is_empty() and not _valid(target):
		target = {}
	if not target.is_empty() and target["where"] == "canvas":
		canvas.drop_hint = {"rect": target["doc_rect"], "line": target["doc_line"]}
	else:
		canvas.drop_hint = {}
	queue_redraw()


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


func hierarchy_target(pos: Vector2) -> Dictionary:
	var lc := shell.get_element("hierarchy-tree")
	if lc == null or not lc.get_global_rect().has_point(pos) or state.session == null:
		return {}
	var root := state.session.root()
	if root == null:
		return {}
	var r := row_at("hierarchy-tree", pos)
	if r.is_empty():
		var lr := lc.get_global_rect()
		return {"where": "hierarchy", "parent": root, "index": root.children.size(),
			"line": [], "rect": lr}
	var n := _tree_node(r["index"])
	if n == null:
		return {}
	var rr: Rect2 = r["rect"]
	var f := (pos.y - rr.position.y) / maxf(rr.size.y, 1.0)
	var top := [rr.position, Vector2(rr.end.x, rr.position.y)]
	var bottom := [Vector2(rr.position.x, rr.end.y), rr.end]
	if n.parent == null:
		return {"where": "hierarchy", "parent": n, "index": n.children.size(), "line": [], "rect": rr}
	var container := EdElementCatalog.accepts_children(n)
	if f < 0.25 or (not container and f < 0.5):
		return {"where": "hierarchy", "parent": n.parent, "index": n.index_in_parent, "line": top, "rect": Rect2()}
	if f > 0.75 or not container:
		return {"where": "hierarchy", "parent": n.parent, "index": n.index_in_parent + 1, "line": bottom, "rect": Rect2()}
	return {"where": "hierarchy", "parent": n, "index": n.children.size(), "line": [], "rect": rr}


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
		var r: Rect2 = target["rect"]
		if r.size != Vector2.ZERO:
			draw_rect(Rect2(inv * r.position, r.size), DROP, false, 1.0)
	var label: String = payload.get("label", "")
	if target.is_empty():
		label += "  (no drop here)"
	var fs := 12
	var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12
	var p := inv * _mouse + Vector2(14, 10)
	draw_rect(Rect2(p, Vector2(w, 18)), Color(0.15, 0.15, 0.15, 0.92))
	draw_rect(Rect2(p, Vector2(w, 18)), DROP if not target.is_empty() else Color(0.6, 0.6, 0.6), false, 1.0)
	draw_string(_font, p + Vector2(6, 13), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
