class_name EdCommandRegistry
extends RefCounted
## Every editor command, its key bindings and the fuzzy search of the
## command palette (milestone 8).
##
## A command is {id, title, category, keys: [shortcut text], scope, platform}.
## `scope` "global": the key works also while a text field has the focus
## (Ctrl+S). `scope` "structure": the key works only when no text field has
## the focus, so a field keeps Ctrl+C, Delete and the others. `platform`
## "web" or "desktop" limits a command to one host ("" for both).
##
## Shortcut text: modifiers and one key with "+", for example "Ctrl+Shift+P",
## "Alt+Up", "Del", "F2". "Ctrl" is the command key on macOS
## (InputEventKey.is_command_or_control_pressed).
##
## The bindings of a command can change (set_keys, the settings section
## "shortcuts"): the key handler, the shortcut map and the palette read the
## same table, so each shows the current bindings.
##
## No godot-uxml dependency.

const DEFAULTS := [
	{"id": "palette", "title": "Show all commands", "category": "Help", "keys": ["Ctrl+Shift+P"], "scope": "global"},
	{"id": "shortcuts", "title": "Show the keyboard shortcuts", "category": "Help", "keys": ["Ctrl+/"], "scope": "global"},
	{"id": "open-project", "title": "Open a project", "category": "File", "keys": ["Ctrl+O"], "scope": "global"},
	{"id": "save", "title": "Save the document", "category": "File", "keys": ["Ctrl+S"], "scope": "global"},
	{"id": "save-all", "title": "Save all files", "category": "File", "keys": ["Ctrl+Shift+S"], "scope": "global"},
	{"id": "open-zip", "title": "Open a project zip", "category": "File", "keys": [], "scope": "global", "platform": "web"},
	{"id": "download-zip", "title": "Download the project as a zip", "category": "File", "keys": [], "scope": "global", "platform": "web"},
	{"id": "close-tab", "title": "Close the document tab", "category": "File", "keys": ["Ctrl+W"], "scope": "global"},
	{"id": "next-tab", "title": "Show the next tab", "category": "File", "keys": ["Ctrl+Tab"], "scope": "global"},
	{"id": "previous-tab", "title": "Show the previous tab", "category": "File", "keys": ["Ctrl+Shift+Tab"], "scope": "global"},
	{"id": "undo", "title": "Undo", "category": "Edit", "keys": ["Ctrl+Z"], "scope": "global"},
	{"id": "redo", "title": "Redo", "category": "Edit", "keys": ["Ctrl+Shift+Z", "Ctrl+Y"], "scope": "global"},
	{"id": "cut", "title": "Cut", "category": "Edit", "keys": ["Ctrl+X"], "scope": "structure"},
	{"id": "copy", "title": "Copy", "category": "Edit", "keys": ["Ctrl+C"], "scope": "structure"},
	{"id": "paste", "title": "Paste", "category": "Edit", "keys": ["Ctrl+V"], "scope": "structure"},
	{"id": "duplicate", "title": "Duplicate", "category": "Edit", "keys": ["Ctrl+D"], "scope": "structure"},
	{"id": "delete", "title": "Delete", "category": "Edit", "keys": ["Del"], "scope": "structure"},
	{"id": "wrap", "title": "Wrap in VisualElement", "category": "Edit", "keys": ["Ctrl+G"], "scope": "structure"},
	{"id": "unwrap", "title": "Unwrap", "category": "Edit", "keys": ["Ctrl+Shift+G"], "scope": "structure"},
	{"id": "move-up", "title": "Move up", "category": "Edit", "keys": ["Alt+Up"], "scope": "structure"},
	{"id": "move-down", "title": "Move down", "category": "Edit", "keys": ["Alt+Down"], "scope": "structure"},
	{"id": "rename", "title": "Rename element type", "category": "Edit", "keys": ["F2"], "scope": "structure"},
	{"id": "preview", "title": "Toggle preview", "category": "View", "keys": ["Ctrl+P"], "scope": "global"},
	{"id": "zoom-in", "title": "Zoom in", "category": "View", "keys": ["Ctrl+=", "Ctrl++"], "scope": "global"},
	{"id": "zoom-out", "title": "Zoom out", "category": "View", "keys": ["Ctrl+-"], "scope": "global"},
	{"id": "fit", "title": "Fit the document in the canvas", "category": "View", "keys": [], "scope": "global"},
	{"id": "snap", "title": "Toggle snapping", "category": "View", "keys": [], "scope": "global"},
	{"id": "states-panel", "title": "Toggle the state-machine panel", "category": "View", "keys": [], "scope": "global"},
	{"id": "theme-auto", "title": "Theme: auto", "category": "View", "keys": [], "scope": "global"},
	{"id": "theme-runtime", "title": "Theme: runtime", "category": "View", "keys": [], "scope": "global"},
	{"id": "theme-editor-dark", "title": "Theme: editor dark", "category": "View", "keys": [], "scope": "global"},
	{"id": "theme-editor-light", "title": "Theme: editor light", "category": "View", "keys": [], "scope": "global"},
	{"id": "timeline-play", "title": "Play or pause the timeline", "category": "Timeline", "keys": [], "scope": "global"},
	{"id": "timeline-restart", "title": "Restart the timeline", "category": "Timeline", "keys": [], "scope": "global"},
	{"id": "timeline-stop", "title": "End the timeline run", "category": "Timeline", "keys": [], "scope": "global"},
]

