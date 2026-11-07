class_name EdElementCatalog
extends RefCounted
## The elements the library offers: every UXML element that godot-uxml
## renders, runtime (`UnityEngine.UIElements`) and editor
## (`UnityEditor.UIElements`), grouped as in the Unity UI Builder library.
##
## The element list, the namespaces, the `container` flag and the
## attributes come from godot-uxml (`UxmlControls.catalog()`, request R9).
## The editor adds what godot-uxml does not know: the library group, the
## order in the library and the attributes of a new element. The core does
## not depend on godot-uxml at compile time: the catalog is read through
## `source` (a Callable; by default the godot-uxml script is loaded by
## path), so the core still loads without the addon.
##
## Entry: {name, uri, group, container: bool, editor_only: bool,
## attributes: [[name, value]] (a new element), catalog_attributes:
## [{name, type, default[, choices]}]}.

const RUNTIME := "UnityEngine.UIElements"
const EDITOR := "UnityEditor.UIElements"
## The prefix a new namespace declaration gets.
const PREFERRED_PREFIX := {RUNTIME: "ui", EDITOR: "uie"}
const GROUPS := ["Containers", "Controls", "Inputs", "Collections", "Editor"]
const _CONTROLS_SCRIPT := "res://addons/godot_uxml/core/uxml_controls.gd"

## The library order and groups: [name, group, attributes of a new element].
## A catalog element that is not listed goes to the end of the group
## that _group_of() gives it.
const _LIBRARY := [
	["VisualElement", "Containers", []],
	["ScrollView", "Containers", []],
	["GroupBox", "Containers", [["text", "Group Box"]]],
	["Foldout", "Containers", [["text", "Foldout"]]],
	["Box", "Containers", []],
	["TwoPaneSplitView", "Containers", []],
	["TabView", "Containers", []],
	["Tab", "Containers", [["label", "Tab"]]],
	["PopupWindow", "Containers", [["text", "Popup Window"]]],
	["RadioButtonGroup", "Containers", [["label", "Radio Button Group"]]],
	["ToggleButtonGroup", "Containers", [["label", "Toggle Button Group"]]],
	["IMGUIContainer", "Containers", []],
	["Label", "Controls", [["text", "Label"]]],
	["TextElement", "Controls", [["text", "Text"]]],
	["Button", "Controls", [["text", "Button"]]],
	["RepeatButton", "Controls", [["text", "Repeat Button"]]],
	["Toggle", "Controls", [["label", "Toggle"]]],
	["RadioButton", "Controls", [["label", "Radio Button"]]],
	["Image", "Controls", []],
	["HelpBox", "Controls", [["text", "Help Box"], ["message-type", "Info"]]],
	["ProgressBar", "Controls", [["title", "Progress"], ["value", "50"]]],
	["Scroller", "Controls", []],
	["TextField", "Inputs", [["label", "Text Field"]]],
	["IntegerField", "Inputs", [["label", "Integer Field"]]],
	["LongField", "Inputs", [["label", "Long Field"]]],
	["FloatField", "Inputs", [["label", "Float Field"]]],
	["DoubleField", "Inputs", [["label", "Double Field"]]],
	["UnsignedIntegerField", "Inputs", [["label", "Unsigned Integer Field"]]],
	["UnsignedLongField", "Inputs", [["label", "Unsigned Long Field"]]],
	["Hash128Field", "Inputs", [["label", "Hash128 Field"]]],
	["Slider", "Inputs", [["label", "Slider"]]],
	["SliderInt", "Inputs", [["label", "Slider Int"]]],
	["MinMaxSlider", "Inputs", [["label", "Min Max Slider"]]],
	["DropdownField", "Inputs", [["label", "Dropdown"], ["choices", "One,Two,Three"], ["index", "0"]]],
	["EnumField", "Inputs", [["label", "Enum Field"]]],
	["Vector2Field", "Inputs", [["label", "Vector2 Field"]]],
	["Vector2IntField", "Inputs", [["label", "Vector2Int Field"]]],
	["Vector3Field", "Inputs", [["label", "Vector3 Field"]]],
	["Vector3IntField", "Inputs", [["label", "Vector3Int Field"]]],
	["Vector4Field", "Inputs", [["label", "Vector4 Field"]]],
	["RectField", "Inputs", [["label", "Rect Field"]]],
	["RectIntField", "Inputs", [["label", "RectInt Field"]]],
	["BoundsField", "Inputs", [["label", "Bounds Field"]]],
	["BoundsIntField", "Inputs", [["label", "BoundsInt Field"]]],
	["ListView", "Collections", []],
	["TreeView", "Collections", []],
	["MultiColumnListView", "Collections", []],
	["MultiColumnTreeView", "Collections", []],
	# UnityEditor.UIElements
	["Toolbar", "Editor", []],
	["ToolbarButton", "Editor", [["text", "Button"]]],
	["ToolbarToggle", "Editor", [["text", "Toggle"]]],
	["ToolbarMenu", "Editor", [["text", "Menu"]]],
	["ToolbarSpacer", "Editor", []],
	["ToolbarBreadcrumbs", "Editor", []],
	["ToolbarSearchField", "Editor", []],
	["ToolbarPopupSearchField", "Editor", []],
	["ColorField", "Editor", [["label", "Color Field"]]],
	["CurveField", "Editor", [["label", "Curve Field"]]],
	["GradientField", "Editor", [["label", "Gradient Field"]]],
	["ObjectField", "Editor", [["label", "Object Field"]]],
	["EnumFlagsField", "Editor", [["label", "Enum Flags Field"]]],
	["MaskField", "Editor", [["label", "Mask Field"], ["choices", "One,Two,Three"]]],
	["LayerField", "Editor", [["label", "Layer Field"]]],
	["LayerMaskField", "Editor", [["label", "Layer Mask Field"]]],
	["RenderingLayerMaskField", "Editor", [["label", "Rendering Layer Mask Field"]]],
	["TagField", "Editor", [["label", "Tag Field"]]],
	["PropertyField", "Editor", [["label", "Property Field"]]],
	["InspectorElement", "Editor", []],
]

