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
| R17 | P3 | open (workaround) | Value updates of field controls without a restyle |
| R18 | P3 | open (workaround) | Elide the placeholder of a text field |
| R19 | P3 | open (workaround) | Runtime classes of an element; finish all transitions |
| R20 | P3 | open (workaround) | Public easing, shorthand and elision helpers |
| R21 | P3 | open (workaround) | A signal when a split view changes size |
| R22 | P3 | open (workaround) | Text changes that are stable inside a ScrollView, and a unitless `flex-basis: 0` |
| R23 | P3 | open (workaround) | A completed transition after an instant change stops a later run |
| R24 | P3 | open (workaround) | The selected row of a list without focus in the editor skins |
| R25 | P2 | open (workaround) | A stylesheet reload that restyles only what the edit can change |
| R26 | P3 | open (workaround) | The transitions of a state change, without the change |

The editor pins godot-uxml `dc2c081` (github.com/splatterfacegames/godot-uxml),
which has R1-R14, R16, R11 and the text and `display` parts of R15. The
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

## R17. Value updates of field controls without a restyle (P3)

```gdscript
# UxmlDocument
## Set the value of a field (TextField, Toggle, DropdownField, ColorField,
## ...) as the user would, without a change notification and without a
## restyle when the size of the control does not change.
func set_field_value(element_name: String, value: Variant, notify: bool = false) -> void
```

**Use case.** The inspector shows the value of every row for each
selection. A model `value` change restyles the field (about 4 ms native,
70 ms GDScript, see R15), so the typed helpers of the inspector are
buttons with menus, not DropdownFields with the current value, and the
colour swatch is a tinted button.

**Workaround.** Text values go to the `LineEdit` controls (`EdUi`);
Toggle values (the state preview) go through the model; the colour
swatch is the `self_modulate` of a Button control. A Toggle value costs one
layout of the inspector: a node of the state-machine panel costs 13 ms native
and 60 ms GDScript on the menu fixture.

## R18. Elide the placeholder of a text field (P3)

`text-overflow: ellipsis` elides a Label or a Button. The placeholder of a
TextField is cut off at the edge of the `LineEdit`.

Request: elide the placeholder of a field with `text-overflow: ellipsis`,
and show the whole text as the tooltip.

**Use case.** The inspector shows the computed value and its origin as the
placeholder: `180px   ← Menu.uss`.

**Workaround.** `EdUi.elided_placeholder()` shortens the text with
`UxmlStyleApplier.elide_text`. The inspector does this at each value change
and when the fields change width.

## R19. Runtime classes of an element; finish all transitions (P3)

```gdscript
# UxmlDocument
## The author classes of `element` at runtime; the classes that the control
## adds stay.
func set_author_classes(element: UxmlElement, classes: PackedStringArray) -> void
## End every running transition at its end value, now.
func finish_transitions() -> void
```

**Use case.** A timeline run shows a From state and a To state of an
element, with no source edit, and needs a start state without transitions.

**Workaround.** `EdTransitionPlayer._apply` sets the `class` attribute of
the model to `UxmlParts.merged_class(el, author)`. `_settle` calls
`advance_transitions(1.0e5)`, which also emits end events and moves the
clock.

## R20. Public easing, shorthand and elision helpers (P3)

The editor calls these static members of godot-uxml. The design document
does not list them as API, so a change in godot-uxml can break the editor:

| Member | Editor use |
| --- | --- |
| `UssTransitions.easing(mode, t)` | `EdEasingCurve` |
| `UssProperties.EASING_MODES` | the easing picker |
| `UssTransitions.SHORTHANDS` | the entry of a track in a `transition-property` list |
| `UxmlStyleApplier.elide_text()` | `EdUi` (R15, R18) |
| `UxmlParts.merged_class()` | `EdTransitionPlayer` (R19) |

Request: document these members as API, or give public equivalents.

## R21. A signal when a split view changes size (P3)

