class_name EdMain
extends Control
## The editor window: the godot-uxml shell document and the views mounted in
## it. Composition root; the views share one EdEditorState.
##
## Command-line options (after `--`):
##   --project=<dir>      open a project directory
##   --open=<path>        open a UXML document (project-relative)
##   --select=<name>      select the element with this `name` attribute
##   --theme=<auto|runtime|editor-dark|editor-light>
##   --preset=<index>     screen size preset
##   --source=<path>      show this file in the source view
##   --screenshot=<png>   save a screenshot after the first renders, then quit
##   --script-edit=<a=b>  demo: set attribute a to b on the selection first
##   --gdscript           use the GDScript path of godot-uxml (no native core)
##   --demo=<name>        stage a documentation state before the screenshot
##                        (EdDemo: palette, drag-canvas, drag-hierarchy,
##                        resize, multi, preview)

const SHELL := "res://src/app/ui/editor_shell.uxml"
const PRESETS := [
	["1920 × 1080", Vector2i(1920, 1080)], ["1600 × 900", Vector2i(1600, 900)],
	["1280 × 720", Vector2i(1280, 720)], ["1024 × 768", Vector2i(1024, 768)],
	["800 × 600", Vector2i(800, 600)], ["390 × 844 (phone)", Vector2i(390, 844)],
	["844 × 390 (phone landscape)", Vector2i(844, 390)],
]
const THEMES := [["Auto theme", "auto"], ["Runtime theme", "runtime"], ["Editor dark", "editor-dark"], ["Editor light", "editor-light"]]
## Edit menu: [label, command]. The shortcuts work in the canvas and the
## hierarchy (not while a text field has focus).
const EDIT_MENU := [
	["Cut   Ctrl+X", "cut"], ["Copy   Ctrl+C", "copy"], ["Paste   Ctrl+V", "paste"],
	["Duplicate   Ctrl+D", "duplicate"], ["Delete   Del", "delete"],
	["Wrap in VisualElement   Ctrl+G", "wrap"], ["Unwrap   Ctrl+Shift+G", "unwrap"],
	["Move up   Alt+Up", "move-up"], ["Move down   Alt+Down", "move-down"],
	["Rename element type   F2", "rename"],
]

var state := EdEditorState.new()
var shell: UxmlDocument
var canvas: EdCanvasView
var source: EdSourceView
var inspector: EdInspectorView
var palette: EdPaletteView
var drag: EdDragController
var layout: EdLayoutController
var source_path := ""
var _render_queued := false
## The queued render may be a patch (only the entry buffer changed).
var _render_patch := false
var _syncing := false
var _diagnostics: Array = []
var _files_shown: Array = []
var _dialog: FileDialog
var _confirm: ConfirmationDialog
var _args := {}
var _preset := 2
## Last data given to each shell list, menu, label and class, so an update
## with the same data costs nothing (a godot-uxml list or text update
## restyles and lays out the window).
var _shown := {}
## The hierarchy changed since the last selection sync.
var _tree_dirty := true
var _tree_selected: Array = []
## Hierarchy item id -> visible row index; empty when stale (a new tree
## source, or an item opened or closed).
var _tree_rows: Dictionary = {}


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--gdscript") or OS.has_feature("web"):
		use_gdscript_path()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	get_window().title = "UXML Editor"
	get_window().min_size = Vector2i(1000, 600)
	shell = UxmlDocument.new()
	shell.auto_load = false
	shell.editor_theme = "always"
	shell.editor_skin = "dark"
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	shell.load_document(SHELL, "res://src/app/ui")
	for d in shell.diagnostics:
		push_warning("editor shell: " + UxmlDiagnostic.format(d))

	canvas = EdCanvasView.new()
	_mount(canvas, "canvas-host")
	source = EdSourceView.new()
	_mount(source, "source-host")
	inspector = EdInspectorView.new()
	_mount(inspector, "inspector-host")
	source.set_workspace(state.workspace)

	shell.button_pressed.connect(_on_button)
	shell.selection_changed.connect(_on_list_selection)
	shell.items_chosen.connect(_on_items_chosen)
	shell.item_expanded_changed.connect(func(_list, _id, _on): _tree_rows.clear())
	shell.value_changed.connect(_on_shell_value)
	shell.set_menu_items("edit-menu", EDIT_MENU.map(func(e): return e[0]), func(i, _t): run_command(EDIT_MENU[i][1]))
	shell.set_menu_items("grid-menu", EdLayoutController.GRIDS.map(func(g): return "No grid" if g <= 1 else "Grid %d px" % g), _on_grid)
	shell.set_menu_items("preset-menu", PRESETS.map(func(p): return p[0]), _on_preset)
	shell.set_menu_items("theme-menu", THEMES.map(func(t): return t[0]), _on_theme)
	canvas.picked.connect(_on_canvas_picked)
	canvas.view_changed.connect(_update_zoom_label)
	layout = EdLayoutController.new(state, canvas)
	canvas.gesture_started.connect(layout.begin)
	canvas.gesture_moved.connect(layout.update)
	canvas.gesture_finished.connect(layout.finish)
	canvas.nudged.connect(layout.nudge)
	palette = EdPaletteView.new(shell)
	palette.refresh()
	drag = EdDragController.new()
	drag.shell = shell
	drag.canvas = canvas
	drag.state = state
	drag.palette = palette
	add_child(drag)
	drag.dropped.connect(_on_dropped)
	source.edited.connect(func(tx): state.execute(tx, "source"))
	source.caret_moved_to.connect(_on_source_caret)
	source.undo_requested.connect(_undo)
	source.redo_requested.connect(_redo)
	inspector.command.connect(func(r, origin): state.execute(r, origin))
	state.project_opened.connect(_on_project_opened)
	state.document_opened.connect(_on_document_opened)
	state.selection_changed.connect(_on_selection_changed)
	state.buffers_changed.connect(_on_buffers_changed)
	state.status.connect(_on_status)
	state.workspace.history.history_changed.connect(_update_history_label)
	canvas.host.rendered.connect(_on_rendered)

	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.title = "Open a project directory"
	_dialog.dir_selected.connect(func(dir): state.open_project(dir))
	add_child(_dialog)
	_confirm = ConfirmationDialog.new()
	add_child(_confirm)

	_set_preset(_preset)
	_parse_args()
	_update_history_label()
	inspector.show_selection(null, null, null)
	get_window().focus_entered.connect(_on_window_focus)


