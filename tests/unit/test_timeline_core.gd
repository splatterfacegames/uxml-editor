extends EdTestCase
## The data of the transition timeline: the transition-* lists, the
## playhead, the time scale, bar drags and the From and To states; layout
## plans with a chosen write target; the settings file.


func test_time_text_and_parse() -> void:
	eq(EdTransitionValues.parse_time("2s"), 2.0)
	eq(EdTransitionValues.parse_time("800ms"), 0.8)
	eq(EdTransitionValues.parse_time(" 0.5 "), 0.5, "a bare number is seconds")
	ok(is_nan(EdTransitionValues.parse_time("fast")))
	eq(EdTransitionValues.format_time(0.25), "0.25s")
	eq(EdTransitionValues.format_time(1.0), "1s")
	eq(EdTransitionValues.format_time(0.1254), "0.125s")
	eq(EdTransitionValues.format_time(0.0), "0s")
	eq(EdTransitionValues.format_time(-0.0001), "0s", "never a negative zero")


func test_lists_repeat_and_collapse() -> void:
	eq(EdTransitionValues.split_list("a, b ,c"), ["a", "b", "c"])
	eq(EdTransitionValues.split_list("initial"), [])
	eq(EdTransitionValues.list_or_initial("transition-duration", ""), ["0s"])
	eq(EdTransitionValues.list_or_initial("transition-property", "unset"), ["all"])
	# A shorter list repeats; one entry changes.
	eq(EdTransitionValues.with_entry("transition-duration", "1s", 3, 1, "2s"), "1s, 2s, 1s")
	eq(EdTransitionValues.with_entry("transition-duration", "1s, 2s", 3, 2, "2s"), "1s, 2s, 2s")
	# Equal entries collapse to one value.
	eq(EdTransitionValues.with_entry("transition-duration", "1s, 2s", 2, 1, "1s"), "1s")
	eq(EdTransitionValues.with_entry("transition-delay", "", 1, 0, "0.5s"), "0.5s")


func test_the_entry_of_a_property() -> void:
	var names := ["opacity", "all", "width"]
	eq(EdTransitionValues.entry_index(names, ["1s"], ["0s"], "width"), 2, "the last entry that names it")
	eq(EdTransitionValues.entry_index(names, ["1s"], ["0s"], "color"), 1, "all")
	eq(EdTransitionValues.entry_index(names, ["1s", "1s", "0s"], ["0s"], "width"), 1, "an entry without time does not animate")
	eq(EdTransitionValues.entry_index(["opacity"], ["1s"], ["0s"], "width"), -1)
	eq(EdTransitionValues.entry_index(["margin"], ["1s"], ["0s"], "margin-left", {"margin": ["margin-left"]}), 0, "a shorthand")


func test_declared_transitions_of_a_computed_style() -> void:
	var st := {"transition-property": {"value": "opacity, none, width"}, "transition-duration": {"value": "1s, 2s"},
		"transition-delay": {"value": "100ms"}, "transition-timing-function": "linear, ease-in"}
	var d := EdTransitionValues.declared(st)
	eq(d.size(), 2, "none is no transition")
	eq(d[0], {"property": "opacity", "duration": 1.0, "delay": 0.1, "easing": "linear", "entry": 0})
	eq(d[1], {"property": "width", "duration": 1.0, "delay": 0.1, "easing": "linear", "entry": 2})
	eq(EdTransitionValues.declared({}), [], "no duration: no transition")


func _model() -> EdTimelineModel:
	var m := EdTimelineModel.new()
	m.tracks = [{"delay": 0.0, "duration": 1.0}, {"delay": 0.5, "duration": 1.0}]
	return m


