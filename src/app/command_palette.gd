class_name EdCommandPalette
extends Control
## The command palette and the shortcut map, over the window (milestone 8).
##
## A godot-uxml document of its own (`ui/command_palette.uxml`), loaded at
## the first open and then changed in place: the search field filters the
## rows, the list shows them through an item template, and the texts of a
## row go through the `text` attribute of the model (a Label of a fixed size:
## no layout). The palette costs nothing while it is closed: the control is
## hidden and the document is not loaded until the first open.
##
## Mode "commands": every command of EdCommandRegistry, fuzzy search, Enter
## runs the chosen command. Mode "shortcuts": the current bindings of every
## command and the fixed keys of the views, by category; Enter on a command
## runs it.

signal command_chosen(id: String)
signal closed

const DOC := "res://src/app/ui/command_palette.uxml"

var registry: EdCommandRegistry
var doc: UxmlDocument
var mode := "commands"
var rows: Array = []
var index := 0
var query := ""
## Number of loads of the document (tests).
var loads := 0
var _loaded := false
var _syncing := false


func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_open() -> bool:
	return visible


## Open in `which` mode ("commands" or "shortcuts") with an empty search.
func open(which: String = "commands") -> void:
	_ensure_loaded()
	mode = which
	visible = true
	move_to_front()
	query = ""
	_syncing = true
	doc.set_field_value("cp-search", "")
	_syncing = false
	EdUi.set_label(doc, "cp-title", "Keyboard shortcuts" if mode == "shortcuts" else "Commands")
	_silent_placeholder("Type to search the shortcuts" if mode == "shortcuts" else "Type to search the commands")
	_refresh()
	var le := EdUi.line_edit(doc, "cp-search")
	if le != null:
		le.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	visible = false
	var le := doc.get_native("cp-search") if doc != null else null
	if le != null and le.has_focus():
		le.release_focus()
	closed.emit()


## Set the search text (as the user types it).
func set_query(text: String) -> void:
	query = text
	_refresh()


## Move the choice by `step` rows.
func move(step: int) -> void:
	if rows.is_empty():
		return
	index = clampi(index + step, 0, rows.size() - 1)
	_show_choice()


## Run the chosen row: emits command_chosen after the palette closes.
## Returns false when the row is not a command (a fixed key of the map).
func run_chosen() -> bool:
	if index < 0 or index >= rows.size():
		return false
	var id := String(rows[index].get("id", ""))
	if id.is_empty():
		return false
	close()
	command_chosen.emit(id)
	return true


## The texts of row `i` as shown: [category, name, keys].
func row_texts(i: int) -> Array:
	var r: Dictionary = rows[i]
	var keys: Array = (r.get("keys", []) as Array).map(func(k): return EdCommandRegistry.display(String(k)))
	return [String(r.get("category", "")), String(r.get("title", "")), ("  ·  " if mode == "shortcuts" else ", ").join(PackedStringArray(keys))]


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	loads += 1
	doc = UxmlDocument.new()
	doc.auto_load = false
	doc.editor_theme = "always"
	doc.editor_skin = "dark"
	doc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(doc)
	doc.load_document(DOC, "res://src/app/ui")
	for d in doc.diagnostics:
		push_warning("command palette: " + UxmlDiagnostic.format(d))
	doc.value_changed.connect(_on_value)
	EdUi.live_text(doc, "cp-search", _on_typed)
	doc.items_chosen.connect(_on_chosen)
	doc.selection_changed.connect(_on_selection)


func _refresh() -> void:
	if registry == null or doc == null:
		return
	rows = registry.shortcut_rows(query) if mode == "shortcuts" else registry.search(query)
	index = 0
	_syncing = true
	doc.set_items_source("cp-list", rows, _bind)
	_syncing = false
	var n := rows.size()
	EdUi.set_label(doc, "cp-count", "%d %s" % [n, ("binding" if mode == "shortcuts" else "command") + ("" if n == 1 else "s")])
	_show_choice()


func _bind(row: UxmlListRow, i: int) -> void:
	if i < 0 or i >= rows.size():
		return
	var t := row_texts(i)
	_row_text(row, "cp-category", t[0])
	_row_text(row, "cp-name", t[1])
	_row_text(row, "cp-keys", t[2])


static func _row_text(row: UxmlListRow, element_name: String, text: String) -> void:
	var el := row.get_element_model(element_name)
	if el != null:
		el.set_attribute("text", text if not text.is_empty() else " ")


func _show_choice() -> void:
	_syncing = true
	if rows.is_empty():
		doc.set_selection("cp-list", [])
	else:
		doc.set_selection("cp-list", [index])
		doc.scroll_to_item("cp-list", index)
	_syncing = false


func _silent_placeholder(text: String) -> void:
	var c := doc.get_native("cp-search") as LineEdit
	if c != null:
		c.placeholder_text = text
	EdUi.set_silent(doc, "cp-search", "placeholder-text", text)


func _on_typed(text: String) -> void:
	if not _syncing and text != query:
		set_query(text)


func _on_value(element_name: String, value: Variant) -> void:
	if element_name == "cp-search" and not _syncing and String(value) != query:
		set_query(String(value))


func _on_chosen(list_name: String, indices: Array) -> void:
	if list_name == "cp-list" and not indices.is_empty():
		index = int(indices[0])
		run_chosen()


func _on_selection(list_name: String, indices: Array) -> void:
	if list_name == "cp-list" and not _syncing and not indices.is_empty():
		index = int(indices[0])


func _input(ev: InputEvent) -> void:
	if not visible:
		return
	var k := ev as InputEventKey
	if k != null and k.pressed:
		match k.keycode:
			KEY_ESCAPE:
				close()
			KEY_UP:
				move(-1)
			KEY_DOWN:
				move(1)
			KEY_PAGEUP:
				move(-10)
			KEY_PAGEDOWN:
				move(10)
			KEY_ENTER, KEY_KP_ENTER:
				run_chosen()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.pressed and doc != null:
		var panel := doc.get_element("cp-panel")
		if panel != null and not panel.get_global_rect().has_point(mb.global_position):
			close()
			get_viewport().set_input_as_handled()
