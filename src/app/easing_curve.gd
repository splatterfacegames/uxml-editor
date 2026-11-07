class_name EdEasingCurve
extends RefCounted
## The curve of a USS timing function, drawn with the easing of godot-uxml
## (UssTransitions.easing, the function the transitions use), so the
## preview is the motion of the canvas.

const SAMPLES := 48


## The eased progress of keyword `name` at `t` (0..1); linear for an
## unknown keyword.
static func value(name: String, t: float) -> float:
	var mode := UssProperties.EASING_MODES.find(name.strip_edges().to_lower())
	if mode < 0:
		return t
	return UssTransitions.easing(mode, clampf(t, 0.0, 1.0))


static func is_keyword(name: String) -> bool:
	return UssProperties.EASING_MODES.has(name.strip_edges().to_lower())


## The points of the curve in `rect`: x is the time, y the progress (up).
## Overshoot (back, elastic) fits in the rectangle.
static func points(name: String, rect: Rect2, samples: int = SAMPLES) -> PackedVector2Array:
	var ys: Array = []
	var lo := 0.0
	var hi := 1.0
	for i in samples + 1:
		var y := value(name, float(i) / samples)
		ys.append(y)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var out := PackedVector2Array()
	for i in samples + 1:
		var x := rect.position.x + rect.size.x * float(i) / samples
		var f: float = (float(ys[i]) - lo) / maxf(hi - lo, 0.0001)
		out.append(Vector2(x, rect.end.y - f * rect.size.y))
	return out


## Draw the curve of `name` into `rect` of canvas item `ci`, with the 0
## and 1 levels as faint lines.
static func draw(ci: CanvasItem, rect: Rect2, name: String, color: Color, width: float = 1.5) -> void:
	if rect.size.x < 4 or rect.size.y < 4:
		return
	var pts := points(name, rect)
	var lo := 0.0
	var hi := 1.0
	for i in SAMPLES + 1:
		var y := value(name, float(i) / SAMPLES)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	var faint := Color(color, 0.18)
	for level in [0.0, 1.0]:
		var f: float = (level - lo) / maxf(hi - lo, 0.0001)
		var y: float = rect.end.y - f * rect.size.y
		ci.draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), faint, 1.0)
	ci.draw_polyline(pts, color, width, true)