## Disable the native core of godot-uxml (the path of the web export and
## of platforms without the DLL). Before the first document loads.
static func use_gdscript_path() -> void:
	UxmlParser.use_native = false
	UssParser.use_native = false
	UssCascade.use_native = false
	UxmlDocument.use_native_layout = false


func _mount(c: Control, host_name: String) -> void:
	var host := shell.get_element(host_name)
	if host == null:
		push_error("editor shell has no element named " + host_name)
		add_child(c)
		return
	host.clip_contents = true
	host.add_child(c)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


# ---------------------------------------------------------------------------
# Command line
# ---------------------------------------------------------------------------

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		var eq := a.find("=")
		if a.begins_with("--") and eq > 2:
			_args[a.substr(2, eq - 2)] = a.substr(eq + 1)
		elif a.begins_with("--"):
			_args[a.substr(2)] = ""
	if _args.has("preset"):
		_set_preset(int(_args["preset"]))
	if _args.has("theme"):
		for i in THEMES.size():
			if THEMES[i][1] == _args["theme"]:
				_on_theme(i, THEMES[i][0])
	if _args.has("project"):
		state.open_project(_args["project"])
		if _args.has("open"):
			state.open_document(_args["open"])
		if _args.has("select") and state.session != null:
			for n in state.session.root().walk():
				if n.get_attribute("name") == _args["select"]:
					state.select_node(n, "args")
					break
		if _args.has("script-edit") and state.selected_node() != null:
			var kv: PackedStringArray = String(_args["script-edit"]).split("=", true, 1)
			if kv.size() == 2:
				state.execute(EdUxmlCommands.set_attribute(state.session, state.selection[0], kv[0], kv[1]), "args")
		if _args.has("source"):
			_show_source(_args["source"])
	if _args.has("screenshot"):
		_screenshot.call_deferred(String(_args["screenshot"]))


func _screenshot(path: String) -> void:
	for i in 20:
		await get_tree().process_frame
	if _args.has("demo"):
		await EdDemo.stage(self, String(_args["demo"]))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_path := path if path.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var err := img.save_png(abs_path)
	print("screenshot %s: %s" % [abs_path, error_string(err)])
	if _args.has("quit") or true:
		get_tree().quit()


