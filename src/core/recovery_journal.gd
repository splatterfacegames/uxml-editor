class_name EdRecoveryJournal
extends RefCounted
## The recovery journal of one project (ADR 0005): a bounded, versioned,
## validated record chain of the unsaved edits, so the edits survive a
## killed process.
##
## The journal is one file of JSON lines in `dir`. Each line is one
## record: {v, seq, prev, kind, ...}. `seq` counts from 0; `prev` is the
## SHA-256 of the line before (the header has prev ""). A reader accepts
## only a complete chain: a line that does not parse, a gap in `seq` or a
## wrong `prev` makes the journal corrupt, and nothing replays. A last line
## without its line break (a write cut by a kill) is dropped; the records
## before it replay.
##
## Kinds:
##   header  {project, created}
##   base    {path, revision, bom, text}   the saved text of a file, before
##                                         its first unsaved edit
##   patch   {path, start, end, text}      one edit (String offsets)
##   clean   {path}                        the file has no unsaved edit
##                                         (saved, reloaded, undone)
##
## Each record is flushed to the operating system at once. When the file
## grows past MAX_BYTES, compact() writes a new journal with one base and
## one patch per unsaved file (temporary file, then rename).

const VERSION := 1
const FILE := "journal.jsonl"
const MAX_BYTES := 4 * 1024 * 1024

var dir: String = ""
var project_root: String = ""
var _file: FileAccess = null
var _seq := 0
var _prev := ""
var _bytes := 0
## path -> text after the last journaled record, for the unsaved files.
var _texts: Dictionary = {}
## path -> {revision, bom, text} of the base record of each unsaved file.
var _bases: Dictionary = {}


