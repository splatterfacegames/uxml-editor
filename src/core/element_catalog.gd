class_name EdElementCatalog
extends RefCounted
## The elements the palette offers: every UXML element that godot-uxml
## renders, runtime (`UnityEngine.UIElements`) and editor
## (`UnityEditor.UIElements`), grouped as in the Unity UI Builder library.
##
## Seam for godot-uxml request R9 (a catalog API). Until R9 lands this is a
## static table. tests/unit/test_palette.gd checks it against the tags that
## godot-uxml knows (UssControls.IMPLICIT_CLASSES), so a tag that godot-uxml
## adds or removes fails the suite. To move to R9, make entries() read
## UxmlControls.catalog() and keep the entry shape.
##
## Entry: {name, uri, group, container: bool, attributes: [[name, value]]}.
## `container` tells where "insert at the selection" puts a new element:
## into a container, after anything else.

const RUNTIME := "UnityEngine.UIElements"
const EDITOR := "UnityEditor.UIElements"
## The prefix a new namespace declaration gets.
const PREFERRED_PREFIX := {RUNTIME: "ui", EDITOR: "uie"}
const GROUPS := ["Containers", "Controls", "Inputs", "Collections", "Editor"]

## [name, group, container, default attributes]
const _RUNTIME_TABLE := [
	["VisualElement", "Containers", true, []],
	["ScrollView", "Containers", true, []],
	["GroupBox", "Containers", true, [["text", "Group Box"]]],
	["Foldout", "Containers", true, [["text", "Foldout"]]],
	["Box", "Containers", true, []],
	["TwoPaneSplitView", "Containers", true, []],
	["TabView", "Containers", true, []],
	["Tab", "Containers", true, [["label", "Tab"]]],
	["PopupWindow", "Containers", true, [["text", "Popup Window"]]],
	["RadioButtonGroup", "Containers", true, [["label", "Radio Button Group"]]],
	["ToggleButtonGroup", "Containers", true, [["label", "Toggle Button Group"]]],
	["IMGUIContainer", "Containers", false, []],
	["Label", "Controls", false, [["text", "Label"]]],
	["TextElement", "Controls", false, [["text", "Text"]]],
	["Button", "Controls", false, [["text", "Button"]]],
	["RepeatButton", "Controls", false, [["text", "Repeat Button"]]],
	["Toggle", "Controls", false, [["label", "Toggle"]]],
	["RadioButton", "Controls", false, [["label", "Radio Button"]]],
	["Image", "Controls", false, []],
	["HelpBox", "Controls", false, [["text", "Help Box"], ["message-type", "Info"]]],
	["ProgressBar", "Controls", false, [["title", "Progress"], ["value", "50"]]],
	["Scroller", "Controls", false, []],
	["TextField", "Inputs", false, [["label", "Text Field"]]],
	["IntegerField", "Inputs", false, [["label", "Integer Field"]]],
	["LongField", "Inputs", false, [["label", "Long Field"]]],
	["FloatField", "Inputs", false, [["label", "Float Field"]]],
	["DoubleField", "Inputs", false, [["label", "Double Field"]]],
	["UnsignedIntegerField", "Inputs", false, [["label", "Unsigned Integer Field"]]],
	["UnsignedLongField", "Inputs", false, [["label", "Unsigned Long Field"]]],
	["Hash128Field", "Inputs", false, [["label", "Hash128 Field"]]],
	["Slider", "Inputs", false, [["label", "Slider"]]],
	["SliderInt", "Inputs", false, [["label", "Slider Int"]]],
	["MinMaxSlider", "Inputs", false, [["label", "Min Max Slider"]]],
	["DropdownField", "Inputs", false, [["label", "Dropdown"], ["choices", "One,Two,Three"], ["index", "0"]]],
	["EnumField", "Inputs", false, [["label", "Enum Field"]]],
	["Vector2Field", "Inputs", false, [["label", "Vector2 Field"]]],
	["Vector2IntField", "Inputs", false, [["label", "Vector2Int Field"]]],
	["Vector3Field", "Inputs", false, [["label", "Vector3 Field"]]],
	["Vector3IntField", "Inputs", false, [["label", "Vector3Int Field"]]],
	["Vector4Field", "Inputs", false, [["label", "Vector4 Field"]]],
	["RectField", "Inputs", false, [["label", "Rect Field"]]],
	["RectIntField", "Inputs", false, [["label", "RectInt Field"]]],
	["BoundsField", "Inputs", false, [["label", "Bounds Field"]]],
	["BoundsIntField", "Inputs", false, [["label", "BoundsInt Field"]]],
	["ListView", "Collections", false, []],
	["TreeView", "Collections", false, []],
	["MultiColumnListView", "Collections", false, []],
	["MultiColumnTreeView", "Collections", false, []],
]

