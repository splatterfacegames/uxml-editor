class_name EdLocator
extends RefCounted
## Find an element again after an edit re-parsed its document.
##
## Element objects do not survive a re-parse. A locator is a plain
## Dictionary that describes an element:
##   {qualified_tag, child_path: Array[int], ancestor_tags: Array[String],
##    attribute_hints: Array[{name, value}], authored_name (optional)}
## resolve() tries a unique `name` attribute first, then the child path
## when the structure and hints still agree, then a unique structural match,
## then the child path when only the structure agrees.


static func create(node: EdUxmlNode) -> Dictionary:
	if node == null:
		return {}
	var hints: Array = []
	for a in node.attributes:
		hints.append({"name": a["name"], "value": a["value"]})
	var loc := {
		"qualified_tag": node.name,
		"child_path": node.child_path(),
		"ancestor_tags": node.ancestor_tags(),
		"attribute_hints": hints,
	}
	var n = node.get_attribute("name")
	if n != null:
		loc["authored_name"] = n
	return loc


static func is_valid(loc: Variant) -> bool:
	if typeof(loc) != TYPE_DICTIONARY:
		return false
	if typeof(loc.get("qualified_tag")) != TYPE_STRING or not EdXml.is_qualified_name(loc["qualified_tag"]):
		return false
	if typeof(loc.get("child_path")) != TYPE_ARRAY:
		return false
	for p in loc["child_path"]:
		if typeof(p) != TYPE_INT or p < 0:
			return false
	if typeof(loc.get("ancestor_tags")) != TYPE_ARRAY or typeof(loc.get("attribute_hints")) != TYPE_ARRAY:
		return false
	if loc.has("authored_name") and typeof(loc["authored_name"]) != TYPE_STRING:
		return false
	return true


static func resolve(root: EdUxmlNode, loc: Dictionary) -> EdUxmlNode:
	if root == null or not is_valid(loc):
		return null
	var all := root.walk()
	if loc.has("authored_name"):
		var named: Array = []
		for n in all:
			if n.get_attribute("name") == loc["authored_name"]:
				named.append(n)
		if named.size() == 1:
			return named[0]
	var direct: EdUxmlNode = null
	for n in all:
		if n.child_path() == loc["child_path"]:
			direct = n
			break
	var structural: EdUxmlNode = direct if direct != null and _structure(direct, loc) else null
	if structural != null and _hints(structural, loc):
		return structural
	var matches: Array = []
	for n in all:
		if _structure(n, loc) and _hints(n, loc):
			matches.append(n)
	if matches.size() == 1:
		return matches[0]
	return structural


static func _structure(n: EdUxmlNode, loc: Dictionary) -> bool:
	return n.name == loc["qualified_tag"] and n.ancestor_tags() == loc["ancestor_tags"]


static func _hints(n: EdUxmlNode, loc: Dictionary) -> bool:
	for h in loc["attribute_hints"]:
		var found := false
		for a in n.attributes:
			if a["name"] == h["name"] and a["value"] == h["value"]:
				found = true
				break
		if not found:
			return false
	return true
