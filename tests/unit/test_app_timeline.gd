extends EdAppTestCase
## Milestone 6 in the real editor scene: state and class changes play on
## the canvas (godot-uxml request R7), the timeline panel, its edits through
## the write targets of the inspector, the easing curve and picker.

const SHEET := """.menu-root {
  padding-left: 24px;
}

/* keep this comment */
.menu-button {
  min-width: 180px;
  background-color: #000000;
  transition-property: background-color, min-width;
  transition-duration: 0.4s, 1s;
  transition-delay: 0s, 0.2s;
  transition-timing-function: ease-in, linear;
}

.menu-button.primary {
  color: #ffffff;
}

.menu-button:hover {
  background-color: #ff0000;
  min-width: 300px;
}

.alt {
  min-width: 400px;
}
"""


func _open(sheet: String = SHEET) -> EdMain:
	tree.root.size = Vector2i(1600, 1000)
	var dir := copy_fixture("menu")
	var f := FileAccess.open(dir + "/" + MENU_USS, FileAccess.WRITE)
	f.store_string(sheet)
	f.close()
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(m)
	await frames()
	m.state.open_project(dir)
	await frames()
	return m


func _select(m: EdMain, authored: String) -> EdUxmlNode:
	var n := node_named(m, authored)
	m.state.select_node(n, "test")
	await frames()
	m.inspector.flush()
	return n


func _value(m: EdMain, n: EdUxmlNode, prop: String) -> String:
	return String(m.canvas.host.computed_style(n.id)[prop]["value"])


func _width(m: EdMain, n: EdUxmlNode) -> float:
	return String(_value(m, n, "min-width")).trim_suffix("px").to_float()


func _track(m: EdMain, prop: String) -> int:
	for i in m.timeline.model.tracks.size():
		if m.timeline.model.tracks[i]["property"] == prop:
			return i
	return -1


## Wait until the playback ends (a slow machine plays with long frames).
func _until_stopped(m: EdMain) -> void:
	var t0 := Time.get_ticks_msec()
	while m.timeline.model.playing and Time.get_ticks_msec() - t0 < 60000:
		await tree.process_frame


func _run_hover(m: EdMain, n: EdUxmlNode) -> void:
	var cls := EdInspectorView.author_classes(n)
	m.timeline.run({"classes": cls, "states": []}, {"classes": cls, "states": ["hover"]})
	await frames()


func _bar_point(m: EdMain, i: int, end: bool = false) -> Vector2:
	var r: Rect2 = m.timeline.bar_rect(i)
	return m.timeline.to_global(Vector2(r.end.x if end else r.position.x + r.size.x * 0.4, r.get_center().y))


# ---------------------------------------------------------------------------
# Tracks
# ---------------------------------------------------------------------------

func test_the_tracks_show_the_declared_transitions() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	var t: Array = m.timeline.model.tracks
	eq(t.size(), 2, "one track per transitioning property")
	eq(t[0]["property"], "background-color")
	eq(t[0]["duration"], 0.4)
	eq(t[0]["delay"], 0.0)
	eq(t[0]["easing"], "ease-in")
	eq(t[1]["property"], "min-width")
	eq(t[1]["delay"], 0.2)
	eq(t[1]["duration"], 1.0)
	eq(t[1]["easing"], "linear")
	ok(not t[0]["running"], "declared, not running")
	eq(m.timeline.model.length(), 1.2)
	await _select(m, "menu-title")
	eq(m.timeline.model.tracks.size(), 0, "a label without transitions")
	ok(EdUi.full_text(m.shell, "tl-info").begins_with("No transition"), "the panel says so")


func test_document_scope_lists_every_element_also_without_a_selection() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	m.timeline.set_scope("document")
	eq(m.timeline.model.tracks.size(), 4, "two buttons, two transitions each")
	ok(m.timeline.model.tracks.any(func(t): return String(t["label"]).contains("#play-button")))
	m.state.select_node(null, "test")
	await frames()
	eq(m.timeline.model.tracks.size(), 4, "no selection: the document stays")
	m.timeline.set_scope("selection")
	eq(m.timeline.model.tracks.size(), 0)
	eq(m.timeline.settings.get_value("timeline", "scope"), "selection")


