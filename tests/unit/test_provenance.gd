extends EdTestCase
## Milestone 4 core: value types, write targets (ADR 0004), provenance rows,
## class edits. The cascade candidates are written by hand here in the shape
## of EdRenderHost.explain(); tests/unit/test_app_inspector.gd runs them from
## godot-uxml explain_style.

const SHEET := "Assets/UI/screen.uss"
const CSS := "/* keep */\r\n.menu-button {\r\n  min-width: 180px;\r\n}\r\n\r\n.menu-button:hover {\r\n  color: red;\r\n}\r\n\r\n.box {\r\n  margin-top: 2px;\r\n  margin: 4px;\r\n}\r\n"


func _doc() -> String:
	return "<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <Style src=\"screen.uss\" />\n  <ui:Button name=\"play\" class=\"menu-button  primary\" style=\"min-width: 10px; color: blue;\" />\n  <ui:Button class=\"menu-button\" />\n</ui:UXML>\n"


func _session() -> EdDocumentSession:
	return open_session(_doc(), {SHEET: CSS})


func _node(s: EdDocumentSession, authored: String) -> EdUxmlNode:
	return s.resolve(with_name(s, authored))


func _item(s: EdDocumentSession, selector: String) -> int:
	for r in s.workspace.uss(SHEET).rules():
		if r["selector_text"] == selector:
			return r["item_index"]
	return -1


func _rule(s: EdDocumentSession, selector: String, decl: int, winner: bool, states: Array = [], property: String = "min-width") -> Dictionary:
	return {"origin": {"kind": "rule", "path": SHEET, "item": _item(s, selector), "decl_index": decl, "states": states},
		"property": property, "status": "winner" if winner else "overridden", "winner": winner, "value": "1px", "declared": "1px"}


# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

func test_value_types_and_checks() -> void:
	eq(EdStyleTypes.kind_of("width"), "length")
	eq(EdStyleTypes.kind_of("flex-direction"), "enum")
	eq(EdStyleTypes.kind_of("background-color"), "color")
	eq(EdStyleTypes.kind_of("background-image"), "asset")
	eq(EdStyleTypes.kind_of("rotate"), "rotate")
	eq(EdStyleTypes.kind_of("transition-duration"), "time")
	eq(EdStyleTypes.kind_of("transition-timing-function"), "easing")
	ok(EdStyleTypes.choices("flex-direction").has("row-reverse"), "enum keywords from godot-uxml")
	ok(EdStyleTypes.choices("transition-timing-function").has("ease-in-out-bounce"), "easing names from godot-uxml")
	for good in [["width", "12px"], ["width", "50%"], ["width", "auto"], ["margin", "1px 2px 0 4px"], ["width", "var(--w)"],
			["width", "initial"], ["opacity", "0.5"], ["color", "#ff00aa"], ["color", "rgba(1, 2, 3, 0.5)"], ["color", "red"],
			["flex-direction", "row"], ["background-image", "url(\"a.png\")"], ["background-image", "none"],
			["rotate", "45deg"], ["scale", "1 2"], ["translate", "10px 50%"], ["transition-duration", "0.3s, 150ms"],
			["transition-timing-function", "ease-in, linear"], ["transform-origin", "left 20%"], ["--custom", "anything"]]:
		eq(EdStyleTypes.check(good[0], good[1]), null, "%s: %s passes" % good)
	for bad in [["width", "12 px"], ["width", "wide"], ["margin", "1px 2px 3px 4px 5px"], ["opacity", "half"],
			["color", "#12"], ["flex-direction", "sideways"], ["background-image", "a.png"], ["rotate", "45"],
			["scale", "big"], ["transition-duration", "3"], ["transition-timing-function", "wobble"]]:
		is_error(EdStyleTypes.check(bad[0], bad[1]), "invalid-value", "%s: %s is refused" % bad)


