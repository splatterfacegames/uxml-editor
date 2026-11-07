class_name EdEditorState
extends RefCounted
## The application state every view reads: the project, the workspace with
## its one undo history, the open documents (tabs), the active document,
## the selection, the recovery journal and the editor refusals.
##
## Views never change buffers directly. They make transactions and pass
## them to execute(), so every edit, from any view, is one undo step and
## every view refreshes from the same buffers_changed signal.
##
## One history for all tabs (docs/adr/0008-tabs-and-history.md): undo and
## redo take the newest step of the project, and the editor shows the tab
## of that step.

signal project_opened
## The active document changed ("" when the last tab closed).
signal document_opened(path: String)
signal tabs_changed
## The selection changed. `origin` names the view that changed it.
signal selection_changed(origin: String)
signal buffers_changed(paths: Array, cause: String, tx: EdTransaction)
signal status(message: String, is_error: bool)
## The recovery journal of the project holds unsaved edits of the last
## session. `info`: {files: {path: {...}}, conflicts: Array, truncated}.
## Call recover() or discard_recovery().
signal recovery_found(info: Dictionary)
## Files that changed on disk and also have unsaved edits.
signal external_conflicts(paths: Array)
## A refused edit (for the diagnostics list).
signal refused(entry: Dictionary)

## Directory of the recovery journals (one subdirectory per project). The
## test runner points the default at a test directory.
static var default_recovery_base := "user://recovery"
var recovery_base: String = default_recovery_base
var store: EdProjectStore = null
var workspace: EdWorkspace = null
var files: Array = []
var session: EdDocumentSession = null
## Array of EdLocator dictionaries for the active document.
var selection: Array = []
## Entry paths of the open UXML documents, in tab order.
var tabs: Array = []
var journal: EdRecoveryJournal = null
## The recovery that waits for a decision ({} when none).
var pending_recovery: Dictionary = {}
## The last refused edits, newest last: {message, file, offset}.
var refusals: Array = []
## path -> sha256 of a disk version the user chose to keep the editor text
## over (not asked again for that version).
var kept_over_disk: Dictionary = {}
## path -> selection of each tab that is not active.
var _tab_selection: Dictionary = {}

const MAX_REFUSALS := 20


func _init() -> void:
	_new_workspace()


func _new_workspace() -> void:
	workspace = EdWorkspace.new()
	workspace.buffers_changed.connect(_on_buffers_changed)


func has_project() -> bool:
	return store != null


func open_project(dir: String) -> bool:
	var probe := DirAccess.open(dir)
	if probe != null:
		dir = probe.get_current_dir()
	var s := EdProjectStore.new(dir)
	if not s.is_valid():
		status.emit("%s is not a directory." % dir, true)
		return false
	close_project()
	store = s
	_new_workspace()
	session = null
	selection = []
	tabs = []
	_tab_selection.clear()
	refusals.clear()
	kept_over_disk.clear()
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
	tabs_changed.emit()
	var uxml := workspace.paths_with_extension(".uxml")
	status.emit("Opened %s: %d UXML and %d USS files%s." % [dir, uxml.size(), files.size() - uxml.size(),
		"" if failed == 0 else ", %d unreadable" % failed], failed > 0)
	_open_journal()
	return true


## Close the journal of the current project: delete it when no file has
## unsaved edits, keep it otherwise (the next start offers recovery).
func close_project() -> void:
	if journal != null:
		if workspace.dirty_paths().is_empty() and pending_recovery.is_empty():
			journal.discard()
		else:
			journal.close()
	journal = null
	pending_recovery = {}


# ---------------------------------------------------------------------------
# Recovery (docs/adr/0005-recovery.md)
# ---------------------------------------------------------------------------

func _open_journal() -> void:
	var base := ProjectSettings.globalize_path(recovery_base) if recovery_base.begins_with("user://") or recovery_base.begins_with("res://") else recovery_base
	journal = EdRecoveryJournal.new(EdRecoveryJournal.dir_for(base, store.root), store.root)
	var info := EdRecoveryJournal.read(journal.dir)
	if not info["ok"]:
		# A corrupt chain is not replayed. Keep the file for inspection.
		DirAccess.rename_absolute(journal.file_path(), journal.file_path() + ".corrupt")
		status.emit("The recovery journal is damaged (%s) and was not used." % info["error"], true)
		_start_journal()
		return
	# A file whose journaled text is the disk text has nothing to recover
	# (a kill after the save of the file, before its `clean` record).
	for p in info["files"].keys():
		var r = store.read(p)
		if r is EdError or r["buffer"].text != info["files"][p]["text"]:
			continue
		info["files"].erase(p)
	if info["files"].is_empty():
		_start_journal()
		return
	# The external-change check before the replay: a file whose disk bytes
	# differ from the base of the journal is a conflict. The recovered text
	# keeps the old revision, so a save asks before an overwrite.
	var conflicts: Array = []
	for p in info["files"]:
		var rev := store.revision(p)
		if not EdProjectStore.same_revision(rev, info["files"][p]["revision"]):
			conflicts.append(p)
	info["conflicts"] = conflicts
	pending_recovery = info
	recovery_found.emit(info)


