# Architecture

The editor is a Godot 4.7 application. godot-uxml renders the edited
document, and godot-uxml also renders most of the editor window. The
source text of each file is the truth: every edit is a patch against the
exact text, and the rendered document is rebuilt from that text.

The previous editor (React, Tauri, a vendored `uxml-preview` engine) is on
`main`. ADR 0006 records why the host changed.

## Layers

```
┌───────────────────────────────────────────────────────────────────────┐
│ src/app/       Editor window and views                               │
│                main.gd            composition root, shortcuts, saves,│
│                                   questions, disk watch timer        │
│                editor_state.gd    project, tabs, selection, one      │
│                                   history, journal, refusals         │
│                canvas_view.gd     SubViewport, pan/zoom, overlay,    │
│                                   handles, guides, preview input     │
│                layout_controller  canvas gestures -> layout writes   │
│                drag_controller    drag and drop (godot-uxml R12)     │
│                palette_view.gd    the library TreeView               │
│                source_view.gd     CodeEdit, LF display copy          │
│                inspector_view.gd  provenance inspector: states,      │
│                                   classes, typed fields, targets     │
│                tab_bar.gd         document tabs (godot-uxml)         │
│                diagnostics.gd     diagnostics entries and filters    │
│                ui_util.gd         label and model updates without a  │
│                                   layout (EdUi)                      │
│                demo.gd            staged states for screenshots      │
│                ui/*.uxml, *.uss   the window, authored in UXML       │
├───────────────────────────────────────────────────────────────────────┤
│ src/render/    godot-uxml as the renderer                            │
│                render_host.gd     render from buffers, partial       │
│                                   updates, element map, hit-test,    │
│                                   provenance, forced states          │
│                buffer_resolver.gd unsaved buffers override disk      │
├───────────────────────────────────────────────────────────────────────┤
│ src/core/      Source-backed editing (no Godot UI, headless-tested)  │
│                uxml_source.gd     UXML -> span tree (EdUxmlNode)     │
│                uss_source.gd      USS -> items with spans            │
│                source_patch.gd    validate / apply / invert patches  │
│                uxml_commands.gd   attribute and structure edits      │
│                structure_commands insert from the library, unwrap,   │
│                                   remove/move several, placement     │
│                clipboard.gd       copy, paste, duplicate             │
│                layout_commands.gd move/resize/nudge as style writes  │
│                snap.gd            snapping geometry                  │
│                step_composer.gd   several steps -> one transaction   │
│                element_catalog.gd library: godot-uxml catalog (R9)   │
│                                   with groups and new-element attrs  │
│                style_types.gd     USS value kinds, checks, helpers   │
│                style_targets.gd   write targets (ADR 0004)           │
│                provenance.gd      declaration rows, class rules,     │
│                                   class edits                        │
│                uss_commands.gd    rule and inline declaration edits  │
│                workspace.gd       buffers + one EdCommandHistory     │
│                project_store.gd   enumerate, read, revision-checked  │
│                                   atomic save, quick disk check      │
│                recovery_journal   unsaved edits as a record chain    │
├───────────────────────────────────────────────────────────────────────┤
│ addons/godot_uxml/  godot-uxml, a synced copy pinned in              │
│                     godot-uxml.pin (native DLL + GDScript path)      │
└───────────────────────────────────────────────────────────────────────┘
```

`src/core` does not use `src/app`, `src/render` or godot-uxml at compile
time. The span parsers are the editor's own code (see "Two parsers, one
identity"). `EdElementCatalog` and `EdStyleTypes` read the godot-uxml
tables (`UxmlControls.catalog()`, `UssProperties.ENUM_VALUES`) through a
`Callable` seam that loads the addon script by path, so the core also
loads where the addon is not present.

## Source fidelity is the invariant

ADR 0003 still applies, unchanged in substance.

- `EdSourceBuffer` holds the decoded text of one file, the byte-order mark,
  and the newline style. `to_bytes()` gives back the original bytes. A file
  that does not decode to the same bytes (invalid UTF-8) has
  `exact == false`; the editor shows the file and refuses every edit and
  every save of the file.
