class_name EdUxmlNode
extends RefCounted
## One authored element of a UXML source, with exact source spans.
##
## Offsets are String indices into the buffer text. Spans are half-open.
##   open_start .. open_end    the open tag, `<` through `>` or `/>`
##   inner_start .. inner_end  the content between the tags (empty when
##                             self-closing)
##   close_start .. close_end  the close tag, -1 when self-closing or missing
##
## Each attribute is a Dictionary:
##   name         qualified name as written
##   value        value with XML entities decoded (what the renderer reads)
##   raw          value text exactly as written between the quotes
##   start, end   the whole lexeme: name start to past the closing quote
##   value_start, value_end   the raw value between the quotes
##   quote        "\"" or "'"; "" when the value is missing or unquoted
##   well_formed  true when the attribute has a terminated quoted value

var id: int = -1
var name: String = ""
var prefix: String = ""
var local: String = ""
var attributes: Array = []
var children: Array = []
var open_start: int = 0
var open_end: int = 0
var inner_start: int = 0
var inner_end: int = 0
var close_start: int = -1
var close_end: int = -1
var self_closing: bool = false
## False when the open tag runs to the end of the text, the close tag is
## missing, or the close tag names another element.
var well_formed: bool = true
var depth: int = 0
var index_in_parent: int = -1
var _parent: WeakRef = null

var parent: EdUxmlNode:
	get:
		return null if _parent == null else _parent.get_ref()
	set(v):
		_parent = null if v == null else weakref(v)


## End of the whole element: past the close tag, or past the open tag.
func outer_end() -> int:
	return close_end if close_end >= 0 else maxi(open_end, inner_end)


func get_attribute(attr_name: String) -> Variant:
	for a in attributes:
		if a["name"] == attr_name:
			return a["value"]
	return null


func attributes_named(attr_name: String) -> Array:
	var out: Array = []
	for a in attributes:
		if a["name"] == attr_name:
			out.append(a)
	return out


func authored_name() -> Variant:
	return get_attribute("name")


## Child indices from the root to this element.
func child_path() -> Array:
	var out: Array = []
	var n: EdUxmlNode = self
	while n.parent != null:
		out.push_front(n.index_in_parent)
		n = n.parent
	return out


func ancestor_tags() -> Array:
	var out: Array = []
	var n := parent
	while n != null:
		out.push_front(n.name)
		n = n.parent
	return out


func walk(out: Array = []) -> Array:
	out.append(self)
	for c in children:
		c.walk(out)
	return out


func contains(other: EdUxmlNode) -> bool:
	var n := other
	while n != null:
		if n == self:
			return true
		n = n.parent
	return false


## A short label for the hierarchy: `Button #play .primary`.
func label() -> String:
	var s := local
	var n = get_attribute("name")
	if n != null and not String(n).is_empty():
		s += " #" + String(n)
	return s
