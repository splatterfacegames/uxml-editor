class_name EdTestCase
extends RefCounted
## Base class of the unit tests. Assertions record failures and continue.

const ENTRY := "Assets/UI/screen.uxml"

var tree: SceneTree
var current: String = ""
var failures: Array = []
var checks: int = 0
var _nodes: Array = []


func teardown() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	if tree != null:
		await tree.process_frame


## Add a node to the scene tree for this test; it is freed after the test.
func add_node(n: Node) -> Node:
	tree.get_root().add_child(n)
	_nodes.append(n)
	return n


func ok(cond: bool, msg: String = "expected true") -> bool:
	checks += 1
	if not cond:
		failures.append(msg)
	return cond


func eq(actual: Variant, expected: Variant, msg: String = "") -> bool:
	checks += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%sexpected %s, got %s" % ["" if msg.is_empty() else msg + ": ", _show(expected), _show(actual)])
		return false
	return true


func is_error(v: Variant, code: String, msg: String = "") -> bool:
	checks += 1
	if not (v is EdError):
		failures.append("%sexpected error %s, got %s" % ["" if msg.is_empty() else msg + ": ", code, _show(v)])
		return false
	if v.code != code:
		failures.append("%sexpected error %s, got %s (%s)" % ["" if msg.is_empty() else msg + ": ", code, v.code, v.message])
		return false
	return true


func is_tx(v: Variant, msg: String = "") -> bool:
	checks += 1
	if not (v is EdTransaction):
		failures.append("%sexpected a transaction, got %s" % ["" if msg.is_empty() else msg + ": ", _show(v)])
		return false
	return true


static func _show(v: Variant) -> String:
	if v is EdError:
		return "EdError(%s: %s)" % [v.code, v.message]
	if typeof(v) == TYPE_STRING:
		return JSON.stringify(v)
	return str(v)


# ---------------------------------------------------------------------------
# Session helpers
# ---------------------------------------------------------------------------

static func open_session(uxml: String, sheets: Dictionary = {}) -> EdDocumentSession:
	var ws := EdWorkspace.new()
	ws.set_buffer(ENTRY, EdSourceBuffer.new(ENTRY, uxml))
	for p in sheets:
		ws.set_buffer(p, EdSourceBuffer.new(p, sheets[p]))
	return EdDocumentSession.new(ws, ENTRY)


static func p(start: int, end: int, replacement: String) -> Dictionary:
	return EdSourcePatch.make(start, end, replacement)


func named(s: EdDocumentSession, qualified_tag: String) -> Dictionary:
	for n in s.root().walk():
		if n.name == qualified_tag:
			return EdLocator.create(n)
	failures.append("missing fixture element " + qualified_tag)
	return {}


func with_name(s: EdDocumentSession, authored: String) -> Dictionary:
	for n in s.root().walk():
		if n.get_attribute("name") == authored:
			return EdLocator.create(n)
	failures.append("missing fixture element named " + authored)
	return {}


static func run(s: EdDocumentSession, tx: Variant) -> Variant:
	if not (tx is EdTransaction):
		return tx
	return s.workspace.history.execute(tx)


static func text(s: EdDocumentSession) -> String:
	return s.workspace.text(s.entry_path)


static func read_file(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


## Every fixture file with one of `exts`, as absolute (res:// or os) paths.
static func fixture_files(exts: Array) -> Array:
	var out: Array = []
	for base in ["res://fixtures/projects", "res://tests/fixtures"]:
		_collect(ProjectSettings.globalize_path(base), exts, out)
	out.sort()
	return out


static func _collect(dir: String, exts: Array, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		if exts.has(f.get_extension().to_lower()):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, exts, out)
