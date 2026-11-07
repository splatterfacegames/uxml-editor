class_name EdStyleTypes
extends RefCounted
## The value type of each USS property, for the typed inspector fields:
## the kind of the helper (a choice menu, units, a colour picker, an asset
## picker), the choices, and a check of a value before a write.
##
## The enum keywords come from godot-uxml (`UssProperties.ENUM_VALUES` and
## `EASING_MODES`, the values Unity reads), through `source` as
## EdElementCatalog does, so the core loads without the addon.
##
## Kinds: length, number, color, enum, asset, rotate, scale, translate,
## origin, time, easing, property-list, text.

const _PROPERTIES_SCRIPT := "res://addons/godot_uxml/core/uss_properties.gd"

const LENGTH := ["width", "height", "min-width", "min-height", "max-width", "max-height", "flex-basis",
	"top", "right", "bottom", "left", "margin", "margin-top", "margin-right", "margin-bottom", "margin-left",
	"padding", "padding-top", "padding-right", "padding-bottom", "padding-left",
	"border-radius", "border-top-left-radius", "border-top-right-radius", "border-bottom-right-radius",
	"border-bottom-left-radius", "font-size", "letter-spacing", "word-spacing", "-unity-paragraph-spacing",
	"border-width", "border-top-width", "border-right-width", "border-bottom-width", "border-left-width",
	"-unity-text-outline-width", "gap", "row-gap", "column-gap"]
const NUMBER := ["flex-grow", "flex-shrink", "opacity", "-unity-slice-left", "-unity-slice-right",
	"-unity-slice-top", "-unity-slice-bottom", "-unity-slice-scale", "aspect-ratio"]
const COLOR := ["color", "background-color", "border-color", "border-top-color", "border-right-color",
	"border-bottom-color", "border-left-color", "-unity-background-image-tint-color", "-unity-text-outline-color"]
const ASSET := ["background-image", "-unity-font", "-unity-font-definition", "cursor", "-unity-material"]
const TIME := ["transition-duration", "transition-delay"]
## Box shorthands take 1 to 4 lengths.
const BOX_SHORTHANDS := ["margin", "padding", "border-width", "border-radius", "border-color"]
const UNITS := {"length": ["px", "%", "auto"], "rotate": ["deg", "rad", "grad", "turn"], "time": ["s", "ms"],
	"translate": ["px", "%"]}
## Asset file extensions by property.
const IMAGE_EXT := ["png", "jpg", "jpeg", "svg", "webp", "bmp", "tga"]
const FONT_EXT := ["ttf", "otf", "woff", "woff2", "fnt", "asset"]
const KEYWORDS := ["initial", "unset", "inherit"]

## () -> {property: [keywords]} (UssProperties.ENUM_VALUES). Not set: the
## godot-uxml script is loaded by path.
static var enum_source: Callable
static var _enums: Dictionary = {}
static var _easing: Array = []


static func _load() -> void:
	if not _enums.is_empty():
		return
	if enum_source.is_valid():
		_enums = enum_source.call()
	elif ResourceLoader.exists(_PROPERTIES_SCRIPT):
		var s = load(_PROPERTIES_SCRIPT)
		_enums = (s.ENUM_VALUES as Dictionary).duplicate(true)
		_easing = (s.EASING_MODES as Array).duplicate()
	if _easing.is_empty():
		_easing = ["ease", "ease-in", "ease-out", "ease-in-out", "linear"]


static func reset() -> void:
	_enums = {}
	_easing = []


static func kind_of(property: String) -> String:
	_load()
	if _enums.has(property):
		return "enum"
	if LENGTH.has(property):
		return "length"
	if NUMBER.has(property):
		return "number"
	if COLOR.has(property):
		return "color"
	if ASSET.has(property):
		return "asset"
	if TIME.has(property):
		return "time"
	match property:
		"rotate":
			return "rotate"
		"scale":
			return "scale"
		"translate":
			return "translate"
		"transform-origin":
			return "origin"
		"transition-timing-function":
			return "easing"
		"transition-property":
			return "property-list"
	return "text"


## The keywords of an enum property (also the easing names), or [].
static func choices(property: String) -> Array:
	_load()
	if property == "transition-timing-function":
		return _easing.duplicate()
	return (_enums.get(property, []) as Array).duplicate()