## Keys that are not commands: the shortcut map lists them too.
const FIXED := [
	{"title": "Nudge the selection 1 px (Shift: 10 px)", "category": "Canvas", "keys": ["Arrows", "Shift+Arrows"]},
	{"title": "Cancel a drag", "category": "Canvas", "keys": ["Escape"]},
	{"title": "Snapping off during a drag", "category": "Canvas", "keys": ["Alt", "Ctrl"]},
	{"title": "Keep the aspect ratio of a corner resize", "category": "Canvas", "keys": ["Shift"]},
	{"title": "Add to the selection or remove from it", "category": "Canvas", "keys": ["Shift+Click"]},
	{"title": "Select more elements in the hierarchy", "category": "Hierarchy", "keys": ["Shift+Click", "Ctrl+Click"]},
	{"title": "Step through the states", "category": "States", "keys": ["Up", "Down"]},
	{"title": "End the state selection", "category": "States", "keys": ["Escape"]},
	{"title": "Choose a command", "category": "Palette", "keys": ["Up", "Down"]},
	{"title": "Run the chosen command", "category": "Palette", "keys": ["Enter"]},
	{"title": "Close the palette", "category": "Palette", "keys": ["Escape"]},
]

const _NAMES := {
	"Del": KEY_DELETE, "Delete": KEY_DELETE, "Backspace": KEY_BACKSPACE, "Tab": KEY_TAB, "Enter": KEY_ENTER,
	"Escape": KEY_ESCAPE, "Esc": KEY_ESCAPE, "Space": KEY_SPACE, "Up": KEY_UP, "Down": KEY_DOWN,
	"Left": KEY_LEFT, "Right": KEY_RIGHT, "Home": KEY_HOME, "End": KEY_END, "PageUp": KEY_PAGEUP,
	"PageDown": KEY_PAGEDOWN, "=": KEY_EQUAL, "+": KEY_PLUS, "-": KEY_MINUS, "/": KEY_SLASH,
	",": KEY_COMMA, ".": KEY_PERIOD, ";": KEY_SEMICOLON,
}

var commands: Array = []
var platform := "desktop"
var _by_id := {}


func _init(host_platform: String = "desktop") -> void:
	platform = host_platform
	for c in DEFAULTS:
		var p := String(c.get("platform", ""))
		if not p.is_empty() and p != platform:
			continue
		var e: Dictionary = (c as Dictionary).duplicate(true)
		e["platform"] = p
		e["defaults"] = (c["keys"] as Array).duplicate()
		commands.append(e)
		_by_id[e["id"]] = e