# ---------------------------------------------------------------------------
# Toolbar
# ---------------------------------------------------------------------------

func _on_button(element_name: String) -> void:
	match element_name:
		"open-button":
			_dialog.popup_centered_ratio(0.6)
		"save-button":
			_save(state.document_files() if state.session != null else [source_path])
		"save-all-button":
			_save(state.workspace.dirty_paths())
		"undo-button":
			_undo()
		"redo-button":
			_redo()
		"zoom-in-button":
			canvas.set_zoom(canvas.zoom * 1.25)
		"zoom-out-button":
			canvas.set_zoom(canvas.zoom / 1.25)
		"fit-button":
			canvas.fit()


func _undo() -> void:
	source.flush()
	state.undo()


func _redo() -> void:
	source.flush()
	state.redo()


func _save(paths: Array) -> void:
	source.flush()
	if not state.has_project():
		return
	var conflicts: Array = []
	for p in paths:
		if state.workspace.is_dirty(p) and not EdProjectStore.same_revision(state.store.revision(p), state.workspace.revision(p)):
			conflicts.append(p)
	state.save(paths.filter(func(p): return not conflicts.has(p)))
	if not conflicts.is_empty():
		_confirm.dialog_text = "These files changed on disk after they were opened:\n\n%s\n\nOverwrite them with the editor's text?" % "\n".join(conflicts)
		_confirm.ok_button_text = "Overwrite"
		for c in _confirm.confirmed.get_connections():
			_confirm.confirmed.disconnect(c["callable"])
		_confirm.confirmed.connect(func(): state.save(conflicts, true), CONNECT_ONE_SHOT)
		_confirm.popup_centered()


func _on_preset(index: int, _text: String) -> void:
	_set_preset(index)


func _set_preset(index: int) -> void:
	_preset = clampi(index, 0, PRESETS.size() - 1)
	canvas.set_screen_size(PRESETS[_preset][1])
	_set_menu_text("preset-menu", PRESETS[_preset][0])
	_queue_render()


func _on_theme(index: int, text: String) -> void:
	canvas.host.theme_mode = THEMES[index][1]
	_set_menu_text("theme-menu", text)
	_queue_render()


## True when `data` differs from the last data shown in `key` (and
## records it).
func _changed(key: String, data: Variant) -> bool:
	if _shown.has(key) and _shown[key] == data:
		return false
	_shown[key] = data.duplicate(true) if data is Array or data is Dictionary else data
	return true


func _shell_class(element_name: String, cls: String) -> void:
	if _changed("class:" + element_name, cls):
		shell.set_class(element_name, cls)


func _set_menu_text(menu: String, text: String) -> void:
	var el := shell.get_element_model(menu)
	if el != null:
		el.set_attribute("text", text)


func _update_zoom_label() -> void:
	EdUi.set_label(shell, "zoom-label", "%d%%" % int(round(canvas.zoom * 100)))


func _update_history_label() -> void:
	var h := state.workspace.history
	var s := ""
	if h.can_undo():
		s += "Undo: %s" % h.undo_label()
	if h.can_redo():
		s += ("   " if not s.is_empty() else "") + "Redo: %s" % h.redo_label()
	EdUi.set_label(shell, "history-label", s)


func _on_status(message: String, is_error: bool) -> void:
	EdUi.set_label(shell, "status-label", message)
	_shell_class("status-label", "status-label status-message" + (" error" if is_error else ""))
	if is_error:
		push_warning(message)


func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed:
		return
	if _structure_shortcut(k):
		get_viewport().set_input_as_handled()
		return
	if not k.is_command_or_control_pressed():
		return
	match k.keycode:
		KEY_Z:
			_redo() if k.shift_pressed else _undo()
		KEY_Y:
			_redo()
		KEY_S:
			_save(state.workspace.dirty_paths() if k.shift_pressed else (state.document_files() if state.session != null else [source_path]))
		KEY_O:
			_dialog.popup_centered_ratio(0.6)
		KEY_P:
			set_preview(not canvas.preview)
		KEY_EQUAL, KEY_PLUS:
			canvas.set_zoom(canvas.zoom * 1.25)
		KEY_MINUS:
			canvas.set_zoom(canvas.zoom / 1.25)
		_:
			return
	get_viewport().set_input_as_handled()