- A command reads the current parse, plans patches
  (`{start, end, replacement}`, String code point offsets) and returns an
  `EdTransaction`, or an `EdError` when the edit cannot be expressed exactly
  (an ambiguous span, a duplicate attribute, an unbound namespace prefix,
  an unterminated element). A refusal changes nothing.
- `EdWorkspace.commit()` validates every patch set of a transaction before
  the first buffer changes. The inverse patches are computed from the same
  text, so undo restores the exact bytes.
- No model is serialized. Comments, attribute order, quote style, entities,
  whitespace and line endings survive because no code writes them again.
- The source view edits a copy with `"\n"` line breaks (`EdNewlineMap`).
  Each typing pause becomes one patch in buffer offsets; untouched `"\r\n"`
  and `"\r"` breaks stay, and new breaks use the buffer's style.

## Two parsers, one identity

godot-uxml parses UXML and USS for rendering. The editor parses the same
text again with `EdUxmlSource` and `EdUssSource`, because the editor needs
spans that godot-uxml does not keep: attribute value spans and quotes,
close tags, declaration value spans.

The editor parsers follow the godot-uxml grammar and recovery, so both
trees contain the same elements and both sheets the same items:

- an authored element has `EdUxmlNode.open_start ==
  UxmlElement.open_tag_start`;
- a USS item has the same index as the godot-uxml sheet item, so a cascade
  origin `{file, item, decl_index}` names an exact declaration span.

`tests/unit/test_source_parsers.gd` checks both statements for every
fixture (144 UXML, 67 USS) on the native and the GDScript paths of
godot-uxml. godot-uxml documents and tests the offsets (request R3).
Control parts carry the offsets of their control, and template clones
carry the offsets of the outermost `<Instance>` of the entry file; the
element map skips both.

## Rendering

`EdRenderHost` is a `SubViewport` with one `UxmlDocument`. Every call goes
through the public editor APIs of godot-uxml (pin `6137987`); no private
field is read.

1. `render()` makes an `EdBufferResolver` that returns the text of open
   buffers for any `<Style src>`, `@import` or template path, and reads
   other files (images, fonts) from disk, and loads the entry text with
   `load_source(text, path, "", resolver)` (request R1).
2. `update()` brings the render up to date after an edit without a full
   load where godot-uxml can (request R4): a changed stylesheet goes to
   `reload_stylesheet()` (the controls stay), a changed entry or template
   to `replace_source()`. `replace_source()` edits in place when the
   element trees match and only `class` or `style` changed (canvas drags,
   nudges, inline style and class edits); otherwise it loads again and
   keeps the view state. A new buffer, another theme or another document
   needs `render()`.
3. After each load or update, the host maps each authored element of the
   entry file to its `UxmlElement` by open tag offset. Control parts
   (`part_of`) and template clones (`UxmlDocumentModel.instance_of()`,
   request R10) are not authored in the entry file and stay unmapped;
   `node_of()` maps them to their control element or their `<Instance>`.
   An `<Instance>` is a `TemplateContainer` in the model.

Lookups:

| Call | godot-uxml API |
| --- | --- |
| `control_of()`, `computed_style()`, `parent_id()` | `get_control_for`, `get_computed_style_for`, `get_parent_element` (R2) |
| `rect_of()`, `border_start()`, `local_box_of()` | `get_element_rect` (border, padding, content box) and `get_element_transform` (R14) |
| `hit_test()` | `element_at(point)` (R8): transforms and clipping apply, `picking-mode` does not (the editor selects what the author wrote) |
| `explain()` | `explain_style` (R5), origins normalized to workspace paths |
| `set_forced()` | `set_forced_states` (R6); the host keeps the states by node id and sets them again after a full load |

The theme menu selects Unity's choice (auto), the runtime theme, or the
editor dark or light skin.

## One history

`EdWorkspace` holds every buffer of the project and one
`EdCommandHistory`. A transaction may patch several files (a UXML file and
a USS file). Every view makes transactions and passes them to
`EdEditorState.execute()`:

| View | Edits |
| --- | --- |
| Canvas | selection; move, resize and nudge (layout writes); drops from the library and the hierarchy |
| Hierarchy | selection; drag to reorder and reparent |
| Library | insert at the selection; drag to insert at a drop position |
| Edit menu and shortcuts | cut, copy, paste, duplicate, delete, wrap, unwrap, move up and down |
| Inspector | attributes, inline style declarations, the element type (rename) |
| Source | any text; typing coalesces into one step per pause run |

