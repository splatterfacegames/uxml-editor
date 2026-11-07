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
│                main.gd            composition root, shortcuts, saves │
│                editor_state.gd    project, selection, one history    │
│                canvas_view.gd     SubViewport, pan/zoom, overlay,    │
│                                   handles, guides, preview input     │
│                layout_controller  canvas gestures -> layout writes   │
│                drag_controller    drag and drop between the views    │
│                palette_view.gd    the library TreeView               │
│                source_view.gd     CodeEdit, LF display copy          │
│                inspector_view.gd  generated godot-uxml document      │
│                demo.gd            staged states for screenshots      │
│                ui/*.uxml, *.uss   the window, authored in UXML       │
├───────────────────────────────────────────────────────────────────────┤
│ src/render/    godot-uxml as the renderer                            │
│                render_host.gd     render from buffers, element map,  │
│                                   hit-test, computed style           │
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
│                                   atomic save                        │
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

Each buffer change renders the whole document again (request R4 asks for
a partial reload). The theme menu selects Unity's choice (auto), the
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
search is a `uie:ToolbarSearchField`. The inspector is a
second godot-uxml document that the editor generates as UXML text for each
selection.

Native Godot controls are used where godot-uxml is the wrong tool. Each
one is mounted into a `*-host` element of the window document:

| Native control | Where | Why |
| --- | --- | --- |
| `SubViewport` | canvas | keeps the edited document apart from the editor's own documents (theme, input, focus); pan and zoom draw the viewport texture |
| `CodeEdit` | source view | text editing, IME, gutters and search; a godot-uxml `TextField` is a field, not a code editor |
| `FileDialog` (native) | Open Project | the operating system folder picker |
| `ConfirmationDialog` | save over an external change | a modal question; godot-uxml has no modal window |
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

When the window gets focus, the editor compares every file with disk. A
clean file that changed on disk reloads. A changed file that also changed
on disk is reported and is not overwritten without confirmation.

The recovery journal of ADR 0005 is not in the Godot app yet (milestone
plan in `docs/roadmap.md`).

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