static func units(property: String) -> Array:
	return (UNITS.get(kind_of(property), []) as Array).duplicate()


## The file extensions an asset property accepts.
static func asset_extensions(property: String) -> Array:
	if property == "-unity-font" or property == "-unity-font-definition":
		return FONT_EXT
	return IMAGE_EXT


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

static var _re_length := RegEx.create_from_string("^[-+]?(\\d+\\.?\\d*|\\.\\d+)(px|%)?$")
static var _re_number := RegEx.create_from_string("^[-+]?(\\d+\\.?\\d*|\\.\\d+)$")
static var _re_angle := RegEx.create_from_string("^[-+]?(\\d+\\.?\\d*|\\.\\d+)(deg|rad|grad|turn)?$")
static var _re_time := RegEx.create_from_string("^[-+]?(\\d+\\.?\\d*|\\.\\d+)(s|ms)$")
static var _re_hex := RegEx.create_from_string("^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
static var _re_fn_color := RegEx.create_from_string("^(rgb|rgba|hsl|hsla)\\(\\s*[^()]*\\)$")
static var _re_url := RegEx.create_from_string("^(url|resource)\\(\\s*(\"[^\"]*\"|'[^']*'|[^)\"'\\s]*)\\s*\\)$")
static var _re_ident := RegEx.create_from_string("^-?[A-Za-z_][A-Za-z0-9_-]*$")


## null when `value` is a value of `property` that the inspector can write,
## else an EdError "invalid-value" that says why. A keyword (initial,
## unset), a var() and a value of an unknown property always pass.
static func check(property: String, value: String) -> Variant:
	var v := value.strip_edges()
	if v.is_empty():
		return null
	if v.contains("var(") or KEYWORDS.has(v.to_lower()):
		return null
	var k := kind_of(property)
	var ok := true
	var expect := ""
	match k:
		"length":
			expect = "a length (12px, 50%, auto)"
			var parts := v.split(" ", false)
			var most := 4 if BOX_SHORTHANDS.has(property) else 1
			ok = parts.size() >= 1 and parts.size() <= most and Array(parts).all(func(p): return is_length(p, property))
		"number":
			expect = "a number"
			ok = _re_number.search(v) != null
		"color":
			expect = "a colour (#rrggbb, rgb(), rgba() or a name)"
			if BOX_SHORTHANDS.has(property):
				ok = Array(v.split(" ", false)).all(is_color)
			else:
				ok = is_color(v)
		"enum":
			var c := choices(property)
			expect = "one of " + ", ".join(c)
			ok = c.has(v.to_lower())
		"asset":
			expect = "url(\"...\"), resource(\"...\") or none"
			ok = v.to_lower() == "none" or _re_url.search(v) != null or (property == "cursor" and _re_ident.search(v) != null)
		"rotate":
			expect = "an angle (45deg) or none"
			ok = v == "none" or v == "0" or (_re_angle.search(v) != null and _re_number.search(v) == null)
		"scale":
			expect = "one or two numbers, or none"
			var sp := v.split(" ", false)
			ok = v == "none" or (sp.size() <= 2 and Array(sp).all(func(p): return _re_number.search(p) != null))
		"translate":
			expect = "one or two lengths, or none"
			var tp := v.split(" ", false)
			ok = v == "none" or (tp.size() <= 2 and Array(tp).all(func(p): return _re_length.search(p) != null))
		"origin":
			expect = "one or two lengths or keywords (left, center, right, top, bottom)"
			var op := v.split(" ", false)
			ok = op.size() <= 3 and Array(op).all(func(p): return _re_length.search(p) != null or ["left", "center", "right", "top", "bottom"].has(p))
		"time":
			expect = "times (0.3s, 150ms), comma-separated"
			ok = Array(v.split(",", false)).all(func(p): return _re_time.search(p.strip_edges()) != null or p.strip_edges() == "0")
		"easing":
			expect = "easing names, comma-separated"
			ok = Array(v.split(",", false)).all(func(p): return choices(property).has(p.strip_edges()))
		"property-list":
			expect = "property names, comma-separated (all, none)"
			ok = Array(v.split(",", false)).all(func(p): return _re_ident.search(p.strip_edges()) != null)
	if ok:
		return null
	return EdError.make("invalid-value", "%s needs %s, not \"%s\"." % [property, expect, v])


static func is_length(p: String, property: String = "") -> bool:
	if p == "auto" or p == "none":
		return true
	if _re_length.search(p) == null:
		return false
	# A bare number other than 0 is not a length in USS (Unity reads it as
	# px for a few properties only).
	return p.ends_with("px") or p.ends_with("%") or _re_number.search(p) == null or float(p) == 0.0 or property.ends_with("-width") or property == "letter-spacing" or property == "word-spacing"


static func is_color(v: String) -> bool:
	if _re_hex.search(v) != null or _re_fn_color.search(v) != null:
		return true
	return _re_ident.search(v) != null and parse_color(v) != null


# ---------------------------------------------------------------------------
# Helpers: a typed control writes a new text value
# ---------------------------------------------------------------------------

## `value` with unit `unit`: the number of the value (or of `fallback`,
## the computed value, when the value has none) and the unit. "auto"
## gives auto.
static func with_unit(value: String, unit: String, fallback: String = "") -> String:
	if unit == "auto" or unit == "none":
		return unit
	var n := _number_of(value)
	if n.is_empty():
		n = _number_of(fallback)
	if n.is_empty():
		n = "0"
	return n + unit


static func _number_of(v: String) -> String:
	var m := RegEx.create_from_string("^\\s*([-+]?(\\d+\\.?\\d*|\\.\\d+))").search(v)
	return "" if m == null else m.get_string(1)


## The unit of `value` among `units` ("" when none).
static func unit_of(value: String, unit_list: Array) -> String:
	var v := value.strip_edges()
	if unit_list.has(v):
		return v
	var best := ""
	for u in unit_list:
		if v.ends_with(String(u)) and String(u).length() > best.length() and _number_of(v) != "":
			best = u
	return best


## A colour as USS text: #rrggbb, or #rrggbbaa when not opaque.
static func color_text(c: Color) -> String:
	return "#" + c.to_html(c.a < 0.999).to_lower()


## The Color of USS colour text (hex, rgb(), rgba() or a name), or null.
static func parse_color(v: String) -> Variant:
	var t := v.strip_edges().to_lower()
	if t.is_empty():
		return null
	if _re_hex.search(t) != null:
		var h := t.substr(1)
		if h.length() == 3 or h.length() == 4:
			var e := ""
			for ch in h:
				e += ch + ch
			h = e
		if h.length() == 6:
			h += "ff"
		return Color.hex(h.hex_to_int())
	var m := RegEx.create_from_string("^rgba?\\(([^)]*)\\)$").search(t)
	if m != null:
		var p := m.get_string(1).replace(",", " ").split(" ", false)
		if p.size() >= 3:
			var a := float(p[3]) if p.size() >= 4 else 1.0
			return Color(float(p[0]) / 255.0, float(p[1]) / 255.0, float(p[2]) / 255.0, a)
		return null
	var c := Color.from_string(t, Color(1, 0, 1, 0.5))
	if t == "transparent" or t == "clear":
		return Color(0, 0, 0, 0)
	return null if c == Color(1, 0, 1, 0.5) else c


## `url("path")` for a project asset path (relative to the sheet or the
## document when possible, else `project://`-free absolute).
static func url_for(asset_path: String, from_path: String) -> String:
	var dir := from_path.get_base_dir()
	var rel := asset_path
	if not dir.is_empty() and asset_path.begins_with(dir + "/"):
		rel = asset_path.substr(dir.length() + 1)
	elif not dir.is_empty():
		var up := ""
		var d := dir
		while not d.is_empty() and not asset_path.begins_with(d + "/"):
			d = d.get_base_dir() if d.contains("/") else ""
			up += "../"
		rel = up + (asset_path.substr(d.length() + 1) if not d.is_empty() else asset_path)
	return "url(\"%s\")" % rel


## The path inside a url() or resource() value, or "".
static func url_path(v: String) -> String:
	var m := _re_url.search(v.strip_edges())
	if m == null:
		return ""
	var p := m.get_string(2)
	if p.begins_with("\"") or p.begins_with("'"):
		p = p.substr(1, p.length() - 2)
	return p
