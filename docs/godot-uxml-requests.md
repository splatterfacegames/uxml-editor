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
| R15 | P2 | text and `display` parts done in `dc2c081`; build cost open (measured again in `f4ffe6e`) | Build cost of a document; text updates without a layout |
| R16 | P3 | done in `dc2c081` | Context menu at a point, in the look of the owner document |
| R17 | P3 | done: text values in `1167eb1`, Toggle values in `f4ffe6e`; a property subset open | Value updates of field controls without a restyle |
| R18 | P3 | done in `1167eb1`; used since `f4ffe6e` (R28) | Elide the placeholder of a text field |
| R19 | P3 | done in `1167eb1` | Runtime classes of an element; finish all transitions |
| R20 | P3 | done in `1167eb1` | Public easing, shorthand and elision helpers |
| R21 | P3 | done in `1167eb1` | A signal when a split view changes size |
| R22 | P3 | done in `1167eb1` | Text changes that are stable inside a ScrollView, and a unitless `flex-basis: 0` |
| R23 | P3 | not changed (Unity does the same); `clear_completed_transitions` in `1167eb1` | A completed transition after an instant change stops a later run |
| R24 | P3 | done in `1167eb1` | The selected row of a list without focus in the editor skins |
| R25 | P2 | done in `1167eb1`; selector and rule edits in `f4ffe6e` | A stylesheet reload that restyles only what the edit can change |
| R26 | P3 | done in `1167eb1` | The transitions of a state change, without the change |
| R27 | P2 | done in `f4ffe6e` | A TextField that is not `is-delayed` loses its caret at each change |
| R28 | P3 | done in `f4ffe6e` | A placeholder update without a restyle |
| R29 | P2 | done in `f4ffe6e` for FixedHeight rows; other cases open | A scroll of a collection view lays out the whole document |
| R30 | P3 | done in `5a51b92` | `set_field_placeholder` costs more than a write to the `LineEdit` |
| R31 | P3 | done in `5a51b92`; used (the winner row is bold again) | A font change of an element whose size does not follow its text lays out the document |
| R32 | P2 | done in `5a51b92`; the library does not get it (R33) | A new source of a TreeView lays out the whole document |
| R33 | P2 | open | The hidden pooled rows of a collection view count as elements of its subtree |
| R34 | P3 | open | The cancel button of a search field lays out the document |

The editor pins godot-uxml `5a51b92` (github.com/splatterfacegames/godot-uxml),
which has R1-R14, R16-R22, R24-R32, the text and `display` parts of R15, and
`clear_completed_transitions` for R23. The sections of the done requests give
the final API and where the editor uses it.

Open upstream (no editor workaround):

- R15: the build cost per control (about 0.5 ms native and 1.5 ms GDScript).
  godot-uxml measured it again in `f4ffe6e` and changed nothing.
- R17: a state change computes every property of the elements that it
  reaches; the `:checked` rules set few. About 0.03 ms of a 0.9 ms update.
- R29: a DynamicHeight row, a row of a view that scrolls horizontally and a
  change of the row element itself (its own padding or `display`) still lay
  out the whole document. The hierarchy, the library, the project list and
  the diagnostics have FixedHeight rows.
- R33: the library search still lays out the whole window document for each
  key. The library view has 415 of the 1,152 elements of the window: its pool
  has 56 rows, and only about 15 rows show. So the R32 subtree layout does not
  apply.
- R34: the first character and the last backspace in a search field lay out
  the whole window document (the cancel button changes `background-image`).

Rules of `5a51b92` (godot-uxml `docs/design.md`): code that moves or resizes
the control of an element directly calls `refresh()`, and a runtime state
change goes through `_queue_restyle()` (the public API does). The editor
moves or resizes no element control. The panes that the editor mounts are
children of the host controls, not element controls. The editor set
`clip_contents` on the hosts, which `.host` already sets with
`overflow: hidden`; that write is removed. The demo script wrote two
`LineEdit.text` values directly; the writes now go through
`set_field_value`.

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

