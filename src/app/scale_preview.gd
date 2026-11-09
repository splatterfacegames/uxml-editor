class_name EdScalePreview
extends RefCounted
## The scale preview of the canvas: Unity's PanelSettings scaling
## (godot-uxml UxmlPanelSettings, UxmlDocument.panel_settings) on the
## screen of the canvas preset.
##
## The bar under the canvas header sets the scale mode (none, Constant
## Pixel Size, Constant Physical Size, Scale With Screen Size), the scale,
## the reference resolution, the screen match mode and the match, the
## reference DPI and the screen DPI. The info label shows the resolved
## pixels per point and the panel size in points. A PanelSettings `.asset`
## of the open project loads through UxmlPanelSettings.load_unity_asset,
## with its theme style sheet (`.tss`).
##
## The preview is editor state: nothing goes into the UXML or USS text.
## The editor does not keep canvas settings between sessions (screen size,
## grid, theme), so the preview starts at one pixel per point.

## The settings changed. `needs_render`: the theme style sheet changed, so
## the document needs a full load.
signal changed(needs_render: bool)

const NONE := -1
## [label, UxmlPanelSettings.ScaleMode or NONE]
const MODES := [
	["1 px per point", NONE],
	["Constant Pixel Size", UxmlPanelSettings.ScaleMode.CONSTANT_PIXEL_SIZE],
	["Constant Physical Size", UxmlPanelSettings.ScaleMode.CONSTANT_PHYSICAL_SIZE],
	["Scale With Screen Size", UxmlPanelSettings.ScaleMode.SCALE_WITH_SCREEN_SIZE],
]
## [label, UxmlPanelSettings.ScreenMatchMode]
const MATCH_MODES := [
	["Match Width Or Height", UxmlPanelSettings.ScreenMatchMode.MATCH_WIDTH_OR_HEIGHT],
	["Expand", UxmlPanelSettings.ScreenMatchMode.EXPAND],
	["Shrink", UxmlPanelSettings.ScreenMatchMode.SHRINK],
]
const NO_ASSET := "No PanelSettings asset"
## Fields of the bar -> the settings modes that show them.
const FIELDS := {
	"scale-group": [0, 1, 2],
	"reference-group": [2],
	"match-mode-menu": [2],
	"match-group": [2],
	"dpi-group": [1],
}
## A PanelSettings asset names its script class in the first lines.
const ASSET_MARK := "UnityEngine.UIElements.PanelSettings"
const ASSET_HEAD := 4096

var shell: UxmlDocument
var host: EdRenderHost
## The settings of the preview, or null (one pixel per point).
var settings: UxmlPanelSettings = null
## The DPI of the previewed screen (Constant Physical Size).
var dpi := 96.0
## The project-relative path of the loaded asset ("" for custom settings)
## and whether a field changed after the load.
var asset := ""
var edited := false
## Project-relative paths of the PanelSettings assets of the project.
var assets: Array = []
var _root := ""
var _shown := {}


func attach(s: UxmlDocument, h: EdRenderHost) -> void:
	shell = s
	host = h
	shell.set_menu_items("scale-mode-menu", MODES.map(func(m): return m[0]), func(i, _t): set_mode(MODES[i][1]))
	shell.set_menu_items("match-mode-menu", MATCH_MODES.map(func(m): return m[0]), func(i, _t): _edit("screen_match_mode", MATCH_MODES[i][1]))
	_set_asset_menu()
	refresh()


## A new project: list its PanelSettings assets. The preview keeps its
## settings, except an asset of the old project.
func set_project(store: EdProjectStore) -> void:
	_root = store.root if store != null else ""
	assets = find_assets(store)
	if not asset.is_empty():
		asset = ""
		edited = false
		settings = null
		_apply()
	_set_asset_menu()
	refresh()