func _input(ev: InputEvent) -> void:
	if canvas.preview:
		if ev is InputEventMouseButton and ev.pressed and not canvas.get_global_rect().has_point(ev.global_position):
			canvas.keys_to_document = false
		elif ev is InputEventKey and canvas.keys_to_document and not EdCanvasView.is_editor_key(ev):
			canvas.forward_input(ev)
			get_viewport().set_input_as_handled()
			return
	if drag != null and drag.handle_input(ev):
		get_viewport().set_input_as_handled()
		return
	# Alt+Up and Alt+Down move the selection before a list takes them as
	# plain arrow keys.
	var k := ev as InputEventKey
	if k != null and k.pressed and k.alt_pressed and not k.is_command_or_control_pressed() and (k.keycode == KEY_UP or k.keycode == KEY_DOWN):
		if _structure_shortcut(k):
			get_viewport().set_input_as_handled()


## Structure shortcuts. They apply when no text field has focus, so a
## field keeps Ctrl+C, Delete and the others.
func _structure_shortcut(k: InputEventKey) -> bool:
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit or f is TextEdit or canvas.preview:
		return false
	var ctrl := k.is_command_or_control_pressed()
	var cmd := ""
	if ctrl and not k.alt_pressed:
		match k.keycode:
			KEY_X:
				cmd = "cut"
			KEY_C:
				cmd = "copy"
			KEY_V:
				cmd = "paste"
			KEY_D:
				cmd = "duplicate"
			KEY_G:
				cmd = "unwrap" if k.shift_pressed else "wrap"
	elif k.alt_pressed and not ctrl:
		if k.keycode == KEY_UP:
			cmd = "move-up"
		elif k.keycode == KEY_DOWN:
			cmd = "move-down"
	elif not ctrl and not k.alt_pressed:
		if k.keycode == KEY_DELETE:
			cmd = "delete"
		elif k.keycode == KEY_F2:
			cmd = "rename"
	if cmd.is_empty():
		return false
	run_command(cmd)
	return true


# ---------------------------------------------------------------------------
# Structure commands
# ---------------------------------------------------------------------------

## Run an Edit menu command on the selection. Returns true when the
## buffers changed (or, for copy, when the clipboard did).
func run_command(cmd: String) -> bool:
	source.flush()
	if state.session == null:
		return false
	var nodes := EdStructureCommands.top_level(state.selected_nodes())
	var locs: Array = nodes.map(func(n): return EdLocator.create(n))
	var s := state.session
	match cmd:
		"copy", "cut":
			if nodes.is_empty():
				return _refuse("Select an element to %s." % cmd)
			var p = EdClipboard.copy(s, locs)
			if p is EdError:
				return state.execute(p)
			EdClipboard.copy_to_system(p)
			if cmd == "copy":
				state.status.emit("Copied %d element%s." % [nodes.size(), "" if nodes.size() == 1 else "s"], false)
				return true
			var rm = EdStructureCommands.remove_elements(s, locs)
			if rm is EdTransaction:
				rm.label = "Cut %s" % nodes[0].local if nodes.size() == 1 else "Cut %d elements" % nodes.size()
			return state.execute(rm, "edit")
		"paste":
			var text := EdClipboard.system_text()
			var payload = null
			if text.is_empty() and not EdClipboard.last_payload.is_empty():
				payload = EdClipboard.last_payload.duplicate(true)
			else:
				payload = EdClipboard.payload_from_text(text)
			if payload is EdError:
				return state.execute(payload)
			var ip := EdStructureCommands.insertion_point(s, state.selected_node())
			return state.execute(EdClipboard.paste(s, EdLocator.create(ip["parent"]), ip["index"], payload), "edit")
		"duplicate":
			if nodes.is_empty():
				return _refuse("Select an element to duplicate.")
			return state.execute(EdClipboard.duplicate_elements(s, locs), "edit")
		"delete":
			if nodes.is_empty():
				return false
			return state.execute(EdStructureCommands.remove_elements(s, locs), "edit")
		"wrap":
			if nodes.is_empty():
				return _refuse("Select the elements to wrap.")
			return state.execute(EdStructureCommands.wrap_in(s, locs), "edit")
		"unwrap":
			if nodes.size() != 1:
				return _refuse("Select one element to unwrap.")
			return state.execute(EdStructureCommands.unwrap_element(s, locs[0]), "edit")
		"move-up", "move-down":
			if nodes.is_empty() or nodes[0].parent == null:
				return false
			var parent: EdUxmlNode = nodes[0].parent
			var first: int = nodes[0].index_in_parent
			var last: int = nodes[-1].index_in_parent
			if (cmd == "move-up" and first == 0) or (cmd == "move-down" and last + 1 >= parent.children.size()):
				return false
			var to := first - 1 if cmd == "move-up" else last + 2
			return state.execute(EdStructureCommands.move_to(s, locs, EdLocator.create(parent), to), "edit")
		"rename":
			inspector.focus_type_field()
			return false
	return false