func test_bars_have_the_times_of_their_track() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	await frames()
	var a: Rect2 = m.timeline.bar_rect(0)
	var b: Rect2 = m.timeline.bar_rect(1)
	var pps := a.size.x / 0.4
	ok(pps > 10.0, "a scale")
	ok(absf(b.size.x - pps) < 0.01, "the bar length is the duration")
	ok(absf(b.position.x - a.position.x - pps * 0.2) < 0.01, "the bar start is the delay")
	ok(b.position.y >= a.end.y, "one row per track")
	eq(m.timeline.hit(b.get_center())["kind"], "bar")
	eq(m.timeline.hit(b.get_center())["track"], 1)
	eq(m.timeline.hit(Vector2(b.end.x, b.get_center().y))["kind"], "end")
	eq(m.timeline.hit(Vector2(b.position.x, 2.0 + m.timeline._area().position.y))["kind"], "ruler")
	await frames(2)
	ok(m.timeline.draws > 0, "the panel draws")


# ---------------------------------------------------------------------------
# Live playback of state and class changes
# ---------------------------------------------------------------------------

func test_a_state_toggle_plays_on_the_canvas() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	var before := m.state.workspace.text(MENU_USS)
	eq(_value(m, n, "min-width"), "180px")
	m.inspector.set_state("hover", true)
	ok(m.timeline.player.armed, "the toggle starts a run")
	ok(m.timeline.model.playing, "and plays it")
	eq(m.timeline.model.tracks.size(), 2)
	ok(m.timeline.model.tracks[0]["running"], "running tracks")
	eq(m.timeline.model.tracks[1]["from"], "180px")
	eq(m.timeline.model.tracks[1]["to"], "300px")
	ok(_width(m, n) < 300.0, "the canvas starts at the old value")
	var seeks0: int = m.timeline.seeks
	await _until_stopped(m)
	ok(m.timeline.seeks > seeks0, "playback moves the transitions")
	ok(not m.timeline.model.playing, "the run ends")
	eq(_value(m, n, "min-width"), "300px", "the canvas ends at the new value")
	await frames()
	m.inspector.flush()
	var field := "style-%d" % EdInspectorView.COMMON_STYLES.find("min-width")
	ok(m.inspector.placeholder_of(field).begins_with("300px"), "the inspector shows the end value: " + m.inspector.placeholder_of(field))
	# And back.
	m.inspector.set_state("hover", false)
	ok(m.timeline.model.playing, "the change back plays too")
	await _until_stopped(m)
	eq(_value(m, n, "min-width"), "180px")
	eq(m.state.workspace.text(MENU_USS), before, "a run changes no source")
	ok(not m.state.workspace.is_dirty(MENU_USS))
	eq(m.state.workspace.history.undo_depth(), 0, "and no undo step")


func test_a_class_toggle_plays_on_the_canvas() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.inspector._set_text_of("new-class", "alt")
	m.inspector._on_button("add-class")
	await frames()
	ok(m.state.workspace.text(MENU).contains("class = 'menu-button alt'"), "the class edit")
	ok(m.timeline.player.armed, "the class edit starts a run")
	eq(m.timeline.from_state["classes"], ["menu-button"])
	eq(m.timeline.to_state["classes"], ["menu-button", "alt"])
	n = node_named(m, "quit-button")
	await _until_stopped(m)
	eq(_value(m, n, "min-width"), "400px")
	# Remove: the run goes the other way.
	m.inspector.flush()
	m.inspector._on_button("remove-class-1")
	await frames()
	eq(m.timeline.to_state["classes"], ["menu-button"])
	await _until_stopped(m)
	eq(_value(m, node_named(m, "quit-button"), "min-width"), "180px")