## Control parts: godot-uxml makes them inside a control; the catalog
## does not list them, and an author does not write them.
const PARTS := [
	"TextInput", "IntegerInput", "LongInput", "FloatInput",
	"DoubleInput", "UnsignedIntegerInput", "UnsignedLongInput", "Hash128Input",
	"PopupTextElement", "ObjectFieldDisplay", "ObjectFieldSelector", "BreadcrumbItem",
	"PopupField`1",
]
## Catalog elements that the library does not offer: the template
## container (an <Instance> makes one).
const NOT_IN_LIBRARY := ["TemplateContainer"]
## Structural UXML tags (not elements of the catalog).
const STRUCTURAL := ["UXML", "Style", "Template", "Instance", "AttributeOverrides"]

## Reads the godot-uxml catalog: () -> Array (UxmlControls.catalog()).
## Not set: the godot-uxml script is loaded by path.
static var source: Callable

static var _entries: Array = []
static var _by_name: Dictionary = {}
## Every catalog element by name (UxmlObjects and the template container
## too), and the names that the library does not show.
static var _catalog: Dictionary = {}
static var _hidden: Dictionary = {}


static func _default_source() -> Array:
	if not ResourceLoader.exists(_CONTROLS_SCRIPT):
		return []
	return load(_CONTROLS_SCRIPT).catalog()


## Read the catalog again (after `source` changed).
static func reset() -> void:
	_entries = []
	_by_name = {}
	_catalog = {}
	_hidden = {}


## The library entries, in library order.
static func entries() -> Array:
	if not _catalog.is_empty() or not _entries.is_empty():
		return _entries
	var cat: Array = source.call() if source.is_valid() else _default_source()
	for c in cat:
		_catalog[c["name"]] = c
		if c.get("uxml_object", false) or NOT_IN_LIBRARY.has(c["name"]):
			_hidden[c["name"]] = true
	var listed := {}
	var by_group := {}
	for g in GROUPS:
		by_group[g] = []
	for row in _LIBRARY:
		var c = _catalog.get(row[0])
		if c == null or _hidden.has(row[0]):
			continue
		listed[row[0]] = true
		by_group[row[1]].append(_entry(c, row[1], row[2]))
	for name in _catalog:
		if listed.has(name) or _hidden.has(name):
			continue
		var c: Dictionary = _catalog[name]
		var g := _group_of(c)
		by_group[g].append(_entry(c, g, []))
	for g in GROUPS:
		for e in by_group[g]:
			_entries.append(e)
			_by_name[e["name"]] = e
	return _entries


static func _group_of(c: Dictionary) -> String:
	if c.get("editor_only", false):
		return "Editor"
	if c.get("container", false):
		return "Containers"
	var n := String(c["name"])
	if n.ends_with("Field") or n.contains("Slider"):
		return "Inputs"
	if n.ends_with("View"):
		return "Collections"
	return "Controls"


static func _entry(c: Dictionary, group: String, attrs: Array) -> Dictionary:
	return {"name": c["name"], "uri": c["namespace"], "group": group, "container": bool(c.get("container", false)),
		"editor_only": bool(c.get("editor_only", false)), "attributes": attrs,
		"catalog_attributes": c.get("attributes", [])}


## The catalog attributes of an element ([{name, type, default[,
## choices]}]), or [] for an element that godot-uxml does not know.
static func attributes_of(local: String) -> Array:
	entries()
	var c = _catalog.get(local)
	return [] if c == null else c.get("attributes", [])


## The catalog attribute `attr` of element `local`, or {}.
static func attribute(local: String, attr: String) -> Dictionary:
	for a in attributes_of(local):
		if a["name"] == attr:
			return a
	return {}


## The entry of an element local name, or {} for a tag the catalog does
## not list (an unknown or custom element).
static func find(local: String) -> Dictionary:
	entries()
	return _by_name.get(local, {})


static func is_known(local: String) -> bool:
	entries()
	return _catalog.has(local) or PARTS.has(local) or STRUCTURAL.has(local)


## True when "insert at the selection" puts a new element inside `node`.
## Unknown elements count as containers (a custom VisualElement subclass).
static func accepts_children(node: EdUxmlNode) -> bool:
	if node == null:
		return false
	if node.parent == null:
		return true
	if node.local == "Style" or node.local == "Template":
		return false
	entries()
	var c = _catalog.get(node.local)
	if c == null:
		return not PARTS.has(node.local)
	return bool(c.get("container", false)) and not c.get("uxml_object", false)


## Entries whose name contains every word of `query` (case-insensitive),
## in table order.
static func search(query: String) -> Array:
	var words := query.to_lower().split(" ", false)
	var out: Array = []
	for e in entries():
		var hay := ("%s %s %s" % [e["name"], e["group"], "editor" if e["uri"] == EDITOR else "runtime"]).to_lower()
		var hit := true
		for w in words:
			if not hay.contains(w):
				hit = false
				break
		if hit:
			out.append(e)
	return out