func _refuse(message: String) -> bool:
	state.status.emit(message, true)
	return false


## Insert a palette entry at the selection.
func insert_entry(entry: Dictionary) -> bool:
	if state.session == null or entry.is_empty():
		return false
	var ip := EdStructureCommands.insertion_point(state.session, state.selected_node())
	return state.execute(EdStructureCommands.insert_new_element(state.session, EdLocator.create(ip["parent"]),
		ip["index"], entry["name"], entry["uri"], entry["attributes"]), "palette")


func _on_dropped(payload: Dictionary, target: Dictionary) -> void:
	source.flush()
	if state.session == null:
		return
	var parent: EdUxmlNode = target["parent"]
	var where: String = target["where"]
	if payload["kind"] == "palette":
		var e: Dictionary = payload["entry"]
		state.execute(EdStructureCommands.insert_new_element(state.session, EdLocator.create(parent), target["index"],
			e["name"], e["uri"], e["attributes"]), where)
	else:
		state.execute(EdStructureCommands.move_to(state.session, payload["locs"], EdLocator.create(parent), target["index"]), where)


func _on_items_chosen(list_name: String, indices: Array) -> void:
	if list_name == "palette-tree" and not indices.is_empty():
		insert_entry(palette.entry_at(indices[0]))


func _on_shell_value(element_name: String, value: Variant) -> void:
	match element_name:
		"palette-search":
			palette.set_query(String(value))
		"snap-toggle":
			layout.snap_enabled = bool(value)
		"preview-toggle":
			set_preview(bool(value))


func _on_grid(index: int, text: String) -> void:
	layout.grid = EdLayoutController.GRIDS[index]
	_set_menu_text("grid-menu", text)


## Preview mode: canvas input goes to the rendered document. Leaving it
## renders again, so runtime state (typed text, toggles) resets to the
## source.
func set_preview(on: bool) -> void:
	if canvas.preview == on:
		return
	canvas.set_preview(on)
	var t := shell.get_element_model("preview-toggle")
	if t != null and str(t.get_attribute("value")) != ("true" if on else "false"):
		t.set_attribute("value", "true" if on else "false")
	if on:
		canvas.grab_focus()
	else:
		_queue_render()
	_update_canvas_header()
	state.status.emit("Preview on: the document gets the mouse and keyboard." if on else "Preview off.", false)


func _update_canvas_header() -> void:
	var path := state.session.entry_path if state.session != null else ""
	shell.set_text("canvas-header", "Canvas" + ("" if path.is_empty() else " — " + path) + ("   ·   PREVIEW" if canvas.preview else ""))


func _on_canvas_picked(id: int, additive: bool) -> void:
	if state.session == null:
		return
	var t := state.session.tree()
	var n: EdUxmlNode = t.nodes[id] if id >= 0 and id < t.nodes.size() else null
	if additive:
		state.toggle_node(n, "canvas")
	else:
		state.select_node(n, "canvas")


func _on_window_focus() -> void:
	if state.has_project():
		state.check_external_changes()


# ---------------------------------------------------------------------------
# Project, documents, rendering
# ---------------------------------------------------------------------------

func _on_project_opened() -> void:
	source.set_workspace(state.workspace)
	state.workspace.history.history_changed.connect(_update_history_label)
	_update_history_label()
	_refresh_files()
	shell.set_text("document-label", state.store.root)
	var uxml := state.workspace.paths_with_extension(".uxml")
	if not uxml.is_empty() and not _args.has("open"):
		state.open_document(uxml[0])
	elif uxml.is_empty():
		_queue_render()


func _on_document_opened(path: String) -> void:
	_update_canvas_header()
	_show_source(path)
	_refresh_files()
	_queue_render()


func _show_source(path: String) -> void:
	source_path = path
	source.show_file(path)
	_refresh_source_menu()
	_mark_selection_in_source(false)


