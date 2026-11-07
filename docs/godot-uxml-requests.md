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
| R4 | P2 | patch for `style`/`class`, else full reload | Partial reload of one stylesheet or one document |
| R5 | P2 | winner only | All cascade candidates of a property |
| R6 | P2 | none | Forced pseudo-states on an element |
| R7 | P2 | none | Transition snapshot and seek |
| R8 | P2 | workaround (transforms applied) | Hit-test that respects transforms and clipping |
| R9 | P2 | static table | Catalog of supported elements and attributes |
| R10 | P3 | workaround | Template instance of a cloned element |
| R11 | P3 | workaround (editor finds the end) | End offsets and a severity on every diagnostic |
| R12 | P2 | workaround | Drag and drop for collection items |
| R13 | P3 | bug | `background-image: none` on a checked ToolbarToggle |
| R14 | P3 | workaround | Rectangle of an element in another element's space |
| R15 | P2 | workaround (in-place updates) | Build cost of a document; text updates without a layout |
| R16 | P3 | workaround | Context menu at a point, in the look of the owner document |

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

**Workaround (2026-11-07).** `EdRenderHost.patch()` handles the common
case: when the only change of the entry buffer is the value of a `style`
or `class` attribute of rendered elements (or such an attribute added or
removed), the new values go to the godot-uxml model through
`UxmlElement.set_attribute()` and the document restyles itself. Canvas
drags, nudges and inline style edits take this path. Measured with
`bench/frame_cost.gd`: a move step on a 507-element document costs about
25 ms (restyle and layout) instead of about 850 ms (full reload), native
path. A USS edit, a structure edit or another attribute still reloads the
whole document.

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

**Use case.** Canvas selection, drop targets. **Workaround.**
`EdRenderHost.hit_test()` tests the point in the local space of each
control and of every clipping ancestor (`get_global_transform()`), so
rotate, scale and translate apply because godot-uxml sets them on the
Control transform. `picking-mode` is not applied (the editor selects what
the author wrote). The workaround depends on the private `_controls` and
`_parents` maps (R2).

## R9. Catalog of supported elements (P2)

```gdscript
# UxmlControls (static)
## [{namespace: "UnityEngine.UIElements" | "UnityEditor.UIElements",
##   name, container: bool, attributes: [{name, type, default}], editor_only: bool}]
static func catalog() -> Array
```

**Use case.** The palette lists every element that godot-uxml supports,
and the inspector offers the attributes of the selected control.

**Workaround.** `src/core/element_catalog.gd` (`EdElementCatalog`) is a
static table with the namespace, the library group, a container flag and
the default attributes of a new element. `tests/unit/test_structure_commands.gd`
compares it with `UssControls.IMPLICIT_CLASSES` and renders every entry.
Please add `container: bool` (the element takes authored children) and,
per attribute, an `enum` value list; the palette and the inspector need
both. To adopt R9, make `EdElementCatalog.entries()` read the catalog.

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

## R12. Drag and drop for collection items (P2)

```gdscript
# UxmlDocument
## A drag of selected items started (Unity CanStartDrag / SetupDragAndDrop).
signal items_drag_started(element_name, indices, global_position)
## The visible item index and its global rectangle at a point, or -1.
func get_item_index_at(list_name: String, global_point: Vector2) -> int
func get_item_rect(list_name: String, index: int) -> Rect2
```

**Use case.** The library and the hierarchy start drags; the hierarchy is
also a drop target (before, into, after a row).

**Workaround.** `EdDragController` watches the raw mouse events of the
window, finds rows with `get_list_rows()` and `UxmlListRow.get_element()`
(public), and draws its own drag label and drop line. A `reorderable`
list moves items itself; the editor does not set `reorderable`.

## R13. `background-image: none` on a checked ToolbarToggle (P3, bug)

