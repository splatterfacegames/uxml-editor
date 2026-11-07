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
│                drag_controller    drag and drop between the views    │
│                palette_view.gd    the library TreeView               │
│                source_view.gd     CodeEdit, LF display copy          │
│                inspector_view.gd  godot-uxml document, in place      │
│                tab_bar.gd         document tabs (godot-uxml)         │
│                diagnostics.gd     diagnostics entries and filters    │
│                ui_util.gd         label and model updates without a  │
│                                   layout (EdUi)                      │
│                demo.gd            staged states for screenshots      │
│                ui/*.uxml, *.uss   the window, authored in UXML       │
├───────────────────────────────────────────────────────────────────────┤
│ src/render/    godot-uxml as the renderer                            │
│                render_host.gd     render from buffers, patch of      │
│                                   style/class, element map, hit-test,│
│                                   computed style                     │
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
│                element_catalog.gd library elements (request R9 seam) │
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

`src/core` does not use `src/app`, `src/render` or godot-uxml. The span
parsers are the editor's own code (see "Two parsers, one identity"), so
the core also runs where the addon is not loaded.

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
godot-uxml. godot-uxml request R3 asks to make the offsets a documented
contract.

## Rendering

`EdRenderHost` is a `SubViewport` with one `UxmlDocument`. `render()`:

1. makes an `EdBufferResolver` that returns the text of open buffers for
   any `<Style src>`, `@import` or template path, and reads other files
   (images, fonts) from disk;
2. loads the entry buffer text through godot-uxml (request R1: the host
   copies the body of `UxmlDocument.load_source()` to pass the resolver);
3. maps each authored element of the entry file to its `UxmlElement` by
   open tag offset. Control parts (`part_of`) and template clones
   (`element_paths`) are not authored in the entry file and stay unmapped.

`hit_test()` returns the deepest mapped element whose control rectangle,
cut by clipping ancestors, holds the point (request R8). `computed_style()`
returns the godot-uxml cascade output, with the winning origin of each
property (request R2 for the lookup).

A change of the entry buffer that only changes the value of `style` or
`class` attributes of rendered elements (or adds or removes such an
attribute) does not reload: `patch()` gives the new values to the
godot-uxml model (`UxmlElement.set_attribute()`), and godot-uxml restyles
those elements. The check compares the source without those attributes
(the skeleton) with the source of the last render; the same skeleton means
the same structure, so the element map stays valid. Canvas drags, nudges
and inline style edits take this path. Every other change renders the
whole document again (request R4 asks for a partial reload). The theme menu selects Unity's choice (auto), the
runtime theme, or the editor dark or light skin.

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

- **Library.** `EdElementCatalog` lists every element that godot-uxml
  renders, with its namespace, its group and the default attributes of a
  new element. The table is a seam for request R9: a test compares it with
  the tags that godot-uxml knows (`UssControls.IMPLICIT_CLASSES`), and a
  second test renders every entry without an `unsupported-control`
  diagnostic.
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
- **Drag and drop** (`EdDragController`) reads the raw mouse events of the
  window and never takes the press, so the lists still select. Rows are
  found with the public `get_list_rows()` and `UxmlListRow.get_element()`.
  A hierarchy drop goes before, into or after the row by the pointer
  height. A canvas drop goes into the deepest container under the pointer,
  at the child index along its `flex-direction`.

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
- **Write targets** (ADR 0004, port of `layoutStyleWritePlanner.ts`). The
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
- **Hit-test.** `EdRenderHost.hit_test()` tests the point in the local
  space of each control and of every clipping ancestor, so rotate, scale
  and translate apply (godot-uxml sets them on the Control transform).
  This is the workaround for request R8.
- **Preview.** The canvas sends its input to the SubViewport
  (`push_input`) in document pixels. When a control in the document takes
  the focus, Godot removes the focus from the viewport of the editor
  window, so `EdMain._input` sends key events to the document after a
  click in the canvas, until a click elsewhere. Ctrl+S, Z, Y, P and O stay
  with the editor. The end of preview renders the document again from the
  source.

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
properties, and pairs of extra rows) and then changes it in place for each
selection: field values and placeholders go to the `LineEdit` controls,
row names go to fixed-size `Label` controls, unused rows are
`visibility: hidden`. A selection change then needs no new controls and
no layout (request R15 has the costs). The document tabs are a third,
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
| `EdDragController` (a `Control` over the window) | drag and drop | draws the drag label and the hierarchy drop line over the godot-uxml shell; godot-uxml has no drag-and-drop API (request R12); it ignores the mouse |
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
- A `style` or `class` change patches the render (`EdRenderHost.patch()`).
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
