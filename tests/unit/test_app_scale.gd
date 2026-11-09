extends EdAppTestCase
## The scale preview of the canvas (PanelSettings, godot-uxml
## UxmlDocument.panel_settings): the resolved scale, the PanelSettings
## assets of a project, and canvas selection, moves, resizes, snapping and
## nudges under 0.5625, 1.333 and 2 pixels per point.
##
## Units: document pixels for the canvas and the hit test, panel points for
## the USS values (godot-uxml docs/design.md, "Panel scaling").

const SWS := UxmlPanelSettings.ScaleMode.SCALE_WITH_SCREEN_SIZE
const CPS := UxmlPanelSettings.ScaleMode.CONSTANT_PIXEL_SIZE
const CPH := UxmlPanelSettings.ScaleMode.CONSTANT_PHYSICAL_SIZE
const GAME_ASSET := "Assets/UI/Panel/Game.asset"


func _preset_index(m: EdMain, s: Vector2i) -> int:
	for i in m.PRESETS.size():
		if m.PRESETS[i][1] == s:
			return i
	return -1


## The editor at a scale: [screen, mode, scale, reference, match].
func _scaled(screen: Vector2i, mode: int, scale: float, reference: Vector2i = Vector2i(1920, 1080), match_value: float = 0.0) -> EdMain:
	var m := await editor()
	m._set_preset(_preset_index(m, screen))
	m.scale_preview.set_custom(mode, scale, reference, UxmlPanelSettings.ScreenMatchMode.MATCH_WIDTH_OR_HEIGHT, match_value)
	await frames(4)
	# The winners are the write targets, without the picker after a drag
	# (the targets have tests of their own).
	m.layout.inspector = null
	# Zoom 1 at a fixed pan: one document pixel is one window pixel.
	m.canvas.zoom = 1.0
	m.canvas.pan = Vector2(16, 16)
	await frames(2)
	return m


## The cases of the brief: 0.5625 (1080 x 1920 at reference 1920 x 1080,
## match the width), 1.333 (2560 x 1440 at 1920 x 1080), 2 (Constant Pixel
## Size, scale 2).
func _cases() -> Array:
	return [
		{"ppp": 0.5625, "screen": Vector2i(1080, 1920), "mode": SWS, "scale": 1.0},
		{"ppp": 1.3333334, "screen": Vector2i(2560, 1440), "mode": SWS, "scale": 1.0},
		{"ppp": 2.0, "screen": Vector2i(1280, 720), "mode": CPS, "scale": 2.0},
	]


func _make_absolute(m: EdMain, authored: String) -> void:
	var t = EdUssCommands.inline_target(m.state.session, EdLocator.create(node_named(m, authored)), "position")
	m.state.execute(EdUssCommands.set_inline_style(m.state.session, t, "absolute"), "test")
	await frames()


## The left or top of `authored` in points, as a gesture starts from it.
func _px(m: EdMain, authored: String, property: String) -> float:
	var base = m.layout._base_for(node_named(m, authored))
	return float(base[property]) if base is Dictionary and base[property] != null else NAN


# ---------------------------------------------------------------------------

func test_presets_and_resolved_scale() -> void:
	var m := await editor()
	for s in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160), Vector2i(1080, 1920), Vector2i(2560, 1080)]:
		ok(_preset_index(m, s) >= 0, "a preset of %s" % s)
	eq(m.canvas.host.pixels_per_point(), 1.0, "no settings: one pixel per point")
	ok(m.scale_preview.info_text().begins_with("1 px/pt"), m.scale_preview.info_text())
	m._set_preset(_preset_index(m, Vector2i(1080, 1920)))
	m.scale_preview.set_custom(SWS, 1.0, Vector2i(1920, 1080), UxmlPanelSettings.ScreenMatchMode.MATCH_WIDTH_OR_HEIGHT, 0.5)
	await frames(3)
	# Unity: 1080 x 1920 at reference 1920 x 1080, match 0.5 is 1.1701 pixels
	# per point (a linear blend; godot-uxml docs/design.md).
	ok(absf(m.canvas.host.pixels_per_point() - 1.1701) < 0.0005, "1.1701 px/pt (%s)" % m.canvas.host.pixels_per_point())
	ok(m.scale_preview.info_text().begins_with("1.1701 px/pt"), m.scale_preview.info_text())
	var ps := m.canvas.host.panel_size()
	ok(absf(ps.x - 1080 / 1.1701) < 1.0 and absf(ps.y - 1920 / 1.1701) < 1.0, "the panel in points (%s)" % ps)
	ok(m.scale_preview.info_text().contains("× "), m.scale_preview.info_text())
	eq(m.shell.get_element_model("scale-mode-menu").get_attribute("text"), "Scale With Screen Size", "the mode menu")
	eq(m.shell.get_field_value("reference-width-field"), "1920")
	eq(m.shell.get_field_value("match-field"), "0.5")
	# A new screen size: the info follows.
	m._set_preset(_preset_index(m, Vector2i(3840, 2160)))
	await frames(3)
	ok(absf(m.canvas.host.pixels_per_point() - 2.0) < 0.0001, "3840 x 2160: 2 px/pt (%s)" % m.canvas.host.pixels_per_point())
	ok(m.scale_preview.info_text().begins_with("2 px/pt · 1920 × 1080 pt"), m.scale_preview.info_text())


