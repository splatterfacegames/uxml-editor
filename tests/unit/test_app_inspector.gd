extends EdAppTestCase
## Milestone 4 in the real editor scene: the provenance inspector on the
## godot-uxml cascade (explain_style, forced states), write targets with
## the picker, typed helpers, the class editor; and the render host on the
## godot-uxml editor APIs (partial updates, template clones, rectangles).

const HOVER_RULE := "\n.menu-button:hover {\n  background-color: #ff0000;\n}\n"


func _select(m: EdMain, authored: String) -> EdUxmlNode:
	var n := node_named(m, authored)
	m.state.select_node(n, "test")
	await frames()
	m.inspector.flush()
	return n


func _undo_depth(m: EdMain) -> int:
	return m.state.workspace.history.undo_depth()


# ---------------------------------------------------------------------------
# Provenance
# ---------------------------------------------------------------------------

func test_declarations_of_a_property_with_status_and_source() -> void:
	var m := await editor()
	await _select(m, "play-button")
	m.inspector.show_property("background-color")
	m.inspector.flush()
	var rows: Array = m.inspector.provenance
	ok(rows.size() >= 2, "the rule and the theme declarations")
	eq(rows[0]["status"], "winner")
	eq(rows[0]["path"], MENU_USS)
	eq(rows[0]["line"], 8, "the declaration line in Menu.uss")
	eq(rows[0]["declared"], "#18794e")
	ok(rows.slice(1).all(func(r): return r["status"] != "winner"), "one winner")
	ok(rows.slice(1).any(func(r): return String(r["where"]).begins_with("theme")), "the theme value it overrides")
	# The list shows the rows; a click shows the declaration in the source.
	var label := String((m.inspector.doc.get_native("prov-0") as Button).text)
	ok(label.begins_with("winner") and label.contains("Menu.uss:8"), "row text: " + label)
	m.inspector.open_provenance(0)
	await frames()
	eq(m.source_path, MENU_USS, "the source view shows the sheet")
	eq(m.source.get_selected_text(), "background-color: #18794e", "the declaration is selected")
	# Focus on a style field shows its declarations.
	var i := EdInspectorView.COMMON_STYLES.find("min-width")
	m.inspector.doc.get_native("style-%d" % i).grab_focus()
	await frames()
	m.inspector.flush()
	eq(m.inspector.focused_property, "min-width")
	eq(m.inspector.provenance[0]["where"], "Menu.uss:13  .menu-button")


func test_inherited_value_selects_the_parent() -> void:
	var m := await editor()
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(node_named(m, "menu-root")), "style", "color: #123456;"), "test")
	await frames()
	await _select(m, "menu-title")
	m.inspector.show_property("color")
	m.inspector.flush()
	var rows: Array = m.inspector.provenance
	var inh: Array = rows.filter(func(r): return r["status"] == "inherited")
	ok(inh.size() == 1 or rows[0]["status"] != "winner", "an inherited entry or a theme winner")
	var at := -1
	for k in rows.size():
		if int(rows[k]["select_id"]) >= 0:
			at = k
	if at >= 0:
		m.inspector.open_provenance(at)
		await frames()
		eq(m.state.selected_node(), node_named(m, "menu-root"), "the parent is selected")


# ---------------------------------------------------------------------------
# Write targets
# ---------------------------------------------------------------------------

func test_picker_writes_the_chosen_rule_and_remembers_it() -> void:
	var m := await editor()
	await _select(m, "play-button")
	var before_uss := m.state.workspace.text(MENU_USS)
	m.inspector.write_style("min-width", "200px")
	var labels := m.inspector.pending_labels()
	eq(labels[0], "Menu.uss · .menu-button  (wins)", "the winning rule first")
	ok(labels.has("Inline style"), "inline is a target")
	ok(labels.has("New rule #play-button in Menu.uss"))
	ok(m.inspector.picker != null, "the picker menu is open")
	ok(m.inspector.choose(0))
	await frames()
	eq(m.state.workspace.text(MENU_USS), before_uss.replace("min-width: 180px", "min-width: 200px"), "one exact patch in the rule")
	eq(_undo_depth(m), 1)
	eq(m.canvas.host.computed_style(node_named(m, "play-button").id)["min-width"]["value"], "200px", "the render follows")
	eq(m.canvas.host.renders, 1, "a USS edit restyles without a full load (reload_stylesheet)")
	# The choice stays for the property: the next write goes there at once.
	m.inspector.flush()
	m.inspector.write_style("min-width", "210px")
	eq(m.inspector.pending_labels(), [], "no question the second time")
	await frames()
	ok(m.state.workspace.text(MENU_USS).contains("min-width: 210px"))
	# A new selection asks again.
	await _select(m, "quit-button")
	m.inspector.write_style("min-width", "220px")
	ok(not m.inspector.pending_labels().is_empty(), "another element asks again")
	m.inspector.choose(99)
	eq(m.inspector.pending_labels(), [], "cancel")
	eq(_undo_depth(m), 2, "a canceled question writes nothing")