A transaction records the selection before it and may name the selection
after it. Undo restores the selection before. Selection is a list of
`EdLocator` dictionaries, which find the element again after a re-parse
(unique `name` first, then child path with structure and attribute hints).

A command that needs several steps (declare a namespace, then insert; set
`left`, then `top`) runs the steps on a shadow copy of the workspace
(`EdStepComposer`). Each step plans against the text of the step before.
`EdSequentialPatchComposer` turns the steps into one patch set per file
against the original text, so the result is one transaction and one undo
step.

A reload from disk replaces a buffer. The history then drops the newest
step that touches that file and every older step; newer steps touch other
files only and stay valid.

**Tabs** (ADR 0008). `EdEditorState.tabs` lists the open documents; the
active one is `session`. Each tab keeps its selection. All tabs share the
one history: undo and redo take the newest step of the project and show
the tab of its document first. A closed tab keeps its edits in the
workspace.

## Structure editing

- **Library.** `EdElementCatalog` reads `UxmlControls.catalog()`
  (request R9): every element, its namespace, the `container` flag and the
  attributes with types, defaults and enum choices. The editor adds the
  library group, the library order and the attributes of a new element.
  UxmlObjects (`Columns`) and `TemplateContainer` are not in the library.
  A test compares the library with the catalog; a second test renders
  every entry without an `unsupported-control` diagnostic.
- **Placement.** "Insert at the selection" puts the element into a
  selected container (the catalog `container` flag; an unknown element
  counts as a container), or after a selected leaf, or at the end of the
  root.
- **Namespaces.** A new element uses the prefix that the document binds to
  its namespace. Without one, the same transaction declares `xmlns:ui` or
  `xmlns:uie` (or a free variant) on the root element. Wrap does the same.
  Paste adds the declaration of a missing prefix to the pasted element and
  refuses a prefix that the destination binds to another URI.
- **Unwrap** removes the open and close tags. A tag alone on its line
  takes the line. The lines of the children lose one indent unit, except
  line starts inside an open tag (attribute values keep their bytes).
- **Clipboard.** Copy keeps the exact source of each element and the
  namespace declarations in scope (port of `ClipboardService`). The system
  clipboard gets the plain text. A paste of text that equals the last copy
  uses the namespace data of that copy; other text pastes when it is
  element source whose prefixes the destination binds. A headless run has
  no system clipboard; the editor then uses its own copy.
- **Drag and drop** (`EdDragController`, request R12). godot-uxml runs
  the drag: the library and the hierarchy TreeViews get Unity's four
  callbacks (`set_drag_and_drop`). A drag starts after 5 pixels. Over the
  hierarchy, the 5-pixel bands at the top and the bottom of a row drop
  between items (the parent and the child index come from the tree); the
  rest of a container row drops into the container, at the end; the rest
  of another row drops before (upper half) or after (lower half) the row.
  A release outside every collection ends with `"outside"`: the canvas
  then takes the drop at the deepest container under the pointer, at the
  child index along its `flex-direction`.

## Canvas manipulation

- **Gestures.** A drag on the selected element moves it; a drag on one of
  the eight handles resizes it. `EdLayoutController` freezes the start
  state (computed style, rectangle, snap targets) and plans the whole
  gesture from that start at each pointer move. Each step executes with
  the coalesce key of the gesture, so the history merges the steps into
  one undo step, and the canvas shows the real godot-uxml render after
  each step. At most one step runs per frame. Escape cancels a drag and
  undoes its steps.
- **Nudge.** Arrow keys move the selection. A run of keys is one gesture
  while each key comes within 0.8 s (or two frames, for slow renders) of
  the render of the key before, the selection stays, and no other edit
  comes between.
- **Properties.** An absolute element moves with `left` and `top`, a
  relative element with `margin-left` and `margin-top`. A resize writes
  `width` and `height`; a handle on the left or top edge also moves the
  element, so the opposite edge stays. Values are whole pixels. A value
  that is not in px (`auto`, a percentage) is refused for a move; a resize
  measures the rendered border box.