func test_a_run_ends_with_the_source_and_the_state_preview() -> void:
	var m := await _open()
	var n := await _select(m, "play-button")
	m.timeline.run({"classes": ["alt"], "states": []}, {"classes": ["alt"], "states": ["hover"]})
	await frames()
	var el: UxmlElement = m.canvas.host.element_for_node[n.id]
	ok(String(el.get_attribute("class")).contains("alt"), "the run shows its classes")
	ok(m.canvas.host.doc.transitions_manual, "the timeline holds the clock")
	# The selection changes: the run ends.
	await _select(m, "quit-button")
	ok(not m.timeline.player.armed)
	eq(String(el.get_attribute("class")).split(" ", false).has("alt"), false, "the source classes are back")
	ok(String(el.get_attribute("class")).contains("menu-button"))
	eq(m.canvas.host.doc.get_forced_states(el).size(), 0, "no forced state")
	ok(not m.canvas.host.doc.transitions_manual, "the frame clock is back")
	# A forced state of the preview stays.
	await _select(m, "play-button")
	m.inspector.set_state("checked", true)
	await frames()
	m.timeline.stop()
	eq(Array(m.canvas.host.doc.get_forced_states(el)), ["checked"], "the preview state stays")


func test_preview_and_a_canvas_gesture_end_the_run() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	ok(m.timeline.player.armed)
	m.set_preview(true)
	await frames()
	ok(not m.timeline.player.armed, "preview ends the run")
	m.set_preview(false)
	await frames()
	await _select(m, "play-button")
	n = await _select(m, "quit-button")
	await _run_hover(m, n)
	var c := m.canvas.screen_to_global(m.canvas.host.rect_of(n.id).get_center())
	await drag(m, c, c + Vector2(30, 0))
	ok(not m.timeline.player.armed, "a canvas drag ends the run")


func test_an_edit_during_a_run_keeps_the_playhead_and_the_source_classes() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	m.timeline.seek_to(0.7)
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(n), "class", "menu-button extra"), "test")
	await frames()
	ok(m.timeline.player.armed, "the run stays")
	eq(m.timeline.model.time, 0.7, "the playhead stays")
	n = node_named(m, "quit-button")
	var el: UxmlElement = m.canvas.host.element_for_node[n.id]
	m.timeline.stop()
	ok(String(el.get_attribute("class")).split(" ", false).has("extra"), "the end of the run keeps the edit")
	# Undo during a run.
	await _run_hover(m, n)
	m.state.undo()
	await frames()
	m.timeline.stop()
	n = node_named(m, "quit-button")
	eq(EdInspectorView.author_classes(n), ["menu-button"])
	el = m.canvas.host.element_for_node[n.id]
	ok(not String(el.get_attribute("class")).split(" ", false).has("extra"))


func test_another_document_resets_the_timeline() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	var f := FileAccess.open(_dir + "/Assets/UI/Other.uxml", FileAccess.WRITE)
	f.store_string("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><ui:Label name=\"x\" text=\"x\" /></ui:UXML>\n")
	f.close()
	m.state.open_project(_dir)
	await frames()
	m.state.open_document("Assets/UI/Other.uxml")
	await frames()
	ok(not m.timeline.player.armed)
	eq(m.timeline.model.tracks.size(), 0, "no track of the other document")


# ---------------------------------------------------------------------------
# Scrub, play, pause, loop, speed
# ---------------------------------------------------------------------------

func test_seek_shows_the_eased_value_at_a_time() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	var w := _track(m, "min-width")
	ok(w >= 0)
	m.timeline.seek_to(0.1)
	eq(_value(m, n, "min-width"), "180px", "inside the delay: the start value")
	m.timeline.seek_to(0.7)
	ok(absf(_width(m, n) - 240.0) < 0.5, "linear, half way: %s" % _value(m, n, "min-width"))
	m.timeline.seek_to(1.2)
	eq(_value(m, n, "min-width"), "300px", "the end value")
	m.timeline.seek_to(0.2)
	eq(_value(m, n, "min-width"), "180px", "back again")
	m.timeline.seek_to(99.0)
	eq(m.timeline.model.time, 1.2, "the playhead stays in the run")
	eq(_value(m, n, "min-width"), "300px")


func test_a_mouse_drag_over_the_ruler_scrubs() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	var src := m.state.workspace.text(MENU_USS)
	var y: float = m.timeline._area().position.y + 6.0
	var a := m.timeline.to_global(Vector2(m.timeline.time_x(0.1), y))
	var b := m.timeline.to_global(Vector2(m.timeline.time_x(0.7), y))
	var s0: int = m.timeline.seeks
	await drag(m, a, b, 4)
	ok(m.timeline.seeks - s0 >= 4, "one seek per move")
	ok(absf(m.timeline.model.time - 0.7) < 0.01, "the playhead follows: %f" % m.timeline.model.time)
	ok(absf(_width(m, n) - 240.0) < 2.0, "the canvas follows: %s" % _value(m, n, "min-width"))
	eq(m.state.workspace.text(MENU_USS), src, "no edit")
	ok(m.shell.get_native("tl-time").text.begins_with("0.70 s"), m.shell.get_native("tl-time").text)


