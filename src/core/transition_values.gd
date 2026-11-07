class_name EdTransitionValues
extends RefCounted
## The `transition-*` lists of USS as Unity reads them: the property,
## duration, delay and timing function lists are aligned by index, and a
## shorter list repeats (ComputeTransitionPropertyData). The timeline edits
## one entry of a list: the list is expanded to the length of
## `transition-property`, the entry changes, and a list whose entries are
## all equal collapses to one value.
##
## No godot-uxml dependency: the shorthand table of the matching rule comes
## from the caller (godot-uxml UssTransitions.SHORTHANDS in the app).

const LONGHANDS := ["transition-property", "transition-duration", "transition-delay", "transition-timing-function"]
const INITIAL := {"transition-property": "all", "transition-duration": "0s", "transition-delay": "0s",
	"transition-timing-function": "ease"}


## "a, b ,c" -> ["a", "b", "c"]; "", "initial" and "unset" -> [].
static func split_list(text: String) -> Array:
	var t := text.strip_edges()
	if t.is_empty() or t == "initial" or t == "unset":
		return []
	var out: Array = []
	for part in t.split(","):
		out.append(String(part).strip_edges())
	return out


## The list of a longhand, with the initial value for an empty one.
static func list_or_initial(longhand: String, text: String) -> Array:
	var l := split_list(text)
	return [INITIAL.get(longhand, "")] if l.is_empty() else l


## "2s", "800ms", "0.5" (seconds) -> seconds; NAN when unreadable.
static func parse_time(t: String) -> float:
	var s := t.strip_edges().to_lower()
	if s.ends_with("ms"):
		var n := s.substr(0, s.length() - 2)
		return n.to_float() / 1000.0 if n.is_valid_float() else NAN
	if s.ends_with("s"):
		var n2 := s.substr(0, s.length() - 1)
		return n2.to_float() if n2.is_valid_float() else NAN
	return s.to_float() if s.is_valid_float() else NAN


## Seconds as USS time text: whole milliseconds, in s ("0.25s", "1s",
## "0.125s"); never negative zero.
static func format_time(seconds: float) -> String:
	var ms := int(roundf(seconds * 1000.0))
	if ms == 0:
		return "0s"
	if ms % 1000 == 0:
		return "%ds" % (ms / 1000)
	return String.num(ms / 1000.0, 3) + "s"


## The index in `names` (the transition-property list) of the entry that
## animates `property`: the last entry whose name is the property, `all`,
## or a shorthand of the property (`shorthands`: name -> [longhands]),
## with a positive duration plus delay. -1 when none.
static func entry_index(names: Array, durations: Array, delays: Array, property: String, shorthands: Dictionary = {}) -> int:
	var k := names.size() - 1
	while k >= 0:
		var nm := String(names[k]).to_lower()
		var d := parse_time(String(durations[k % durations.size()])) if not durations.is_empty() else 0.0
		var dl := parse_time(String(delays[k % delays.size()])) if not delays.is_empty() else 0.0
		if is_nan(d):
			d = 0.0
		if is_nan(dl):
			dl = 0.0
		var matches: bool = nm == property or nm == "all" or (shorthands.has(nm) and (shorthands[nm] as Array).has(property))
		if matches and maxf(0.0, d) + dl > 0.0:
			return k
		k -= 1
	return -1


## The text of list `list_text` (a longhand) with entry `k` set to
## `value`, for a transition-property list of `count` entries.
static func with_entry(longhand: String, list_text: String, count: int, k: int, value: String) -> String:
	var l := list_or_initial(longhand, list_text)
	var n := maxi(count, k + 1)
	var out: Array = []
	for i in n:
		out.append(String(l[i % l.size()]))
	out[k] = value
	var same := true
	for x in out:
		if x != out[0]:
			same = false
	if same:
		return String(out[0])
	return ", ".join(out)


## The declared transitions of a computed style (property -> {value} or
## a value): [{property, duration, delay, easing, entry}] for each entry of
## transition-property with a positive duration plus delay (seconds).
static func declared(style: Dictionary) -> Array:
	var names := list_or_initial("transition-property", _v(style, "transition-property"))
	var durs := list_or_initial("transition-duration", _v(style, "transition-duration"))
	var delays := list_or_initial("transition-delay", _v(style, "transition-delay"))
	var easings := list_or_initial("transition-timing-function", _v(style, "transition-timing-function"))
	var out: Array = []
	for k in names.size():
		var nm := String(names[k])
		if nm == "none":
			continue
		var d := parse_time(String(durs[k % durs.size()]))
		var dl := parse_time(String(delays[k % delays.size()]))
		d = 0.0 if is_nan(d) else maxf(0.0, d)
		dl = 0.0 if is_nan(dl) else dl
		if d + dl <= 0.0:
			continue
		out.append({"property": nm, "duration": d, "delay": dl, "easing": String(easings[k % easings.size()]), "entry": k})
	return out


static func _v(style: Dictionary, prop: String) -> String:
	var e = style.get(prop)
	if e is Dictionary:
		return String(e.get("value", ""))
	return "" if e == null else str(e)
