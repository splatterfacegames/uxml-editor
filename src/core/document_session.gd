class_name EdDocumentSession
extends RefCounted
## One UXML document of a workspace: the entry file and its parsed tree.
##
## Commands read the session and return transactions. The session holds no
## state of its own except the entry path: the tree is always the current
## parse of the workspace buffer.

var workspace: EdWorkspace
var entry_path: String = ""


func _init(ws: EdWorkspace = null, path: String = "") -> void:
	workspace = ws
	entry_path = path


func tree() -> EdUxmlSource:
	return workspace.uxml(entry_path)


func root() -> EdUxmlNode:
	var t := tree()
	return null if t == null else t.root


func source() -> String:
	return workspace.text(entry_path)


func resolve(loc: Dictionary) -> EdUxmlNode:
	return EdLocator.resolve(root(), loc)


func locator_for(node: EdUxmlNode) -> Dictionary:
	return EdLocator.create(node)


## The stylesheet paths this document references with <Style src>, in
## document order, as workspace paths (see EdProjectPaths.resolve).
func style_paths() -> Array:
	var out: Array = []
	var r := root()
	if r == null:
		return out
	for n in r.walk():
		if n.local == "Style":
			var src = n.get_attribute("src")
			if src == null:
				continue
			var p = EdProjectPaths.resolve(String(src), entry_path)
			if p != null and workspace.has(p) and not out.has(p):
				out.append(p)
	return out