- **Write targets of a gesture** (ADR 0004, port of `layoutStyleWritePlanner.ts`). The
  godot-uxml computed style names the declaration that wins.
  `EdRenderHost.style_facts()` normalizes the origin: a rule of a project
  stylesheet, a theme rule, inline, inherited or default. A property is
  written where its winner is: the rule declaration, or the inline
  declaration. A winner from the theme or from no declaration gets a new
  inline declaration. A winner from a pseudo-state rule is refused. When
  the winner is a shorthand (`margin`), the longhand is appended to the
  same block after it; an earlier longhand in that block is refused,
  because the shorthand overrides it. Two selected elements that share one
  rule need the same value.
- **Snapping** (`EdSnap`). The left, centre and right edges (top, middle,
  bottom) snap to the edges and centres of the siblings and the parent
  within 6 screen pixels, and draw a guide. Without a target the leading
  edge snaps to the pixel grid.
- **Hit-test.** `EdRenderHost.hit_test()` is `UxmlDocument.element_at()`
  (request R8): transforms and `overflow: hidden` clipping apply. A hit on
  a control part selects the control; a hit on template content selects
  the `<Instance>`. The selection outline of a rotated or scaled element
  follows its transform (`get_element_transform`, request R14).
- **Preview.** The canvas sends its input to the SubViewport
  (`push_input`) in document pixels. When a control in the document takes
  the focus, Godot removes the focus from the viewport of the editor
  window, so `EdMain._input` sends key events to the document after a
  click in the canvas, until a click elsewhere. Ctrl+S, Z, Y, P and O stay
  with the editor. The end of preview renders the document again from the
  source.

## Provenance inspector

The inspector (`EdInspectorView`) shows, top down: the element type, the
state preview, the classes, the attributes, the style rows, the
declarations of the focused style property and the layout readout.

- **Declarations.** A style field with the keyboard focus (or
  `show_property()`) lists every declaration of the property from
  `explain_style` (request R5), winner first: the status (`winner`,
  `overridden`, `dropped`, `keyword`, `inherited`, `default`), the value
  as written, and the origin with file and line (`EdProvenance`). A
  shorthand row (`margin`) lists the declarations of its first longhand
  (`margin-top`). A click on a row selects the declaration in the source
  view; an inherited row selects the parent.
- **Write targets** (ADR 0004, `EdStyleTargets`). The valid targets of a
  property are the authored rules that apply with the same pseudo-states
  (the winner first), the inline style (no state, one `style` attribute)
  and a new rule `#name` or `.class` (with the states) in each stylesheet
  of the document. Theme, inherited and default values are not targets.
  A longhand before the shorthand that wins is not a target. One target
  commits at once; more than one opens a picker menu (a godot-uxml
  `UxmlPopupMenu` under the field). The choice stays for the property
  until the selection or the state preview changes; a new rule becomes
  the rule target after its first write. A target freezes its source; a
  choice after a change of that source is refused (`stale-target`). An
  empty value removes the declaration of the chosen target.
- **Typed fields** (`EdStyleTypes`). Each value is checked for its kind
  before a write: length, number, colour, enum (the keywords of
  godot-uxml `UssProperties.ENUM_VALUES`), asset (`url()`, `resource()`,
  `none`), angle, scale, translate, transform origin, time, easing,
  property list. `var()` and the keywords `initial`, `unset` and
  `inherit` always pass. Each fixed style row has a helper button: a
  keyword menu (enum, easing, transition property), a unit menu (length,
  angle, time, translate: the number of the field or of the computed
  value with the new unit), the colour picker of godot-uxml (each change
  writes to the target; one picker is one undo step) or an asset menu
  (the project files of the right kind, as `url()` relative to the file
  of the target; a `url()` to a file outside the project is refused).
- **Classes.** Each class shows the rules of the document's stylesheets
  that name it, with a mark when the rule applies now (an `explain_style`
  query of the first declared property). A click shows the first rule.
  Add and remove patch only the `class` value (`EdProvenance.add_class`,
  `remove_class`); the last class removes the attribute.
- **State preview.** Toggles force `:hover`, `:active`, `:focus`,
  `:checked`, `:selected` and `:disabled` on the selected element
  (request R6). The canvas shows the state, real input cannot clear it,
  and the declarations and the write targets follow the states.