func test_play_pause_loop_and_speed() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	# The Play button arms the run of the From and To choice.
	eq(m.timeline.to_state["states"], ["hover"], "the default run: to :hover")
	m._on_button("tl-play")
	ok(m.timeline.model.playing)
	ok(m.timeline.player.armed)
	eq(m.shell.get_native("tl-play").text, "❚❚")
	m._on_button("tl-play")
	ok(not m.timeline.model.playing, "pause")
	eq(m.shell.get_native("tl-play").text, "▶")
	var t: float = m.timeline.model.time
	await frames(3)
	eq(m.timeline.model.time, t, "a pause holds the playhead")
	# Loop.
	m._on_shell_value("tl-loop", true)
	ok(m.timeline.model.loop)
	m.timeline.set_speed(2.0)
	eq(m.timeline.model.speed, 2.0)
	eq(String(m.shell.get_element_model("tl-speed").get_attribute("text")), "2×")
	m._on_button("tl-play")
	var t0 := Time.get_ticks_msec()
	var wrapped := false
	var last: float = m.timeline.model.time
	while Time.get_ticks_msec() - t0 < 30000 and not wrapped:
		await tree.process_frame
		wrapped = m.timeline.model.time < last
		last = m.timeline.model.time
	ok(wrapped, "the playhead starts again")
	ok(m.timeline.model.playing, "a loop keeps playing")
	m.timeline.set_loop(false)
	await _until_stopped(m)
	ok(not m.timeline.model.playing, "without loop it stops")
	m._on_button("tl-restart")
	eq(m.timeline.model.time, 0.0)
	# Options are per-user settings.
	eq(m.timeline.settings.get_value("timeline", "speed"), 2.0)
	var fresh := EdSettings.new(m.timeline.settings.path)
	eq(fresh.get_value("timeline", "speed"), 2.0, "saved")
	eq(fresh.get_value("timeline", "loop"), false)


func test_the_from_and_to_choice() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	# Class a -> class b.
	ok(m.timeline.set_state_text("from", ".menu-button"))
	ok(m.timeline.set_state_text("to", ".menu-button.alt"))
	ok(m.timeline.player.armed)
	m.timeline.seek_to(1.2)
	eq(_value(m, n, "min-width"), "400px", "the To class wins")
	m.timeline.seek_to(0.0)
	eq(_value(m, n, "min-width"), "180px", "the From class")
	eq(m.state.workspace.text(MENU).count(" alt"), 0, "a run edits no text")
	# A state -> a state.
	ok(m.timeline.set_state_text("from", ".menu-button:hover"))
	ok(m.timeline.set_state_text("to", ".menu-button"))
	m.timeline.seek_to(0.0)
	eq(_value(m, n, "min-width"), "300px")
	m.timeline.seek_to(1.2)
	eq(_value(m, n, "min-width"), "180px")
	# Refused text changes nothing.
	var msgs: Array = []
	m.timeline.status.connect(func(msg, err): msgs.append([msg, err]))
	ok(not m.timeline.set_state_text("to", "not a state"))
	eq(msgs.size(), 1, "a message")
	ok(msgs[0][1], "an error")
	eq(EdTimelineModel.state_text(m.timeline.to_state), ".menu-button")
	# The menus offer the states and the classes of the rules.
	var items: Array = m.timeline._menu_choices["to"].map(EdTimelineModel.state_text)
	ok(items.has(".menu-button:hover"), str(items))
	ok(items.has(".menu-button.alt"), str(items))
	ok(items.has(".menu-button.primary"), str(items))
	# The field shows the state.
	eq((m.shell.get_native("tl-to") as LineEdit).text, ".menu-button")
	eq((m.shell.get_native("tl-from") as LineEdit).text, ".menu-button:hover")