## The PanelSettings assets of `store` (project-relative paths): `.asset`
## files whose head names the PanelSettings class.
static func find_assets(store: EdProjectStore) -> Array:
	var out: Array = []
	if store == null or not store.is_valid():
		return out
	for rel in store.list_assets(["asset"]):
		var f := FileAccess.open(store.absolute(rel), FileAccess.READ)
		if f == null:
			continue
		var head := f.get_buffer(mini(ASSET_HEAD, f.get_length())).get_string_from_utf8()
		f.close()
		if head.contains(ASSET_MARK) or (head.contains("m_ScaleMode:") and head.contains("m_ReferenceResolution:")):
			out.append(rel)
	return out


## Load the PanelSettings asset `rel` (project-relative) and its theme
## style sheet. Returns false when the file is not a PanelSettings asset.
func load_asset(rel: String) -> bool:
	if _root.is_empty():
		return false
	var ps := UxmlPanelSettings.load_unity_asset(_root + "/" + rel, _root)
	if ps == null:
		return false
	settings = ps
	asset = rel
	edited = false
	_apply()
	_set_asset_menu()
	refresh()
	return true


## The scale mode: a UxmlPanelSettings.ScaleMode, or NONE (no settings).
## The first mode after NONE starts from Unity's defaults; another mode
## keeps the other fields.
func set_mode(mode: int) -> void:
	if mode == NONE:
		settings = null
		asset = ""
		edited = false
	else:
		if settings == null:
			settings = UxmlPanelSettings.new()
			# The reference of the canvas presets: 1920 x 1080.
			settings.reference_resolution = Vector2i(1920, 1080)
		settings.scale_mode = mode as UxmlPanelSettings.ScaleMode
		edited = not asset.is_empty()
	_apply()
	refresh()


## Custom settings in one call (tests, the command line).
func set_custom(mode: int, scale: float = 1.0, reference: Vector2i = Vector2i(1920, 1080),
		match_mode: int = UxmlPanelSettings.ScreenMatchMode.MATCH_WIDTH_OR_HEIGHT, match_value: float = 0.0) -> void:
	asset = ""
	edited = false
	if mode == NONE:
		settings = null
	else:
		var ps := UxmlPanelSettings.new()
		ps.scale_mode = mode as UxmlPanelSettings.ScaleMode
		ps.scale = scale
		ps.reference_resolution = reference
		ps.screen_match_mode = match_mode as UxmlPanelSettings.ScreenMatchMode
		ps.match_width_or_height = match_value
		settings = ps
	_apply()
	refresh()


## A value of the bar (EdMain routes UxmlDocument.value_changed). Returns
## false for an element of another view.
func on_value(element_name: String, value: Variant) -> bool:
	var text := String(value).strip_edges()
	# The field shows the value of the settings again after the edit (an
	# invalid entry goes back to the old value).
	_shown.erase(element_name)
	match element_name:
		"scale-field":
			_edit("scale", _number(text, 0.01, 100.0))
		"reference-width-field":
			if settings != null:
				var w = _number(text, 1.0, 100000.0)
				if w != null:
					_edit("reference_resolution", Vector2i(int(w), settings.reference_resolution.y))
				else:
					refresh()
		"reference-height-field":
			if settings != null:
				var h = _number(text, 1.0, 100000.0)
				if h != null:
					_edit("reference_resolution", Vector2i(settings.reference_resolution.x, int(h)))
				else:
					refresh()
		"match-field":
			_edit("match_width_or_height", _number(text, 0.0, 1.0))
		"reference-dpi-field":
			_edit("reference_dpi", _number(text, 1.0, 10000.0))
		"dpi-field":
			var d = _number(text, 1.0, 10000.0)
			if d != null:
				dpi = d
				_apply()
			refresh()
		_:
			return false
	return true


## A number in [lo, hi], or null.
static func _number(text: String, lo: float, hi: float) -> Variant:
	if not text.is_valid_float():
		return null
	return clampf(text.to_float(), lo, hi)


func _edit(field: String, value: Variant) -> void:
	if settings == null or value == null:
		refresh()
		return
	if settings.get(field) == value:
		refresh()
		return
	settings.set(field, value)
	edited = not asset.is_empty()
	_apply()
	_set_asset_menu()
	refresh()


func _apply() -> void:
	changed.emit(host.set_panel_settings(settings, dpi))


func mode() -> int:
	return NONE if settings == null else int(settings.scale_mode)


