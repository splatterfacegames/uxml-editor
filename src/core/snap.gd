class_name EdSnap
extends RefCounted
## Snapping for canvas gestures, in document pixels.
##
## Targets are the edges and centres of sibling elements and the edges and
## centre of the parent. An edge within `threshold` of a target snaps to
## it (the nearest target wins) and makes a guide. An edge that snaps to
## no target snaps to the pixel grid (`grid` px; 0 or 1 turns the grid
## off, values stay whole pixels).


## Snap targets from rectangles: {x: Array[float], y: Array[float]}.
static func targets(parent: Rect2, siblings: Array) -> Dictionary:
	var xs: Array = []
	var ys: Array = []
	if parent.size != Vector2.ZERO:
		xs.append_array([parent.position.x, parent.get_center().x, parent.end.x])
		ys.append_array([parent.position.y, parent.get_center().y, parent.end.y])
	for r in siblings:
		var rr: Rect2 = r
		xs.append_array([rr.position.x, rr.get_center().x, rr.end.x])
		ys.append_array([rr.position.y, rr.get_center().y, rr.end.y])
	return {"x": xs, "y": ys}


## Snap one coordinate. Returns {value, guide (the target or null)}.
static func snap_value(v: float, candidates: Array, grid: float, threshold: float) -> Dictionary:
	var best = null
	var best_d := threshold + 0.0001
	for t in candidates:
		var d := absf(float(t) - v)
		if d < best_d:
			best_d = d
			best = float(t)
	if best != null:
		return {"value": best, "guide": best}
	if grid > 1.0:
		return {"value": roundf(v / grid) * grid, "guide": null}
	return {"value": roundf(v), "guide": null}


## Snap a gesture. `rect` is the start rectangle, `handle` "move" or a
## resize handle, `delta` the raw pointer travel. Returns
## {delta: Vector2 (snapped travel), guides_x: Array, guides_y: Array}.
## A move snaps the left, centre or right edge, whichever is nearest a
## target, else the left/top edge to the grid. A resize snaps the edges
## that the handle moves.
static func snap_gesture(rect: Rect2, handle: String, delta: Vector2, tg: Dictionary, grid: float, threshold: float) -> Dictionary:
	var out := {"delta": delta, "guides_x": [], "guides_y": []}
	var moved := EdLayoutCommands.gesture_rect(rect, handle, delta)
	var ax := _axis(handle, true)
	var ay := _axis(handle, false)
	var sx := _snap_axis(moved.position.x, moved.size.x, ax, tg.get("x", []), grid, threshold)
	var sy := _snap_axis(moved.position.y, moved.size.y, ay, tg.get("y", []), grid, threshold)
	out["delta"] = Vector2(delta.x + sx["shift"], delta.y + sy["shift"])
	if sx["guide"] != null:
		out["guides_x"].append(sx["guide"])
	if sy["guide"] != null:
		out["guides_y"].append(sy["guide"])
	return out


## Which edges of an axis a handle moves: "both" (move), "start", "end"
## or "" (the axis does not change).
static func _axis(handle: String, horizontal: bool) -> String:
	if handle == "move":
		return "both"
	if horizontal:
		return "start" if handle.contains("w") else ("end" if handle.contains("e") else "")
	return "start" if handle.contains("n") else ("end" if handle.contains("s") else "")


static func _snap_axis(pos: float, size: float, mode: String, candidates: Array, grid: float, threshold: float) -> Dictionary:
	if mode == "":
		return {"shift": 0.0, "guide": null}
	var edges: Array = []
	if mode == "both":
		edges = [pos, pos + size * 0.5, pos + size]
	elif mode == "start":
		edges = [pos]
	else:
		edges = [pos + size]
	var best_shift := 0.0
	var best_guide = null
	var best_d := INF
	for e in edges:
		var s := snap_value(e, candidates, 0.0, threshold)
		if s["guide"] != null and absf(s["value"] - e) < best_d:
			best_d = absf(s["value"] - e)
			best_shift = s["value"] - e
			best_guide = s["guide"]
	if best_guide != null:
		return {"shift": best_shift, "guide": best_guide}
	var lead: float = edges[0]
	var g := snap_value(lead, [], grid, threshold)
	return {"shift": g["value"] - lead, "guide": null}
