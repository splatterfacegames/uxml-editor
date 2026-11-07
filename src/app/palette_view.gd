class_name EdPaletteView
extends RefCounted
## The element library: a godot-uxml TreeView (`palette-tree`) and a
## search field (`palette-search`) in the editor shell. Groups are the
## parent items; an element item inserts on a double-click or Enter, and a
## drag from it inserts at the drop position (EdDragController).
##
## Tree item ids: an element is its index in EdElementCatalog.entries();
## a group is -1 - its index in EdElementCatalog.GROUPS.

const TREE := "palette-tree"
const SEARCH := "palette-search"

var shell: UxmlDocument
var query := ""


func _init(s: UxmlDocument) -> void:
	shell = s


func refresh() -> void:
	var entries := EdElementCatalog.entries()
	var hits := EdElementCatalog.search(query)
	var roots: Array = []
	for gi in EdElementCatalog.GROUPS.size():
		var group: String = EdElementCatalog.GROUPS[gi]
		var children: Array = []
		for e in hits:
			if e["group"] == group:
				var label: String = e["name"]
				if e["uri"] == EdElementCatalog.EDITOR:
					label += "   uie"
				children.append({"id": entries.find(e), "data": label, "children": []})
		if not children.is_empty():
			roots.append({"id": -1 - gi, "data": "%s (%d)" % [group, children.size()], "children": children})
	shell.set_tree_source(TREE, roots)
	for r in roots:
		shell.set_tree_item_expanded(TREE, r["id"], true)


func set_query(q: String) -> void:
	if q == query:
		return
	query = q
	refresh()


## The catalog entry of visible tree index `index`, or {} for a group row.
func entry_at(index: int) -> Dictionary:
	var item := shell.get_tree_item(TREE, index)
	if item.is_empty():
		return {}
	var id := int(item["id"])
	var entries := EdElementCatalog.entries()
	return entries[id] if id >= 0 and id < entries.size() else {}


## Visible tree indices of every element item (tests, screenshots).
func element_indices() -> Array:
	var out: Array = []
	var i := 0
	while true:
		var item := shell.get_tree_item(TREE, i)
		if item.is_empty():
			break
		if int(item["id"]) >= 0:
			out.append(i)
		i += 1
	return out