## The scale on the screen of the canvas: {pixels_per_point, panel_size}.
func resolved() -> Dictionary:
	var screen := Vector2(host.size)
	if settings == null:
		return {"pixels_per_point": 1.0, "panel_size": screen}
	return settings.resolve(screen, dpi)


## The text of the info label: "1.1701 px/pt · 1641 × 923 pt".
func info_text() -> String:
	var r := resolved()
	var ppp := float(r["pixels_per_point"])
	var ps: Vector2 = r["panel_size"]
	if settings != null and ppp <= 0.0:
		return "Scale 0: Unity draws nothing"
	return "%s px/pt · %s × %s pt" % [_short(ppp, 4), _short(ps.x, 2), _short(ps.y, 2)]


## `v` with at most `digits` decimals and no trailing zeros: 2, 1.1701.
static func _short(v: float, digits: int) -> String:
	var s := String.num(snappedf(v, pow(10.0, -digits)), digits)
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return s


## Bring the bar up to date: the menus, the fields of the mode and the
## info label.
func refresh() -> void:
	if shell == null:
		return
	var m := mode()
	for entry in MODES:
		if entry[1] == m:
			_menu_text("scale-mode-menu", entry[0])
	var mode_index := -1 if m == NONE else m
	for key in FIELDS:
		_set_class(key, ("scale-menu" if key.ends_with("-menu") else "scale-group") + ("" if FIELDS[key].has(mode_index) else " hidden"))
	if settings != null:
		_field("scale-field", _short(settings.scale, 3))
		_field("reference-width-field", str(settings.reference_resolution.x))
		_field("reference-height-field", str(settings.reference_resolution.y))
		_field("match-field", _short(settings.match_width_or_height, 3))
		_field("reference-dpi-field", _short(settings.reference_dpi, 2))
		for entry in MATCH_MODES:
			if entry[1] == int(settings.screen_match_mode):
				_menu_text("match-mode-menu", entry[0])
		_set_class("match-group", "scale-group" + ("" if int(settings.scale_mode) == UxmlPanelSettings.ScaleMode.SCALE_WITH_SCREEN_SIZE
			and int(settings.screen_match_mode) == UxmlPanelSettings.ScreenMatchMode.MATCH_WIDTH_OR_HEIGHT else " hidden"))
	_field("dpi-field", _short(dpi, 2))
	_set_asset_menu()
	refresh_info()


## The info label only (a new screen size).
func refresh_info() -> void:
	if shell != null:
		EdUi.set_label(shell, "scale-info", info_text())


func _set_asset_menu() -> void:
	if shell == null:
		return
	var items: Array = [NO_ASSET]
	items.append_array(assets)
	if _shown.get("asset-items") != items:
		_shown["asset-items"] = items
		shell.set_menu_items("panel-asset-menu", items, func(i, _t): choose_asset(i))
	var text := NO_ASSET if asset.is_empty() else asset.get_file() + (" (edited)" if edited else "")
	if assets.is_empty() and asset.is_empty():
		text = "No PanelSettings in the project"
	_menu_text("panel-asset-menu", text)


## Item `index` of the asset menu: 0 keeps the values of a loaded asset as
## custom settings without its theme; another item loads that asset.
func choose_asset(index: int) -> void:
	if index > 0 and index <= assets.size():
		load_asset(assets[index - 1])
		return
	if asset.is_empty():
		refresh()
		return
	asset = ""
	edited = false
	if settings != null:
		settings.theme_style_sheet = ""
	_apply()
	refresh()


func _menu_text(menu: String, text: String) -> void:
	if _shown.get(menu) == text:
		return
	_shown[menu] = text
	var el := shell.get_element_model(menu)
	if el != null:
		el.set_attribute("text", text)


func _field(field: String, text: String) -> void:
	if _shown.get(field) == text:
		return
	_shown[field] = text
	if shell.get_field_value(field) != text:
		shell.set_field_value(field, text)


func _set_class(element: String, cls: String) -> void:
	if _shown.get("class:" + element) == cls:
		return
	_shown["class:" + element] = cls
	shell.set_class(element, cls)
