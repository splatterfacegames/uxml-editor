class_name EdEditorState
extends RefCounted
## The application state every view reads: the project, the workspace with
## its one undo history, the active document and the selection.
##
## Views never change buffers directly. They make transactions and pass
## them to execute(), so every edit, from any view, is one undo step and
## every view refreshes from the same buffers_changed signal.

signal project_opened
signal document_opened(path: String)
## The selection changed. `origin` names the view that changed it.
signal selection_changed(origin: String)
signal buffers_changed(paths: Array, cause: String, tx: EdTransaction)
signal status(message: String, is_error: bool)

var store: EdProjectStore = null
var workspace: EdWorkspace = null
var files: Array = []
var session: EdDocumentSession = null
## Array of EdLocator dictionaries for the active document.
var selection: Array = []


func _init() -> void:
	_new_workspace()


func _new_workspace() -> void:
	workspace = EdWorkspace.new()
	workspace.buffers_changed.connect(_on_buffers_changed)


func has_project() -> bool:
	return store != null


func open_project(dir: String) -> bool:
	var s := EdProjectStore.new(dir)
	if not s.is_valid():
		status.emit("%s is not a directory." % dir, true)
		return false
	store = s
	_new_workspace()
	session = null
	selection = []
	files = store.list_files()
	var failed := 0
	for rel in files:
		var r = store.read(rel)
		if r is EdError:
			failed += 1
			continue
		workspace.set_buffer(rel, r["buffer"], r["revision"])
	EdProjectPaths.exists_hint = func(p: String) -> bool: return workspace.has(p)
	project_opened.emit()
	var uxml := workspace.paths_with_extension(".uxml")
	status.emit("Opened %s: %d UXML and %d USS files%s." % [dir, uxml.size(), files.size() - uxml.size(),
		"" if failed == 0 else ", %d unreadable" % failed], failed > 0)
	return true


func open_document(rel: String) -> void:
	if not workspace.has(rel) or not rel.to_lower().ends_with(".uxml"):
		return
	if session != null and session.entry_path == rel:
		return
	session = EdDocumentSession.new(workspace, rel)
	selection = []
	workspace.history.break_coalescing()
	document_opened.emit(rel)
	selection_changed.emit("open")


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func selected_node() -> EdUxmlNode:
	if session == null or selection.is_empty():
		return null
	return session.resolve(selection[0])


func select_node(node: EdUxmlNode, origin: String) -> void:
	var next := [] if node == null else [EdLocator.create(node)]
	if next == selection:
		return
	selection = next
	selection_changed.emit(origin)


func select_id(id: int, origin: String) -> void:
	if session == null:
		return
	var t := session.tree()
	select_node(t.nodes[id] if id >= 0 and id < t.nodes.size() else null, origin)


# ---------------------------------------------------------------------------
# Edits
# ---------------------------------------------------------------------------

## Run a command result: a transaction is executed, an error is reported.
## Returns true when the buffers changed.
func execute(r: Variant, origin: String = "") -> bool:
	if r is EdError:
		status.emit("Refused: %s" % r.message, true)
		return false
	if r == null:
		return false
	var tx: EdTransaction = r
	if tx.is_empty():
		return false
	if tx.document.is_empty() and session != null:
		tx.document = session.entry_path
	tx.origin = origin
	tx.selection_before = selection.duplicate(true)
	var res = workspace.history.execute(tx)
	if res is EdError:
		status.emit("Refused: %s" % res.message, true)
		return false
	status.emit(tx.label, false)
	return true


func undo() -> void:
	var r = workspace.history.undo()
	if r is EdError:
		status.emit("Undo failed: %s" % r.message, true)
	elif r != null:
		_restore_selection(r["entry"]["inverse"][-1])
		status.emit("Undo " + r["entry"]["forward"][-1].label, false)


func redo() -> void:
	var r = workspace.history.redo()
	if r is EdError:
		status.emit("Redo failed: %s" % r.message, true)
	elif r != null:
		_restore_selection(r["entry"]["forward"][-1])
		status.emit("Redo " + r["entry"]["forward"][-1].label, false)


func _restore_selection(tx: EdTransaction) -> void:
	if tx.selection_after != null and session != null and tx.document == session.entry_path:
		selection = tx.selection_after.duplicate(true)
		selection_changed.emit("history")


func _on_buffers_changed(paths: Array, cause: String, tx: EdTransaction) -> void:
	if cause == "execute" and tx != null and tx.selection_after != null and session != null and tx.document == session.entry_path:
		selection = tx.selection_after.duplicate(true)
	buffers_changed.emit(paths, cause, tx)
	if cause == "execute" and tx != null and tx.selection_after != null:
		selection_changed.emit("history")


# ---------------------------------------------------------------------------
# Saving and external changes
# ---------------------------------------------------------------------------

## The files the active document saves: its entry and the stylesheets it
## references.
func document_files() -> Array:
	if session == null:
		return []
	var out := [session.entry_path]
	out.append_array(session.style_paths())
	return out


## Save `paths` (only the changed ones). Returns the number saved; reports
## every refusal. `force` overwrites files changed on disk.
func save(paths: Array, force: bool = false) -> int:
	var saved := 0
	var refused: Array = []
	for p in paths:
		if not workspace.is_dirty(p):
			continue
		var r = store.save(p, workspace.buffer(p), workspace.revision(p), force)
		if r is EdError:
			refused.append("%s (%s)" % [p, r.message])
			continue
		workspace.mark_saved(p, r)
		saved += 1
	if not refused.is_empty():
		status.emit("Not saved: " + "; ".join(refused), true)
	elif saved > 0:
		status.emit("Saved %d file%s." % [saved, "" if saved == 1 else "s"], false)
	else:
		status.emit("Nothing to save.", false)
	return saved


## Compare every open file with disk. Clean files that changed on disk are
## reloaded; changed files that also changed on disk are reported.
## Returns {reloaded: Array, conflicts: Array}.
func check_external_changes() -> Dictionary:
	var out := {"reloaded": [], "conflicts": []}
	if store == null:
		return out
	for p in workspace.buffers.keys():
		var rev := store.revision(p)
		if EdProjectStore.same_revision(rev, workspace.revision(p)):
			continue
		if workspace.is_dirty(p):
			out["conflicts"].append(p)
			continue
		if not rev["exists"]:
			continue
		var r = store.read(p)
		if r is EdError:
			continue
		workspace.set_buffer(p, r["buffer"], r["revision"], "reload")
		out["reloaded"].append(p)
	if not out["reloaded"].is_empty():
		status.emit("Reloaded from disk: " + ", ".join(out["reloaded"]), false)
	if not out["conflicts"].is_empty():
		status.emit("Changed on disk and in the editor: %s. Save overwrites only after confirmation." % ", ".join(out["conflicts"]), true)
	return out
