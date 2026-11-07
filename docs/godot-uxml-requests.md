# godot-uxml API requests

The editor uses godot-uxml at the commit in `godot-uxml.pin`. The editor
does not change godot-uxml. Where the editor needs something that
godot-uxml does not expose, the editor uses a workaround and the need is
recorded here. A separate godot-uxml change adds each API, with that
repository's full verification suite. When an API lands, move the pin
(`tools/update_godot_uxml.py`) and remove the workaround.

Priority: **P1** blocks or slows milestone 1 work (a workaround exists),
**P2** is needed by the next milestones, **P3** is an improvement.

| ID | Priority | Status | Request |
| --- | --- | --- | --- |
| R1 | P1 | workaround | Load from text with a caller resolver |
| R2 | P1 | workaround | Element-handle lookups |
| R3 | P1 | relied on, untested upstream | Stable source offsets on `UxmlElement` |
| R4 | P2 | full reload | Partial reload of one stylesheet or one document |
| R5 | P2 | winner only | All cascade candidates of a property |
| R6 | P2 | none | Forced pseudo-states on an element |
| R7 | P2 | none | Transition snapshot and seek |
| R8 | P2 | workaround | Hit-test that respects transforms and clipping |
| R9 | P2 | none | Catalog of supported elements and attributes |
| R10 | P3 | workaround | Template instance of a cloned element |
| R11 | P3 | partial | End offsets on every diagnostic |

## R1. Load from text with a caller resolver (P1)

```gdscript
# UxmlDocument
func load_source(uxml: String, virtual_path: String = "res://__uxml_source__.uxml",
		root: String = "", resolver: UxmlResourceResolver = null) -> int
```

`resolver == null` keeps the current behaviour. Otherwise the load uses
`resolver` for every `<Style src>`, `@import`, template and asset read, and
`root` is ignored. `reload()` must keep the resolver of the last load.

**Use case.** The canvas shows unsaved text. The editor subclasses
`UxmlResourceResolver` (`EdBufferResolver`) and returns open buffers from
`resolve_text()`. Edited USS, `@import` targets and template files then
render before a save.

**Workaround.** `EdRenderHost._load_source()` copies the body of
`load_source()` at the pinned commit and sets `_resolver`, `_doc` and
`_effective_root` directly. Any change to `load_source()` upstream breaks
the copy without an error.

## R2. Element-handle lookups (P1)

```gdscript
# UxmlDocument
func get_document_model() -> UxmlDocumentModel
func get_control_for(element: UxmlElement) -> Control        # outer box
func get_native_for(element: UxmlElement) -> Control         # interactive native
func get_element_for(control: Control) -> UxmlElement        # inverse, any part control
func get_parent_element(element: UxmlElement) -> UxmlElement
func get_computed_style_for(element: UxmlElement) -> Dictionary
func set_element_state_for(element: UxmlElement, state: String, on: bool) -> void
```

**Use case.** Most authored elements have no `name`. The editor maps
every authored element to its control (selection overlay, hit-test,
layout readout) and reads the computed style of the selection.

**Workaround.** `EdRenderHost` reads `_doc`, `_controls`, `_parents` and
`_styles`.

## R3. Stable source offsets on `UxmlElement` (P1)

Document as API, and test upstream:

- `UxmlElement.open_tag_start` is the String index of the `<` of the open
  tag in the source text of the file the element was authored in.
- `open_tag_end` is past `>` or `/>`; `source_end` is past the close tag.
- `attributes[i].offset` is the index of the attribute name.
- Both parsers (native and GDScript) give the same values.

Optional addition: `UxmlElement.source_file: String` (today
`UxmlDocumentModel.path_of(element)`).

**Use case.** The editor maps rendered elements to its own span tree by
`open_tag_start`. `tests/unit/test_source_parsers.gd` checks the
agreement for all 144 UXML fixtures on both godot-uxml paths, but godot-uxml
does not promise the contract.

## R4. Partial reload (P2)

```gdscript
# UxmlDocument
## Re-parse one stylesheet that the document uses and restyle. Returns OK,
## or ERR_DOES_NOT_EXIST when no sheet of the document has that origin.
func reload_stylesheet(origin: String, text: String) -> int
## Replace the document text. Elements whose (path, open_tag_start, tag)
## survive keep their controls, view data, focus and running transitions.
func replace_source(uxml: String) -> int
```

