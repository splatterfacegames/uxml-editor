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
## the classes go to the `class` attribute of the godot-uxml element (with
## the classes that the control adds) and the states to
## set_forced_states. disarm() puts back the classes of the source text
## and the forced states of the state preview, without transitions, and
## gives the frame clock back to godot-uxml.

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
	node_id = id
	from_state = from.duplicate(true)
	to_state = to.duplicate(true)
	armed = true
	arms += 1
	doc.transitions_manual = true
	_apply(el, from)
	_settle(doc)
	_apply(el, to)
	return doc.get_transitions()


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
	var doc := host.doc
	if doc != null and _el != null and is_instance_valid(doc) and host.element_for_node.get(node_id) == _el:
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
		if el == null:
			armed = false
			node_id = -1


func _apply(el: UxmlElement, st: Dictionary) -> void:
	var author := " ".join(PackedStringArray(st.get("classes", [])))
	var want := UxmlParts.merged_class(el, author)
	var cur = el.get_attribute("class")
	if want.is_empty() and cur != null:
		el.remove_attribute("class")
	elif not want.is_empty() and String(cur if cur != null else "") != want:
		el.set_attribute("class", want)
	host.doc.set_forced_states(el, PackedStringArray(st.get("states", [])))


## Finish every transition at once: the restyle of the change runs
## first (get_transitions), then playback passes every end.
static func _settle(doc: UxmlDocument) -> void:
	doc.get_transitions()
	if doc.has_running_transitions():
		doc.advance_transitions(1.0e5)