func has(id: String) -> bool:
	return _by_id.has(id)


func get_command(id: String) -> Dictionary:
	return _by_id.get(id, {})


## The current shortcut texts of command `id`.
func keys_of(id: String) -> Array:
	return (_by_id.get(id, {}) as Dictionary).get("keys", [])


## The first binding of `id` as text ("" when it has none).
func key_text(id: String) -> String:
	var k := keys_of(id)
	return "" if k.is_empty() else display(String(k[0]))


## Bind command `id` to `keys`. A text that does not parse is dropped and
## returned in the result: {ok, dropped: [text]}.
func set_keys(id: String, keys: Array) -> Dictionary:
	var c: Dictionary = _by_id.get(id, {})
	if c.is_empty():
		return {"ok": false, "dropped": keys}
	var kept: Array = []
	var dropped: Array = []
	for k in keys:
		if parse(String(k)).is_empty():
			dropped.append(k)
		else:
			kept.append(String(k))
	c["keys"] = kept
	return {"ok": dropped.is_empty(), "dropped": dropped}


## Apply the overrides of a settings section: {command id: "Ctrl+K" or
## ["Ctrl+K", "F5"] or ""}. Returns the texts that were dropped.
func apply_overrides(overrides: Dictionary) -> Array:
	var dropped: Array = []
	for id in overrides:
		var v = overrides[id]
		var keys: Array = []
		if v is Array or v is PackedStringArray:
			keys = Array(v)
		elif not String(v).strip_edges().is_empty():
			keys = Array(String(v).split(",", false)).map(func(x): return String(x).strip_edges())
		dropped.append_array(set_keys(String(id), keys)["dropped"])
	return dropped


## The command of key event `ev` in `scope` ("global" or "structure"),
## or "".
func command_for(ev: InputEventKey, scope: String) -> String:
	if ev == null or not ev.pressed:
		return ""
	var spec := spec_of(ev)
	for c in commands:
		if c["scope"] != scope:
			continue
		for k in c["keys"]:
			if parse(String(k)) == spec:
				return String(c["id"])
	return ""


## {keycode, ctrl, shift, alt} of a key event.
static func spec_of(ev: InputEventKey) -> Dictionary:
	var code := ev.keycode
	if code == KEY_NONE:
		code = ev.physical_keycode
	if code == KEY_KP_ADD:
		code = KEY_PLUS
	elif code == KEY_KP_SUBTRACT:
		code = KEY_MINUS
	return {"keycode": int(code), "ctrl": ev.is_command_or_control_pressed(), "shift": ev.shift_pressed, "alt": ev.alt_pressed}


