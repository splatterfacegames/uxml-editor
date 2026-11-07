class_name EdAppTestCase
extends EdTestCase
## Base of the tests that run the real editor scene headless: a copy of a
## fixture project, the editor, frame waits and input helpers.

const MENU := "Assets/UI/Menu.uxml"
const MENU_USS := "Assets/UI/Menu.uss"

var _dir := ""


func copy_fixture(fixture: String) -> String:
	_dir = ProjectSettings.globalize_path("user://test-app-%d" % Time.get_ticks_usec())
	_copy_tree(ProjectSettings.globalize_path("res://fixtures/projects/" + fixture), _dir)
	return _dir


static func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for f in DirAccess.get_files_at(from):
		DirAccess.copy_absolute(from + "/" + f, to + "/" + f)
	for d in DirAccess.get_directories_at(from):
		_copy_tree(from + "/" + d, to + "/" + d)


static func _rm(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_rm(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func teardown() -> void:
	await super()
	if not _dir.is_empty():
		_rm(_dir)


## The editor with `fixture` open, rendered.
func editor(fixture: String = "menu") -> EdMain:
	tree.root.size = Vector2i(1600, 1000)
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	add_node(m)
	await frames()
	m.state.open_project(copy_fixture(fixture))
	await frames()
	return m


func frames(n: int = 3) -> void:
	for i in n:
		await tree.process_frame


func node_named(m: EdMain, authored: String) -> EdUxmlNode:
	for n in m.state.session.root().walk():
		if n.get_attribute("name") == authored:
			return n
	return null


func tree_index(m: EdMain, list: String, id: int) -> int:
	for i in 200:
		var it := m.shell.get_tree_item(list, i)
		if it.is_empty():
			return -1
		if int(it["id"]) == id:
			return i
	return -1


## The global rectangle of the bound row of `index` in collection `list`
## (scrolls the row into view first).
func row_rect(m: EdMain, list: String, index: int) -> Rect2:
	m.shell.scroll_to_item(list, index)
	await frames(2)
	for row in m.shell.get_list_rows(list):
		if row.index == index:
			return row.get_element().get_global_rect()
	return Rect2()


## Send mouse events through the window, as a user would.
func mouse_button(m: EdMain, pos: Vector2, pressed: bool, button: int = MOUSE_BUTTON_LEFT, shift: bool = false, double: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.shift_pressed = shift
	e.double_click = double
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	m.get_viewport().push_input(e)


func mouse_move(m: EdMain, pos: Vector2, held: bool = true, shift: bool = false) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	e.shift_pressed = shift
	m.get_viewport().push_input(e)


func key(m: EdMain, keycode: int, ctrl: bool = false, shift: bool = false, alt: bool = false) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = keycode
		e.physical_keycode = keycode
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.shift_pressed = shift
		e.alt_pressed = alt
		m.get_viewport().push_input(e)


## A press, moves in `steps` and a release from `a` to `b`.
func drag(m: EdMain, a: Vector2, b: Vector2, steps: int = 5) -> void:
	mouse_button(m, a, true)
	await frames(1)
	for i in range(1, steps + 1):
		mouse_move(m, a.lerp(b, float(i) / steps))
		await frames(1)
	mouse_button(m, b, false)
	await frames(2)
