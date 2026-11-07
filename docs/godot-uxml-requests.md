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
| R1 | P1 | done in `6137987` | Load from text with a caller resolver |
| R2 | P1 | done in `6137987` | Element-handle lookups |
| R3 | P1 | done in `6137987` (documented, tested) | Stable source offsets on `UxmlElement` |
| R4 | P2 | done in `6137987` | Partial reload of one stylesheet or one document |
| R5 | P2 | done in `6137987` | All cascade candidates of a property |
| R6 | P2 | done in `6137987` | Forced pseudo-states on an element |
| R7 | P2 | done in `6137987` | Transition snapshot and seek |
| R8 | P2 | done in `6137987` | Hit-test that respects transforms and clipping |
| R9 | P2 | done in `6137987` | Catalog of supported elements and attributes |
| R10 | P3 | done in `6137987` | Template instance of a cloned element |
| R11 | P3 | done: `end_offset` in `6137987`, severity in `dc2c081` | End offsets and a severity on every diagnostic |
| R12 | P2 | done in `6137987` | Drag and drop for collection items |
| R13 | P3 | fixed in `6137987` | `background-image: none` on a checked ToolbarToggle |
| R14 | P3 | done in `6137987` | Rectangle of an element in another element's space |
| R15 | P2 | text and `display` parts done in `dc2c081`; build cost open | Build cost of a document; text updates without a layout |
| R16 | P3 | done in `dc2c081` | Context menu at a point, in the look of the owner document |
| R17 | P3 | text values done in `1167eb1`; Toggle open | Value updates of field controls without a restyle |
| R18 | P3 | done in `1167eb1`; not used yet (R28) | Elide the placeholder of a text field |
| R19 | P3 | done in `1167eb1` | Runtime classes of an element; finish all transitions |
| R20 | P3 | done in `1167eb1` | Public easing, shorthand and elision helpers |
| R21 | P3 | done in `1167eb1` | A signal when a split view changes size |
| R22 | P3 | done in `1167eb1` | Text changes that are stable inside a ScrollView, and a unitless `flex-basis: 0` |
| R23 | P3 | not changed (Unity does the same); `clear_completed_transitions` in `1167eb1` | A completed transition after an instant change stops a later run |
| R24 | P3 | done in `1167eb1` | The selected row of a list without focus in the editor skins |
| R25 | P2 | done in `1167eb1` | A stylesheet reload that restyles only what the edit can change |
| R26 | P3 | done in `1167eb1` | The transitions of a state change, without the change |
| R27 | P2 | open (workaround) | A TextField that is not `is-delayed` loses its caret at each change |
| R28 | P3 | open (workaround) | A placeholder update without a restyle |
| R29 | P2 | open (workaround) | A scroll of a collection view lays out the whole document |

The editor pins godot-uxml `1167eb1` (github.com/splatterfacegames/godot-uxml),
which has R1-R14, R16, R18-R22, R24-R26, the text and `display` parts of R15,
the text part of R17, and `clear_completed_transitions` for R23. The
sections of the done requests give the final API and where the editor uses
it. The open requests keep their workaround notes.

## R1. Load from text with a caller resolver (P1, done)

```gdscript
# UxmlDocument
func load_source(uxml: String, virtual_path: String = "res://__uxml_source__.uxml",
		root: String = "", resolver: UxmlResourceResolver = null) -> int
func load_document(path: String, root: String = "", resolver: UxmlResourceResolver = null) -> int
```

With a resolver, the load reads every file through it and `root` is not
used. `reload()`, `replace_source()` and `reload_stylesheet()` keep the
resolver.

**Editor use.** `EdRenderHost.render()` passes `EdBufferResolver`; the
host updates the overrides of the resolver before each partial update.
The copy of the body of `load_source()` is gone.

## R2. Element-handle lookups (P1, done)

```gdscript
# UxmlDocument
func get_document_model() -> UxmlDocumentModel
func get_control_for(element: UxmlElement) -> Control
func get_native_for(element: UxmlElement) -> Control
func get_element_for(control: Control) -> UxmlElement   # can be a part: follow part_of
func get_parent_element(element: UxmlElement) -> UxmlElement
func get_computed_style_for(element: UxmlElement) -> Dictionary
func set_element_state_for(element: UxmlElement, state: String, on: bool) -> void
```

**Editor use.** `EdRenderHost` (element map, controls, computed style,
parents). No private field of godot-uxml is read.