func test_no_transition_runs() -> void:
	var m := await _open()
	await _select(m, "menu-title")
	var msgs: Array = []
	m.timeline.status.connect(func(msg, _e): msgs.append(msg))
	m.timeline.toggle_play()
	ok(not m.timeline.model.playing)
	eq(msgs.size(), 1, "a message")
	m.timeline.stop()
	m.state.select_node(null, "test")
	await frames()
	m.timeline.toggle_play()
	ok(not m.timeline.player.armed, "no selection: no run")


# ---------------------------------------------------------------------------
# Edits from the timeline
# ---------------------------------------------------------------------------

func test_a_bar_drag_changes_the_delay_as_one_undo_step() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU_USS)
	await frames()
	var w := _track(m, "min-width")
	var p := _bar_point(m, w)
	var pps: float = m.timeline._pps
	await drag(m, p, p + Vector2(pps * 0.2, 0), 5)
	await frames()
	ok(m.state.workspace.text(MENU_USS).contains("transition-delay: 0s, 0.4s;"), m.state.workspace.text(MENU_USS))
	eq(m.state.workspace.history.undo_depth(), 1, "one undo step for the whole drag")
	# More than one target: the picker asks at the end.
	ok(not m.inspector.pending.is_empty(), "the write-target picker asks")
	ok(m.inspector.pending_labels()[0].contains(".menu-button"), str(m.inspector.pending_labels()))
	ok(m.inspector.pending_labels()[0].contains("(wins)"), "the winner first")
	ok(m.inspector.choose(0))
	await frames()
	eq(m.state.workspace.history.undo_depth(), 1, "the chosen target needs no second step")
	# The bytes outside the value stay.
	eq(m.state.workspace.text(MENU_USS), src.replace("transition-delay: 0s, 0.2s;", "transition-delay: 0s, 0.4s;"))
	# The next drag uses the remembered choice: no question.
	eq(m.timeline.model.tracks[w]["delay"], 0.4, "the track follows")
	p = _bar_point(m, w)
	await drag(m, p, p + Vector2(pps * 0.1, 0), 3)
	await frames()
	ok(m.inspector.pending.is_empty(), "the choice is remembered")
	ok(m.state.workspace.text(MENU_USS).contains("transition-delay: 0s, 0.5s;"), m.state.workspace.text(MENU_USS))
	eq(m.state.workspace.history.undo_depth(), 2, "one step per gesture")
	m.state.undo()
	await frames()
	m.state.undo()
	await frames()
	eq(m.state.workspace.text(MENU_USS), src, "undo restores the exact text")
	var _unused := n


func test_a_drag_of_the_bar_end_changes_the_duration() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU_USS)
	await frames()
	m.inspector.remember_choice("transition-duration", m.inspector.gesture_target("transition-duration")["choice"]["id"])
	var bg := _track(m, "background-color")
	var p := _bar_point(m, bg, true)
	var pps: float = m.timeline._pps
	await drag(m, p, p + Vector2(pps * 0.2, 0), 4)
	await frames()
	var text := m.state.workspace.text(MENU_USS)
	ok(text.contains("transition-duration: 0.6s, 1s;"), text)
	eq(m.state.workspace.history.undo_depth(), 1)
	ok(m.inspector.pending.is_empty(), "a remembered choice: no question")
	ok(text.contains("/* keep this comment */"), "the comment stays")
	m.state.undo()
	await frames()
	eq(m.state.workspace.text(MENU_USS), src)


func test_a_cancelled_question_undoes_the_drag() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU_USS)
	await frames()
	var p := _bar_point(m, _track(m, "min-width"))
	await drag(m, p, p + Vector2(40, 0), 3)
	await frames()
	ok(not m.inspector.pending.is_empty())
	ok(not m.inspector.choose(99), "cancel")
	await frames()
	eq(m.state.workspace.text(MENU_USS), src, "the drag is gone")
	eq(m.state.workspace.history.undo_depth(), 0)


func test_another_target_gets_the_end_of_the_drag() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU_USS)
	await frames()
	var p := _bar_point(m, _track(m, "min-width"))
	var pps: float = m.timeline._pps
	await drag(m, p, p + Vector2(pps * 0.2, 0), 3)
	await frames()
	ok(m.inspector.choose_id("inline"), str(m.inspector.pending_labels()))
	await frames()
	eq(m.state.workspace.text(MENU_USS), src, "the rule has its text again")
	n = node_named(m, "quit-button")
	ok(String(n.get_attribute("style")).contains("transition-delay: 0s, 0.4s"), str(n.get_attribute("style")))
	eq(m.state.workspace.history.undo_depth(), 1, "one undo step")
	eq(m.inspector.remembered_choice("transition-delay"), "inline")