func test_value_helpers() -> void:
	eq(EdStyleTypes.with_unit("12px", "%"), "12%")
	eq(EdStyleTypes.with_unit("", "px", "180px"), "180px", "the computed value gives the number")
	eq(EdStyleTypes.with_unit("12px", "auto"), "auto")
	eq(EdStyleTypes.unit_of("1.5s", ["s", "ms"]), "s")
	eq(EdStyleTypes.unit_of("150ms", ["s", "ms"]), "ms")
	eq(EdStyleTypes.color_text(Color(1, 0, 0)), "#ff0000")
	eq(EdStyleTypes.color_text(Color(1, 0, 0, 0.5)), "#ff000080")
	eq(EdStyleTypes.parse_color("#f00"), Color(1, 0, 0))
	eq(EdStyleTypes.parse_color("rgb(255, 0, 0)"), Color(1, 0, 0))
	eq(EdStyleTypes.parse_color("nonsense"), null)
	eq(EdStyleTypes.url_for("Assets/Textures/icon.png", "Assets/UI/Menu.uss"), "url(\"../Textures/icon.png\")")
	eq(EdStyleTypes.url_for("Assets/UI/img/a.png", "Assets/UI/Menu.uss"), "url(\"img/a.png\")")
	eq(EdStyleTypes.url_path("url('x/y.png')"), "x/y.png")


# ---------------------------------------------------------------------------
# Write targets
# ---------------------------------------------------------------------------

func test_targets_follow_the_candidates() -> void:
	var s := _session()
	var play := _node(s, "play")
	var entries := [{"origin": {"kind": "inline", "decl_index": 0}, "property": "min-width", "status": "winner", "winner": true},
		_rule(s, ".menu-button", 0, false),
		{"origin": {"kind": "theme", "file": "res://addons/godot_uxml/themes/x.uss", "item": 3}, "property": "min-width", "status": "overridden", "winner": false}]
	var cs := EdStyleTargets.choices(s, play, "min-width", entries)
	eq(cs.map(func(c): return c["id"]), ["rule:%s:%d" % [SHEET, _item(s, ".menu-button")], "inline",
		"new:%s:#play" % SHEET, "new:%s:.menu-button" % SHEET, "new:%s:.primary" % SHEET], "rules, inline, new rules; no theme")
	eq(cs[0]["label"], "screen.uss · .menu-button  (overridden)")
	eq(cs[0]["line"], 2)
	eq(cs[1]["label"], "Inline style  (wins)")
	# The rule target names the exact declaration; a commit patches its value.
	var tx = EdStyleTargets.commit(s, cs[0], "200px")
	ok(is_tx(tx))
	run(s, tx)
	eq(s.workspace.text(SHEET), CSS.replace("180px", "200px"), "only the value changed")
	# The choices froze the old text: a second commit is refused, not redirected.
	is_error(EdStyleTargets.commit(s, cs[0], "220px"), "stale-target")
	is_error(EdStyleTargets.commit(s, cs[0], "wide"), "invalid-value", "a typed check comes first")


func test_state_targets_need_rules() -> void:
	var s := _session()
	var play := _node(s, "play")
	var entries := [_rule(s, ".menu-button:hover", 0, true, ["hover"], "color")]
	var plain := EdStyleTargets.choices(s, play, "color", entries)
	ok(not plain.any(func(c): return c["kind"] == "rule"), "a :hover rule is not a target without the state")
	var cs := EdStyleTargets.choices(s, play, "color", entries, ["hover"])
	eq(cs.map(func(c): return c["id"]), ["rule:%s:%d" % [SHEET, _item(s, ".menu-button:hover")],
		"new:%s:#play:hover" % SHEET, "new:%s:.menu-button:hover" % SHEET, "new:%s:.primary:hover" % SHEET], "no inline target for a state")
	var tx = EdStyleTargets.commit(s, cs[1], "#00ff00")
	run(s, tx)
	ok(s.workspace.text(SHEET).ends_with("}\r\n\r\n#play:hover {\r\n  color: #00ff00;\r\n}\r\n"), "a new state rule at the end, with the sheet's newlines")


func test_shorthand_winner_skips_an_earlier_longhand() -> void:
	var s := _session()
	var anon: EdUxmlNode = s.root().children[2]
	var entries := [{"origin": {"kind": "rule", "path": SHEET, "item": _item(s, ".box"), "decl_index": 1, "states": []},
		"property": "margin", "status": "winner", "winner": true}]
	var cs := EdStyleTargets.choices(s, anon, "margin-top", entries)
	ok(not cs.any(func(c): return c["kind"] == "rule"), "margin-top before margin would be overridden")
	cs = EdStyleTargets.choices(s, anon, "margin", entries)
	eq(cs[0]["kind"], "rule", "the shorthand itself is a target")
	eq(EdStyleTargets.selectors_for(s, anon, []), [".menu-button"], "no name: class selectors only")


