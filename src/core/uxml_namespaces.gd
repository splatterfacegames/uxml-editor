class_name EdUxmlNamespaces
extends RefCounted
## XML namespace checks for UXML edits: an edit must not unbind or change
## the namespace of any element or attribute name.
##
## Functions return a Dictionary (prefix -> URI), true, or an EdError.


static func base_bindings() -> Dictionary:
	return {"xml": EdXml.XML_NS}


## Bindings in scope at `target` (its own declarations included).
static func bindings_at(target: EdUxmlNode) -> Variant:
	var lineage: Array = []
	var n := target
	while n != null:
		lineage.push_front(n)
		n = n.parent
	var b := base_bindings()
	for el in lineage:
		var scoped = with_declarations(b, el)
		if scoped == null:
			return EdError.make("ambiguous-source", "The namespace declarations in scope for %s are not safe to interpret." % target.name)
		b = scoped
	return b


static func bindings_before(target: EdUxmlNode) -> Variant:
	if target.parent == null:
		return base_bindings()
	return bindings_at(target.parent)


static func with_declarations(inherited: Dictionary, el: EdUxmlNode) -> Variant:
	var scoped := inherited.duplicate()
	var declared := {}
	for a in el.attributes:
		var n: String = a["name"]
		var prefix = null
		if n == "xmlns":
			prefix = ""
		elif n.begins_with("xmlns:"):
			prefix = n.substr(6)
		if prefix == null:
			continue
		if declared.has(prefix):
			return null
		declared[prefix] = true
		var uri = EdUxmlSource.decode_strict(a["raw"])
		if uri == null:
			return null
		if prefix == "":
			if is_reserved(uri):
				return null
			scoped[""] = uri
			continue
		if not EdXml.is_nc_name(prefix) or prefix == "xmlns":
			return null
		if prefix == "xml":
			if uri != EdXml.XML_NS:
				return null
		elif String(uri).is_empty() or is_reserved(uri):
			return null
		scoped[prefix] = uri
	return scoped


static func is_reserved(uri: String) -> bool:
	return uri == EdXml.XML_NS or uri == EdXml.XMLNS_NS


## The namespace URI of a qualified name, or null when unbound.
static func resolved(qname: String, attribute: bool, b: Dictionary) -> Variant:
	if not EdXml.is_qualified_name(qname):
		return null
	var colon := qname.find(":")
	if colon < 0:
		return "" if attribute else b.get("", "")
	var prefix := qname.substr(0, colon)
	if prefix == "xmlns":
		return null
	return b.get(prefix)


static func require_bound(context: EdUxmlNode, qname: String, attribute: bool) -> Variant:
	var b = bindings_at(context)
	if b is EdError:
		return b
	if resolved(qname, attribute, b) == null:
		return EdError.make("illegal-hierarchy", "Namespace prefix in %s is not bound at %s." % [qname, context.name])
	return true


static func require_attribute_namespace(el: EdUxmlNode, attr_name: String, value: String) -> Variant:
	if attr_name == "xmlns":
		if is_reserved(value):
			return EdError.make("invalid-value", "The default namespace cannot use a reserved namespace URI.")
		return true
	if attr_name.begins_with("xmlns:"):
		var prefix := attr_name.substr(6)
		if prefix == "xmlns":
			return EdError.make("invalid-name", "The xmlns prefix cannot itself be declared.")
		if prefix == "xml":
			if value != EdXml.XML_NS:
				return EdError.make("invalid-value", "The xml prefix must use the XML namespace URI.")
			return true
		if value.is_empty() or is_reserved(value):
			return EdError.make("invalid-value", "Namespace prefix %s requires a non-reserved, non-empty namespace URI." % prefix)
		return true
	return require_bound(el, attr_name, true)


static func require_safe_removal(el: EdUxmlNode, attr_name: String, raw: String) -> Variant:
	var prefix := "" if attr_name == "xmlns" else attr_name.substr(6)
	var removed = EdUxmlSource.decode_strict(raw)
	if removed == null or not usable_binding(prefix, removed):
		return EdError.make("ambiguous-source", "Namespace declaration %s is not safe to interpret." % attr_name)
	var inherited = bindings_before(el)
	if inherited is EdError:
		return inherited
	var inherited_uri = inherited.get(prefix, "" if prefix.is_empty() else null)
	if inherited_uri == removed:
		return true
	var dep = depends_on(el, prefix, true)
	if dep is EdError:
		return dep
	if dep:
		return EdError.make("illegal-hierarchy", "Removing %s would change or unbind a QName in %s." % [attr_name, el.name])
	return true


static func usable_binding(prefix: String, uri: String) -> bool:
	if prefix == "xmlns":
		return false
	if prefix == "xml":
		return uri == EdXml.XML_NS
	if prefix.is_empty():
		return not is_reserved(uri)
	return not uri.is_empty() and not is_reserved(uri)


static func depends_on(el: EdUxmlNode, prefix: String, owner: bool) -> Variant:
	if not owner:
		var decl := "xmlns" if prefix.is_empty() else "xmlns:" + prefix
		var overrides := el.attributes_named(decl)
		if overrides.size() > 1:
			return EdError.make("ambiguous-source", "%s occurs more than once on %s." % [decl, el.name])
		if overrides.size() == 1:
			var uri = EdUxmlSource.decode_strict(overrides[0]["raw"])
			if uri == null or not usable_binding(prefix, uri):
				return EdError.make("ambiguous-source", "Nested namespace declaration %s is not safe to interpret." % decl)
			return false
	if uses_prefix(el.name, prefix, false):
		return true
	for a in el.attributes:
		var n: String = a["name"]
		if n != "xmlns" and not n.begins_with("xmlns:") and uses_prefix(n, prefix, true):
			return true
	for c in el.children:
		var d = depends_on(c, prefix, false)
		if d is EdError or d == true:
			return d
	return false


static func uses_prefix(qname: String, prefix: String, attribute: bool) -> bool:
	var colon := qname.find(":")
	if prefix.is_empty():
		return not attribute and colon < 0
	return colon == prefix.length() and qname.substr(0, colon) == prefix


static func preserves(el: EdUxmlNode, source_b: Dictionary, dest_b: Dictionary) -> bool:
	var s = with_declarations(source_b, el)
	var d = with_declarations(dest_b, el)
	if s == null or d == null:
		return false
	var sn = resolved(el.name, false, s)
	var dn = resolved(el.name, false, d)
	if sn == null or dn == null or sn != dn:
		return false
	for a in el.attributes:
		var n: String = a["name"]
		if n == "xmlns" or n.begins_with("xmlns:"):
			continue
		var sa = resolved(n, true, s)
		var da = resolved(n, true, d)
		if sa == null or sa != da:
			return false
	for c in el.children:
		if not preserves(c, s, d):
			return false
	return true