- **Attributes.** Unset common attributes show the enum choices or the
  default of the godot-uxml catalog as the placeholder; a menu next to the
  add row lists the catalog attributes of the element.

## Editor window

The window is `src/app/ui/editor_shell.uxml`, rendered by godot-uxml with
the Unity editor dark skin. The toolbar is a `uie:Toolbar` with
`ToolbarButton`, `ToolbarToggle` (Snap, Preview) and `ToolbarMenu` (Edit,
grid, screen size, theme) elements, the panes are `TwoPaneSplitView`
elements, the project list and the diagnostics are `ListView` elements,
the hierarchy and the library are `TreeView` elements, and the library
search is a `uie:ToolbarSearchField`. The diagnostics filters are
`ToolbarMenu` elements.

The inspector is a second godot-uxml document. The editor generates its
UXML once (a skeleton with fixed rows for the common attributes and style
properties, pairs of extra rows, class rows and declaration rows) and
then changes it in place for each selection: field values and
placeholders go to the `LineEdit` controls, row names and declaration
texts go to fixed-size `Label` and `Button` controls, unused rows of a
shown block are `visibility: hidden`, and a block that is not in use is
not displayed (so the Attributes section has no gap). A selection change
then needs few restyles and seldom a layout (requests R15, R17 have the
costs). The document tabs are a third,
small godot-uxml document (`EdTabBar`), generated when the tabs change.
The hierarchy context menu is a godot-uxml `UxmlPopupMenu`.

Native Godot controls are used where godot-uxml is the wrong tool. Each
one is mounted into a `*-host` element of the window document:

| Native control | Where | Why |
| --- | --- | --- |
| `SubViewport` | canvas | keeps the edited document apart from the editor's own documents (theme, input, focus); pan and zoom draw the viewport texture |
| `CodeEdit` | source view | text editing, IME, gutters and search; a godot-uxml `TextField` is a field, not a code editor |
| `FileDialog` (native) | Open Project | the operating system folder picker |
| `ConfirmationDialog` | save over an external change; recovery (Recover or Discard); a file changed on disk and in the editor (Reload or Keep) | a modal question; godot-uxml has no modal window. `EdMain.ask()` queues the questions, one dialog at a time |
| `Control` (menu anchor) | hierarchy context menu | `UxmlPopupMenu.open()` needs an anchor control; a plain `Control` at the pointer (request R16) |
| `EdDragController` (a `Control` over the window) | drag and drop | draws the drag title at the pointer and the drop line of a before/after drop over a leaf row; godot-uxml runs the drag and draws its own indicator for the other drops (request R12); it ignores the mouse |
| `ColorPicker` in a `PopupPanel` | inspector colour helper | the picker of godot-uxml `ColorField` (`UxmlEditorWidgets.open_color_picker`), opened for the chosen write target |
| `Button.self_modulate` | inspector colour swatch | the computed colour without a restyle per selection (request R17) |
| `EdCanvasView._draw` | selection outlines, handles, snap guides, the drop hint, the preview badge | drawn over the SubViewport texture at the canvas zoom; not document content |

## Projects and saving

`EdProjectStore` lists `.uxml` and `.uss` files under the project directory
(Unity cache folders, hidden folders and `node_modules` are skipped), reads
each file into a buffer, and records its revision (size, modification
time, SHA-256).

`save()` reads the disk revision again. When the disk file differs from
the revision of the last read or save, the save stops with `stale-revision`
and the editor asks before an overwrite. Otherwise the store writes a
temporary file next to the target, renames the temporary file over the
target, and reads the file back to check the bytes.

When the window gets focus, and every 2 seconds on a timer
(`--watch-interval`), the editor compares every file with disk. The timer
check reads the size and the time of each file first
(`EdProjectStore.may_differ()`); only a file that may have changed is read
and hashed. A clean file that changed on disk reloads. A file with unsaved
edits that changed on disk asks: **Reload from disk** (the unsaved edits
of the file are lost) or **Keep editor text** (a save asks before an
overwrite; the same disk version is not asked again).

## Recovery

