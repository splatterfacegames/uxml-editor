class_name EdReel
extends Node
## The announcement reel (`--reel`): the editor on a fixed timeline,
## recorded frame by frame with Godot's Movie Maker (no screen capture, no
## real-time clock). Each step uses the same calls as the user input paths
## (EdDemo does the same for the documentation screenshots).
##
## The document is the settings screen of godot-uxml's web demo, a copy in
## tools/reel. The window draws at a content scale of 1.5 (1280x720 layout
## units in a 1920x1080 frame); a caption band and a zoom lead the eye.
## Record with tools/record_reel.sh.
##
##   godot --path . -- --reel --watch-interval=0 --settings=<tmp.cfg>

const PROJECT := "res://tools/reel"
const W := 1280.0
const H := 720.0
const LENGTH := 6.4
const NEW_COLOR := "#f2a33a"

# The palette of the godot-uxml site (godot-uxml.splatterfacegames.com).
const PAPER := Color("#eef1f4")
const INK := Color("#15191e")
const GODOT := Color("#478cbf")

## Captions: [start time, title, line].
const CAPTIONS := [
	[0.0, "UXML Editor: a visual editor built on godot-uxml", "Canvas, hierarchy, inspector and source of the same UXML and USS files"],
	[1.5, "Change a USS value. The canvas updates.", "Pick the rule to write to: .primary in Settings.uss"],
	[3.4, "Force :hover. See the rule that wins.", "The state preview needs no mouse"],
	[4.9, "Keep every byte you did not change", "The edit replaced one value in Settings.uss"],
]

var m: EdMain
var _frame := 0
var _done := {}
var _layer: CanvasLayer
var _band: ColorRect
var _title: Label
var _line: Label
var _fade: ColorRect
var _dir := ""
## Zoom keys: [time, zoom, focus point in layout units].
var _zoom: Array = []


func _init(main: EdMain) -> void:
	m = main


func _ready() -> void:
	var w := get_window()
	# The frames come from the viewport: the window stays small.
	var pos := w.position
	w.min_size = Vector2i.ZERO
	w.size = Vector2i(384, 216)
	w.position = pos
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	w.content_scale_size = Vector2i(1920, 1080)
	w.content_scale_factor = 1.5
	# Distance-field glyphs stay sharp under the zoom of the camera.
	for f in [UxmlTheme.default_font(), load(EdMain.SYMBOL_FONT)]:
		if f is FontFile:
			(f as FontFile).multichannel_signed_distance_field = true
	_build_overlay()
	_dir = ProjectSettings.globalize_path("user://reel-project")
	EdDemo._copy(ProjectSettings.globalize_path(PROJECT), _dir)
	m.state.open_project(_dir)
	m.state.open_document("Assets/UI/Settings.uxml")
	m._set_preset(4)
	_show_caption(0)
	_fade.modulate.a = 1.0


func _build_overlay() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)
	var font := UxmlTheme.default_font()
	var bold := FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.55
	_band = ColorRect.new()
	_band.color = INK
	_band.size = Vector2(W, 104)
	_band.position = Vector2.ZERO
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_band)
	var accent := ColorRect.new()
	accent.color = GODOT
	accent.size = Vector2(W, 4)
	accent.position = Vector2(0, 100)
	_band.add_child(accent)
	_title = Label.new()
	_title.add_theme_font_override("font", bold)
	_title.add_theme_font_size_override("font_size", 41)
	_title.add_theme_color_override("font_color", PAPER)
	_title.position = Vector2(42, 12)
	_band.add_child(_title)
	_line = Label.new()
	_line.add_theme_font_override("font", font)
	_line.add_theme_font_size_override("font_size", 23)
	_line.add_theme_color_override("font_color", Color("#aab4c0"))
	_line.position = Vector2(43, 64)
	_band.add_child(_line)
	_fade = ColorRect.new()
	_fade.color = INK
	_fade.size = Vector2(W, H)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)


func _show_caption(i: int) -> void:
	_title.text = CAPTIONS[i][1]
	_line.text = CAPTIONS[i][2]


## Real mouse input does not reach the editor while the reel runs.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Movie Maker runs at a fixed frame rate: count frames, not seconds.
	_frame += 1
	var t := _frame / 60.0
	_run(t)
	if t >= LENGTH:
		get_tree().quit()


func _at(t: float, when: float) -> bool:
	if t < when or _done.has(when):
		return false
	_done[when] = true
	return true


