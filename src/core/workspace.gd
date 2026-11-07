class_name EdWorkspace
extends RefCounted
## Every open source buffer of a project, and the one undo history.
##
## Buffers are the truth. The parsed trees (uxml(), uss()) are caches of the
## current buffer text, and the rendered documents are rebuilt from the
## buffers. An edit from any view is an EdTransaction; commit() validates
## every patch set first and changes no buffer when one patch set is
## invalid.

## `paths` changed. `cause` is "execute", "undo", "redo", "load", "save",
## "reload" or "recover". `tx` is the transaction that ran (null for the
## others).
signal buffers_changed(paths: Array, cause: String, tx: EdTransaction)

## path -> EdSourceBuffer
var buffers: Dictionary = {}
## path -> {text: String, bom: bool, revision: Dictionary} at the last
## load or save. A buffer is dirty when its text differs from this base.
var base: Dictionary = {}
var history: EdCommandHistory = null

var _uxml_cache: Dictionary = {}
var _uss_cache: Dictionary = {}


func _init() -> void:
	history = EdCommandHistory.new(self)


func has(path: String) -> bool:
	return buffers.has(path)


func buffer(path: String) -> EdSourceBuffer:
	return buffers.get(path)


func text(path: String) -> String:
	var b: EdSourceBuffer = buffers.get(path)
	return "" if b == null else b.text


## Add or replace a buffer from disk (or from a test). Replacing a buffer
## drops the undo steps that touch it (EdCommandHistory.forget_path); the
## steps of other files stay.
func set_buffer(path: String, b: EdSourceBuffer, revision: Dictionary = {}, cause: String = "load") -> void:
	if buffers.has(path):
		history.forget_path(path)
	buffers[path] = b
	base[path] = {"text": b.text, "bom": b.bom, "revision": revision}
	_uxml_cache.erase(path)
	_uss_cache.erase(path)
	buffers_changed.emit([path], cause, null)


## Put recovered unsaved text into `path` (the recovery journal): the
## buffer gets `text`; the saved state gets `base_text` and `revision`, so
## the file is dirty and a save checks the disk against `revision`.
func restore(path: String, text: String, base_text: String, bom: bool, revision: Dictionary) -> void:
	if buffers.has(path):
		history.forget_path(path)
	buffers[path] = EdSourceBuffer.new(path, text, bom)
	base[path] = {"text": base_text, "bom": bom, "revision": revision}
	_uxml_cache.erase(path)
	_uss_cache.erase(path)
	buffers_changed.emit([path], "recover", null)


## Record that `path` now matches disk at `revision` (after a save).
func mark_saved(path: String, revision: Dictionary) -> void:
	var b: EdSourceBuffer = buffers.get(path)
	if b == null:
		return
	base[path] = {"text": b.text, "bom": b.bom, "revision": revision}
	buffers_changed.emit([path], "save", null)


func revision(path: String) -> Dictionary:
	return base.get(path, {}).get("revision", {})


func is_dirty(path: String) -> bool:
	var b: EdSourceBuffer = buffers.get(path)
	return b != null and base.has(path) and b.text != base[path]["text"]


func dirty_paths() -> Array:
	var out: Array = []
	for p in buffers:
		if is_dirty(p):
			out.append(p)
	out.sort()
	return out


func paths_with_extension(ext: String) -> Array:
	var out: Array = []
	for p in buffers:
		if String(p).to_lower().ends_with(ext):
			out.append(p)
	out.sort()
	return out


## The parsed UXML tree of `path` (cached per buffer text).
func uxml(path: String) -> EdUxmlSource:
	var b: EdSourceBuffer = buffers.get(path)
	if b == null:
		return null
	var c = _uxml_cache.get(path)
	if c != null and c.text == b.text:
		return c
	var parsed := EdUxmlSource.parse(b.text)
	_uxml_cache[path] = parsed
	return parsed


## The parsed USS items of `path` (cached per buffer text).
func uss(path: String) -> EdUssSource:
	var b: EdSourceBuffer = buffers.get(path)
	if b == null:
		return null
	var c = _uss_cache.get(path)
	if c != null and c.text == b.text:
		return c
	var parsed := EdUssSource.parse(b.text)
	_uss_cache[path] = parsed
	return parsed


## Apply `tx` to the buffers. Returns {forward, inverse, paths} or an
## EdError. Does not touch the history; EdCommandHistory calls this.
func commit(tx: EdTransaction) -> Variant:
	if tx == null or tx.label.is_empty():
		return EdError.make("invalid-transaction", "A transaction needs a label.")
	var validated := {}
	for path in tx.patches_by_file:
		var b: EdSourceBuffer = buffers.get(path)
		if b == null:
			return EdError.make("missing-file", "Transaction %s references missing file %s." % [tx.id, path])
		if not b.exact:
			return EdError.make("inexact-source", "%s does not decode to its exact bytes; the editor does not change it." % path)
		var v := EdSourcePatch.validate(b.text, tx.patches_by_file[path])
		if not v["ok"]:
			return EdError.make("invalid-patch", v["error"]["message"], v["error"])
		validated[path] = v["patches"]
	var inverse_by_file := {}
	var next := {}
	for path in validated:
		var sorted: Array = validated[path]
		if sorted.is_empty():
			continue
		var b: EdSourceBuffer = buffers[path]
		inverse_by_file[path] = EdSourcePatch.invert(b.text, sorted)
		next[path] = b.with_text(EdSourcePatch.apply_sorted(b.text, sorted))
	for path in next:
		buffers[path] = next[path]
	var inverse := EdTransaction.new()
	inverse.id = tx.id
	inverse.label = "Undo " + tx.label
	inverse.patches_by_file = inverse_by_file
	inverse.document = tx.document
	inverse.selection_after = tx.selection_before
	inverse.selection_before = tx.selection_after
	inverse.origin = tx.origin
	return {"forward": tx, "inverse": inverse, "paths": next.keys()}


## A transaction that turns the text of `path` into `new_text` with one
## patch over the changed middle (common prefix and suffix kept). Returns
## null when nothing changed.
func replace_text_transaction(path: String, new_text: String, tx_label: String) -> EdTransaction:
	var old := text(path)
	if old == new_text:
		return null
	var p := 0
	var max_p := mini(old.length(), new_text.length())
	while p < max_p and old.unicode_at(p) == new_text.unicode_at(p):
		p += 1
	var s := 0
	var max_s := mini(old.length(), new_text.length()) - p
	while s < max_s and old.unicode_at(old.length() - 1 - s) == new_text.unicode_at(new_text.length() - 1 - s):
		s += 1
	var patch := EdSourcePatch.make(p, old.length() - s, new_text.substr(p, new_text.length() - s - p))
	return EdTransaction.make("source-edit", tx_label, path, [patch])