A `uie:ToolbarToggle` with `value="true"` in the editor dark skin reports
`missing-file: background-image "none" resolved to
res://addons/godot_uxml/themes/none but is not a readable image` (the
theme sheets set `background-image: none`, for example
`unity-editor-dark.uss` line 421). `none` is a keyword, not a path.
The editor shell shows the warning for its Snap toggle.

## R14. Rectangle of an element in another element's space (P3)

```gdscript
# UxmlDocument
## The border box of `element` in the coordinates of `space` (null: the
## document), as Unity WorldToLocal / ChangeCoordinatesTo.
func get_element_rect(element: UxmlElement, space: UxmlElement = null) -> Rect2
```

**Use case.** Snap targets, drop indicators and the absolute `left`/`top`
fallback need the rectangles of the parent, the siblings and the
children, and the parent border. **Workaround.** `EdRenderHost.rect_of()`
reads `Control.get_global_rect()` of the private control map (R2), and
`border_start()` reads the computed border widths.

## R11. End offsets and a severity on every diagnostic (P3)

Every diagnostic gets `end_offset` (parser warnings have one today; cascade
and runtime diagnostics do not) and `severity` ("error", "warning",
"info").

**Use case.** The diagnostics panel selects the exact range in the source
view and filters by severity.

**Workaround.** `EdDiagnostics.range_end()` finds the end: the open tag of
an element that starts at the offset, the attribute that holds the offset,
or the token. `EdDiagnostics.severity_of()` maps the kinds: `malformed`,
`import-*`, `missing-file`, `path-outside-root`, `malformed-reference` and
`template-*` are errors, `version-dependent` is info, the others are
warnings.

## R15. Build cost of a document; text updates without a layout (P2)

Measured on the editor inspector, a generated document of 310 controls
(rows of `TextField` and `Button` in `Foldout` sections, editor theme):

| Step | Native | GDScript |
| --- | --- | --- |
| `_index()` (build the controls) | 160-290 ms | 430-460 ms |
| first `_restyle_now()` | 120-160 ms | 430-550 ms |
| a `display` change of one row (restyle and layout) | 6 ms, then 12 ms in the next frame | 60 ms, then 90 ms in the next frame |
| a `label` change of one `TextField` | 4 ms | 70 ms |
| a paint-only class change (`color`) | 1.4 ms | 10 ms |
| `visibility` change | 1 ms | 4 ms |

A 507-element document (12 panels of labels, buttons, toggles and text
fields) loads in about 850 ms on the native path.

Requests:

1. Lower the build cost per control (about 0.5 ms native and 1.5 ms
   GDScript per control today).
2. `UxmlDocument.set_text()` lays out the whole document. A Label whose
   size does not depend on its text (fixed width, or stretched by its
   parent) needs no layout.
3. A `text` change of the model (`UxmlElement.set_attribute("text", ...)`)
   is not applied to a Label or a Button control. `label` on a field is.
4. A `display` change lays out twice (the second pass in the next frame,
   `_unsettled`).

**Workaround.** The inspector builds its document once and changes it in
place (`EdInspectorView`): values and placeholders go straight to the
`LineEdit` controls, labels of fixed size straight to the `Label`
controls (`EdUi.set_label()`), and the model attributes change without a
change notification (`EdUi.set_silent()`). Rows that are not in use are
`visibility: hidden`, so a new selection needs no layout. Window labels
that change often (status, history, source state, zoom) have a size that
does not depend on the text, for the same fast path.

## R16. Context menu at a point (P3)

```gdscript
# UxmlDocument
## A menu at `global_point` with `items` (Unity DropdownMenu /
## ContextualMenuManipulator). Emits menu_chosen(index). The menu uses the
## theme and the editor skin of this document.
func show_context_menu(global_point: Vector2, items: PackedStringArray) -> void
```

**Use case.** The hierarchy context menu (the Edit commands).

**Workaround.** `UxmlPopupMenu.open()` under a `Control` anchor at the
pointer (its width sets the menu width). The menu takes the theme path of
the shell document but not its editor theme and skin, so it has the
runtime look in the editor window (the same as the menus of `ToolbarMenu`
elements).