```gdscript
# UxmlDocument
signal split_changed(view_name: String, dimension: float)  # at the end of a drag
```

**Use case.** The editor keeps the pane sizes per user.

**Workaround.** `EdMain.save_splits()` reads `get_split_dimension()` of the
seven views after each release of the left mouse button, and at close.

## R22. Text changes that are stable inside a ScrollView; a unitless `flex-basis: 0` (P3)

`_text_stable` treats two cases as "the text can move an element", so a
`set_text()` lays out the whole document (on the inspector: 4.4 ms native,
30 ms GDScript per selection):

1. A Label that stretches across a column inside a ScrollView. The content
   container of a ScrollView is not definite on its cross axis, also without a
   horizontal scroller.
2. `flex-basis: 0`. `_is_px()` needs the unit; only `0px` counts.

Request: a ScrollView without horizontal scrolling has a definite content
width; `0` counts as a length.

**Workaround.** Each text line of the inspector is a Label with `flex-basis:
0px` in a row (`.line` in `inspector.uss`). The sheets of the editor write
`0px`.

## R23. A completed transition after an instant change stops a later run (P3)

`UssTransitions._start` keeps a completed transition per element and property.
A later change with `combined <= 0` returns before it removes the entry, so a
later change to the same end value starts nothing:

```
.a { min-width: 100px; transition: min-width 1s; }
.a:checked { min-width: 300px; transition-duration: 0s; }
hover -> normal (completes to 100px), normal -> checked (instant),
checked -> normal: no transition starts (the entry still says 100px).
```

**Use case.** A run of the timeline after other runs of the same element shows
no track. CSS removes a completed transition when the after-change style
differs from its end value.

**Workaround.** None. Another selection or a render starts clean; the edge of
the state-machine panel keeps its kind, and the timeline says that no
transition runs.

## R24. The selected row of a list without focus in the editor skins (P3)

`.unity-collection-view__item--selected` is `rgb(174, 174, 174)` in
`unity-default-containers.uss`, and the editor skins do not override it. With
the light text of the dark skin, the row is hard to read. The Unity dark skin
uses `rgb(77, 77, 77)`.

**Workaround.** A rule in `editor_shell.uss` for `.panel-list`.

## R25. A stylesheet reload that restyles only what the edit can change (P2)

`reload_stylesheet()` rebuilds the cascade and applies every control again. On
the 507-element document:

| Step of the render after one `transition-delay` edit | Native | GDScript |
| --- | --- | --- |
| `reload_stylesheet` and the element map | 157 ms | |
| the restyle that the next `get_transitions` runs, and the arm of the run | 128 ms | |
| the whole frame | 312-408 ms | 1090 ms |

The same edit on the menu fixture: 14 ms native, 18 ms GDScript.

Request: when only declarations change and the selectors stay, keep the rule
matches and restyle only the elements of those rules. A change of only
`transition-*` declarations needs no apply and no layout.

**Workaround.** A timeline bar drag writes once, at its end, and the render
waits for a pause of 0.4 s (`EdMain.RELOAD_PAUSE`). The canvas shows the new
values through the model until then (`EdTransitionPlayer.set_preview`). The
frame of the render itself still costs what this table says.

## R26. The transitions of a state change, without the change (P3)

```gdscript
# UxmlDocument
## What get_transitions() would list after a change of `element` from
## `from_states` to `to_states`, without the change.
func preview_transitions(element: UxmlElement, from_states: PackedStringArray, to_states: PackedStringArray) -> Array
```

**Use case.** The state-machine panel draws an edge with a transition
differently from an instant change.

**Workaround.** `EdStateMachine` compares the computed values of the two states
(`explain_style`), reads the `transition-*` values of the state that the change
goes to, and treats `auto`, `none` and an unset value as instant, as
`UssTransitions._start` does. Limits: a property that only the theme changes
counts only when `transition-property` names it, not through `all`. A test
compares the kinds with real runs.