func _start_journal() -> void:
	var err = journal.start()
	if err is EdError:
		status.emit(err.message, true)


## Apply the pending recovery: every journaled file gets its unsaved text.
## Returns the recovered paths.
func recover() -> Array:
	if pending_recovery.is_empty():
		return []
	var info := pending_recovery
	pending_recovery = {}
	var out: Array = []
	for p in info["files"]:
		var f: Dictionary = info["files"][p]
		if not workspace.has(p):
			if not files.has(p):
				files.append(p)
				files.sort()
		workspace.restore(p, f["text"], f["base_text"], f["bom"], f["revision"])
		out.append(p)
	out.sort()
	_start_journal()
	for p in out:
		journal.record(p, workspace.text(p), workspace.is_dirty(p), workspace.base[p])
	var conflicts: Array = info.get("conflicts", [])
	status.emit("Recovered unsaved edits of %s.%s" % [", ".join(out),
		"" if conflicts.is_empty() else " Changed on disk since: %s; a save asks before an overwrite." % ", ".join(conflicts)], not conflicts.is_empty())
	return out


## Drop the pending recovery and start a new journal.
func discard_recovery() -> void:
	if pending_recovery.is_empty():
		return
	pending_recovery = {}
	_start_journal()
	status.emit("Discarded the unsaved edits of the last session.", false)


# ---------------------------------------------------------------------------
# Documents and tabs
# ---------------------------------------------------------------------------

## Open `rel` in a tab (or show its tab) and make it the active document.
func open_document(rel: String) -> void:
	if not workspace.has(rel) or not rel.to_lower().ends_with(".uxml"):
		return
	if session != null and session.entry_path == rel:
		return
	if session != null:
		_tab_selection[session.entry_path] = selection.duplicate(true)
	if not tabs.has(rel):
		tabs.append(rel)
	session = EdDocumentSession.new(workspace, rel)
	selection = _tab_selection.get(rel, [])
	_tab_selection.erase(rel)
	workspace.history.break_coalescing()
	tabs_changed.emit()
	document_opened.emit(rel)
	selection_changed.emit("open")


## Close the tab of `rel`. Unsaved edits stay in the workspace (the
## project list marks the file; Save All saves it).
func close_document(rel: String) -> void:
	var i := tabs.find(rel)
	if i < 0:
		return
	tabs.remove_at(i)
	_tab_selection.erase(rel)
	if session != null and session.entry_path == rel:
		session = null
		selection = []
		if not tabs.is_empty():
			open_document(tabs[mini(i, tabs.size() - 1)])
			return
		document_opened.emit("")
		selection_changed.emit("open")
	tabs_changed.emit()


# ---------------------------------------------------------------------------
# Selection
# ---------------------------------------------------------------------------

func selected_node() -> EdUxmlNode:
	if session == null or selection.is_empty():
		return null
	return session.resolve(selection[0])


## Every selected element that still resolves, primary first.
func selected_nodes() -> Array:
	var out: Array = []
	if session == null:
		return out
	for loc in selection:
		var n := session.resolve(loc)
		if n != null and not out.has(n):
			out.append(n)
	return out


func select_node(node: EdUxmlNode, origin: String) -> void:
	select_nodes([] if node == null else [node], origin)


## Select `nodes`; the first one is the primary selection.
func select_nodes(nodes: Array, origin: String) -> void:
	var next: Array = []
	for n in nodes:
		if n != null:
			next.append(EdLocator.create(n))
	if next == selection:
		return
	selection = next
	selection_changed.emit(origin)


## Add `node` to the selection, or remove it when it is selected.
func toggle_node(node: EdUxmlNode, origin: String) -> void:
	if node == null:
		return
	var nodes := selected_nodes()
	if nodes.has(node):
		nodes.erase(node)
	else:
		nodes.append(node)
	select_nodes(nodes, origin)


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
		_refuse(r.message)
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
		_refuse(res.message)
		return false
	status.emit(tx.label, false)
	return true


