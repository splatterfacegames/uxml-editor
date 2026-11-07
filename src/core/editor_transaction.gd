class_name EdTransaction
extends RefCounted
## One undoable edit: patch sets for one or more files.
##
## Every view (canvas, hierarchy, inspector, source) edits through
## transactions, and one EdCommandHistory records them. Each patch set is
## against the text of its file before the transaction.

var id: String = ""
var label: String = ""
## path -> Array of patches (see EdSourcePatch)
var patches_by_file: Dictionary = {}
## The document (entry UXML path) whose selection `selection_after` names.
var document: String = ""
## Array of EdLocator dictionaries, or null to keep the selection.
var selection_after: Variant = null
## The selection when the edit ran; the inverse restores it.
var selection_before: Variant = null
## Consecutive transactions with the same nonempty key merge into one undo
## step (typing in the source view, dragging a slider).
var coalesce_key: String = ""
## Which view made the edit ("source", "inspector", "hierarchy", ...).
var origin: String = ""


static func make(op: String, tx_label: String, path: String, patches: Array) -> EdTransaction:
	var tx := EdTransaction.new()
	tx.label = tx_label
	tx.patches_by_file = {path: patches}
	tx.id = "%s:%s" % [op, _hash(JSON.stringify([op, path, patches]))]
	return tx


static func multi(op: String, tx_label: String, by_file: Dictionary) -> EdTransaction:
	var tx := EdTransaction.new()
	tx.label = tx_label
	tx.patches_by_file = by_file
	tx.id = "%s:%s" % [op, _hash(JSON.stringify([op, by_file]))]
	return tx


func patches(path: String) -> Array:
	return patches_by_file.get(path, [])


func paths() -> Array:
	return patches_by_file.keys()


func copy() -> EdTransaction:
	var tx := EdTransaction.new()
	tx.id = id
	tx.label = label
	tx.patches_by_file = patches_by_file.duplicate(true)
	tx.document = document
	tx.selection_after = null if selection_after == null else (selection_after as Array).duplicate(true)
	tx.selection_before = null if selection_before == null else (selection_before as Array).duplicate(true)
	tx.coalesce_key = coalesce_key
	tx.origin = origin
	return tx


func is_empty() -> bool:
	for p in patches_by_file:
		if not (patches_by_file[p] as Array).is_empty():
			return false
	return true


## FNV-1a, 32 bit, as hex. Used only to make transaction ids readable.
static func _hash(s: String) -> String:
	var h := 0x811c9dc5
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return "%08x" % h