func _refresh_source_menu() -> void:
	var files := state.document_files()
	if not source_path.is_empty() and not files.has(source_path):
		files.append(source_path)
	if _changed("source-file-menu", files):
		shell.set_menu_items("source-file-menu", files, func(_i, t): _show_source(t))
	_set_menu_text("source-file-menu", source_path if not source_path.is_empty() else "(no file)")
	var b := state.workspace.buffer(source_path)
	var st := ""
	if b != null:
		st = ("modified" if state.workspace.is_dirty(source_path) else "saved") + "  ·  " + b.newline_style.to_upper() + ("  ·  BOM" if b.bom else "") + ("" if b.exact else "  ·  read only (inexact bytes)")
	EdUi.set_label(shell, "source-state", st)


## Queue a render at the end of the frame. `patch_ok`: the change may go
## to the live render as a patch (EdRenderHost.patch); any full request in
## the same frame wins.
func _queue_render(patch_ok: bool = false) -> void:
	if _render_queued:
		_render_patch = _render_patch and patch_ok
		return
	_render_queued = true
	_render_patch = patch_ok
	_render.call_deferred()


func _render() -> void:
	_render_queued = false
	if state.session == null or not state.has_project():
		_refresh_hierarchy()
		_refresh_diagnostics()
		return
	if _render_patch and canvas.host.patch(state.workspace, state.session.entry_path):
		return
	canvas.host.render(state.workspace, state.session.entry_path, state.store.root)


func _on_rendered() -> void:
	layout.rendered()
	# A patch changes `style` or `class` only; the hierarchy shows classes.
	if not canvas.host.last_was_patch or canvas.host.last_patch_attrs.has("class"):
		_refresh_hierarchy()
	_refresh_diagnostics()
	_on_selection_changed("render")


func _on_buffers_changed(paths: Array, _cause: String, tx: EdTransaction) -> void:
	_refresh_files()
	_refresh_source_menu()
	if paths.has(source_path) and (tx == null or tx.origin != "source" or not source.has_focus()):
		source.reload_from_buffer()
	elif paths.has(source_path):
		source.reload_from_buffer()
	_queue_render(state.session != null and paths.size() == 1 and paths[0] == state.session.entry_path and not canvas.preview)


func _refresh_files() -> void:
	var items: Array = []
	_files_shown = state.files.duplicate()
	for f in _files_shown:
		var mark := "● " if state.workspace.is_dirty(f) else "   "
		var active: bool = state.session != null and state.session.entry_path == f
		items.append("%s%s%s" % [mark, f, "  (open)" if active else ""])
	if not _changed("files-list", items):
		return
	_syncing = true
	shell.set_items_source("files-list", items)
	_syncing = false


func _refresh_hierarchy() -> void:
	var roots: Array = []
	if state.session != null and state.session.root() != null:
		roots = [_tree_item(state.session.root())]
	if not _changed("hierarchy-tree", roots):
		return
	_tree_dirty = true
	_tree_rows.clear()
	_syncing = true
	shell.set_tree_source("hierarchy-tree", roots)
	_syncing = false


func _tree_item(n: EdUxmlNode) -> Dictionary:
	var label := n.local
	var nm = n.get_attribute("name")
	if nm != null and not String(nm).is_empty():
		label += "  #" + String(nm)
	var cls = n.get_attribute("class")
	if cls != null and not String(cls).strip_edges().is_empty():
		label += "  ." + " .".join(String(cls).split(" ", false))
	if not n.well_formed:
		label += "  ⚠"
	if n.parent != null and not EdElementCatalog.is_known(n.local):
		label += "  (unknown)"
	return {"id": n.id, "data": label, "children": n.children.map(_tree_item)}