func test_during_a_run_the_targets_come_from_the_to_state() -> void:
	# The state rule gives its own duration: the drag edits that rule.
	var sheet := SHEET.replace("  min-width: 300px;\n", "  min-width: 300px;\n  transition-duration: 2s;\n")
	var m := await _open(sheet)
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	var w := _track(m, "min-width")
	eq(m.timeline.model.tracks[w]["duration"], 2.0, "the run uses the state rule")
	var p := _bar_point(m, w, true)
	var pps: float = m.timeline._pps
	await drag(m, p, p - Vector2(pps * 0.5, 0), 3)
	await frames()
	ok(m.inspector.pending_labels().size() > 0, "a question")
	ok(m.inspector.pending_labels()[0].contains(":hover"), str(m.inspector.pending_labels()))
	m.inspector.choose(0)
	await frames()
	var text := m.state.workspace.text(MENU_USS)
	ok(text.contains("transition-duration: 2s, 1.5s;"), "one entry of the list changes: " + text)
	ok(text.contains("transition-duration: 0.4s, 1s;"), "the other rule keeps its text")
	ok(m.timeline.player.armed, "the run goes on")
	eq(m.timeline.model.tracks[w]["duration"], 1.5, "with the new time")


func test_a_transition_shorthand_gets_a_longhand_after_it() -> void:
	var sheet := ".menu-button {\n  transition: min-width 1s ease-in 0.5s;\n}\n.menu-button:hover {\n  min-width: 300px;\n}\n"
	var m := await _open(sheet)
	await _select(m, "quit-button")
	await frames()
	eq(m.timeline.model.tracks.size(), 1)
	eq(m.timeline.model.tracks[0]["delay"], 0.5)
	m.timeline.edit_track(0, "end", 2.0)
	await frames()
	ok(m.inspector.pending_labels().size() > 0)
	m.inspector.choose(0)
	await frames()
	var text := m.state.workspace.text(MENU_USS)
	ok(text.contains("transition: min-width 1s ease-in 0.5s;"), "the shorthand stays: " + text)
	ok(text.contains("transition-duration: 2s;"), text)
	ok(text.find("transition-duration") > text.find("transition:"), "after the shorthand")
	eq(m.timeline.model.tracks[0]["duration"], 2.0, "the longhand applies")


func test_escape_cancels_a_bar_drag() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	var src := m.state.workspace.text(MENU_USS)
	await frames()
	var p := _bar_point(m, _track(m, "min-width"))
	mouse_button(m, p, true)
	await frames(1)
	var delay0: float = m.timeline.model.tracks[_track(m, "min-width")]["delay"]
	mouse_move(m, p + Vector2(40, 0))
	await frames(2)
	eq(m.state.workspace.text(MENU_USS), src, "a drag writes at its end")
	ok(m.timeline.model.tracks[_track(m, "min-width")]["delay"] != delay0, "the bar follows the pointer")
	key(m, KEY_ESCAPE)
	await frames(2)
	mouse_button(m, p + Vector2(40, 0), false)
	await frames(2)
	eq(m.state.workspace.text(MENU_USS), src, "escape leaves the text")
	eq(m.timeline.model.tracks[_track(m, "min-width")]["delay"], delay0, "and the bar goes back")
	ok(m.inspector.pending.is_empty(), "no question")
	eq(m.state.workspace.history.undo_depth(), 0)