func test_stale_choice_is_refused() -> void:
	var m := await editor()
	await _select(m, "play-button")
	m.inspector.write_style("min-width", "200px")
	ok(not m.inspector.pending_labels().is_empty())
	# The sheet changes while the question is open.
	var t = EdUssCommands.new_rule_target(m.state.workspace, MENU_USS, ".other", "width")
	m.state.execute(EdUssCommands.insert_rule(m.state.workspace, t, "1px"), "test")
	var text := m.state.workspace.text(MENU_USS)
	var refusals := m.state.refusals.size()
	m.inspector.choose(0)
	await frames()
	eq(m.state.workspace.text(MENU_USS), text, "nothing written")
	eq(m.state.refusals.size(), refusals + 1, "the stale choice is refused")
	ok(String(m.state.refusals[-1]["message"]).contains("changed after this target was created"))


func test_new_rule_target_and_later_writes() -> void:
	var m := await editor()
	await _select(m, "quit-button")
	m.inspector.write_style("width", "120px")
	ok(m.inspector.choose_id("new:%s:#quit-button" % MENU_USS))
	await frames()
	ok(m.state.workspace.text(MENU_USS).ends_with("#quit-button {\r\n  width: 120px;\r\n}\r\n") or m.state.workspace.text(MENU_USS).ends_with("#quit-button {\n  width: 120px;\n}\n"), "a new rule at the end")
	m.inspector.flush()
	m.inspector.write_style("width", "130px")
	eq(m.inspector.pending_labels(), [], "the new rule is now the target")
	await frames()
	var css := m.state.workspace.text(MENU_USS)
	eq(css.count("#quit-button"), 1, "no second rule")
	ok(css.contains("width: 130px"))


func test_typed_checks_and_helpers() -> void:
	var m := await editor()
	await _select(m, "play-button")
	var refusals := m.state.refusals.size()
	m.inspector.write_style("width", "wide")
	eq(m.state.refusals.size(), refusals + 1, "an invalid length is refused")
	eq(m.inspector.pending_labels(), [], "before any question")
	# Enum menu: the keywords of godot-uxml.
	m.inspector._menu_value("row", "flex-direction", null)
	ok(m.inspector.choose_id("inline"))
	await frames()
	ok(m.state.workspace.text(MENU).contains("flex-direction: row;"))
	# Unit helper: the number of the computed value with the new unit.
	m.inspector.flush()
	m.inspector._unit_value("%", "min-width", null)
	ok(m.inspector.choose_id("inline"))
	await frames()
	ok(m.state.workspace.text(MENU).contains("min-width: 180%;"), "180px -> 180%")
	# Colour picker: the changes of one picker are one undo step.
	m.inspector.flush()
	var depth := _undo_depth(m)
	m.inspector._sticky["border-color"] = "inline"
	m.inspector.color_changed("border-color", Color(1, 0, 0), "color:test")
	await frames()
	m.inspector.color_changed("border-color", Color(0, 0, 1, 0.5), "color:test")
	await frames()
	ok(m.state.workspace.text(MENU).contains("border-color: #0000ff80;"), "the last colour")
	eq(_undo_depth(m), depth + 1, "one step for the picker")


func test_asset_picker_validates_project_paths() -> void:
	var m := await editor("assets")
	var root := node_named(m, "relative-image")
	m.state.select_node(root, "test")
	await frames()
	m.inspector.flush()
	var assets: Array = m.inspector.asset_lister.call(EdStyleTypes.IMAGE_EXT)
	ok(assets.has("Assets/Textures/icon.png"), "project images are listed")
	m.inspector._asset_value("Assets/Textures/icon.png", "background-image", null)
	ok(m.inspector.choose_id("inline"))
	await frames()
	ok(m.state.workspace.text("Assets/UI/Assets.uxml").contains("background-image: url(&quot;../Textures/icon.png&quot;);"), "a url relative to the document")
	var refusals := m.state.refusals.size()
	m.inspector.flush()
	m.inspector.write_style("background-image", "url(\"../Textures/missing.png\")")
	if not m.inspector.pending_labels().is_empty():
		m.inspector.choose_id("inline")
	await frames()
	eq(m.state.refusals.size(), refusals + 1, "a missing file is refused")