func _refresh_diagnostics() -> void:
	_diagnostics.clear()
	var files := state.document_files()
	for p in files:
		var b := state.workspace.buffer(p)
		if b == null:
			continue
		if not b.exact:
			_diagnostics.append({"file": p, "offset": 0, "text": "editor  %s  the file does not decode to its exact bytes; it is read only" % p})
		var problems: Array = state.workspace.uxml(p).problems if p.to_lower().ends_with(".uxml") else state.workspace.uss(p).problems
		for pr in problems:
			var lc := UxmlDiagnostic.line_col(b.text, pr["start"])
			_diagnostics.append({"file": p, "offset": pr["start"], "text": "editor  %s:%d:%d  %s" % [p, lc.x, lc.y, pr["message"]]})
	var root := state.store.root if state.has_project() else ""
	for d in canvas.host.diagnostics if state.session != null else []:
		var f := String(d.get("file", ""))
		var rel := f
		if not root.is_empty() and EdBufferResolver.key(f).begins_with(EdBufferResolver.key(root) + "/"):
			rel = f.substr(root.length() + 1)
		_diagnostics.append({"file": rel, "offset": int(d.get("offset", 0)), "text": "%s  %s:%d:%d  %s" % [d.get("kind", ""), rel.get_file(), d.get("line", 0), d.get("column", 0), d.get("message", "")]})
	var texts: Array = _diagnostics.map(func(d): return d["text"])
	if _changed("diagnostics-list", texts):
		_syncing = true
		shell.set_items_source("diagnostics-list", texts)
		_syncing = false
	EdUi.set_label(shell, "diagnostics-header", "Diagnostics (%d)" % _diagnostics.size() if not _diagnostics.is_empty() else "Diagnostics")


# ---------------------------------------------------------------------------
# Selection sync
# ---------------------------------------------------------------------------

func _on_list_selection(list_name: String, indices: Array) -> void:
	if _syncing or indices.is_empty():
		return
	match list_name:
		"files-list":
			var f: String = _files_shown[indices[0]]
			if f.to_lower().ends_with(".uxml"):
				state.open_document(f)
			else:
				_show_source(f)
		"hierarchy-tree":
			var t := state.session.tree() if state.session != null else null
			if t == null:
				return
			var nodes: Array = []
			for i in indices:
				var item := shell.get_tree_item("hierarchy-tree", i)
				if not item.is_empty() and int(item["id"]) < t.nodes.size():
					nodes.append(t.nodes[int(item["id"])])
			state.select_nodes(nodes, "hierarchy")
		"diagnostics-list":
			var d: Dictionary = _diagnostics[indices[0]]
			if state.workspace.has(d["file"]):
				if d["file"] != source_path:
					_show_source(d["file"])
				source.mark_range(d["offset"], d["offset"] + 1)


func _on_source_caret(offset: int) -> void:
	if state.session == null or source_path != state.session.entry_path or source.has_pending_edit():
		return
	var n := state.session.tree().element_at_offset(offset)
	if n != null:
		state.select_node(n, "source")


func _on_selection_changed(origin: String) -> void:
	var nodes := state.selected_nodes()
	var n: EdUxmlNode = nodes[0] if not nodes.is_empty() else null
	canvas.selected_ids = nodes.map(func(x): return x.id)
	if origin != "hierarchy":
		_select_in_tree(nodes)
	else:
		_tree_selected = nodes.map(func(x): return x.id)
	if origin != "source":
		_mark_selection_in_source(origin != "render")
	inspector.show_selection(state.session, n, canvas.host, nodes.size())


func _mark_selection_in_source(reveal: bool) -> void:
	var n := state.selected_node()
	if n == null or state.session == null or source_path != state.session.entry_path:
		source.clear_mark()
		return
	if source.has_focus():
		return
	source.mark_range(n.open_start, n.open_end, reveal)


func _select_in_tree(nodes: Array) -> void:
	var ids: Array = nodes.map(func(x): return x.id)
	if not _tree_dirty and ids == _tree_selected:
		return
	_tree_dirty = false
	_tree_selected = ids
	_syncing = true
	if nodes.is_empty():
		shell.set_selection("hierarchy-tree", [])
		_syncing = false
		return
	var want := {}
	for n in nodes:
		want[n.id] = true
		var a: EdUxmlNode = n.parent
		while a != null:
			shell.set_tree_item_expanded("hierarchy-tree", a.id, true)
			a = a.parent
	if _tree_rows.is_empty():
		var i := 0
		while true:
			var item := shell.get_tree_item("hierarchy-tree", i)
			if item.is_empty():
				break
			_tree_rows[int(item["id"])] = i
			i += 1
	# Primary first, as the canvas and the inspector show it.
	var found: Array = []
	for n in nodes:
		if _tree_rows.has(n.id) and not found.has(_tree_rows[n.id]):
			found.append(_tree_rows[n.id])
	shell.set_selection("hierarchy-tree", found)
	if not found.is_empty():
		shell.scroll_to_item("hierarchy-tree", found[0])
	_syncing = false