func _run(t: float) -> void:
	_fade.modulate.a = _key([[0.0, 1.0], [0.25, 0.0], [LENGTH - 0.3, 0.0], [LENGTH, 1.0]], t)
	for i in range(CAPTIONS.size() - 1, -1, -1):
		if t >= CAPTIONS[i][0]:
			_show_caption(i)
			break
	if _at(t, 0.02):
		# Smaller side panes and a shorter lower pane: a larger canvas.
		m.shell.set_split_dimension("main-split", 210.0)
		m.shell.set_split_dimension("right-split", 380.0)
		m.shell.set_split_dimension("center-split", 290.0)
		m.shell.set_split_dimension("lower-split", 96.0)
		EdDemo._select(m, "apply")
	if _at(t, 0.15):
		_frame_canvas(0.62)
	if _at(t, 0.3):
		m.inspector.flush()
		m.inspector.show_property("background-color")
		m.inspector.flush()
	if _at(t, 1.5):
		# The inspector field write, as on Enter: the target picker opens.
		m.inspector.write_style("background-color", NEW_COLOR, _style_field("background-color"))
	if _at(t, 2.3):
		var ok := false
		for i in m.inspector.pending.get("choices", []).size():
			var c: Dictionary = m.inspector.pending["choices"][i]
			if String(c["label"]).contains(".primary") and not String(c["label"]).contains(":hover"):
				ok = m.inspector.choose(i)
				break
		if not ok:
			push_warning("reel: no .primary target in %s" % str(m.inspector.pending_labels()))
	if _at(t, 2.35):
		_frame_canvas(1.0)
	if _at(t, 3.5):
		m.inspector.set_state("hover", true)
	if _at(t, 4.9):
		m.inspector.set_state("hover", false)
		var path := "Assets/UI/Settings.uss"
		var text := m.state.workspace.text(path)
		var at := text.find(NEW_COLOR)
		if at < 0:
			push_warning("reel: the edit is not in " + path)
		else:
			m.show_source_range(path, at, at + NEW_COLOR.length())
	_camera(t)


## Zoom the canvas to `z` with the Apply button in the middle.
func _frame_canvas(z: float) -> void:
	var c := m.canvas
	var r := c.host.rect_of(EdDemo._node(m, "apply").id)
	# Zoomed out: the middle of the card; zoomed in: the button.
	var focus := r.get_center() + (Vector2(-190, -150) if z < 0.9 else Vector2(-60, -20))
	c.zoom = z
	c.pan = c.size * 0.5 - focus * z
	c.view_changed.emit()
	c.queue_redraw()


## The inspector's value field of `property` (the picker opens under it).
func _style_field(property: String) -> Control:
	var i := EdInspectorView.COMMON_STYLES.find(property)
	return m.inspector.doc.get_native("style-%d" % i) if i >= 0 else null


## The global point of the Apply button on the canvas.
func _apply_point() -> Vector2:
	var n := EdDemo._node(m, "apply")
	if n == null:
		return Vector2(W, H) * 0.5
	return m.canvas.screen_to_global(m.canvas.host.rect_of(n.id).get_center())


## The global point of the marked value in the source view.
func _source_point() -> Vector2:
	var s := m.source
	var line := s.get_selection_from_line()
	var col := s.get_selection_from_column()
	var r := s.get_rect_at_line_column(line, col)
	if r.position.x < 0:
		return s.get_global_rect().get_center()
	return s.get_global_transform() * Vector2(r.position.x + 40, r.get_center().y)


## Zoom keys: [time, zoom, focus]; a zoom of 1 shows the whole window.
func _camera(t: float) -> void:
	var whole := Vector2(W, H) * 0.5
	var keys: Array = [
		[0.0, 1.0, whole], [2.45, 1.0, whole],
		[3.1, 2.1, _apply_point() + Vector2(0, 30)], [4.75, 2.1, _apply_point() + Vector2(0, 30)],
		[5.35, 2.2, _source_point() + Vector2(120, 0)], [LENGTH, 2.2, _source_point() + Vector2(120, 0)],
	]
	var z := _key(keys.map(func(k): return [k[0], k[1]]), t)
	var fx := _key(keys.map(func(k): return [k[0], k[2].x]), t)
	var fy := _key(keys.map(func(k): return [k[0], k[2].y]), t)
	# The view stays inside the window; the caption band covers its foot.
	var half := Vector2(W, H) * 0.5 / z
	var f := Vector2(clampf(fx, half.x, W - half.x), clampf(fy, half.y, H - half.y))
	var view_center := whole.lerp(Vector2(W * 0.5, 104.0 + (H - 104.0) * 0.5), clampf(z - 1.0, 0.0, 1.0))
	get_viewport().canvas_transform = Transform2D(0.0, Vector2(z, z), 0.0, view_center - f * z)


## [time, value] pairs, eased between (as the Typesetter reel).
static func _key(keys: Array, t: float) -> float:
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t <= b[0]:
			var k := clampf((t - a[0]) / maxf(b[0] - a[0], 1e-4), 0.0, 1.0)
			return lerpf(a[1], b[1], k * k * (3.0 - 2.0 * k))
	return keys[-1][1]