func test_fields_of_the_bar_change_the_scale() -> void:
	var m := await editor()
	m.scale_preview.set_mode(CPS)
	await frames(2)
	eq(m.canvas.host.pixels_per_point(), 1.0, "Constant Pixel Size at scale 1")
	m._on_shell_value("scale-field", "2")
	await frames(2)
	eq(m.canvas.host.pixels_per_point(), 2.0, "scale 2")
	ok(m.scale_preview.info_text().begins_with("2 px/pt · 640 × 360 pt"), m.scale_preview.info_text())
	m._on_shell_value("scale-field", "abc")
	eq(m.scale_preview.settings.scale, 2.0, "an invalid value changes nothing")
	eq(m.shell.get_field_value("scale-field"), "2", "the field shows the value again")
	m.scale_preview.set_mode(CPH)
	m._on_shell_value("dpi-field", "192")
	await frames(2)
	ok(absf(m.canvas.host.pixels_per_point() - 4.0) < 0.0001, "192 dpi over 96 at scale 2 (%s)" % m.canvas.host.pixels_per_point())
	m.scale_preview.set_mode(SWS)
	m._on_shell_value("reference-width-field", "640")
	m._on_shell_value("reference-height-field", "360")
	m._on_shell_value("scale-field", "1")
	await frames(2)
	ok(absf(m.canvas.host.pixels_per_point() - 2.0) < 0.0001, "1280 x 720 at reference 640 x 360 (%s)" % m.canvas.host.pixels_per_point())
	m.scale_preview.set_mode(EdScalePreview.NONE)
	await frames(2)
	eq(m.canvas.host.pixels_per_point(), 1.0, "no settings again")
	eq(m.state.workspace.history.undo_depth(), 0, "the preview is not an edit")
	for p in m.state.workspace.buffers:
		eq(m.state.workspace.text(p), FileAccess.get_file_as_string(_dir + "/" + p), "%s keeps its bytes" % p)


func test_panel_settings_asset_of_the_project() -> void:
	var m := await editor("panel")
	eq(m.scale_preview.assets, [GAME_ASSET], "the PanelSettings asset, not the other asset")
	var before := m.canvas.host.renders
	m.scale_preview.choose_asset(1)
	await frames(4)
	var ps := m.scale_preview.settings
	ok(ps != null and int(ps.scale_mode) == SWS, "the mode of the asset")
	eq(ps.reference_resolution, Vector2i(1920, 1080), "the reference of the asset")
	ok(is_equal_approx(ps.match_width_or_height, 0.5), "the match of the asset")
	ok(ps.theme_style_sheet.ends_with("Game.tss"), "the theme style sheet by its GUID (%s)" % ps.theme_style_sheet)
	ok(m.canvas.host.renders > before, "a new theme loads the document again")
	eq(m.shell.get_element_model("panel-asset-menu").get_attribute("text"), "Game.asset")
	# The .tss imports the default theme and colours every label red.
	var cs := m.canvas.host.computed_style(node_named(m, "menu-title").id)
	var color := String(cs.get("color", {}).get("value", ""))
	ok(color.contains("255, 0, 0") or color.to_lower().contains("ff0000") or color.contains("1, 0, 0"), "the theme of the asset applies (%s)" % color)
	ok(absf(m.canvas.host.pixels_per_point() - 1280.0 / 1920.0) < 0.001, "1280 x 720 at reference 1920 x 1080 (%s)" % m.canvas.host.pixels_per_point())
	m._on_shell_value("match-field", "1")
	await frames(2)
	eq(m.shell.get_element_model("panel-asset-menu").get_attribute("text"), "Game.asset (edited)")
	m.scale_preview.choose_asset(0)
	await frames(3)
	eq(m.scale_preview.settings.theme_style_sheet, "", "custom settings drop the theme of the asset")
	eq(m.shell.get_element_model("panel-asset-menu").get_attribute("text"), EdScalePreview.NO_ASSET)
	eq(m.state.workspace.history.undo_depth(), 0, "the preview is not an edit")