# ---------------------------------------------------------------------------
# Classes, states, attributes
# ---------------------------------------------------------------------------

func test_class_editor_lists_rules_and_edits_classes() -> void:
	var m := await editor()
	await _select(m, "play-button")
	var cls: Array = m.inspector.classes
	eq(cls.map(func(c): return c["name"]), ["menu-button", "primary"])
	eq(cls[0]["rules"].map(func(r): return r["selector"]), [".menu-button.primary", ".menu-button"])
	ok(cls[0]["rules"].all(func(r): return r["matches"]), "both rules apply")
	var txt := String((m.inspector.doc.get_native("class-rules-0") as Button).text)
	ok(txt.contains("✓ .menu-button.primary  Menu.uss:7"), txt)
	m.inspector._on_button("class-rules-1")
	await frames()
	eq(m.source_path, MENU_USS, "a click shows the first rule")
	# Add and remove: one exact patch each.
	var before := m.state.workspace.text(MENU)
	m.inspector._set_text_of("new-class", "big")
	m.inspector._on_button("add-class")
	await frames()
	eq(m.state.workspace.text(MENU), before.replace("class='menu-button primary'", "class='menu-button primary big'"), "quote style kept")
	m.inspector.flush()
	eq(m.inspector.classes[2]["rules"], [], "no rule names .big")
	m.inspector._on_button("remove-class-1")
	await frames()
	ok(m.state.workspace.text(MENU).contains("class='menu-button big'"))
	eq(_undo_depth(m), 2)
	m.inspector.flush()
	eq(m.inspector.classes[0]["rules"].filter(func(r): return r["matches"]).map(func(r): return r["selector"]), [".menu-button"], "without .primary the compound rule does not apply")


func test_state_preview_forces_states_and_edits_state_rules() -> void:
	var m := await editor()
	var t = EdUssCommands.new_rule_target(m.state.workspace, MENU_USS, ".menu-button:hover", "background-color")
	m.state.execute(EdUssCommands.insert_rule(m.state.workspace, t, "#ff0000"), "test")
	await frames()
	var quit := await _select(m, "quit-button")
	var host := m.canvas.host
	ok(host.computed_style(quit.id)["background-color"]["value"] != "#ff0000", "not hovered")
	m.inspector._on_value_changed("state-hover", true)
	await frames()
	m.inspector.flush()
	eq(host.forced_of(quit.id), ["hover"])
	eq(Array(host.doc.get_forced_states(host.element_for_node[quit.id])), ["hover"], "godot-uxml keeps the state (R6)")
	eq(EdStyleTypes.parse_color(host.computed_style(quit.id)["background-color"]["value"]), Color(1, 0, 0), "the canvas shows the hover rule")
	m.inspector.show_property("background-color")
	m.inspector.flush()
	eq(m.inspector.provenance[0]["status"], "winner")
	ok(String(m.inspector.provenance[0]["where"]).contains(".menu-button:hover"), "the state rule wins")
	var ids: Array = m.inspector.targets.map(func(c): return c["id"])
	ok(not ids.has("inline"), "no inline target for a state")
	ok(ids.has("new:%s:#quit-button:hover" % MENU_USS))
	# A real mouse exit does not clear a forced state; a re-render keeps it.
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(quit), "text", "Bye"), "test")
	await frames()
	quit = node_named(m, "quit-button")
	eq(host.forced_of(quit.id), ["hover"], "the state survives an edit")
	ok(host.doc.get_forced_states(host.element_for_node[quit.id]).has("hover"))
	# Write to the state rule.
	m.inspector.flush()
	m.inspector.write_style("background-color", "#00ff00")
	if not m.inspector.pending_labels().is_empty():
		m.inspector.choose(0)
	await frames()
	ok(m.state.workspace.text(MENU_USS).contains(".menu-button:hover {\r\n  background-color: #00ff00;") or m.state.workspace.text(MENU_USS).contains(".menu-button:hover {\n  background-color: #00ff00;"), "the :hover rule changed")
	m.inspector._on_value_changed("state-hover", false)
	await frames()
	eq(host.forced_of(quit.id), [])
	ok(host.doc.get_forced_states(host.element_for_node[quit.id]).is_empty())