## The journal directory of `project_root` under `base_dir`
## (user://recovery by default): one directory per project.
static func dir_for(base_dir: String, root: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(EdProjectStore.normalize_root(root).to_lower().to_utf8_buffer())
	return base_dir.path_join(ctx.finish().hex_encode().substr(0, 16))


func _init(journal_dir: String = "", root: String = "") -> void:
	dir = journal_dir
	project_root = root


func file_path() -> String:
	return dir.path_join(FILE)


func exists() -> bool:
	return FileAccess.file_exists(file_path())


func is_open() -> bool:
	return _file != null


## Start a new, empty journal (a header only). Replaces an old journal.
func start() -> Variant:
	close()
	DirAccess.make_dir_recursive_absolute(dir)
	_texts.clear()
	_bases.clear()
	var err = _write_new([{"kind": "header", "project": project_root, "created": int(Time.get_unix_time_from_system())}])
	return err


## Record that `path` now has the text `new_text`. `dirty`: the file has
## unsaved edits. `base` is the saved state {text, bom, revision} of the
## file (EdWorkspace.base[path]). The record is a patch from the text of
## the last record of the file (or from the base).
func record(path: String, new_text: String, dirty: bool, base: Dictionary) -> void:
	if _file == null:
		return
	if not dirty:
		if _texts.has(path):
			_texts.erase(path)
			_bases.erase(path)
			_append({"kind": "clean", "path": path})
		return
	var old_text := ""
	if not _texts.has(path):
		var b := {"revision": base.get("revision", {}), "bom": bool(base.get("bom", false)), "text": String(base.get("text", ""))}
		_bases[path] = b
		_append({"kind": "base", "path": path, "revision": b["revision"], "bom": b["bom"], "text": b["text"]})
		old_text = b["text"]
	else:
		old_text = _texts[path]
	var d = diff(old_text, new_text)
	_texts[path] = new_text
	if d != null:
		_append({"kind": "patch", "path": path, "start": d[0], "end": d[1], "text": d[2]})
	if _bytes > MAX_BYTES:
		compact()


## Write a new journal with the current state of every unsaved file.
func compact() -> void:
	var records: Array = [{"kind": "header", "project": project_root, "created": int(Time.get_unix_time_from_system())}]
	for p in _texts:
		var b: Dictionary = _bases[p]
		records.append({"kind": "base", "path": p, "revision": b["revision"], "bom": b["bom"], "text": b["text"]})
		var d = diff(b["text"], _texts[p])
		if d != null:
			records.append({"kind": "patch", "path": p, "start": d[0], "end": d[1], "text": d[2]})
	_write_new(records)


## Close the journal file and delete it (no unsaved edits remain, or the
## user discarded them).
func discard() -> void:
	close()
	if exists():
		DirAccess.remove_absolute(file_path())


func close() -> void:
	if _file != null:
		_file.close()
		_file = null


## The unsaved files of the journal at `journal_dir`:
## {ok: bool, error: String, truncated: bool, project: String,
##  files: {path: {revision, bom, base_text, text}}}.
## A missing journal is ok with no files. A corrupt chain is not ok.
static func read(journal_dir: String) -> Dictionary:
	var out := {"ok": true, "error": "", "truncated": false, "project": "", "files": {}}
	var p := journal_dir.path_join(FILE)
	if not FileAccess.file_exists(p):
		return out
	var raw := FileAccess.get_file_as_string(p)
	var lines := raw.split("\n")
	# The part after the last line break is a record cut by a kill.
	if not lines[-1].is_empty():
		out["truncated"] = true
	lines.remove_at(lines.size() - 1)
	var prev := ""
	var files := {}
	for i in lines.size():
		var line: String = lines[i]
		var rec = JSON.parse_string(line)
		if typeof(rec) != TYPE_DICTIONARY:
			return _corrupt(out, "record %d does not parse" % i)
		if int(rec.get("v", -1)) != VERSION:
			return _corrupt(out, "record %d has version %s" % [i, str(rec.get("v"))])
		if int(rec.get("seq", -1)) != i or String(rec.get("prev", "?")) != prev:
			return _corrupt(out, "record %d breaks the chain" % i)
		prev = _hash(line)
		var path := String(rec.get("path", ""))
		match String(rec.get("kind", "")):
			"header":
				if i != 0:
					return _corrupt(out, "record %d is a second header" % i)
				out["project"] = String(rec.get("project", ""))
			"base":
				files[path] = {"revision": rec.get("revision", {}), "bom": bool(rec.get("bom", false)),
					"base_text": String(rec.get("text", "")), "text": String(rec.get("text", ""))}
			"patch":
				if not files.has(path):
					return _corrupt(out, "record %d patches %s without a base" % [i, path])
				var t: String = files[path]["text"]
				var s := int(rec.get("start", -1))
				var e := int(rec.get("end", -1))
				if s < 0 or e < s or e > t.length():
					return _corrupt(out, "record %d has an invalid range" % i)
				files[path]["text"] = t.substr(0, s) + String(rec.get("text", "")) + t.substr(e)
			"clean":
				files.erase(path)
			_:
				return _corrupt(out, "record %d has an unknown kind" % i)
		if i == 0 and String(rec.get("kind", "")) != "header":
			return _corrupt(out, "the journal has no header")
	for path in files.keys():
		if files[path]["text"] == files[path]["base_text"]:
			files.erase(path)
	out["files"] = files
	return out


static func _corrupt(out: Dictionary, why: String) -> Dictionary:
	out["ok"] = false
	out["error"] = why
	out["files"] = {}
	return out


## [start, end, replacement] that turns `a` into `b` (common prefix and
## suffix kept), or null when they are equal.
static func diff(a: String, b: String) -> Variant:
	if a == b:
		return null
	var n := mini(a.length(), b.length())
	var lo := 0
	var hi := n
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if a.substr(0, mid) == b.substr(0, mid):
			lo = mid
		else:
			hi = mid - 1
	var p := lo
	lo = 0
	hi = n - p
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if a.substr(a.length() - mid) == b.substr(b.length() - mid):
			lo = mid
		else:
			hi = mid - 1
	var s := lo
	return [p, a.length() - s, b.substr(p, b.length() - s - p)]


static func _hash(line: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(line.to_utf8_buffer())
	return ctx.finish().hex_encode()


func _line(rec: Dictionary) -> String:
	var r := rec.duplicate()
	r["v"] = VERSION
	r["seq"] = _seq
	r["prev"] = _prev
	var line := JSON.stringify(r)
	_seq += 1
	_prev = _hash(line)
	return line


func _append(rec: Dictionary) -> void:
	var line := _line(rec)
	_file.store_string(line + "\n")
	_file.flush()
	_bytes += line.length() + 1


## Write `records` as a new journal: a temporary file, then a rename over
## the old journal, so a kill leaves either the old or the new journal.
func _write_new(records: Array) -> Variant:
	close()
	_seq = 0
	_prev = ""
	_bytes = 0
	var tmp := file_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return EdError.make("journal-write-failed", "The recovery journal could not be written (%s)." % error_string(FileAccess.get_open_error()))
	for rec in records:
		var line := _line(rec)
		f.store_string(line + "\n")
		_bytes += line.length() + 1
	f.flush()
	f.close()
	var err := DirAccess.rename_absolute(tmp, file_path())
	if err != OK:
		return EdError.make("journal-write-failed", "The recovery journal could not be replaced (%s)." % error_string(err))
	_file = FileAccess.open(file_path(), FileAccess.READ_WRITE)
	if _file == null:
		return EdError.make("journal-write-failed", "The recovery journal could not be opened.")
	_file.seek_end()
	return null