func test_select_move_resize_at_each_scale() -> void:
	for c in _cases():
		var m := await _scaled(c["screen"], c["mode"], c["scale"])
		var ppp: float = c["ppp"]
		var host := m.canvas.host
		ok(absf(host.pixels_per_point() - ppp) < 0.0001, "%s px/pt (%s)" % [ppp, host.pixels_per_point()])
		await _make_absolute(m, "quit-button")
		var quit := node_named(m, "quit-button")
		var r := host.rect_of(quit.id)
		var rp := host.points_rect_of(quit.id)
		ok(absf(r.size.x - rp.size.x * ppp) < 0.01 and absf(r.position.y - rp.position.y * ppp) < 0.01, "pixels are points times %s (%s, %s)" % [ppp, r, rp])
		ok(rp.size.x >= 179.5, "min-width 180 in points (%s)" % rp.size.x)
		# Select: a click in the middle of the button (document pixels).
		var at := m.canvas.screen_to_global(r.get_center())
		ok(m.canvas.get_global_rect().has_point(at), "the button is in the canvas")
		mouse_button(m, at, true)
		await frames(1)
		mouse_button(m, at, false)
		await frames(2)
		eq(m.state.selected_node().get_attribute("name") if m.state.selected_node() != null else "", "quit-button", "a click selects at %s px/pt" % ppp)
		var v := m.canvas.screen_rect_to_view(r)
		eq(m.canvas.handle_at(v.get_center()), "move", "the handles are on the outline")
		eq(m.canvas.handle_at(v.end), "se", "the corner handle")
		# Move by (30, 20) points: (30, 20) * ppp pixels.
		m.layout.snap_enabled = false
		var left0 := _px(m, "quit-button", "left")
		var top0 := _px(m, "quit-button", "top")
		var d := Vector2(30, 20)
		await drag(m, at, at + d * ppp * m.canvas.zoom, 5)
		var t := m.state.workspace.text(MENU)
		ok(t.contains("left: %dpx" % int(roundf(left0 + 30))) and t.contains("top: %dpx" % int(roundf(top0 + 20))),
			"a move writes points at %s px/pt (left %s, top %s): %s" % [ppp, left0, top0, t])
		var r2 := host.points_rect_of(quit.id)
		ok(absf(r2.position.x - (rp.position.x + 30)) <= 1.0 / ppp + 0.01, "the render follows in points (%s -> %s)" % [rp.position.x, r2.position.x])
		# Resize by (40.2, 10.2) points from the corner (not a half point:
		# a size at a half point rounds either way).
		var rr := host.rect_of(node_named(m, "quit-button").id)
		var rrp := host.points_rect_of(node_named(m, "quit-button").id)
		var se := m.canvas.screen_to_global(rr.end)
		await drag(m, se, se + Vector2(40.2, 10.2) * ppp * m.canvas.zoom, 5)
		t = m.state.workspace.text(MENU)
		var w := int(roundf(rrp.size.x + 40.2))
		var h := int(roundf(rrp.size.y + 10.2))
		ok(t.contains("width: %dpx" % w) and t.contains("height: %dpx" % h), "a resize writes points at %s px/pt (%d x %d): %s" % [ppp, w, h, t])
		var r3 := host.points_rect_of(node_named(m, "quit-button").id)
		ok(absf(r3.size.x - w) <= 1.0 / ppp + 0.01 and absf(r3.size.y - h) <= 1.0 / ppp + 0.01, "the size follows (%s)" % r3.size)
		# Each gesture is one step: the position setup, the move, the resize.
		eq(m.state.workspace.history.undo_depth(), 3, "one undo step per gesture")
		# A nudge moves one point.
		var left1 := _px(m, "quit-button", "left")
		m.canvas.grab_focus()
		key(m, KEY_RIGHT)
		await frames()
		eq(_px(m, "quit-button", "left"), left1 + 1.0, "a nudge key is one point at %s px/pt" % ppp)
		await teardown_editor(m)


