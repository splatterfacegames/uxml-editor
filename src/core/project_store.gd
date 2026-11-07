class_name EdProjectStore
extends RefCounted
## Disk access for one project directory: enumerate, read and save UXML and
## USS files, with revision checks.
##
## A revision is {exists, size, mtime, sha256}. save() refuses to write when
## the file on disk no longer has the revision the buffer was read or last
## saved at ("stale-revision"), so an external change is never overwritten
## without a decision. A save writes a temporary file next to the target and
## renames it over the target.

const EXTENSIONS := ["uxml", "uss"]
## Directories never scanned: Unity caches, VCS and tool folders.
const SKIP_DIRS := ["Library", "Temp", "Logs", "obj", "UserSettings", "Build", "Builds", "node_modules"]
const TEMP_SUFFIX := ".uxml-editor-save.tmp"

var root: String = ""


func _init(project_root: String = "") -> void:
	root = normalize_root(project_root)


static func normalize_root(p: String) -> String:
	var r := p.replace("\\", "/")
	while r.length() > 1 and r.ends_with("/") and not r.ends_with(":/"):
		r = r.substr(0, r.length() - 1)
	return r


func is_valid() -> bool:
	return not root.is_empty() and DirAccess.dir_exists_absolute(root)


func absolute(rel: String) -> String:
	return root + "/" + rel


## Project-relative paths of every .uxml and .uss file, sorted.
func list_files() -> Array:
	var out: Array = []
	_scan("", out, 0)
	out.sort()
	return out


## Project-relative paths of every file with one of the extensions
## `exts` (lower case, no dot), sorted. The same folders are skipped as
## for list_files().
func list_assets(exts: Array) -> Array:
	var out: Array = []
	_scan("", out, 0, exts)
	out.sort()
	return out


func _scan(rel_dir: String, out: Array, depth: int, exts: Array = EXTENSIONS) -> void:
	if depth > 32:
		return
	var abs_dir := root if rel_dir.is_empty() else root + "/" + rel_dir
	var d := DirAccess.open(abs_dir)
	if d == null:
		return
	d.include_hidden = false
	d.include_navigational = false
	for f in d.get_files():
		if exts.has(f.get_extension().to_lower()):
			out.append(f if rel_dir.is_empty() else rel_dir + "/" + f)
	for sub in d.get_directories():
		if sub.begins_with(".") or SKIP_DIRS.has(sub):
			continue
		_scan(sub if rel_dir.is_empty() else rel_dir + "/" + sub, out, depth + 1, exts)


func exists(rel: String) -> bool:
	return FileAccess.file_exists(absolute(rel))


func revision(rel: String) -> Dictionary:
	var p := absolute(rel)
	if not FileAccess.file_exists(p):
		return {"exists": false, "size": 0, "mtime": 0, "sha256": ""}
	var bytes := FileAccess.get_file_as_bytes(p)
	return revision_of(bytes, FileAccess.get_modified_time(p))


## True when the file may differ from `known` (a revision): the size or the
## modification time differs, or the time is too recent to tell (the time
## has whole seconds). Reads no bytes, so a timer can call it often; a
## true result needs revision() to decide.
func may_differ(rel: String, known: Dictionary) -> bool:
	var p := absolute(rel)
	var exists := FileAccess.file_exists(p)
	if exists != bool(known.get("exists", false)):
		return true
	if not exists:
		return false
	var mtime := FileAccess.get_modified_time(p)
	if mtime != int(known.get("mtime", -1)):
		return true
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null or f.get_length() != int(known.get("size", -1)):
		return true
	return int(Time.get_unix_time_from_system()) - mtime <= 3


static func revision_of(bytes: PackedByteArray, mtime: int) -> Dictionary:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not bytes.is_empty():
		ctx.update(bytes)
	return {"exists": true, "size": bytes.size(), "mtime": mtime, "sha256": ctx.finish().hex_encode()}


static func same_revision(a: Dictionary, b: Dictionary) -> bool:
	return a.get("exists", false) == b.get("exists", false) and a.get("sha256", "") == b.get("sha256", "")


## Returns {buffer: EdSourceBuffer, revision} or an EdError.
func read(rel: String) -> Variant:
	var p := absolute(rel)
	if not FileAccess.file_exists(p):
		return EdError.make("missing-file", "%s does not exist." % rel)
	var bytes := FileAccess.get_file_as_bytes(p)
	if bytes.is_empty() and FileAccess.get_open_error() != OK:
		return EdError.make("read-failed", "%s could not be read (%s)." % [rel, error_string(FileAccess.get_open_error())])
	return {"buffer": EdSourceBuffer.from_bytes(rel, bytes), "revision": revision_of(bytes, FileAccess.get_modified_time(p))}


## Write `buffer` if the disk file still has `expected` revision. Returns
## the new revision or an EdError ("stale-revision", "inexact-source",
## "write-failed").
func save(rel: String, buffer: EdSourceBuffer, expected: Dictionary, force: bool = false) -> Variant:
	if not buffer.exact:
		return EdError.make("inexact-source", "%s does not decode to its exact bytes; the editor does not save it." % rel)
	var current := revision(rel)
	if not force and not same_revision(current, expected):
		return EdError.make("stale-revision", "%s changed on disk after it was opened. Reload it or overwrite it." % rel, current)
	var p := absolute(rel)
	var bytes := buffer.to_bytes()
	var tmp := p + TEMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return EdError.make("write-failed", "%s could not be written (%s)." % [rel, error_string(FileAccess.get_open_error())])
	f.store_buffer(bytes)
	f.flush()
	var werr := f.get_error()
	f.close()
	if werr != OK:
		DirAccess.remove_absolute(tmp)
		return EdError.make("write-failed", "%s could not be written (%s)." % [rel, error_string(werr)])
	var rerr := DirAccess.rename_absolute(tmp, p)
	if rerr != OK:
		DirAccess.remove_absolute(tmp)
		return EdError.make("write-failed", "%s could not be replaced (%s)." % [rel, error_string(rerr)])
	var after := revision(rel)
	if after["sha256"] != revision_of(bytes, 0)["sha256"]:
		return EdError.make("write-failed", "%s does not read back as the bytes that were written." % rel, after)
	return after