const _EDITOR_TABLE := [
	["Toolbar", "Editor", true, []],
	["ToolbarButton", "Editor", false, [["text", "Button"]]],
	["ToolbarToggle", "Editor", false, [["text", "Toggle"]]],
	["ToolbarMenu", "Editor", false, [["text", "Menu"]]],
	["ToolbarSpacer", "Editor", false, []],
	["ToolbarBreadcrumbs", "Editor", false, []],
	["ToolbarSearchField", "Editor", false, []],
	["ToolbarPopupSearchField", "Editor", false, []],
	["ColorField", "Editor", false, [["label", "Color Field"]]],
	["CurveField", "Editor", false, [["label", "Curve Field"]]],
	["GradientField", "Editor", false, [["label", "Gradient Field"]]],
	["ObjectField", "Editor", false, [["label", "Object Field"]]],
	["EnumFlagsField", "Editor", false, [["label", "Enum Flags Field"]]],
	["MaskField", "Editor", false, [["label", "Mask Field"], ["choices", "One,Two,Three"]]],
	["LayerField", "Editor", false, [["label", "Layer Field"]]],
	["LayerMaskField", "Editor", false, [["label", "Layer Mask Field"]]],
	["RenderingLayerMaskField", "Editor", false, [["label", "Rendering Layer Mask Field"]]],
	["TagField", "Editor", false, [["label", "Tag Field"]]],
	["PropertyField", "Editor", false, [["label", "Property Field"]]],
	["InspectorElement", "Editor", true, []],
]

## Tags that godot-uxml knows but that are not authored as palette items:
## control parts, column UxmlObjects (they live inside a multi-column
## view), and the template container (an <Instance> makes one).
const NOT_IN_PALETTE := [
	"TemplateContainer", "TextInput", "IntegerInput", "LongInput", "FloatInput",
	"DoubleInput", "UnsignedIntegerInput", "UnsignedLongInput", "Hash128Input",
	"PopupTextElement", "ObjectFieldDisplay", "ObjectFieldSelector", "BreadcrumbItem",
	"PopupField`1", "Columns", "Column", "SortColumnDescriptions", "SortColumnDescription",
]

static var _entries: Array = []
static var _by_name: Dictionary = {}


static func entries() -> Array:
	if _entries.is_empty():
		for row in _RUNTIME_TABLE:
			_add(row, RUNTIME)
		for row in _EDITOR_TABLE:
			_add(row, EDITOR)
	return _entries


static func _add(row: Array, uri: String) -> void:
	var e := {"name": row[0], "uri": uri, "group": row[1], "container": row[2], "attributes": row[3]}
	_entries.append(e)
	_by_name[row[0]] = e


## The entry of an element local name, or {} for a tag the catalog does
## not list (an unknown or custom element).
static func find(local: String) -> Dictionary:
	entries()
	return _by_name.get(local, {})


static func is_known(local: String) -> bool:
	return not find(local).is_empty() or NOT_IN_PALETTE.has(local) \
		or ["UXML", "Style", "Template", "Instance", "AttributeOverrides"].has(local)


## True when "insert at the selection" puts a new element inside `node`.
## Unknown elements count as containers (a custom VisualElement subclass).
static func accepts_children(node: EdUxmlNode) -> bool:
	if node == null:
		return false
	if node.parent == null:
		return true
	if node.local == "Style" or node.local == "Template":
		return false
	var e := find(node.local)
	if e.is_empty():
		return not NOT_IN_PALETTE.has(node.local)
	return e["container"]


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
