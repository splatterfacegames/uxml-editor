extends EdTestCase
## The span parsers: exact spans, and the same element and item identity as
## godot-uxml for every fixture and every godot-uxml parity case.


func test_uxml_spans() -> void:
	var src := "<?xml version=\"1.0\"?>\n<ui:UXML xmlns:ui='UnityEngine.UIElements'>\n  <!-- c -->\n  <ui:Label text=\"a &amp; b\"/>\n  <ui:VisualElement name=\"v\" >x</ui:VisualElement >\n</ui:UXML>\n"
	var t := EdUxmlSource.parse(src)
	eq(t.problems, [])
	eq(t.nodes.size(), 3)
	var label: EdUxmlNode = t.nodes[1]
	eq(label.self_closing, true)
	eq(src.substr(label.open_start, label.open_end - label.open_start), "<ui:Label text=\"a &amp; b\"/>")
	var a: Dictionary = label.attributes[0]
	eq(a["value"], "a & b")
	eq(a["raw"], "a &amp; b")
	eq(src.substr(a["start"], a["end"] - a["start"]), "text=\"a &amp; b\"")
	eq(a["quote"], "\"")
	var ve: EdUxmlNode = t.nodes[2]
	eq(src.substr(ve.inner_start, ve.inner_end - ve.inner_start), "x")
	eq(src.substr(ve.close_start, ve.close_end - ve.close_start), "</ui:VisualElement >")
	eq(t.root.attributes[0]["quote"], "'")
	eq(t.element_at_offset(src.find("name=\"v\"")), ve)
	eq(t.find_by_open_start(ve.open_start), ve)


func test_uxml_recovery_is_recorded() -> void:
	var t := EdUxmlSource.parse("<A><B></C><D x=1 /></A><E/>")
	ok(t.problems.size() >= 3, "mismatch, unquoted value and trailing element reported")
	eq(t.nodes.size(), 3, "elements after the root are dropped")
	eq(t.nodes[1].well_formed, false)


func test_uss_items_and_declarations() -> void:
	var src := "@import url(\"a.uss\");\n/* c */\n.a, #b > Label:hover {\n  color : red;\n  width: 10px /* n */;\n}\n@media x { .q { a: b; } }\n.z { }"
	var u := EdUssSource.parse(src)
	eq(u.items.size(), 4)
	eq(u.items[0]["kind"], "import")
	eq(u.items[0]["url"], "a.uss")
	var r: Dictionary = u.items[1]
	eq(r["selector_text"], ".a, #b > Label:hover")
	var d: Array = r["declarations"]
	eq(d.size(), 2)
	eq(d[0]["property"], "color")
	eq(d[0]["raw"], "red")
	eq(src.substr(d[0]["start"], d[0]["end"] - d[0]["start"]), "color : red")
	eq(d[1]["value"], "10px")
	eq(d[1]["raw"], "10px /* n */")
	eq(d[1]["has_comment"], true)
	eq(u.items[2]["kind"], "unknown")
	eq(u.items[2]["at_rule"], "media")
	eq(u.items[3]["closed"], true)


func test_uxml_tree_matches_godot_uxml_for_every_fixture() -> void:
	var files := fixture_files(["uxml"])
	ok(files.size() >= 140, "fixtures found (%d)" % files.size())
	var mismatched: Array = []
	for f in files:
		var src := EdSourceBuffer.from_bytes(f, read_file(f)).text
		var ours := EdUxmlSource.parse(src)
		var theirs: Dictionary = UxmlParser.new().parse(src, f)
		var their_nodes: Array = []
		if theirs["root"].local != "" or theirs["root"].open_tag_end > 0:
			their_nodes = theirs["root"].walk()
		var a: Array = ours.nodes.map(func(n): return [n.name, n.open_start, n.open_end, n.outer_end(), n.attributes.size()])
		var b: Array = their_nodes.map(func(n): return [n.tag(), n.open_tag_start, n.open_tag_end, n.source_end, n.attributes.size()])
		if a != b:
			mismatched.append(f.get_file())
		else:
			for k in ours.nodes.size():
				var mine: Array = ours.nodes[k].attributes.map(func(x): return [x["name"], x["value"], x["start"]])
				var godot: Array = their_nodes[k].attributes.map(func(x): return [x["name"], x["value"], x["offset"]])
				if mine != godot:
					mismatched.append(f.get_file() + " (attributes)")
					break
	eq(mismatched, [], "element identity differs from godot-uxml")


func test_uss_items_match_godot_uxml_for_every_fixture() -> void:
	var files := fixture_files(["uss"])
	ok(files.size() >= 50, "fixtures found (%d)" % files.size())
	var mismatched: Array = []
	for f in files:
		var src := EdSourceBuffer.from_bytes(f, read_file(f)).text
		var ours := EdUssSource.parse(src)
		var theirs: Array = UssParser.new().parse(src, f)["items"]
		var a: Array = []
		for it in ours.items:
			var row := [it["kind"], it["start"], it["end"]]
			if it["kind"] == "rule":
				row.append(it["declarations"].map(func(d): return [d["property"], d["value"], d["start"], d["end"]]))
			a.append(row)
		var b: Array = []
		for it in theirs:
			var span: Dictionary = it["rule"]["span"] if it["kind"] == "rule" else it["span"]
			var row := [it["kind"], int(span["start"]), int(span["end"])]
			if it["kind"] == "rule":
				row.append(it["rule"]["declarations"].map(func(d): return [d["property"], d["value"], int(d["span"]["start"]), int(d["span"]["end"])]))
			b.append(row)
		if a != b:
			mismatched.append(f.get_file())
	eq(mismatched, [], "item identity differs from godot-uxml")
