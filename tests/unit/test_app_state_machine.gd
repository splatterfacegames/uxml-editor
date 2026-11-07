extends EdAppTestCase
## The state-machine panel: the nodes and edges from the document, forced
## states, the rules in the inspector, runs on the timeline, and that no
## forced state stays behind.

const SHEET := """.menu-root { flex-grow: 1; }
.menu-button {
  min-width: 100px;
  transition-property: background-color, min-width;
  transition-duration: 0.5s, 1s;
  transition-delay: 0s, 0.2s;
  transition-timing-function: ease-in-out, linear;
}
.menu-button:hover {
  background-color: #c0392b;
  min-width: 300px;
}
.menu-button:active {
  background-color: #902010;
}
.menu-button:disabled {
  color: #808080;
}
.menu-button:checked {
  background-color: #00ff00;
  transition-duration: 0s;
}
Label:hover { color: #ff0000; }
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
	m.states.set_open(true)
	await frames(3)
	return m


func _select(m: EdMain, authored: String) -> EdUxmlNode:
	var n := node_named(m, authored)
	m.state.select_node(n, "test")
	await frames(3)
	m.inspector.flush()
	return n


func _elem_states(m: EdMain, n: EdUxmlNode) -> Array:
	return Array(m.canvas.host.doc.get_forced_states(m.canvas.host.element_for_node[n.id]))


func _bg(m: EdMain, n: EdUxmlNode) -> String:
	return String(m.canvas.host.computed_style(n.id)["background-color"]["value"])


func _edge(m: EdMain, id: String) -> Dictionary:
	return EdStateMachine.edge_of(m.states.model, id)


func _node(m: EdMain, id: String) -> Dictionary:
	return EdStateMachine.node_of(m.states.model, id)


# ---------------------------------------------------------------------------
# The graph
# ---------------------------------------------------------------------------

func test_the_graph_comes_from_the_document() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	var sm := m.states
	eq(sm.model["nodes"].size(), 6, "six states")
	eq(_node(m, "active")["label"], "pressed")
	eq(_node(m, "focus")["label"], "focused")
	eq((_node(m, "hover")["rules"] as Array).size(), 1, "one rule of :hover")
	ok(String(_node(m, "hover")["rules"][0]["selector"]).contains(":hover"))
	eq((_node(m, "focus")["rules"] as Array).size(), 0, "no rule of :focus")
	eq((_node(m, "normal")["rules"] as Array).size(), 1, "the rule without a state")
	ok(String(_node(m, "normal")["rules"][0]["selector"]) == ".menu-button")
	# An edge per direction where the far state has rules; none without rules.
	ok(not _edge(m, "normal>hover").is_empty() and not _edge(m, "hover>normal").is_empty(), "both directions")
	ok(not _edge(m, "hover>active").is_empty())
	ok(_edge(m, "normal>focus").is_empty(), "no edge to a state without rules")


func test_an_edge_with_a_transition_differs_from_an_instant_change() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	var e := _edge(m, "normal>hover")
	eq(e["kind"], "transition")
	eq((e["timing"] as Array).size(), 2, "two properties")
	ok(absf(float(e["length"]) - 1.2) < 0.001, "the end of the last: %f" % float(e["length"]))
	# The To state gives the transition: :checked turns its duration off.
	eq(_edge(m, "normal>checked")["kind"], "instant", "to :checked: duration 0")
	eq(_edge(m, "checked>normal")["kind"], "transition", "back: the normal rule")


func test_each_kind_of_edge_agrees_with_a_run() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	await frames()
	# Not checked>normal: a transition that ended before an instant change
	# stops a later run to the same value (request R23).
	for e in m.states.model["edges"]:
		if e["id"] == "checked>normal":
			continue
		m.states.select_edge(e["id"])
		await frames(2)
		var tracks: int = m.timeline.model.tracks.size()
		if e["kind"] == "transition":
			eq(tracks, (e["timing"] as Array).size(), "%s: the tracks of the run" % e["id"])
			ok(absf(m.timeline.model.length() - float(e["length"])) < 0.001, "%s: the length" % e["id"])
		else:
			eq(tracks, 0, "%s: no transition runs" % e["id"])


func test_a_change_without_a_transition_is_instant() -> void:
	var m := await _open(".menu-button { min-width: 100px; transition-property: min-width; transition-duration: 1s; }\n.menu-button:disabled { color: #808080; }\n")
	await _select(m, "quit-button")
	eq(_edge(m, "normal>disabled")["kind"], "instant", "color has no transition")
	ok(EdStateMachineView.edge_text(_edge(m, "normal>disabled")).contains("instant"), "the info says so")
	m.states.select_edge("normal>disabled")
	await frames(2)
	eq(m.timeline.model.tracks.size(), 0, "no track")


func test_a_keyword_value_is_instant() -> void:
	var m := await _open(".menu-button { transition-property: min-width; transition-duration: 1s; }\n.menu-button:hover { min-width: 300px; }\n")
	await _select(m, "quit-button")
	eq(_edge(m, "normal>hover")["kind"], "instant", "from auto: no transition starts")
	m.states.select_edge("normal>hover")
	await frames(2)
	eq(m.timeline.model.tracks.size(), 0, "no track")


func test_the_transitions_of_the_theme_count() -> void:
	# The theme changes background-color on :hover; the author rule only names
	# it in transition-property, and :hover has a rule for another property.
	var m := await _open(".menu-button { transition-property: background-color; transition-duration: 1s; }\n.menu-button:hover { margin-left: 3px; }\n")
	await _select(m, "quit-button")
	var e := _edge(m, "normal>hover")
	m.states.select_edge("normal>hover")
	await frames(2)
	eq((e["timing"] as Array).size(), m.timeline.model.tracks.size(), "the model and the run agree")


func test_a_rule_that_changes_nothing_is_an_edge_of_kind_none() -> void:
	var m := await _open(".menu-button { min-width: 100px; }\n.menu-button:hover { min-width: 100px; }\n")
	await _select(m, "quit-button")
	eq(_edge(m, "normal>hover")["kind"], "none")
	ok(EdStateMachineView.edge_text(_edge(m, "normal>hover")).contains("no value"))


func test_rules_of_another_element_are_not_rules_of_this_one() -> void:
	var m := await _open()
	await _select(m, "menu-title")
	eq((_node(m, "hover")["rules"] as Array).size(), 1, "Label:hover")
	eq((_node(m, "active")["rules"] as Array).size(), 0, ".menu-button:active is not for the label")
	ok(_edge(m, "normal>disabled").is_empty())


func test_selected_is_the_checked_node() -> void:
	var m := await _open(".menu-button:selected { color: #123456; }\n")
	await _select(m, "quit-button")
	eq((_node(m, "checked")["rules"] as Array).size(), 1, ":selected is the old name of :checked")


func test_a_comma_list_is_a_rule_of_both_states() -> void:
	var m := await _open(".menu-button, .menu-button:hover { color: #123456; }\n")
	await _select(m, "quit-button")
	eq((_node(m, "normal")["rules"] as Array).size(), 1)
	eq((_node(m, "hover")["rules"] as Array).size(), 1)
	eq(_edge(m, "normal>hover")["kind"], "none", "the same value")


func test_a_state_of_a_parent_is_not_a_state_of_the_element() -> void:
	var m := await _open(".menu-root:hover .menu-button { color: #123456; }\n")
	await _select(m, "quit-button")
	eq((_node(m, "hover")["rules"] as Array).size(), 0, "the hover of the parent")


func test_the_state_preview_does_not_change_the_graph() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	var before: String = _edge(m, "normal>hover")["kind"]
	m.inspector.set_state("checked", true)
	m.timeline.stop()
	await frames(2)
	m.states.refresh_now()
	eq(_edge(m, "normal>hover")["kind"], before, "a query names every state")
	eq(_edge(m, "normal>hover")["changes"].size(), 2)
	eq(host_forced(m, n), ["checked"])


func host_forced(m: EdMain, n: EdUxmlNode) -> Array:
	return m.canvas.host.forced_of(n.id)


# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

func test_a_click_on_a_node_forces_it_and_shows_the_rules() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	var sm := m.states
	var normal := _bg(m, n)
	var at := sm.to_global(sm.node_rect("hover").get_center())
	mouse_button(m, at, true)
	mouse_button(m, at, false)
	await frames(3)
	eq(sm.selected, {"kind": "node", "id": "hover"})
	eq(_elem_states(m, n), ["hover"], "forced on the canvas (R6)")
	ok(_bg(m, n) != normal or m.canvas.host.doc.has_running_transitions(), "the rule applies")
	# The rules in the provenance inspector.
	m.inspector.flush()
	await frames(2)
	ok(m.inspector.shows_state_rules(), "the inspector shows the rules")
	eq(m.inspector.provenance.size(), 2, "two declarations")
	eq(m.inspector.provenance[0]["property"], "background-color")
	eq(m.inspector.provenance[0]["status"], "winner")
	ok(EdUi.full_text(m.inspector.doc, "prov-title").contains("hover"), EdUi.full_text(m.inspector.doc, "prov-title"))
	ok(EdUi.full_text(m.inspector.doc, "prov-0").contains(".menu-button:hover"), EdUi.full_text(m.inspector.doc, "prov-0"))
	# A row selects the declaration in the source view.
	m.inspector.open_provenance(0)
	await frames()
	eq(m.source_path, MENU_USS)
	ok(m.source.get_selected_text().contains("background-color"), m.source.get_selected_text())
	# A style field shows its property again; the state stays.
	m.inspector.show_property("color")
	m.inspector.flush()
	ok(not m.inspector.shows_state_rules())
	eq(_elem_states(m, n), ["hover"])


func test_the_inspector_shows_the_values_after_the_transitions() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	var doc := m.canvas.host.doc
	var t0 := Time.get_ticks_msec()
	while doc.has_running_transitions() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	await frames(3)
	m.inspector.flush()
	var i := EdInspectorView.COMMON_STYLES.find("min-width")
	var line := m.inspector.doc.get_native("style-%d" % i) as LineEdit
	ok(m.inspector.placeholder_of("style-%d" % i).begins_with("300px"), "the end value: " + m.inspector.placeholder_of("style-%d" % i))
	var _unused := line


func test_a_state_with_an_overridden_declaration_says_so() -> void:
	var m := await _open(".menu-button:hover { color: #111111; }\n#quit-button:hover { color: #222222; }\n")
	var _n := await _select(m, "quit-button")
	var rows := EdStateMachine.rows(_node(m, "hover")["rules"])
	eq(rows.size(), 2)
	eq(rows[0]["status"], "overridden", "the less specific rule")
	eq(rows[1]["status"], "winner")


func test_pressed_forces_hover_too() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_node("active")
	await frames(2)
	eq(_elem_states(m, n), ["hover", "active"], "a press happens under the pointer")
	m.states.select_node("normal")
	await frames(2)
	eq(_elem_states(m, n), [], "normal: no state")


func test_keys_step_through_the_nodes_and_escape_ends() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	var sm := m.states
	sm.box.grab_focus()
	key(m, KEY_DOWN)
	await frames(2)
	eq(sm.selected.get("id"), "normal", "the first state")
	key(m, KEY_DOWN)
	await frames(2)
	eq(_elem_states(m, n), ["hover"])
	key(m, KEY_ESCAPE)
	await frames(2)
	eq(_elem_states(m, n), [], "escape releases it")
	eq(sm.selected, {})


# ---------------------------------------------------------------------------
# Edges
# ---------------------------------------------------------------------------

func test_a_click_on_an_edge_plays_the_change_on_the_timeline() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	var sm := m.states
	var line := sm.edge_line(_edge(m, "normal>hover"))
	var at := sm.to_global((line[0] + line[1]) * 0.5)
	eq(sm.hit((line[0] + line[1]) * 0.5).get("id"), "normal>hover", "the hit test")
	var back := sm.edge_line(_edge(m, "hover>normal"))
	eq(sm.hit((back[0] + back[1]) * 0.5).get("id"), "hover>normal", "each direction has a lane")
	mouse_button(m, at, true)
	mouse_button(m, at, false)
	await frames(2)
	ok(m.timeline.player.armed, "a run")
	ok(m.timeline.model.playing, "it plays")
	eq(m.timeline.to_state["states"], ["hover"])
	eq(m.timeline.from_state["states"], [])
	eq(m.timeline.model.tracks.size(), 2, "the transitions of the change")
	ok(sm._edge_shown(_edge(m, "normal>hover")), "the arrow is lit")
	# The end state, without a state preview.
	eq(m.canvas.host.forced_of(n.id), [], "a run is not a state preview")
	# The way back has the transitions of the normal rule, from hover.
	sm.select_edge("hover>normal")
	await frames(2)
	eq(m.timeline.from_state["states"], ["hover"])
	eq(m.timeline.to_state["states"], [])
	eq(m.timeline.model.tracks.size(), 2)


func test_a_click_on_a_node_ends_the_run_of_an_edge() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_edge("normal>hover")
	await frames(2)
	m.states.select_node("disabled")
	await frames(2)
	ok(not m.timeline.player.armed, "no run")
	eq(_elem_states(m, n), ["disabled"])


func test_another_from_or_to_of_the_timeline_unlights_the_arrow() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	m.states.select_edge("normal>hover")
	await frames(2)
	m.timeline.set_state_text("to", ".menu-button:active")
	await frames(2)
	ok(not m.states._edge_shown(_edge(m, "normal>hover")))


# ---------------------------------------------------------------------------
# Nothing stays behind
# ---------------------------------------------------------------------------

func test_another_selection_releases_the_state() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	await _select(m, "play-button")
	await frames(2)
	eq(_elem_states(m, n), [], "no forced state stays")
	eq(m.canvas.host.forced_of(n.id), [])
	eq(m.states.selected, {})
	ok(not m.inspector.shows_state_rules(), "the inspector shows no state rules")


func test_closing_the_panel_releases_the_state_and_the_run() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	var close := m.shell.get_element("sm-close").get_global_rect().get_center()
	mouse_button(m, close, true)
	mouse_button(m, close, false)
	await frames(3)
	ok(not m.states.open, "the button closes the panel")
	eq(_elem_states(m, n), [], "no forced state stays")
	ok(not m.inspector.shows_state_rules())
	eq(str(m.shell.get_element_model("states-toggle").get_attribute("value")), "false", "the toggle follows")
	m.states.set_open(true)
	await frames(3)
	m.states.select_edge("normal>hover")
	await frames(2)
	m.states.set_open(false)
	await frames(2)
	ok(not m.timeline.player.armed, "the run of the panel ends")
	eq(_elem_states(m, n), [])


func test_the_panel_gives_the_state_preview_its_states_back() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.inspector.set_state("checked", true)
	m.timeline.stop()
	await frames(2)
	m.states.select_node("hover")
	await frames(2)
	eq(_elem_states(m, n), ["hover"], "the state of the node")
	m.states.clear()
	await frames(2)
	eq(_elem_states(m, n), ["checked"], "the preview again")
	eq(m.canvas.host.forced_of(n.id), ["checked"])
	# Per selection: the preview of an element stays with it.
	m.states.select_node("disabled")
	await frames(2)
	await _select(m, "play-button")
	eq(_elem_states(m, n), ["checked"])


func test_a_toggle_of_the_state_preview_takes_the_state_over() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	m.inspector.set_state("focus", true)
	m.timeline.stop()
	await frames(2)
	eq(m.states.selected, {}, "the panel lets go")
	await _select(m, "play-button")
	eq(_elem_states(m, n), ["hover", "focus"], "the user set these: they stay as a state preview")


func test_a_preview_and_another_document_release_the_state() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	m.set_preview(true)
	await frames(2)
	eq(_elem_states(m, n), [], "preview: the document gets the input")
	m.set_preview(false)
	await frames(3)
	n = await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	var second := "Assets/UI/Second.uxml"
	var path := _dir + "/" + second
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Label name=\"second\" text=\"B\" />\n</ui:UXML>\n")
	f.close()
	m.state.open_project(_dir)
	await frames(3)
	eq(m.states.selected, {}, "another project")
	ok(m.canvas.host.forced.is_empty(), "no forced state in the new render")


func test_an_edit_that_moves_the_selection_releases_the_state() -> void:
	# The new element becomes the selection, before the render of the edit.
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	var ip := EdLocator.create(n.parent)
	m.state.execute(EdStructureCommands.insert_new_element(m.state.session, ip, 0, "VisualElement", "UnityEngine.UIElements", []), "test")
	await frames(3)
	eq(m.state.selected_node().local, "VisualElement", "the new element")
	for x in m.state.session.root().walk():
		if m.canvas.host.element_for_node.has(x.id):
			eq(_elem_states(m, x), [], "%s has no forced state" % x.local)
	ok(m.canvas.host.forced.is_empty(), "no forced state in the host")


func test_the_state_stays_with_the_element_through_a_source_edit() -> void:
	# An element goes in before the selection, in the source: the ids change,
	# the state stays with the element, and a later release finds it.
	var m := await _open()
	var n := await _select(m, "quit-button")
	m.states.select_node("hover")
	await frames(2)
	var at: int = node_named(m, "play-button").open_start
	m.state.execute(EdTransaction.make("test", "A label", MENU, [{"start": at, "end": at, "replacement": "<ui:Label text=\"x\" />\n"}]), "test")
	await frames(3)
	var n2 := node_named(m, "quit-button")
	ok(n2.id != n.id, "another id")
	eq(m.state.selected_node(), n2, "the selection follows")
	eq(m.states.selected.get("id"), "hover", "the panel keeps the node")
	eq(m.canvas.host.forced_of(n2.id), ["hover"], "the state moved with the element")
	eq(_elem_states(m, n2), ["hover"], "on the canvas too")
	m.states.clear()
	await frames(2)
	eq(_elem_states(m, n2), [], "the release finds it")
	eq(m.canvas.host.forced_of(n2.id), [])
	for x in m.state.session.root().walk():
		if m.canvas.host.element_for_node.has(x.id):
			eq(_elem_states(m, x), [], "%s has no forced state" % x.local)


# ---------------------------------------------------------------------------
# Sync with the source
# ---------------------------------------------------------------------------

func test_source_edits_undo_and_redo_keep_the_graph_in_sync() -> void:
	var m := await _open()
	var n := await _select(m, "quit-button")
	await frames(2)
	eq((_node(m, "focus")["rules"] as Array).size(), 0)
	var at := m.state.workspace.text(MENU_USS).length()
	m.state.execute(EdTransaction.make("test", "Focus rule", MENU_USS, [{"start": at, "end": at, "replacement": ".menu-button:focus { color: #00ff00; }\n"}]), "test")
	await frames(3)
	eq((_node(m, "focus")["rules"] as Array).size(), 1, "an edit adds the rule")
	ok(not _edge(m, "normal>focus").is_empty())
	m.states.select_node("focus")
	await frames(3)
	m.inspector.flush()
	eq(m.inspector.provenance.size(), 1, "the rules in the inspector")
	m.state.undo()
	await frames(3)
	eq((_node(m, "focus")["rules"] as Array).size(), 0, "undo removes it")
	ok(_edge(m, "normal>focus").is_empty())
	eq(_elem_states(m, n), ["focus"], "the forced state stays until it is released")
	m.inspector.flush()
	eq(m.inspector.provenance.size(), 0, "the inspector follows")
	m.state.redo()
	await frames(3)
	eq((_node(m, "focus")["rules"] as Array).size(), 1, "redo")
	m.states.clear()
	await frames(2)
	eq(_elem_states(m, n), [])


func test_a_transition_edit_changes_the_edge() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	await frames(2)
	eq(_edge(m, "normal>hover")["kind"], "transition")
	var text := m.state.workspace.text(MENU_USS)
	var from := text.find("transition-duration: 0.5s, 1s;")
	m.state.execute(EdTransaction.make("test", "Durations", MENU_USS, [{"start": from, "end": from + "transition-duration: 0.5s, 1s;".length(), "replacement": "transition-duration: 0s, 0s;"}]), "test")
	await frames(3)
	var from2 := m.state.workspace.text(MENU_USS).find("transition-delay: 0s, 0.2s;")
	m.state.execute(EdTransaction.make("test", "Delays", MENU_USS, [{"start": from2, "end": from2 + "transition-delay: 0s, 0.2s;".length(), "replacement": "transition-delay: 0s, 0s;"}]), "test")
	await frames(3)
	eq(_edge(m, "normal>hover")["kind"], "instant", "no time left")
	m.state.undo()
	await frames(3)
	m.state.undo()
	await frames(3)
	eq(_edge(m, "normal>hover")["kind"], "transition", "undo")


func test_a_bar_drag_on_the_run_of_an_edge_keeps_one_undo_step() -> void:
	var m := await _open()
	await _select(m, "quit-button")
	await frames(2)
	var src := m.state.workspace.text(MENU_USS)
	m.states.select_edge("normal>hover")
	await frames(2)
	m.timeline.toggle_play()
	await frames(1)
	m.timeline.edit_track(0, "move", 0.3)
	await frames(2)
	if not m.inspector.pending.is_empty():
		m.inspector.choose(0)
	await frames(3)
	m.flush_waiting_render()
	await frames(3)
	eq(m.state.workspace.history.undo_depth(), 1, "one step")
	ok(m.state.workspace.text(MENU_USS) != src)
	ok(float(_edge(m, "normal>hover")["length"]) > 0.0, "the graph has the new time")
	m.state.undo()
	await frames(3)
	eq(m.state.workspace.text(MENU_USS), src, "the exact bytes")


func test_no_element_and_an_unknown_element() -> void:
	var m := await _open()
	m.state.select_node(null, "test")
	await frames(3)
	eq(m.states.model["nodes"].size(), 0, "no selection: no graph")
	m.states.select_node("hover")
	eq(m.states.selected, {}, "nothing to force")
	await _select(m, "quit-button")
	eq(m.states.model["nodes"].size(), 6)


func test_a_closed_panel_builds_nothing() -> void:
	var m := await _open()
	m.states.set_open(false)
	await frames(2)
	var b0: int = m.states.builds
	await _select(m, "quit-button")
	await _select(m, "play-button")
	eq(m.states.builds, b0, "no model while closed")
	m.states.set_open(true)
	await frames(3)
	eq(m.states.builds, b0 + 1, "one on open")
	eq(m.states.model["nodes"].size(), 6, "of the selection")


func test_the_panel_state_and_width_are_kept_per_user() -> void:
	var saved := EdSettings.default_path
	EdSettings.default_path = "user://test-states-%d.cfg" % Time.get_ticks_usec()
	var path := EdSettings.default_path
	var m := await editor()
	ok(not m.states.open, "closed by default")
	var tl_w: float = m.shell.get_element("tl-tracks").size.x
	m.states.set_open(true)
	await frames(3)
	ok(m.shell.get_element("tl-tracks").size.x < tl_w - 200.0, "the timeline makes room")
	m.shell.set_split_dimension("states-split", 400.0)
	mouse_button(m, Vector2(800, 12), false)
	await frames()
	var w2: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(w2)
	await frames(3)
	ok(w2.states.open, "open again")
	eq(w2.shell.get_split_dimension("states-split"), 400.0, "with its width")
	w2.states.set_open(false)
	await frames(3)
	eq(w2.shell.get_split_dimension("states-split"), 0.0, "closed: no room")
	ok(w2.shell.get_element("tl-tracks").size.x >= tl_w - 2.0, "the timeline has the room again")
	EdSettings.default_path = saved
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
