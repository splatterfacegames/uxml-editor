class_name EdCommandHistory
extends RefCounted
## The one undo history of a workspace.
##
## Each entry holds the forward transactions and their inverses. A
## transaction with the same nonempty coalesce key as the previous entry
## joins that entry, until an undo or redo (or break_coalescing()) closes it.

signal history_changed

var _ws: WeakRef
var _undo: Array = []
var _redo: Array = []
var _coalescing := true


func _init(ws: EdWorkspace) -> void:
	_ws = weakref(ws)


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo_depth() -> int:
	return _undo.size()


func redo_depth() -> int:
	return _redo.size()


func undo_label() -> String:
	return "" if _undo.is_empty() else _undo[-1]["forward"][-1].label


func redo_label() -> String:
	return "" if _redo.is_empty() else _redo[-1]["forward"][-1].label


## Commit `tx` and record it. Returns the commit result or an EdError (the
## history and the buffers are then unchanged).
func execute(tx: EdTransaction) -> Variant:
	var ws: EdWorkspace = _ws.get_ref()
	var r = ws.commit(tx)
	if r is EdError:
		return r
	var prev = null if _undo.is_empty() else _undo[-1]
	if _coalescing and prev != null and not tx.coalesce_key.is_empty() and prev["key"] == tx.coalesce_key:
		prev["forward"].append(r["forward"])
		prev["inverse"].push_front(r["inverse"])
	else:
		_undo.append({"forward": [r["forward"]], "inverse": [r["inverse"]], "key": tx.coalesce_key})
	_redo.clear()
	_coalescing = true
	ws.buffers_changed.emit(r["paths"], "execute", tx)
	history_changed.emit()
	return r


## Undo the last step. Returns {entry, results} or null.
func undo() -> Variant:
	if _undo.is_empty():
		return null
	var entry: Dictionary = _undo[-1]
	var r = _run(entry["inverse"], "undo")
	if r is EdError:
		return r
	_undo.pop_back()
	_redo.append(entry)
	_coalescing = false
	history_changed.emit()
	return {"entry": entry, "paths": r}


func redo() -> Variant:
	if _redo.is_empty():
		return null
	var entry: Dictionary = _redo[-1]
	var r = _run(entry["forward"], "redo")
	if r is EdError:
		return r
	_redo.pop_back()
	_undo.append(entry)
	_coalescing = false
	history_changed.emit()
	return {"entry": entry, "paths": r}


func break_coalescing() -> void:
	_coalescing = false


func clear() -> void:
	_undo.clear()
	_redo.clear()
	history_changed.emit()


## Commit a sequence; on a failure roll back the ones that ran.
func _run(seq: Array, cause: String) -> Variant:
	var ws: EdWorkspace = _ws.get_ref()
	var done: Array = []
	var paths := {}
	for tx in seq:
		var r = ws.commit(tx)
		if r is EdError:
			for k in range(done.size() - 1, -1, -1):
				ws.commit(done[k]["inverse"])
			return r
		done.append(r)
		for p in r["paths"]:
			paths[p] = true
	var last: EdTransaction = seq[-1]
	ws.buffers_changed.emit(paths.keys(), cause, last)
	return paths.keys()