## R17. Value updates of field controls without a restyle (P3, done)

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

**Toggle values: done in `f4ffe6e`.** A Toggle value restyles only the
subtree of the Toggle and lays out nothing. Before, a node of the
state-machine panel cost one layout of the inspector: 15.3 ms native and 68
ms GDScript on the menu fixture (`1167eb1`). After the pin, the bold winner
row of the declaration list still laid out the inspector (R31); without it,
forcing a state costs 16.2 ms GDScript on the menu fixture (65.7 ms before).
The figures are in `docs/roadmap.md` ("Re-pin to godot-uxml f4ffe6e").

**Open upstream: a property subset.** The cascade of a state change computes
every property of the elements that it reaches. About 0.03 ms native of a 0.9
ms update; not a need of the editor.

**Cost.** In a scratch document with 70 fields, 70 `set_field_value` calls
cost about 11 ms (native and GDScript) against about 1.6 ms for direct
`LineEdit` writes. Selection on the menu fixture went from 9.8 to 10.4 ms
(native) and from 16.7 to 18.3 ms (GDScript). Not a request yet.

## R18. Elide the placeholder of a text field (P3, done)

Done in `1167eb1`: `text-overflow: ellipsis` on a single-line field elides its
placeholder, with the whole text as the tooltip.

**Editor use (since `f4ffe6e`).** The inspector fields have
`text-overflow: ellipsis` (`.field` in `inspector.uss`) and get their
placeholder through `set_field_placeholder` (R28). godot-uxml elides the text
at the width of the field, also after a pane resize. `EdUi.elided_placeholder()`
and the refit of the inspector at a resize are gone. The fields have
`display-tooltip-when-elided="false"`: the inspector sets the tooltip itself
(the value, or the whole placeholder).

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

**Selector and rule edits (`f4ffe6e`).** `get_last_reload_mode()` can also
return `"rules"`: a selector or rule edit compiles the rules again in the same
cascade and computes only the elements that the changed rules match (above 32
changed rules, `"cascade"`). The controls and the forced states stay, as for
`"restyle"`. The editor does not branch on the mode: every mode of
`reload_stylesheet` keeps the controls. `EdRenderHost.last_modes` records the
mode of each file of the last update (tests and benchmarks).
`test_a_selector_edit_reloads_the_rules_in_place` checks that a selector edit
and a new rule take `"rules"`, keep the control and the forced state, and
apply the new rule.

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

## R27. A TextField that is not `is-delayed` loses its caret at each change (P2, done)

Each character typed into a TextField without `is-delayed` put the caret at
position 0 after the restyle of the change, so "dupl" showed as "lpud" (seen
at `dc2c081` and `1167eb1`).

Done in `f4ffe6e`: `UxmlTextInput.configure` writes only the properties that
change, and the model update of a value change does not configure the editor
again. The caret stays where the user typed.

**Editor use.** The library search (`palette-search`) and the command palette
search (`cp-search`) are live TextFields without `is-delayed`, and the editor
reads them through `value_changed`. The workaround `EdUi.live_text()` (the
caret read at `gui_input` and put back at the next frame) is gone. Tests, on
both paths: `test_typing_in_the_library_search_keeps_the_order` and
`test_typing_in_the_command_palette_keeps_the_order` (keys through
`Viewport.push_input`).

## R28. A placeholder update without a restyle (P3, done)

Done in `f4ffe6e`:

```gdscript
# UxmlDocument
func set_field_placeholder(element_name: String, text: String) -> bool
func get_field_placeholder(element_name: String) -> String
```

`placeholder-text` is not an input of the cascade, so no restyle runs. A
layout runs only when the minimum size of the `LineEdit` changes. R18 elides
the new text.