func test_attribute_rows_have_no_gap_and_catalog_hints() -> void:
	var m := await editor()
	await _select(m, "menu-title")
	var block := m.inspector.doc.get_element_model("block-attr-0")
	ok(String(block.get_attribute("class")).contains("hidden"), "no spare rows without extra attributes")
	var i := EdInspectorView.COMMON_ATTRIBUTES.find("picking-mode")
	eq((m.inspector.doc.get_native("attr-%d" % i) as LineEdit).placeholder_text, "Position | Ignore", "enum choices from the catalog")
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(node_named(m, "play-button")), "data-note", "x"), "test")
	await frames()
	await _select(m, "play-button")
	ok(not String(m.inspector.doc.get_element_model("block-attr-0").get_attribute("class")).contains("hidden"), "a block in use is shown")


# ---------------------------------------------------------------------------
# Render host on the editor APIs
# ---------------------------------------------------------------------------

func test_render_host_partial_updates() -> void:
	var m := await editor()
	var host := m.canvas.host
	var r0 := host.renders
	var p0 := host.patches
	var play := node_named(m, "play-button")
	# class/style: replace_source in place.
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(play), "class", "menu-button"), "test")
	await frames()
	eq([host.renders, host.patches], [r0, p0 + 1], "class change in place")
	eq(host.doc.get_last_replace_mode(), "in-place")
	# Another attribute: replace_source reloads, the view state moves.
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(node_named(m, "play-button")), "text", "Go"), "test")
	await frames()
	eq(host.doc.get_last_replace_mode(), "reload")
	eq(host.renders, r0 + 1)
	eq(host.element_for_node[node_named(m, "play-button").id].get_attribute("text"), "Go")
	# A USS edit: reload_stylesheet.
	var t = EdUssCommands.rule_target(m.state.workspace, MENU_USS, 2, "min-width")
	m.state.execute(EdUssCommands.set_declaration(m.state.workspace, t, "99px"), "test")
	await frames()
	eq(host.renders, r0 + 1, "no full load for a USS edit")
	eq(host.computed_style(node_named(m, "quit-button").id)["min-width"]["value"], "99px")


func test_render_host_maps_template_clones_to_the_instance() -> void:
	var dir := copy_fixture("menu")
	var f := FileAccess.open(dir + "/Assets/UI/Card.uxml", FileAccess.WRITE)
	f.store_string("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Label name=\"card-label\" text=\"Card\" style=\"width: 80px; height: 30px;\" />\n</ui:UXML>\n")
	f.close()
	f = FileAccess.open(dir + "/Assets/UI/Host.uxml", FileAccess.WRITE)
	f.store_string("<ui:UXML xmlns:ui=\"UnityEngine.UIElements\">\n  <ui:Template name=\"Card\" src=\"Card.uxml\" />\n  <ui:VisualElement name=\"box\" style=\"padding: 10px; border-left-width: 3px; border-top-width: 5px; rotate: 0deg;\">\n    <ui:Instance template=\"Card\" name=\"card\" />\n  </ui:VisualElement>\n</ui:UXML>\n")
	f.close()
	tree.root.size = Vector2i(1600, 1000)
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(m)
	await frames()
	m.state.open_project(dir)
	m.state.open_document("Assets/UI/Host.uxml")
	await frames()
	var host := m.canvas.host
	var model := host.doc.get_document_model()
	var clone := model.find_by_name("card-label")
	ok(clone != null, "the clone renders")
	ok(not host.node_for_element.has(clone), "a clone is not an authored element of the entry")
	var card := node_named(m, "card")
	eq(host.node_of(clone), card.id, "a clone answers for its <Instance> (R10)")
	var cr := host.doc.get_element_rect(clone)
	eq(host.hit_test(cr.get_center()), card.id, "a click on template content selects the instance")
	var box := node_named(m, "box")
	eq(host.border_start(box.id), Vector2(3, 5), "the border widths from the padding box (R14)")
	ok(host.rect_of(box.id).has_area())
	eq(host.parent_id(card.id), box.id)