func test_a_bar_drag_writes_once_and_previews_on_the_run() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	await frames()
	var src := m.state.workspace.text(MENU_USS)
	var tl := m.timeline
	var prop := "transition-delay"
	m.inspector.remember_choice(prop, m.inspector.gesture_target(prop, ["hover"])["choice"]["id"])
	var w := _track(m, "min-width")
	var p := _bar_point(m, w)
	var pps: float = tl._pps
	var renders: int = m.canvas.host.renders + m.canvas.host.patches
	mouse_button(m, p, true)
	await frames(1)
	mouse_move(m, p + Vector2(pps * 0.2, 0))
	await frames(2)
	eq(m.state.workspace.text(MENU_USS), src, "no patch during the drag")
	eq(tl.model.tracks[_track(m, "min-width")]["delay"], 0.4, "the run uses the new delay: the preview")
	var el: UxmlElement = m.canvas.host.element_for_node[n.id]
	ok(String(el.get_attribute("style")).contains("transition-delay"), "the preview is in the model")
	mouse_move(m, p + Vector2(pps * 0.3, 0))
	await frames(2)
	mouse_button(m, p + Vector2(pps * 0.3, 0), false)
	await frames(2)
	ok(m.state.workspace.text(MENU_USS).contains("transition-delay: 0s, 0.5s;"), m.state.workspace.text(MENU_USS))
	eq(m.state.workspace.history.undo_depth(), 1, "one write, one undo step")
	eq(m.canvas.host.renders + m.canvas.host.patches, renders, "the stylesheet reload waits for a pause")
	ok(not m.reload_timer.is_stopped(), "the timer runs")
	eq(tl.model.tracks[_track(m, "min-width")]["delay"], 0.5, "the run keeps the value")
	# The pause: the render agrees with the source, and the preview is gone.
	m.flush_waiting_render()
	await frames(2)
	eq(m.canvas.host.renders + m.canvas.host.patches, renders + 1, "one reload")
	el = m.canvas.host.element_for_node[n.id]
	var style = el.get_attribute("style")
	ok(style == null or not String(style).contains("transition-delay"), "no preview: " + str(style))
	eq(tl.model.tracks[_track(m, "min-width")]["delay"], 0.5, "from the stylesheet now")
	ok(tl.player.armed, "the run goes on")
	# Undo restores the text and the run.
	m.state.undo()
	await frames(3)
	eq(m.state.workspace.text(MENU_USS), src, "undo restores the bytes")
	eq(tl.model.tracks[_track(m, "min-width")]["delay"], 0.2)


func test_an_undo_in_the_pause_after_a_bar_drag() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	await frames()
	var src := m.state.workspace.text(MENU_USS)
	var prop := "transition-delay"
	m.inspector.remember_choice(prop, m.inspector.gesture_target(prop, ["hover"])["choice"]["id"])
	var w := _track(m, "min-width")
	var p := _bar_point(m, w)
	await drag(m, p, p + Vector2(m.timeline._pps * 0.2, 0), 3)
	ok(not m.reload_timer.is_stopped(), "the pause runs")
	m.state.undo()
	await frames(3)
	eq(m.state.workspace.text(MENU_USS), src)
	ok(m.reload_timer.is_stopped(), "the undo renders: no render waits")
	eq(m.timeline.model.tracks[_track(m, "min-width")]["delay"], 0.2, "the run shows the source")
	var el: UxmlElement = m.canvas.host.element_for_node[n.id]
	var style = el.get_attribute("style")
	ok(style == null or not String(style).contains("transition-delay"), "no preview: " + str(style))


func test_a_selection_change_in_the_pause_renders_first() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	await frames()
	var prop := "transition-delay"
	m.inspector.remember_choice(prop, m.inspector.gesture_target(prop, ["hover"])["choice"]["id"])
	var p := _bar_point(m, _track(m, "min-width"))
	await drag(m, p, p + Vector2(m.timeline._pps * 0.2, 0), 3)
	var el: UxmlElement = m.canvas.host.element_for_node[n.id]
	await _select(m, "play-button")
	await frames(2)
	ok(m.reload_timer.is_stopped(), "no render waits")
	ok(not m.timeline.player.armed, "the run ended")
	var style = m.canvas.host.element_for_node[n.id].get_attribute("style")
	ok(style == null or not String(style).contains("transition-delay"), "no preview stays: " + str(style))
	var _unused := el