## R3. Stable source offsets on `UxmlElement` (P1, done)

godot-uxml documents and tests the offsets (design.md, "Source offsets
(contract)"). Differences from the request:

- a template clone carries the offsets of the **outermost `<Instance>`**
  of the entry file, not offsets in the template file;
  `UxmlDocumentModel.source_offset_of(el)` gives the offset in the
  template file and `path_of(el)` the file;
- a control part carries the offsets of its control element.

**Editor use.** `EdRenderHost._map()` skips parts and clones
(`instance_of(el) != null`), so a clone never maps to the `<Instance>` by
offset; `node_of()` maps a clone to its instance. `<Instance>` elements
are `TemplateContainer` in the model and map by offset.
`tests/unit/test_source_parsers.gd` still checks both parsers.

## R4. Partial reload (P2, done)

```gdscript
# UxmlDocument
func reload_stylesheet(origin: String, text: String) -> int    # OK, ERR_DOES_NOT_EXIST
func replace_source(uxml: String) -> int
func get_last_replace_mode() -> String                         # "in-place" or "reload"
signal source_replaced(in_place)
```

`replace_source()` edits in place only when the element trees match and
only `class` and `style` values (or white space and comments) differ;
otherwise it loads again and moves the view state, the focus and the
forced states to the elements with the same name or tree position.

**Editor use.** `EdRenderHost.update()`: a changed stylesheet goes to
`reload_stylesheet()`, a changed entry or template to `replace_source()`.
The skeleton comparison and the model patch of the editor are gone.
Measured with `bench/frame_cost.gd` (3 runs each): the commit of a typing
pause on the 507-element document costs 300-500 ms (native) and 830-950
ms (GDScript) instead of 980-2040 ms and 2240-33100 ms.

## R5. All cascade candidates of a property (P2, done)

```gdscript
# UxmlDocument
func explain_style(element: UxmlElement, property: String, states: Dictionary = {}) -> Array
```

Each entry, winner first: `value`, `property` (the shorthand name when a
shorthand gave the value), `declared` (as written), `winner`, `status`
(`winner`, `overridden`, `dropped`, `keyword`, `inherited`, `default`),
`rank`, `specificity`, `order`, `origin` (`{kind: "rule", sheet, item,
decl_index, file[, states]}`, `{kind: "inline", decl_index}`, `{kind:
"inherited", from, origin}`, `{kind: "default"}`). The query takes a
longhand.

**Editor use.** `EdRenderHost.explain()` normalizes the origins;
`EdProvenance` makes the declaration list, `EdStyleTargets` the write
targets of ADR 0004, and the class editor checks which rules of a class
apply.

## R6. Forced pseudo-states (P2, done)

```gdscript
# UxmlDocument
func set_forced_states(element: UxmlElement, states: PackedStringArray) -> void
func get_forced_states(element: UxmlElement) -> PackedStringArray
func clear_forced_states() -> void
```

States: hover, active, focus, checked, selected, disabled, enabled.

**Editor use.** The state preview of the inspector
(`EdRenderHost.set_forced()`). The host keeps the states by editor node
id and sets them again after a full load.

## R7. Transition snapshot and seek (P2, done)

```gdscript
# UxmlDocument (with transitions_manual = true)
func get_transitions() -> Array          # entries also have `value` and `progress`
func seek_transitions(seconds: float) -> void
func get_transition_clock() -> float
```

**Editor use.** `EdTransitionPlayer` runs one state change for the
timeline (milestone 6). `get_transitions()` gives the tracks;
`seek_transitions()` runs at each scrub and playback frame. On the menu
fixture a scrub frame costs about 3.4 ms on the native path.

## R8. Hit-test (P2, done)

```gdscript
# UxmlDocument
func element_at(point: Vector2, respect_picking: bool = false, include_parts: bool = false) -> UxmlElement
```

A hit on a part gives its control element unless `include_parts`; null
when only the root is hit.

**Editor use.** `EdRenderHost.hit_test()` (`respect_picking = false`: the
editor selects what the author wrote). A hit on template content selects
the `<Instance>`.

## R9. Catalog of supported elements (P2, done)

```gdscript
# UxmlControls (static)
static func catalog() -> Array          # {namespace, name, container, editor_only, uxml_object,
                                        #  attributes: [{name, type, default[, choices]}]}
static func describe(element_name: String) -> Dictionary
```

**Editor use.** `EdElementCatalog.entries()` reads the catalog (without
UxmlObjects and `TemplateContainer`); the editor keeps only the library
groups, the order and the attributes of a new element. The inspector
shows enum choices and defaults of unset attributes, and the attribute
menu lists the catalog attributes of the element.

## R10. Template instance of a cloned element (P3, done)

```gdscript
# UxmlDocumentModel
func instance_of(element: UxmlElement) -> UxmlElement   # innermost; call again for outer ones
func source_offset_of(element: UxmlElement) -> int
func path_of(element: UxmlElement) -> String
```

**Editor use.** `EdRenderHost.node_of()` walks `instance_of()` to the
instance of the entry file.

## R12. Drag and drop for collection items (P2, done)

```gdscript
# UxmlDocument
func set_drag_and_drop(list_name: String, callbacks: Dictionary) -> int
	# {can_start_drag, setup_drag_and_drop, drag_and_drop_update, handle_drop}
func get_item_index_at(list_name: String, global_point: Vector2) -> int
func get_item_rect(list_name: String, index: int) -> Rect2
func get_drag() -> Dictionary
func cancel_drag() -> void
signal items_drag_started(element_name, indices, global_position)
signal items_drag_updated(element_name, global_position, target)
signal items_drag_ended(element_name, global_position, result)   # dropped, rejected, outside, canceled
```

An `"outside"` result (target `{}`) is a drop outside every collection
of the document. A reorderable TreeView now reports
`item_index_changed(element_name, id, parent_id)`.

**Editor use.** `EdDragController` gives the library and the hierarchy
the four callbacks; the canvas takes `"outside"` drops. The raw mouse
watch and the `get_list_rows()` row search are gone. The editor does not
set `reorderable`.

## R13. `background-image: none` on a checked ToolbarToggle (P3, fixed)

Fixed in `6137987`: `none` is a keyword, also in the checked state. The
Snap toggle of the editor shell no longer reports `missing-file`.

## R14. Rectangle of an element in another element's space (P3, done)

```gdscript
# UxmlDocument
func get_element_rect(element: UxmlElement, space: UxmlElement = null, box: String = "border") -> Rect2
	# box: "border", "padding" or "content"; transforms applied (bounding box)
func get_element_transform(element: UxmlElement, space: UxmlElement = null) -> Transform2D
```

**Editor use.** `EdRenderHost.rect_of()` (selection, snapping, drop
targets), `border_start()` (the padding box in the element's own space;
the computed-border workaround is gone) and `local_box_of()` (the canvas
draws the rotated outline of a transformed element).

## R11. End offsets and a severity on every diagnostic (P3, done)

```gdscript
UxmlDiagnostic.severity_of(kind: String) -> String   # "error", "warning" or "info"
# Each diagnostic has `severity` and `end_offset`.
```

**Editor use.** `EdDiagnostics.collect()` reads `severity` and `end_offset`
of each diagnostic. The map of the kinds in the editor is gone.
`EdDiagnostics.range_end()` stays for a diagnostic whose `end_offset` equals
its `offset` (no source text).

## R15. Build cost of a document; text updates without a layout (P2, partly done)

Done in `dc2c081`:

- A text change (`set_text`, a model `text` attribute) lays out only when the
  text can move an element. `var layout_count: int` counts the layout passes.
- A model `text` change reaches a Label or a Button control.
- A `display` change is one layout pass. The first interaction after a load
  has no settling layout.

**Editor use.** `EdUi.set_label()` calls `set_text()`. The direct write to the
Label control and the elision copy of the editor are gone. A label needs a
size that does not follow its text (request R22).

**Open: the build cost per control.** `load_document` is unchanged: about 0.5
ms native and 1.5 ms GDScript per control. The editor inspector (310 controls)
is built once and changes in place.

**Workaround of the `display` layout.** One layout pass of the inspector costs
about 7 ms native and 60 ms GDScript. `EdInspectorView._compact()` keeps every
row in the layout: a row that is not in use is `visibility: hidden`, and the
content below moves up with `translate` (a paint-only property). The cost is
scroll room below the last section: at most the unused rows.

## R16. Context menu at a point (P3, done)

```gdscript
# UxmlDocument
signal menu_chosen(index)
func show_context_menu(global_point: Vector2, items) -> UxmlPopupMenu
func get_context_menu() -> UxmlPopupMenu
func close_context_menu() -> void
func set_context_menu(element: UxmlElement, populate: Callable) -> void
```

**Editor use.** The hierarchy has `set_context_menu`, and the Edit commands
run from `menu_chosen`. The write-target questions and the helper menus of the
inspector use `show_context_menu`. The anchor `Control` of `UxmlPopupMenu.open`
is gone.

**Visual check.** In a real window (`docs/screenshots/m5-context-menu.png`,
`m4-target-picker.png`), and with a checked, a disabled, a hovered and a long
item, and at the corner of the window: the editor skin, the checkmark column,
separators, the hover colour, and the menu stays inside the window. No defect.

## R17. Value updates of field controls without a restyle (P3, partly done)

Done in `1167eb1`:

```gdscript
# UxmlDocument
func set_field_value(element_name: String, value: Variant, notify: bool = false) -> bool
func get_field_value(element_name: String) -> Variant
```

A text value runs no restyle. **Editor use.** The inspector, the From and To
fields of the timeline, and the Preview, States, Snap and state-preview
toggles write through `set_field_value`. The direct writes to the `LineEdit`
controls and the silent model writes of the values are gone.

**Open: a Toggle value still restyles** through `:checked`. A node of the
state-machine panel costs one layout of the inspector: 15.3 ms native and 68
ms GDScript on the menu fixture (`1167eb1`).

**Cost.** In a scratch document with 70 fields, 70 `set_field_value` calls
cost about 11 ms (native and GDScript) against about 1.6 ms for direct
`LineEdit` writes. Selection on the menu fixture went from 9.8 to 10.4 ms
(native) and from 16.7 to 18.3 ms (GDScript). Not a request yet.

## R18. Elide the placeholder of a text field (P3, done; not used yet)

Done in `1167eb1`: `text-overflow: ellipsis` on a single-line field elides its
placeholder, with the whole text as the tooltip.

**Editor use: none yet.** godot-uxml elides a placeholder that changes through
the model (`placeholder-text`), and a model change restyles the field. The
inspector changes about 70 placeholders per selection: 8 ms through the model
against 1.6 ms through the `LineEdit`. Request R28 asks for a placeholder
update without a restyle. Until then `EdUi.elided_placeholder()` shortens the
text, and the inspector sets it on the `LineEdit`.

## R19. Runtime classes of an element; finish all transitions (P3, done)

Done in `1167eb1`:

```gdscript
# UxmlDocument
func set_author_classes(element: UxmlElement, classes: PackedStringArray) -> void
func get_author_classes(element: UxmlElement) -> PackedStringArray
func finish_transitions() -> void
```

**Editor use.** `EdTransitionPlayer._apply` calls `set_author_classes`;
`_settle` calls `finish_transitions` (no end events, the clock stays). The
`merged_class` write and `advance_transitions(1.0e5)` are gone.

## R20. Public easing, shorthand and elision helpers (P3, done)

Done in `1167eb1`: godot-uxml documents `UssTransitions.easing`,
`UssProperties.EASING_MODES`, `UssTransitions.SHORTHANDS`,
`UxmlStyleApplier.elide_text` and `UxmlParts.merged_class` as API ("Public
helpers" in its design document), and `test_public_helpers` keeps them.

**Editor use.** `EdEasingCurve`, `EdEasingPicker`, `EdStateMachine` (through
the caller), the timeline and `EdUi.elided_placeholder` call these members.
The editor has no copies of them. `merged_class` is no longer used (R19).

## R21. A signal when a split view changes size (P3, done)

Done in `1167eb1`: `signal split_changed(view_name, dimension)` at the end of
a drag.

**Editor use.** `EdMain` saves the pane sizes on `split_changed` and at
close. The save after each release of the left mouse button is gone.

## R22. Text changes that are stable inside a ScrollView; a unitless `0` (P3, done)

Done in `1167eb1`: a Label stretched across the viewport of a vertical
ScrollView changes its text without a layout; `flex-basis: 0` is a px length.

**Editor use.** The `.line` row around each text line of the inspector is
gone: the labels are children of the sections. The sheets of the editor write
`flex-basis: 0`. The inspector still lays out nothing per selection
(`bench/frame_cost.gd`, column `lay.insp`).

## R23. A completed transition after an instant change stops a later run (P3, done)

Not changed in godot-uxml: Unity's source behaves the same way (godot-uxml
design document, "A completed transition after an instant change"). New in
`1167eb1`: `clear_completed_transitions()`.

**Editor use.** `EdTransitionPlayer.arm()` calls it before the change of each
run, so a run starts as if it were the first. The edge-kind test of the
state-machine panel checks every edge again, `checked>normal` included, and
`test_the_same_edge_twice_runs_twice` runs the sequence twice.

## R24. The selected row of a list without focus in the editor skins (P3, done)

Done in `1167eb1`: the dark editor skin has `rgb(77, 77, 77)`. The
`.panel-list` rule of `editor_shell.uss` is gone.

## R25. A stylesheet reload that restyles only what the edit can change (P2, done)

Done in `1167eb1`: `reload_stylesheet(origin, text)` restyles only the
elements of the changed rules when only declarations change, and
`get_last_reload_mode()` tells `"restyle"`, `"cascade"` or `"full"`. A
`transition-*`-only change applies nothing and lays out nothing.

**Editor use.** No code change for the reload itself. The render after a
timeline bar edit on the 507-element document (`bench/frame_cost.gd`):

| | native | GDScript |
| --- | --- | --- |
| `dc2c081` | 317 ms | 1079 ms |
| `1167eb1` (the frames of the release, write and render) | 59 ms | 480 ms |

The target is 100 ms (native), so the pause of 0.4 s before the render
(`EdMain.RELOAD_PAUSE`) is gone: the release of a bar drag writes and
renders in the same frame. The preview of the drag (`set_preview`) stays for
the frames of the drag.

## R26. The transitions of a state change, without the change (P3, done)

Done in `1167eb1`:

```gdscript
# UxmlDocument
func preview_transitions(element: UxmlElement, from_states: PackedStringArray, to_states: PackedStringArray) -> Array
```

**Editor use.** `EdRenderHost.preview_transitions()` keeps the entries of the
element itself; `EdStateMachine` takes the timing of each edge from it. The
derivation from the declarations and the computed values is gone. A property
that only the theme changes through `transition-property: all` now counts
(`test_a_theme_property_through_all_is_a_transition`). One build of the graph
costs more: 3.0 -> 3.8 ms (menu, native) and 3.0 -> 10.6 ms (large, native);
a build waits for a frame without a change.

## R27. A TextField that is not `is-delayed` loses its caret at each change (P2)

Each character typed into a TextField without `is-delayed` puts the caret at
position 0 after the restyle of the change, so "dupl" shows as "lpud". Seen
in a plain document with one `<ui:TextField>` at `dc2c081` and `1167eb1`, and
in the library search of the editor (a `ToolbarSearchField`). A field with
`is-delayed="true"` keeps its caret.

Request: keep the caret column of the `LineEdit` when the restyle of a value
change writes the same text.

**Workaround.** `EdUi.live_text()` reads the caret at `gui_input` (before the
`LineEdit` handles the key), and puts it back after the change and at the next
frame. The command palette search is `is-delayed`, and both searches read the
text through `LineEdit.text_changed`. Test:
`test_typing_in_the_library_search_keeps_the_order`.

## R28. A placeholder update without a restyle (P3)

```gdscript
# UxmlDocument
## Set the placeholder of a text field; no restyle when the size of the
## field does not change. R18 elides the new text.
func set_field_placeholder(element_name: String, text: String) -> bool
```

**Use case.** The inspector shows the computed value and its origin as the
placeholder of about 70 fields per selection (R18).

**Workaround.** `EdUi.elided_placeholder()` and a direct write to
`LineEdit.placeholder_text`, with the model attribute set without a change
notification (`EdUi.set_silent`).

## R29. A scroll of a collection view lays out the whole document (P2)

`scroll_to_item()` on a TreeView binds the visible rows again, and the next
restyle lays out the whole window document. On the 507-element document a
selection that scrolls the hierarchy costs about 32 ms native and 98 ms
GDScript, against 15 ms and 17 ms for a selection without the scroll
(scratch measure, two frames per selection). This was the unexplained window
layout of selection in milestone 7 (37 layouts per 60 selections).

Request: a scroll and a row rebind of a collection view with a fixed item
height lay out only the rows (the viewport has a fixed size).

**Workaround.** `EdMain._select_in_tree` scrolls only for a row outside the
view, and only after a frame without another selection, so a run of
selections scrolls once (`test_a_selection_outside_the_hierarchy_view_scrolls_once`).