func test_removal_and_inline_targets() -> void:
	var s := _session()
	var play := _node(s, "play")
	var cs := EdStyleTargets.choices(s, play, "color", [{"origin": {"kind": "inline", "decl_index": 1}, "property": "color", "status": "winner", "winner": true}])
	var inline: Dictionary = cs.filter(func(c): return c["kind"] == "inline")[0]
	var tx = EdStyleTargets.commit(s, inline, "")
	run(s, tx)
	ok(text(s).contains("style=\"min-width: 10px; \""), "the declaration and its terminator went (EdUssCommands removal)")
	is_error(EdStyleTargets.commit(s, cs.filter(func(c): return c["kind"] == "new-rule")[0], ""), "invalid-value", "a new rule needs a value")


# ---------------------------------------------------------------------------
# Provenance rows
# ---------------------------------------------------------------------------

func test_provenance_rows_name_the_source() -> void:
	var s := _session()
	var play := _node(s, "play")
	var rows := EdProvenance.rows(s, play, [
		{"origin": {"kind": "inline", "decl_index": 0}, "property": "min-width", "status": "winner", "value": "10px", "declared": "10px"},
		_rule(s, ".menu-button", 0, false),
		{"origin": {"kind": "theme", "file": "res://addons/godot_uxml/themes/unity-runtime.uss", "item": 1}, "status": "overridden", "value": "0px"},
		{"origin": {"kind": "inherited", "origin": {"kind": "default"}, "from_id": 0}, "status": "inherited", "value": "1"},
		{"origin": {"kind": "default"}, "status": "default", "value": null}])
	eq(rows[0]["path"], ENTRY)
	eq(text(s).substr(rows[0]["start"], rows[0]["end"] - rows[0]["start"]), "min-width: 10px", "the inline declaration span")
	eq(rows[0]["line"], 3)
	eq(rows[1]["path"], SHEET)
	eq(s.workspace.text(SHEET).substr(rows[1]["start"], rows[1]["end"] - rows[1]["start"]), "min-width: 180px", "the rule declaration span")
	eq(rows[1]["where"], "screen.uss:3  .menu-button")
	eq(rows[2]["where"], "theme  unity-runtime.uss")
	eq(rows[2]["start"], -1, "a theme value has no source to show")
	eq(rows[3]["select_id"], 0)
	eq(rows[3]["where"], "inherited from UXML")
	eq(rows[4]["where"], "initial value")
	ok(EdProvenance.line(rows[1]).begins_with("overridden"))


func test_class_rules_and_class_edits() -> void:
	var s := _session()
	var rules := EdProvenance.class_rules(s.workspace, [SHEET], "menu-button")
	eq(rules.map(func(r): return r["selector"]), [".menu-button", ".menu-button:hover"])
	eq(rules[0]["line"], 2)
	eq(rules[0]["properties"], ["min-width"])
	eq(EdProvenance.class_rules(s.workspace, [SHEET], "menu").size(), 0, "a prefix is not the class")
	var loc := with_name(s, "play")
	run(s, EdProvenance.add_class(s, loc, "big"))
	ok(text(s).contains("class=\"menu-button  primary big\""), "appended; the other bytes stay")
	is_error(EdProvenance.add_class(s, with_name(s, "play"), "big"), "invalid-value", "no duplicate class")
	is_error(EdProvenance.add_class(s, with_name(s, "play"), "1x"), "invalid-value", "not an identifier")
	run(s, EdProvenance.remove_class(s, with_name(s, "play"), "menu-button"))
	ok(text(s).contains("class=\"primary big\""), "the token and the spaces after it went")
	run(s, EdProvenance.remove_class(s, with_name(s, "play"), "big"))
	ok(text(s).contains("class=\"primary\""), "the last token and the space before it went")
	run(s, EdProvenance.remove_class(s, with_name(s, "play"), "primary"))
	ok(not text(s).contains("class=\"primary"), "the last class removes the attribute")
	ok(text(s).contains("<ui:Button name=\"play\" style="), "the tag stays as written")
	is_error(EdProvenance.remove_class(s, with_name(s, "play"), "primary"), "invalid-target")
	s.workspace.history.undo()
	s.workspace.history.undo()
	s.workspace.history.undo()
	s.workspace.history.undo()
	eq(text(s), _doc(), "undo restores the exact bytes")
