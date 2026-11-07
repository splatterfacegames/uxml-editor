class_name EdProjectPaths
extends RefCounted
## Project-relative paths ("Assets/UI/Menu.uxml") and the reference forms
## UXML/USS authors write. Workspace keys are project-relative paths with
## "/" separators and no "." or ".." segments.


## Resolve a `<Style src>`, `@import` or `url()` reference made from the
## file `from` (a workspace path). Returns a workspace path or null when the
## reference leaves the project or has a foreign scheme.
static func resolve(reference: String, from: String) -> Variant:
	var ref := reference.strip_edges().replace("\\", "/")
	var cut := ref.find("?")
	var frag := ref.find("#")
	if frag >= 0 and (cut < 0 or frag < cut):
		cut = frag
	if cut >= 0:
		ref = ref.substr(0, cut)
	if ref.is_empty():
		return null
	if ref.begins_with("project://"):
		ref = ref.substr(10)
		if ref.begins_with("database/"):
			ref = ref.substr(9)
		return normalize(ref)
	if ref.begins_with("/"):
		return normalize(ref)
	if _has_scheme(ref):
		return null
	var base := from.get_base_dir()
	if ref.begins_with("Assets/") or ref.begins_with("Packages/"):
		# Unity reads these as relative to the referencing file first.
		var rel = normalize(ref if base.is_empty() else base + "/" + ref)
		return rel if rel != null and _exists_hint(rel) else normalize(ref)
	return normalize(ref if base.is_empty() else base + "/" + ref)


static var exists_hint: Callable = Callable()


static func _exists_hint(p: String) -> bool:
	return exists_hint.is_valid() and bool(exists_hint.call(p))


static func normalize(path: String) -> Variant:
	var segs: Array = []
	for s in path.replace("\\", "/").split("/"):
		if s.is_empty() or s == ".":
			continue
		if s == "..":
			if segs.is_empty():
				return null
			segs.pop_back()
		else:
			segs.append(s)
	return null if segs.is_empty() else "/".join(segs)


static func _has_scheme(p: String) -> bool:
	var colon := p.find(":")
	if colon <= 0:
		return false
	var c := p.unicode_at(0)
	if not ((c >= 65 and c <= 90) or (c >= 97 and c <= 122)):
		return false
	for i in range(1, colon):
		var d := p.unicode_at(i)
		if not ((d >= 65 and d <= 90) or (d >= 97 and d <= 122) or (d >= 48 and d <= 57) or d == 43 or d == 46 or d == 45):
			return false
	return true