func test_playhead() -> void:
	var m := _model()
	eq(m.length(), 1.5)
	ok(not m.step(0.1), "no move while paused")
	m.toggle_play()
	ok(m.playing)
	ok(m.step(0.5))
	eq(m.time, 0.5)
	m.speed = 2.0
	ok(m.step(0.25))
	eq(m.time, 1.0, "speed scales the time")
	m.speed = 1.0
	ok(m.step(1.0))
	eq(m.time, 1.5, "stops at the end")
	ok(not m.playing)
	m.toggle_play()
	eq(m.time, 0.0, "play at the end starts again")
	m.loop = true
	ok(m.step(1.75))
	eq(m.time, 0.25, "loop wraps")
	ok(m.playing)
	m.seek(99.0)
	eq(m.time, 1.5, "seek clamps")
	m.seek(-1.0)
	eq(m.time, 0.0)
	var empty := EdTimelineModel.new()
	empty.toggle_play()
	ok(not empty.playing, "nothing to play")


func test_bar_drags_and_the_scale() -> void:
	eq(EdTimelineModel.drag_bar(0.5, 1.0, "move", 0.12), {"delay": 0.6, "duration": 1.0}, "snap to 0.05")
	eq(EdTimelineModel.drag_bar(0.5, 1.0, "move", 0.123, false), {"delay": 0.623, "duration": 1.0}, "whole ms without snap")
	eq(EdTimelineModel.drag_bar(0.5, 1.0, "move", -9.0), {"delay": 0.0, "duration": 1.0}, "no negative delay")
	eq(EdTimelineModel.drag_bar(0.5, 1.0, "end", 0.26), {"delay": 0.5, "duration": 1.25})
	eq(EdTimelineModel.drag_bar(0.5, 1.0, "end", -9.0), {"delay": 0.5, "duration": 0.01}, "a bar keeps a duration")
	eq(EdTimelineModel.scale_for(1.0, 1000.0), 850.0)
	eq(EdTimelineModel.scale_for(0.0, 1000.0), 1700.0, "at least 0.5 s shows")
	ok(EdTimelineModel.tick_step(850.0) * 850.0 >= 48.0)
	eq(EdTimelineModel.tick_step(0.1), 30.0)


func test_state_text() -> void:
	eq(EdTimelineModel.state_text({"classes": ["a", "b"], "states": ["hover"]}), ".a.b:hover")
	eq(EdTimelineModel.state_text({}), "(none)")
	eq(EdTimelineModel.parse_state(".a.b:hover"), {"classes": ["a", "b"], "states": ["hover"]})
	eq(EdTimelineModel.parse_state("(none)"), {"classes": [], "states": []})
	eq(EdTimelineModel.parse_state(" :checked:hover "), {"classes": [], "states": ["checked", "hover"]})
	is_error(EdTimelineModel.parse_state("button"), "invalid-value", "no selector text")
	is_error(EdTimelineModel.parse_state(".a b"), "invalid-value", "one compound only")
	is_error(EdTimelineModel.parse_state(":nope"), "invalid-value", "only the states of the preview")


func test_state_menu_choices() -> void:
	var c := EdTimelineModel.state_choices(["a"], ["hover"], ["a", "b"])
	var texts: Array = c.map(EdTimelineModel.state_text)
	eq(texts[0], ".a:hover", "the element as it is")
	ok(texts.has(".a:hover:active"), "with another state")
	ok(texts.has(".a"), "without the states")
	ok(texts.has(":hover"), "without the class")
	ok(texts.has(".a.b:hover"), "with another class of the rules")
	ok(not texts.has(".a.a:hover"))


func _layout_session() -> EdDocumentSession:
	return open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><Style src=\"S.uss\" /><ui:Button name=\"b\" class=\"c\" /></ui:UXML>",
		{"S.uss": ".c {\r\n  left: 1px;\r\n}\r\n"})


func test_a_layout_plan_writes_to_a_chosen_target() -> void:
	var s := _layout_session()
	var loc := with_name(s, "b")
	var none := func(_node): return {}
	# A rule without the property: the declaration goes into the rule.
	var tx = EdLayoutCommands.plan(s, [{"locator": loc, "property": "top", "value": 7.0}], none, "Move", "",
		{"top": {"kind": "rule", "path": "S.uss", "item": 0, "decl_index": -1}}, loc)
	is_tx(tx)
	run(s, tx)
	ok(s.workspace.text("S.uss").contains("top: 7px"), "the rule: " + s.workspace.text("S.uss"))
	ok(s.workspace.text("S.uss").contains("left: 1px;\r\n"), "the other bytes stay")
	ok(not String(s.source()).contains("style="), "no inline style")