## Parse shortcut text: {keycode, ctrl, shift, alt}, or {} when the text
## is not one key with modifiers.
static func parse(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.is_empty():
		return {}
	var parts: Array = []
	# "Ctrl++": the last "+" is the key.
	if t.ends_with("++"):
		parts = Array(t.substr(0, t.length() - 2).split("+", false))
		parts.append("+")
	elif t == "+":
		parts = ["+"]
	else:
		parts = Array(t.split("+", false))
	if parts.is_empty():
		return {}
	var spec := {"keycode": 0, "ctrl": false, "shift": false, "alt": false}
	for i in parts.size():
		var p := String(parts[i]).strip_edges()
		var last := i == parts.size() - 1
		var low := p.to_lower()
		if not last:
			if low == "ctrl" or low == "cmd" or low == "control" or low == "command":
				spec["ctrl"] = true
			elif low == "shift":
				spec["shift"] = true
			elif low == "alt" or low == "option":
				spec["alt"] = true
			else:
				return {}
			continue
		var code := _keycode(p)
		if code == 0:
			return {}
		spec["keycode"] = code
	return spec


static func _keycode(name: String) -> int:
	if _NAMES.has(name):
		return int(_NAMES[name])
	if name.length() == 1:
		var u := name.to_upper()
		var c := u.unicode_at(0)
		if (c >= 65 and c <= 90) or (c >= 48 and c <= 57):
			return c
		return 0
	var f := name.to_upper()
	if f.begins_with("F") and f.substr(1).is_valid_int():
		var n := int(f.substr(1))
		if n >= 1 and n <= 12:
			return KEY_F1 + n - 1
	return 0


## Shortcut text as the host shows it: "Ctrl" is "Cmd" on macOS.
static func display(text: String) -> String:
	if OS.get_name() == "macOS":
		return text.replace("Ctrl+", "Cmd+")
	return text


# ---------------------------------------------------------------------------
# Search
# ---------------------------------------------------------------------------

## The palette rows for `query`, best first: [{id, title, category, keys,
## score}]. An empty query lists every command in table order.
func search(query: String) -> Array:
	var q := query.strip_edges()
	var out: Array = []
	for i in commands.size():
		var c: Dictionary = commands[i]
		var text := "%s: %s" % [c["category"], c["title"]]
		var s := 0 if q.is_empty() else fuzzy_score(q, text)
		if s < 0:
			s = fuzzy_score(q, String(c["id"]))
		if s < 0:
			continue
		out.append({"id": c["id"], "title": c["title"], "category": c["category"], "keys": c["keys"], "score": s, "order": i})
	if not q.is_empty():
		out.sort_custom(func(a, b): return a["score"] > b["score"] or (a["score"] == b["score"] and a["order"] < b["order"]))
	return out


## The rows of the shortcut map: every command with a binding and the fixed
## keys, by category, filtered by `query` (fuzzy). [{category, title, keys,
## id}] where `id` is "" for a fixed key.
func shortcut_rows(query: String = "") -> Array:
	var q := query.strip_edges()
	var out: Array = []
	var cats: Array = []
	var rows: Array = []
	for c in commands:
		if not (c["keys"] as Array).is_empty():
			rows.append({"category": c["category"], "title": c["title"], "keys": c["keys"], "id": c["id"]})
	for f in FIXED:
		rows.append({"category": f["category"], "title": f["title"], "keys": f["keys"], "id": ""})
	for r in rows:
		if not cats.has(r["category"]):
			cats.append(r["category"])
	for cat in cats:
		for r in rows:
			if r["category"] != cat:
				continue
			var text := "%s: %s %s" % [r["category"], r["title"], " ".join(PackedStringArray(r["keys"]))]
			if q.is_empty() or fuzzy_score(q, text) >= 0:
				out.append(r)
	return out


## Fuzzy match of `query` in `text`, case-insensitive: every character of
## the query in order. Returns -1 without a match, else a score: higher is
## better (consecutive characters, the start of a word, an early first
## character and a short text count).
static func fuzzy_score(query: String, text: String) -> int:
	var q := query.to_lower().replace(" ", "")
	var t := text.to_lower()
	if q.is_empty():
		return 0
	var score := 0
	var ti := 0
	var prev := -2
	var first := -1
	for qi in q.length():
		var ch := q[qi]
		var found := -1
		# Prefer the start of a word for this character.
		var j := ti
		while j < t.length():
			if t[j] == ch and (j == 0 or _is_boundary(t, j)):
				found = j
				break
			j += 1
		if found < 0 or (prev >= 0 and t.find(ch, ti) == prev + 1):
			found = t.find(ch, ti)
		if found < 0:
			return -1
		if first < 0:
			first = found
		score += 10
		if found == prev + 1:
			score += 15
		if found == 0 or _is_boundary(t, found):
			score += 20
		prev = found
		ti = found + 1
	score -= first
	score -= t.length() / 8
	return score


static func _is_boundary(t: String, i: int) -> bool:
	if i <= 0:
		return true
	var p := t[i - 1]
	return p == " " or p == ":" or p == "-" or p == "." or p == "(" or p == "/"