func test_snap_and_guides_at_each_scale() -> void:
	for c in _cases():
		var m := await _scaled(c["screen"], c["mode"], c["scale"])
		var ppp: float = c["ppp"]
		var host := m.canvas.host
		await _make_absolute(m, "quit-button")
		var quit := node_named(m, "quit-button")
		m.state.select_node(quit, "test")
		await frames()
		var rp := host.points_rect_of(quit.id)
		var play_p := host.points_rect_of(node_named(m, "play-button").id)
		var play_px := host.rect_of(node_named(m, "play-button").id)
		# The left edge 2 points right of the play button's left edge, and
		# 30.4 points down: snaps to the sibling on x, to the grid on y.
		m.layout.grid = 4
		var d := Vector2(play_p.position.x + 2 - rp.position.x, 30.4)
		var a := m.canvas.screen_to_global(host.rect_of(quit.id).get_center())
		mouse_button(m, a, true)
		await frames(1)
		mouse_move(m, a + d * ppp * m.canvas.zoom * 0.5)
		await frames(1)
		mouse_move(m, a + d * ppp * m.canvas.zoom)
		await frames(1)
		var gx: Array = m.canvas.guides.get("x", [])
		var gy: Array = m.canvas.guides.get("y", [])
		ok(gx.size() == 1 and absf(float(gx[0]) - play_px.position.x) < 0.01, "the guide is in document pixels at %s px/pt (%s vs %s)" % [ppp, gx, play_px.position.x])
		mouse_button(m, a + d * ppp * m.canvas.zoom, false)
		await frames()
		var q := host.points_rect_of(quit.id)
		ok(absf(q.position.x - play_p.position.x) <= 1.0 / ppp + 0.01, "the left edge snapped to the sibling in points (%s vs %s)" % [q.position.x, play_p.position.x])
		# Without a y target in reach, the top edge snaps to the grid in
		# panel points. The written value is a whole point and the layout puts
		# the edge on the pixel grid: up to half a point and one pixel off.
		if gy.is_empty():
			var off := fmod(q.position.y, 4.0)
			ok(minf(off, 4.0 - off) <= 0.5 + 1.0 / ppp + 0.01, "the top edge snaps to the 4-point grid at %s px/pt (%s)" % [ppp, q.position.y])
		else:
			# The top, middle or bottom edge is on the guide (document pixels).
			var qp := host.rect_of(quit.id)
			var near := INF
			for e in [qp.position.y, qp.get_center().y, qp.end.y]:
				near = minf(near, absf(float(e) - float(gy[0])))
			ok(near <= 1.0 + 0.5 * ppp, "an edge snapped to the y guide at %s px/pt (%s, %s)" % [ppp, qp, gy])
		eq(m.canvas.guides, {}, "guides clear after the gesture")
		# The snap threshold is 6 view pixels: 20 points is out of reach at
		# zoom 1 for every scale here.
		var far := EdSnap.snap_gesture(rp, "move", Vector2(play_p.position.x + 20 - rp.position.x, 0), EdSnap.targets(Rect2(), [play_p]), 0.0, EdLayoutController.SNAP_THRESHOLD_VIEW / (m.canvas.zoom * ppp))
		eq(far["guides_x"], [], "no snap from 20 points away at %s px/pt" % ppp)
		await teardown_editor(m)


func test_overlay_of_an_untransformed_element_under_a_scale() -> void:
	var m := await _scaled(Vector2i(1280, 720), CPS, 2.0)
	var host := m.canvas.host
	var id := node_named(m, "play-button").id
	var b := host.local_box_of(id)
	var t: Transform2D = b["transform"]
	ok(t.x.is_equal_approx(Vector2(2, 0)) and t.y.is_equal_approx(Vector2(0, 2)), "the element transform is the panel scale (%s)" % t)
	var corner: Vector2 = t * Vector2(b["size"])
	ok(corner.distance_to(host.rect_of(id).end) < 0.01, "the local box in points maps onto the pixel rectangle")
	# A hit on a document pixel finds the element there.
	eq(host.hit_test(host.rect_of(id).get_center()), id, "element_at in document pixels")
	eq(host.hit_test(host.points_rect_of(id).get_center()) == id, host.points_rect_of(id).get_center().distance_to(host.rect_of(id).get_center()) < 1.0,
		"points are not pixels for the hit test")


func teardown_editor(m: EdMain) -> void:
	m.queue_free()
	await frames(2)
	if not _dir.is_empty():
		_rm(_dir)
		_dir = ""
