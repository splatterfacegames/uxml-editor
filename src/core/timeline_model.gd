class_name EdTimelineModel
extends RefCounted
## The transition timeline as data: the tracks, the playhead, playback
## (play, pause, loop, speed), the time scale of the track area, and the
## From and To states of a run.
##
## A track: {node_id, label, property, delay, duration, easing, from, to,
## entry, running}. Times are seconds after the state change. `running`
## tracks come from a run of godot-uxml (get_transitions, request R7);
## other tracks are the declared transitions of the computed style.
##
## A state (the From or the To of a run) is {classes: Array, states:
## Array}: the author classes of the element and the forced pseudo-states.
## Its text is a compound selector: `.menu-button.primary:hover`; an
## element without classes and states is `(none)`.

const STATES := ["hover", "active", "focus", "checked", "selected", "disabled"]
const SPEEDS := [0.1, 0.25, 0.5, 1.0, 2.0]
## Bar edits snap to this step (seconds) unless snapping is off.
const SNAP := 0.05

var tracks: Array = []
var time := 0.0
var playing := false
var loop := false
var speed := 1.0


## The end of the last track (seconds); 0 without tracks.
func length() -> float:
	var l := 0.0
	for t in tracks:
		l = maxf(l, float(t["delay"]) + float(t["duration"]))
	return l


## Advance the playhead by `dt` seconds of wall time when playing.
## Returns true when the playhead moved. At the end the playback stops, or
## starts again from 0 with loop.
func step(dt: float) -> bool:
	if not playing:
		return false
	var l := length()
	if l <= 0.0:
		playing = false
		return false
	var t := time + dt * speed
	if t >= l:
		if loop:
			t = fmod(t, l)
		else:
			t = l
			playing = false
	time = t
	return true


func seek(t: float) -> void:
	time = clampf(t, 0.0, maxf(length(), 0.0))


## Play from the start when the playhead is at the end.
func toggle_play() -> void:
	if playing:
		playing = false
		return
	if time >= length() - 0.0001:
		time = 0.0
	playing = length() > 0.0


# ---------------------------------------------------------------------------
# Time scale
# ---------------------------------------------------------------------------

## Pixels per second for a track area of `width` pixels: the run fills
## 85% of the area; at least 0.5 s shows.
static func scale_for(total: float, width: float) -> float:
	return maxf(width, 10.0) * 0.85 / maxf(total, 0.5)


## A tick step (seconds) that keeps ticks at least `min_px` apart.
static func tick_step(pps: float, min_px: float = 48.0) -> float:
	for s in [0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0]:
		if s * pps >= min_px:
			return s
	return 30.0


static func snap_time(t: float, on: bool = true) -> float:
	var s := t if not on else roundf(t / SNAP) * SNAP
	return roundf(s * 1000.0) / 1000.0


## The new delay and duration of a bar drag: `part` "move" (the bar
## moves: the delay changes) or "end" (the right edge: the duration
## changes), by `dt` seconds from the start values. Delay >= 0, duration
## >= 0.01 s.
static func drag_bar(delay: float, duration: float, part: String, dt: float, snap: bool = true) -> Dictionary:
	if part == "end":
		return {"delay": delay, "duration": maxf(0.01, snap_time(duration + dt, snap))}
	return {"delay": maxf(0.0, snap_time(delay + dt, snap)), "duration": duration}


# ---------------------------------------------------------------------------
# States
# ---------------------------------------------------------------------------

static func state_text(st: Dictionary) -> String:
	var s := ""
	for c in st.get("classes", []):
		s += "." + String(c)
	for p in st.get("states", []):
		s += ":" + String(p)
	return "(none)" if s.is_empty() else s


## Parse a state text (`.a.b:hover`, `(none)`) into {classes, states}, or
## an EdError.
static func parse_state(text: String) -> Variant:
	var t := text.strip_edges()
	if t.is_empty() or t == "(none)":
		return {"classes": [], "states": []}
	var re := RegEx.create_from_string("([.:])(-?[A-Za-z_][A-Za-z0-9_-]*)")
	var classes: Array = []
	var states: Array = []
	var at := 0
	for m in re.search_all(t):
		if m.get_start() != at:
			return EdError.make("invalid-value", "%s is not a state: write classes and pseudo-states, for example .button:hover." % t)
		at = m.get_end()
		var name := m.get_string(2)
		if m.get_string(1) == ".":
			if not classes.has(name):
				classes.append(name)
		else:
			if not STATES.has(name):
				return EdError.make("invalid-value", ":%s is not a state of the preview (%s)." % [name, ", ".join(STATES.map(func(x): return ":" + x))])
			if not states.has(name):
				states.append(name)
	if at != t.length():
		return EdError.make("invalid-value", "%s is not a state: write classes and pseudo-states, for example .button:hover." % t)
	return {"classes": classes, "states": states}


## The choices of the state menus for an element with author classes
## `classes`, states `states` and the classes `known` of the document's
## rules: the element as it is, with each state, without each class, and
## with each other known class.
static func state_choices(classes: Array, states: Array, known: Array) -> Array:
	var out: Array = []
	var base := {"classes": classes.duplicate(), "states": states.duplicate()}
	out.append(base)
	for s in STATES:
		if not states.has(s):
			out.append({"classes": classes.duplicate(), "states": states + [s]})
	if not states.is_empty():
		out.append({"classes": classes.duplicate(), "states": []})
	for c in classes:
		var without := classes.duplicate()
		without.erase(c)
		out.append({"classes": without, "states": states.duplicate()})
	for c in known:
		if not classes.has(c):
			out.append({"classes": classes + [c], "states": states.duplicate()})
	return out
