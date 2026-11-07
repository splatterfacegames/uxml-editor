class_name EdBufferResolver
extends UxmlResourceResolver
## A godot-uxml resolver that reads stylesheets and templates from the
## editor's source buffers when the editor has them open, so the canvas
## shows unsaved text. Every other file comes from disk as usual.
##
## Workaround: godot-uxml has no public way to pass a resolver or text
## overrides to UxmlDocument.load_source() (docs/godot-uxml-requests.md,
## request R1).

## canonical absolute path (lower case on Windows) -> text
var overrides: Dictionary = {}
## canonical absolute paths read through this resolver
var reads: Array = []


func _init(root: String = "res://") -> void:
	super(root)


static func key(path: String) -> String:
	var k := UxmlResourceResolver.collapse_path(path.replace("\\", "/"))
	if OS.get_name() == "Windows" or OS.get_name() == "macOS":
		k = k.to_lower()
	return k


func set_override(abs_path: String, text: String) -> void:
	overrides[key(abs_path)] = text


func resolve_text(reference: String, from: String = "") -> Dictionary:
	var r := resolve(reference, from)
	if not r["ok"]:
		r["text"] = ""
		return r
	var k := key(r["path"])
	reads.append(k)
	if overrides.has(k):
		return {"ok": true, "path": r["path"], "text": overrides[k], "diagnostic": {}}
	return super(reference, from)