**Editor use.** The inspector sets the computed value and its origin (about
70 fields per selection) with `set_field_placeholder`, and
`EdInspectorView.placeholder_of()` reads `get_field_placeholder`. The value
hint of the add row and the placeholder of the command palette search per
mode use it too. `EdUi.elided_placeholder()`, `EdUi.set_silent()` and the
direct writes to `LineEdit.placeholder_text` are gone.

## R29. A scroll of a collection view lays out the whole document (P2, done for FixedHeight rows)

`scroll_to_item()` on a TreeView bound the visible rows again, and the next
restyle laid out the whole window document. On the 507-element document a
selection that scrolled the hierarchy cost about 32 ms native and 98 ms
GDScript (`1167eb1`).

Done in `f4ffe6e`: a rebind of rows (a scroll, a selection, a new source)
lays out only the rows when a row has a fixed size (a FixedHeight row of a
vertical view). `layout_count` does not count these layouts;
`local_layout_count` counts them.

**Editor use.** No code change was necessary. The window layouts of 60 scroll
frames of the hierarchy on the 507-element document went from 61 to 1. The
rebind of the rows still costs about 16 ms native and 50 ms GDScript, so
`EdMain._select_in_tree` keeps the scroll for a row outside the view, after a
frame without another selection.
`test_a_selection_outside_the_hierarchy_view_scrolls_once_without_a_layout`:
five selections that scroll keep `layout_count` and raise
`local_layout_count`; a run of selections scrolls once.

**Open upstream.** A DynamicHeight row, a row of a view that scrolls
horizontally and a change of the row element itself still lay out the whole
document. The editor has none of these.

## R30. `set_field_placeholder` costs more than a write to the `LineEdit` (P3)

The inspector sets about 70 placeholders per selection. A scratch measure on
the menu fixture (60 selections, the state-machine panel open, `f4ffe6e`),
ms per frame:

| Placeholder write | native | GDScript |
| --- | --- | --- |
| `set_field_placeholder` (R28, with the R18 elision) | 20.3-22.6 | 70.0-71.5 |
| `set_field_placeholder` of a text that the editor elided (no `text-overflow`) | 17.6 | 62.8-64.0 |
| a direct write to `LineEdit.placeholder_text` | 13.6-16.6 | 49.0-54.9 |
| no placeholder write | 15.4-16.0 | 53.3-55.2 |

So most of the cost is the write itself (`bind_write`), not the elision. The
editor uses `set_field_placeholder` (the model and the control stay the
same). The selection of the menu fixture went from 11.8 to 14.3 ms (native)
and from 18.3 to 20.2 ms (GDScript) in `bench/frame_cost.gd`.

Request: a placeholder write that costs about as much as the `LineEdit`
write (about 0.02 ms per field) when the minimum size of the field does not
change, for example a write of the control and the attribute without the
behavior's whole `bind_write`.

**Done in `5a51b92`.** `set_field_placeholder` with the text that the field
already has writes nothing. A new placeholder of a field that elides is
written once, elided.