**Use case.** Every edit re-renders the whole document (`render()`), and
typing in the source view re-renders at each pause. The full reload costs
10-600 ms on the fixtures and resets scroll offsets, focus and
transitions. A USS edit only needs a restyle; an attribute edit only needs
`UxmlElement.set_attribute()` on the matching element.

## R5. All cascade candidates of a property (P2)

```gdscript
# UxmlDocument
## Every declaration of `property` that matches `element`, winner first:
## [{value, winner: bool, rank: "theme"|"author"|"inline",
##   specificity: Vector3i, order: int,
##   origin: {kind: "rule", file, sheet, item, decl_index} | {kind: "inline", decl_index}
##         | {kind: "inherited", from: UxmlElement, origin} | {kind: "default"}}]
## `states` forces pseudo-states for the query only ({"hover": true}).
func explain_style(element: UxmlElement, property: String, states: Dictionary = {}) -> Array
```

**Use case.** The provenance inspector shows which rule a value comes from,
the rules it overrides, and offers each authored rule as a write target
(`docs/adr/0004-style-write-targets.md`). The computed style already gives
the winning origin (`{kind: "rule", file, sheet, item, decl_index}`); the
editor maps `item` and `decl_index` to exact spans with `EdUssSource`. The
losing candidates and the specificity are not exposed.

Please also document the `inline` origin shape and the shorthand case (a
longhand that comes from a `margin` declaration).

## R6. Forced pseudo-states (P2)

```gdscript
# UxmlDocument
## States that stay on until cleared, whatever the input does. Transitions
## run as for a real state change.
func set_forced_states(element: UxmlElement, states: PackedStringArray) -> void
func get_forced_states(element: UxmlElement) -> PackedStringArray
func clear_forced_states() -> void
```

**Use case.** State preview (`:hover`, `:active`, `:focus`, `:checked`,
`:disabled`) on the canvas without the pointer, and the state-machine
panel. `set_element_state()` works by name, and the next real
`mouse_exited` clears the state.

## R7. Transition snapshot and seek (P2)

```gdscript
# UxmlDocument (with transitions_manual = true)
## Every running or pending transition:
## [{element: UxmlElement, property, from, to, start_time, delay, duration,
##   easing, elapsed}]
func get_transitions() -> Array
## Set every running transition to `seconds` after its start (scrub). Does
## not emit transition_end until playback passes the end.
func seek_transitions(seconds: float) -> void
```

**Use case.** The transition timeline (old roadmap issues #6-#11) shows
the tracks of a state change and scrubs them. `advance_transitions()`
only moves forward.

## R8. Hit-test (P2)

```gdscript
# UxmlDocument
## The deepest element at `point` (document coordinates). Applies
## transforms (rotate, scale, translate), overflow clipping and, when
## `respect_picking` is true, picking-mode.
func element_at(point: Vector2, respect_picking: bool = false) -> UxmlElement
```

**Use case.** Canvas selection. **Workaround.** `EdRenderHost.hit_test()`
tests control rectangles cut by clipping ancestors. A rotated or scaled
element hits at its untransformed rectangle.

## R9. Catalog of supported elements (P2)

```gdscript
# UxmlControls (static)
## [{namespace: "UnityEngine.UIElements" | "UnityEditor.UIElements",
##   name, container: bool, attributes: [{name, type, default}], editor_only: bool}]
static func catalog() -> Array
```

**Use case.** The palette lists every element that godot-uxml supports,
and the inspector offers the attributes of the selected control.

## R10. Template instance of a cloned element (P3)

```gdscript
# UxmlDocumentModel
## The <Instance> (TemplateContainer) element whose expansion made
## `element`, or null for an element of the entry file.
func instance_of(element: UxmlElement) -> UxmlElement
```

**Use case.** A click on template content selects the instance in the
entry document. **Workaround.** Walk `_parents` up to the first element
that is not in `element_paths`.

## R11. End offsets on every diagnostic (P3)

Every diagnostic gets `end_offset` (parser warnings have one today; cascade
and runtime diagnostics do not).

**Use case.** The diagnostics panel highlights the exact range in the
source view.