ADR 0005 has the design (section "Godot app"). `EdRecoveryJournal` writes
one JSON line per buffer change of an unsaved file, chained by SHA-256, in
`user://recovery/<project hash>/journal.jsonl`. At project open, a journal
with unsaved files asks Recover or Discard, after the external-change
check. A clean close deletes the journal.

## Diagnostics

`EdDiagnostics.collect()` builds the list from the files of the open tabs:

| Source | Entries |
| --- | --- |
| godot-uxml | the diagnostics of the last render of each open document (import, cascade, runtime) |
| editor | parse problems of the editor parsers; files that do not decode exactly; elements that godot-uxml does not know (when no render reported them); the last 20 refused edits |

Each entry has a severity (error, warning, info; `severity_of()` maps the
godot-uxml kinds, request R11), a file and a range. The panel filters by
severity, file and source. A selection in the list opens the document of a
UXML file in a tab, selects the element at the range (canvas, hierarchy,
inspector) and selects the range in the source view.

## Frame cost

`bench/frame_cost.gd` runs the editor headless and measures the wall time
of each frame (the headless main loop wait is off) for idle, hover,
selection, typing, the commit of typing, and a canvas drag, on the menu
fixture or a generated 507-element document (`--fixture=large`). Rules
that keep a frame cheap:

- Nothing renders or rebuilds on a frame without a change. The canvas
  draws its overlay only.
- A change of the shell (lists, menus, labels) goes through a cache
  (`EdMain._changed()`) and skips the update when the data is the same.
  Labels that change often have a size that does not depend on the text,
  so `EdUi.set_label()` changes them without a layout.
- The inspector changes its document in place.
- A `style` or `class` change goes to `replace_source()` in place, a USS
  change to `reload_stylesheet()` (`EdRenderHost.update()`).
- The source view replaces only the changed text.
- The hierarchy keeps a map from item id to row; the hit-test tries the
  deepest element first.

## Testing

```
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
godot --headless --path . -s res://tests/run_tests.gd -- --gdscript
```

The runner loads every script under `src/` first (a compile error fails
the run), then runs each `test_*` method of `tests/unit/test_*.gd`. A
script error inside a test fails the test. `--gdscript` disables the
godot-uxml native core.

- Core: patch sets, buffers, history, locators, both parsers, the UXML and
  USS commands (ported from the TypeScript suites), project store.
- Round trip: open and save every fixture of `fixtures/projects` and the
  godot-uxml parity cases (211 files); the bytes stay the same.
- Alignment: the editor parsers against godot-uxml for every fixture.
- App: the real editor scene, headless: open, hit-test, selection sync,
  inspector and source edits through one history, re-render from unsaved
  USS, revision-checked save, external change reload.
- Provenance (`test_provenance.gd`, `test_app_inspector.gd`): value
  kinds and checks, write targets and the picker, stale choices, state
  rules, class rules and class edits, the declaration rows and the jump
  to source, the state preview on the canvas, the partial updates of the
  render host, template clones and element rectangles.
- Structure and layout: the library catalog against godot-uxml, insert
  with a namespace declaration, unwrap, remove and move of several
  elements, the clipboard, the step composer, write targets, gesture
  math, snapping, one undo step per gesture.
- Recovery (`test_recovery_journal.gd`, `test_app_recovery.gd`): the
  record chain, truncation, corruption, compaction, recovery in a new
  session, and an edit that survives a killed child editor process (the
  test starts the process and kills it by its PID).
- Workspace (`test_app_workspace.gd`): diagnostics filters and the jump to
  a range, tabs with one history, the disk watch timer (reload and the
  conflict question), the hierarchy context menu.
- Editing in the app (`tests/unit/test_app_editing.gd`): the input goes
  through the window (`Viewport.push_input`): library insert and search,
  drag from the library to the hierarchy and the canvas, hierarchy
  reorder and reparent, the Edit commands and shortcuts, rename, a resize
  drag and a move drag with a snap, a write to the winning USS rule,
  nudge, preview clicks and typing.

## Updating godot-uxml

```
python tools/update_godot_uxml.py --ref <commit> [--source <checkout-or-url>]
```

The script exports `addons/godot_uxml` and the parity cases from the
commit with `git archive` and writes `godot-uxml.pin`. Run the tests on
both paths after an update. ADR 0007 records why the addon is a synced
copy and not a submodule.