**Editor use.** No code change: `EdInspectorView._value()` already skipped a
write of the same text. On the menu fixture a selection changes about 6
placeholders, not 70. A scratch measure (60 selections, native): the
synchronous part of `select_node` is 1.4 ms on both pins, also with direct
`LineEdit` writes. So the placeholders are not the cost of a selection frame
(about 15-16 ms on the menu fixture on both pins). The profile of the
restyles of a selection (`UxmlDocument.profile`): the layout went from about
4.5-5.8 ms to 2.7-3.8 ms; the control applies (about 6-9 ms) are the larger
part now. The 11.8 ms of the earlier run did not come back: an A/B run of the
old pin on the same machine gives 15.3 ms (`docs/roadmap.md`, "Re-pin to
godot-uxml 5a51b92").

## R31. A font change of an element whose size does not follow its text lays out the document (P3)

The rows of the declaration list (`.link.prov`, `height: 18px`, stretched in
a column) changed `-unity-font-style` with their status class (bold for the
winner). A font change is not paint-only, so each change laid out the whole
inspector: forcing a state in the state-machine panel cost 28 layouts in 60
frames, about 25 ms on GDScript each.

**Workaround.** The winner row has no `-unity-font-style`; it has a brighter
colour (`.status-winner` in `inspector.uss`). Test:
`test_forcing_states_lays_out_no_inspector`.

Request: a change of `-unity-font-style`, `-unity-font` or `font-size` on an
element whose two axes are fixed (the rule of `_text_stable` and
`_fixed_axis`) runs no layout, or lays out only its subtree, as a text change
does (R15).

**Done in `5a51b92`.** A change of a text-measure property
(`-unity-font-style`, `-unity-font`, `font-size`, the spacings) on an element
whose two axes are fixed lays out the subtree of the element.

**Editor use.** `.status-winner` in `inspector.uss` has
`-unity-font-style: bold` again. Forcing a state lays out no inspector
(`test_forcing_states_lays_out_no_inspector` also checks that the winner row
is bold). The cost of the bold row, `bench/frame_cost.gd` "states: force a
node", median of the runs: native +0.7 ms on the menu fixture (13.5 -> 14.2,
5 runs) and +0.9 ms on the large document (16.9 -> 17.8, 4 runs); GDScript no
change (17.8 -> 17.4 menu, 110 -> 102 large).

## R32. A new source of a TreeView lays out the whole document (P2)

Each key in the library search filters the library: `set_tree_source` with
the new items and `set_tree_item_expanded` for each group. Each key lays out
the whole window document twice (`bench/frame_cost.gd`, "typing in the
library search": 120 window layouts in 60 frames). A key costs about 15-17
ms native and 88-96 ms GDScript (the browser) on both pins. The rows have a
fixed height, and the tree view has a fixed size in its pane.

Request: a new source and an expand of a collection view with FixedHeight
rows in a view of a fixed size lay out only the rows, as R29 does for a
scroll.

**Done in `5a51b92`.** A change inside a collection view (a new source, an
expand) whose border box cannot follow its content lays out the subtree of
the view.

**Editor use.** No code change. The library does not get the subtree layout
(R33): the window document still lays out twice per key (120 layouts in 60
frames). A key costs 13.3 ms native (15.8 ms before) and about 81 ms
GDScript (no change) on the menu fixture.

## R33. The hidden pooled rows of a collection view count as elements of its subtree (P2)

godot-uxml builds the rows of a collection view at load, for the tallest
viewport (`UxmlContainerParts.pool_height`, at least 1080 px): 56 rows of
20 px. The rows that do not show are `display: none`. The window document of
the editor has 1,152 elements; the library TreeView has 415 of them, but only
about 15 rows show (a 278 px view). `_add_local()` lays out the document when
the roots cover a third of the document, and counts the hidden rows. So a new
source of the library (each key in the library search) lays out the whole
window document. The layout leaves the document unsettled, so the next
restyle lays out the document again.

A scratch measure without the third-of-the-document check (the library then
gets a subtree layout): native 13.5 -> 23.4 ms per key, GDScript 83.6 -> 73.8
ms. So on the native path a subtree layout of the 56 rows costs more than a
layout of the whole document with the cross-pass cache.

Request: the subtree layout of a collection view and the third-of-the-document
check count only the rows that show (or skip the `display: none` rows), so a
new source of a view in a fixed pane costs about one layout of its visible
rows. The files list, the hierarchy and the diagnostics have the same pool.

## R34. The cancel button of a search field lays out the document (P3)

The first character in a `ToolbarSearchField` and the backspace that empties
it change `background-image` of the cancel button
(`unity-search-field-base__cancel-button`, a `Button`). `background-image` is
paint-only only on a `UxmlBox` (Style application), so the change lays out
the whole window document (`bench/frame_cost.gd`, "typing in the library
search": 60 of the 120 window layouts; one layout per key in a scratch run
without the R33 check).

Request: a `background-image` change of a control whose size does not follow
the image (a fixed size, or a button with a fixed size in the theme) runs no
layout, or lays out only the subtree of the control.