func _refuse(message: String) -> void:
	status.emit("Refused: %s" % message, true)
	var n := selected_node()
	var entry := {"message": message, "file": session.entry_path if session != null else "",
		"offset": n.open_start if n != null else -1, "end": n.open_end if n != null else -1}
	refusals.append(entry)
	if refusals.size() > MAX_REFUSALS:
		refusals.remove_at(0)
	refused.emit(entry)


func undo() -> void:
	var r = workspace.history.undo()
	if r is EdError:
		status.emit("Undo failed: %s" % r.message, true)
	elif r != null:
		_show_document_of(r["entry"]["forward"][-1])
		_restore_selection(r["entry"]["inverse"][-1])
		status.emit("Undo " + r["entry"]["forward"][-1].label, false)


func redo() -> void:
	var r = workspace.history.redo()
	if r is EdError:
		status.emit("Redo failed: %s" % r.message, true)
	elif r != null:
		_show_document_of(r["entry"]["forward"][-1])
		_restore_selection(r["entry"]["forward"][-1])
		status.emit("Redo " + r["entry"]["forward"][-1].label, false)


## One history for all tabs: an undo or redo of a step of another document
## shows the tab of that document.
func _show_document_of(tx: EdTransaction) -> void:
	if tx.document.is_empty() or (session != null and session.entry_path == tx.document):
		return
	open_document(tx.document)


func _restore_selection(tx: EdTransaction) -> void:
	if tx.selection_after != null and session != null and tx.document == session.entry_path:
		selection = tx.selection_after.duplicate(true)
		selection_changed.emit("history")


func _on_buffers_changed(paths: Array, cause: String, tx: EdTransaction) -> void:
	if journal != null and journal.is_open():
		for p in paths:
			if workspace.has(p):
				journal.record(p, workspace.text(p), workspace.is_dirty(p), workspace.base[p])
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


## The files of every open tab (entries and their stylesheets), no
## duplicates, tab order.
func open_files() -> Array:
	var out: Array = []
	for t in tabs:
		var s := EdDocumentSession.new(workspace, t)
		for p in [t] + s.style_paths():
			if not out.has(p):
				out.append(p)
	return out


## Save `paths` (only the changed ones). Returns the number saved; reports
## every refusal. `force` overwrites files changed on disk. The journal
## records each saved file as clean after its replacement.
func save(paths: Array, force: bool = false) -> int:
	var saved := 0
	var refused_paths: Array = []
	for p in paths:
		if not workspace.is_dirty(p):
			continue
		var r = store.save(p, workspace.buffer(p), workspace.revision(p), force)
		if r is EdError:
			refused_paths.append("%s (%s)" % [p, r.message])
			continue
		workspace.mark_saved(p, r)
		kept_over_disk.erase(p)
		saved += 1
	if not refused_paths.is_empty():
		status.emit("Not saved: " + "; ".join(refused_paths), true)
	elif saved > 0:
		status.emit("Saved %d file%s." % [saved, "" if saved == 1 else "s"], false)
	else:
		status.emit("Nothing to save.", false)
	return saved


## Compare every open file with disk. Clean files that changed on disk are
## reloaded; changed files that also changed on disk are conflicts
## (external_conflicts, once per disk version). `quick`: only files whose
## size or time changed are read (the timer check).
## Returns {reloaded: Array, conflicts: Array}.
func check_external_changes(quick: bool = false) -> Dictionary:
	var out := {"reloaded": [], "conflicts": []}
	if store == null:
		return out
	for p in workspace.buffers.keys():
		if quick and not store.may_differ(p, workspace.revision(p)):
			continue
		var rev := store.revision(p)
		if EdProjectStore.same_revision(rev, workspace.revision(p)):
			continue
		if workspace.is_dirty(p):
			if kept_over_disk.get(p, "") != rev["sha256"]:
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
		status.emit("Changed on disk and in the editor: %s." % ", ".join(out["conflicts"]), true)
		external_conflicts.emit(out["conflicts"])
	return out


## Conflict decision: replace the editor text of `path` with the disk
## file. The unsaved edits of the file are gone (the history drops the
## steps of the file).
func reload_from_disk(path: String) -> bool:
	var r = store.read(path)
	if r is EdError:
		status.emit(r.message, true)
		return false
	workspace.set_buffer(path, r["buffer"], r["revision"], "reload")
	kept_over_disk.erase(path)
	status.emit("Reloaded %s from disk; the unsaved edits are gone." % path, false)
	return true


## Conflict decision: keep the editor text of `path`. The next save asks
## before an overwrite; the same disk version is not reported again.
func keep_editor_text(path: String) -> void:
	kept_over_disk[path] = store.revision(path).get("sha256", "")
	status.emit("Kept the editor text of %s. A save asks before an overwrite." % path, false)