func test_one_plan_inserts_one_new_rule() -> void:
	var s := _layout_session()
	var loc := with_name(s, "b")
	var none := func(_node): return {}
	var t := {"kind": "new-rule", "path": "S.uss", "selector": "#b"}
	var tx = EdLayoutCommands.plan(s, [{"locator": loc, "property": "left", "value": 3.0}, {"locator": loc, "property": "top", "value": 4.0}],
		none, "Move", "", {"left": t, "top": t}, loc)
	is_tx(tx)
	run(s, tx)
	var text := s.workspace.text("S.uss")
	eq(text.count("#b"), 1, "one rule: " + text)
	ok(text.contains("left: 3px") and text.contains("top: 4px"))
	ok(text.begins_with(".c {\r\n  left: 1px;\r\n}\r\n"), "the old rule stays")
	eq(EdLayoutCommands.target_of_choice({"kind": "inline"})["kind"], "inline")
	eq(EdLayoutCommands.target_of_choice({"kind": "new-rule", "path": "S.uss", "target": {"selector": ".c"}}),
		{"kind": "new-rule", "path": "S.uss", "selector": ".c"})
	eq(EdLayoutCommands.target_of_choice({"kind": "rule", "target": {"path": "S.uss", "item_index": 2}}),
		{"kind": "rule", "path": "S.uss", "item": 2, "decl_index": -1})


func test_run_targets_put_the_winner_first_and_add_the_rules_without_states() -> void:
	var uss: String = ENTRY.get_base_dir().path_join("S.uss")
	var s := open_session("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\"><Style src=\"S.uss\" /><ui:Button name=\"b\" class=\"c\" /></ui:UXML>",
		{uss: ".c {
  left: 1px;
}
"})
	var node: EdUxmlNode = null
	for x in s.root().walk():
		if x.get_attribute("name") == "b":
			node = x
	var entries := [{"origin": {"kind": "rule", "path": uss, "item": 0, "decl_index": 0, "states": []}, "property": "left", "winner": true, "status": "winner"}]
	var plain := EdStyleTargets.choices(s, node, "left", entries, ["hover"])
	ok(plain.all(func(c): return c["kind"] == "new-rule"), "a state alone: only new rules")
	var run_c := EdStyleTargets.run_choices(s, node, "left", entries, ["hover"])
	eq(run_c[0]["id"], "rule:%s:0" % uss, "the rule that gives the value comes first")
	ok(run_c[0]["winner"])
	ok(run_c.any(func(c): return c["id"] == "inline"), "inline")
	ok(run_c.any(func(c): return c["id"] == "new:%s:#b:hover" % uss), "a new rule of the state")
	ok(run_c.any(func(c): return c["id"] == "new:%s:#b" % uss), "a new rule without the state")
	var ids := {}
	for c in run_c:
		ok(not ids.has(c["id"]), "no double: " + String(c["id"]))
		ids[c["id"]] = true


func test_settings_file() -> void:
	var path := "user://test-settings-%d.cfg" % Time.get_ticks_usec()
	var a := EdSettings.new(path)
	eq(a.get_value("layout", "missing"), null, "no error for a null default")
	eq(a.get_value("layout", "missing", 5), 5)
	ok(a.set_value("layout", "main-split", 300.0), "a new value")
	ok(not a.set_value("layout", "main-split", 300.0), "the same value is no change")
	eq(a.save(), OK)
	var b := EdSettings.new(path)
	eq(b.get_value("layout", "main-split"), 300.0, "a new session reads it")
	b.clear()
	eq(b.get_value("layout", "main-split"), null)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# A broken file gives the defaults.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("not a [config file\n= =")
	f.close()
	eq(EdSettings.new(path).get_value("layout", "main-split", 1), 1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
