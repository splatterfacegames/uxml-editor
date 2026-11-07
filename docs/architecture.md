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
│                canvas_view.gd     SubViewport, pan/zoom, overlay     │
│                source_view.gd     CodeEdit, LF display copy          │
│                inspector_view.gd  generated godot-uxml document      │
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
| Canvas | selection; Delete removes the selected element |
| Hierarchy | selection |
| Inspector | attributes, inline style declarations |
| Source | any text; typing coalesces into one step per pause run |

A transaction records the selection before it and may name the selection
after it. Undo restores the selection before. Selection is a list of
`EdLocator` dictionaries, which find the element again after a re-parse
(unique `name` first, then child path with structure and attribute hints).

A reload from disk replaces a buffer. The history then drops the newest
step that touches that file and every older step; newer steps touch other
files only and stay valid.

## Editor window

The window is `src/app/ui/editor_shell.uxml`, rendered by godot-uxml with
the Unity editor dark skin. The toolbar is a `uie:Toolbar` with
`ToolbarButton` and `ToolbarMenu` elements, the panes are
`TwoPaneSplitView` elements, the project list and the diagnostics are
`ListView` elements, and the hierarchy is a `TreeView`. The inspector is a
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

## Updating godot-uxml

```
python tools/update_godot_uxml.py --ref <commit> [--source <checkout-or-url>]
```

The script exports `addons/godot_uxml` and the parity cases from the
commit with `git archive` and writes `godot-uxml.pin`. Run the tests on
both paths after an update. ADR 0007 records why the addon is a synced
copy and not a submodule.
