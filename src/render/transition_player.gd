class_name EdTransitionPlayer
extends RefCounted
## Runs the USS transitions of one state change on the canvas render, for
## the timeline (godot-uxml request R7: get_transitions, seek_transitions).
##
## arm(node, from, to) puts the element in state `from` (author classes
## and forced pseudo-states), lets every transition finish, then puts it in
## state `to`: godot-uxml starts the transitions of the change, and
## get_transitions() lists them. The document runs with
## `transitions_manual = true`, so only seek() moves them: a seek is the
## time after the change, also back and past the end (godot-uxml keeps a
## transition alive until playback passes its end, and the player never
## plays).
##
## A state change is a runtime change of the render, not of the source:
## the classes go to set_author_classes (the classes that the control adds
## stay) and the states to set_forced_states. disarm() puts back the classes of the source text
## and the forced states of the state preview, without transitions, and
## gives the frame clock back to godot-uxml.
##
## set_preview() shows edited `transition-*` values on the element of the
## run before they are written: declarations at the end of the `style`
## attribute of the godot-uxml model. A stylesheet reload costs a restyle of
## the whole document; a change of one `style` attribute costs a restyle of
## one element. The source text does not change.

var host: EdRenderHost
var node_id := -1
var armed := false
var from_state: Dictionary = {}
var to_state: Dictionary = {}
## The author classes of the element in the source text: disarm() shows
## them. The owner keeps this current (an edit can change the classes
## during a run).
var source_classes: Array = []
## The godot-uxml element of the run.
var _el: UxmlElement = null
## Number of arms (tests and the benchmark).
var arms := 0
## property -> value of the preview declarations.
var _preview: Dictionary = {}
## The `style` attribute of the element before the preview ({} when no
## preview shows).
var _style_saved: Dictionary = {}


func _init(h: EdRenderHost) -> void:
	host = h


## Run the change from state `from` to state `to` of editor node `id`.
## Returns the running transitions (godot-uxml get_transitions entries),
## or [] when the element is not rendered.
func arm(id: int, from: Dictionary, to: Dictionary) -> Array:
	var doc := host.doc
	var el: UxmlElement = host.element_for_node.get(id)
	if doc == null or el == null:
		disarm()
		return []
	if armed and (id != node_id or el != _el):
		disarm()
	if not armed:
		_el = el
		_style_saved = {}
	node_id = id
	from_state = from.duplicate(true)
	to_state = to.duplicate(true)
	armed = true
	arms += 1
	doc.transitions_manual = true
	_apply(el, from)
	_show_preview(el)
	_settle(doc)
	# A run as if it were the first: a transition that completed in an
	# earlier run does not stop this one (Unity keeps it, request R23).
	doc.clear_completed_transitions()
	_apply(el, to)
	return doc.get_transitions()


## Show `declarations` (property -> value) on the element of the run. The
## next arm() starts the transitions with them.
func set_preview(declarations: Dictionary) -> void:
	_preview = declarations.duplicate()


func has_preview() -> bool:
	return not _preview.is_empty()


## The source value of the `style` attribute again; the next arm() or the
## next restyle shows it.
func clear_preview() -> void:
	_preview = {}
	if _el != null and not _style_saved.is_empty():
		_restore_style(_el)


func _show_preview(el: UxmlElement) -> void:
	if _preview.is_empty():
		return
	if _style_saved.is_empty():
		_style_saved = {"value": el.get_attribute("style")}
	var base := String(_style_saved["value"]) if _style_saved["value"] != null else ""
	var text := base.strip_edges()
	if not text.is_empty() and not text.ends_with(";"):
		text += ";"
	for prop in _preview:
		text += " %s: %s;" % [prop, _preview[prop]]
	el.set_attribute("style", text.strip_edges())


func _restore_style(el: UxmlElement) -> void:
	var was = _style_saved["value"]
	_style_saved = {}
	if was == null:
		el.remove_attribute("style")
	else:
		el.set_attribute("style", String(was))


## The running transitions of the armed run.
func transitions() -> Array:
	if not armed or host.doc == null:
		return []
	return host.doc.get_transitions()


## Show the run `seconds` after the change.
func seek(seconds: float) -> void:
	if armed and host.doc != null:
		host.doc.seek_transitions(seconds)


## End the run: the class value of the load, the states of the state
## preview, no transitions, and the frame clock of godot-uxml.
func disarm() -> void:
	if not armed:
		return
	armed = false
	_preview = {}
	var doc := host.doc
	if doc != null and _el != null and is_instance_valid(doc) and host.element_for_node.get(node_id) == _el:
		if not _style_saved.is_empty():
			_restore_style(_el)
		_apply(_el, {"classes": source_classes, "states": host.forced_of(node_id)})
		_settle(doc)
	if doc != null and is_instance_valid(doc):
		doc.transitions_manual = false
	_el = null
	node_id = -1


## A new render: a full load made new elements (the run is gone; the next
## arm starts from the loaded classes), an update kept them.
func rendered() -> void:
	if not armed:
		return
	var el = host.element_for_node.get(node_id)
	if el != _el:
		_el = el
		_style_saved = {}
		if el == null:
			armed = false
			node_id = -1


func _apply(el: UxmlElement, st: Dictionary) -> void:
	var author := PackedStringArray(st.get("classes", []))
	if host.doc.get_author_classes(el) != author:
		host.doc.set_author_classes(el, author)
	host.doc.set_forced_states(el, PackedStringArray(st.get("states", [])))


## Finish every transition at once (the restyle of the change runs first),
## with no event and no move of the clock.
static func _settle(doc: UxmlDocument) -> void:
	doc.finish_transitions()