func test_a_refused_bar_write_changes_nothing() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await _run_hover(m, n)
	await frames()
	var src := m.state.workspace.text(MENU_USS)
	var prop := "transition-delay"
	m.inspector.remember_choice(prop, m.inspector.gesture_target(prop, ["hover"])["choice"]["id"])
	var w := _track(m, "min-width")
	var p := _bar_point(m, w)
	mouse_button(m, p, true)
	await frames(1)
	mouse_move(m, p + Vector2(m.timeline._pps * 0.2, 0))
	await frames(2)
	# The target goes away during the drag.
	m.timeline._drag["id"] = "rule:no-such-sheet:0"
	mouse_button(m, p + Vector2(m.timeline._pps * 0.2, 0), false)
	await frames(2)
	eq(m.state.workspace.text(MENU_USS), src, "refused")
	ok(not m.timeline.defer_next_render, "no render waits")
	eq(m.timeline.model.tracks[_track(m, "min-width")]["delay"], 0.2, "the run shows the source")
	var style = m.canvas.host.element_for_node[n.id].get_attribute("style")
	ok(style == null or not String(style).contains("transition-delay"), "no preview: " + str(style))


# ---------------------------------------------------------------------------
# Easing
# ---------------------------------------------------------------------------

func test_easing_curves_use_the_transition_function() -> void:
	eq(EdEasingCurve.value("linear", 0.25), 0.25)
	ok(EdEasingCurve.value("ease-in", 0.25) < 0.25, "ease-in starts slowly")
	ok(EdEasingCurve.value("ease-out", 0.25) > 0.25)
	eq(EdEasingCurve.value("no-such-easing", 0.3), 0.3, "unknown: linear")
	for kw in UssProperties.EASING_MODES:
		ok(EdEasingCurve.is_keyword(kw))
		eq(EdEasingCurve.value(kw, 0.0), UssTransitions.easing(UssProperties.EASING_MODES.find(kw), 0.0), kw)
		ok(absf(EdEasingCurve.value(kw, 1.0) - 1.0) < 0.001, "%s ends at 1" % kw)
		var pts := EdEasingCurve.points(kw, Rect2(10, 10, 100, 50))
		eq(pts.size(), EdEasingCurve.SAMPLES + 1)
		ok(pts[0].x == 10.0 and pts[-1].x == 110.0)
		for q in pts:
			ok(q.y >= 9.99 and q.y <= 60.01, "%s stays in the rectangle" % kw)


func test_the_inspector_shows_the_curve_and_the_picker_writes() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	m.inspector.flush()
	eq(m.inspector._easing_shown, "ease-in", "the first timing function")
	eq(String(m.inspector.doc.get_native("easing-name").text), "ease-in +1", "the name fits")
	eq(EdInspectorView.helper_kind("transition-timing-function"), "easing")
	m.inspector.remember_choice("transition-timing-function", "inline")
	m.inspector.open_easing_picker("transition-timing-function", m.inspector.doc.get_element("easing-curve"))
	await frames()
	var pick: EdEasingPicker = m.inspector.easing_picker
	ok(pick != null and pick.visible, "the picker opens")
	eq(pick._keywords, Array(UssProperties.EASING_MODES), "every Unity keyword")
	for kw in ["ease", "ease-in-out", "ease-out-bounce", "ease-in-elastic", "ease-in-back", "linear"]:
		ok(pick._keywords.has(kw), kw)
	var i: int = pick._keywords.find("ease-out-bounce")
	pick._on_button("ease-%d" % i)
	await frames()
	ok(not pick.visible, "a choice closes the picker")
	var n := node_named(m, "quit-button")
	ok(String(n.get_attribute("style")).contains("transition-timing-function: ease-out-bounce"), str(n.get_attribute("style")))
	eq(m.state.workspace.history.undo_depth(), 1, "one undo step")
	m.inspector.flush()
	eq(m.inspector._easing_shown, "ease-out-bounce", "the curve follows")


func test_the_timeline_edits_one_easing_of_a_list() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	await frames()
	var w := _track(m, "min-width")
	m.inspector.remember_choice("transition-timing-function", m.inspector.gesture_target("transition-timing-function")["choice"]["id"])
	m.timeline.set_track_easing(m.timeline.easing_entry(w), "ease-out-sine")
	await frames()
	ok(m.state.workspace.text(MENU_USS).contains("transition-timing-function: ease-in, ease-out-sine;"), m.state.workspace.text(MENU_USS))
	eq(m.timeline.model.tracks[w]["easing"], "ease-out-sine")
	eq(m.state.workspace.history.undo_depth(), 1)
