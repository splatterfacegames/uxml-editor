# UXML Editor

UXML Editor is a visual editor for Unity UI Toolkit documents (UXML) and
stylesheets (USS). The editor is a Godot 4.7 application.
[godot-uxml](https://github.com/jethac/godot-uxml) renders the documents.

> The `godot` branch holds the Godot rebuild. The `main` branch holds the
> previous React and Tauri editor.

![The editor with the menu fixture: project, hierarchy and library on the
left, the canvas with a resize in progress and a snap guide in the
center, the source view and the diagnostics below, the inspector on the
right](docs/screenshots/m3-resize-snap.png)

## Source text is the truth

The editor changes a file only with a patch on the exact text of the
file. A patch replaces one range of characters. All other bytes stay the
same: comments, attribute order, quote style, entities, whitespace and
line endings. An edit that cannot be made as an exact patch stops with a
message. Such an edit changes no file and adds no undo step.

## Features

- **Projects.** Open a project directory. The editor lists every `.uxml`
  and `.uss` file and skips Unity cache folders.
- **Canvas.** godot-uxml renders the active document from the text in the
  editor, also before a save. Select an element with a click. Shift+click
  adds an element to the selection or removes the element from the
  selection. Pan and zoom the view.
  Select a screen size and a theme: auto, runtime, editor dark or editor
  light.
- **Move and resize.** Drag the selected element to move the element.
  Drag a handle to resize the element. Arrow keys nudge the selection by
  1 px (Shift: 10 px). Escape during a drag cancels the drag.
  Each drag and each run of arrow keys is one undo step. An absolute
  element gets `left` and `top`; a relative element gets `margin-left` and
  `margin-top`. A resize writes `width` and `height`.
- **Write targets.** A layout value goes to the declaration that sets the
  current value: the USS rule or the inline style. A value from the theme
  or from no declaration goes into the inline style
  (`docs/adr/0004-style-write-targets.md`). A value from a pseudo-state
  rule (for example `:hover`) stops the edit with a message.
- **Snapping.** Edges and centres snap to the siblings and the parent and
  show a guide. Other edges snap to the pixel grid. **Snap** turns
  snapping on and off; the grid menu sets the grid. Alt or Ctrl during a
  drag turns snapping off for that drag. Shift keeps the aspect ratio of a
  corner resize.
- **Preview.** **Preview** (Ctrl+P) sends the mouse and the keyboard to the
  document. Buttons, toggles, fields, sliders and scroll views work as at
  runtime. Preview changes no source text. The end of preview renders the
  document from the source again.
- **Library.** The library lists every element that godot-uxml renders,
  runtime (`ui:`) and editor (`uie:`), in five groups. Type in the search
  field to filter the list. A double-click on an element (or Enter)
  inserts the element at the selection: into a selected container, or
  after another selected element. A drag to the canvas or the hierarchy
  inserts the element at the drop position. When the document has no
  prefix for the namespace of the element, the same edit declares
  `xmlns:ui` or `xmlns:uie` on the root element.
- **Hierarchy.** The tree shows the authored elements. A selection in the
  tree, the canvas or the source view selects the same element in all
  views. Shift+click and Ctrl+click select more than one element. Drag
  rows to reorder elements: a drop on the top quarter of a row goes before
  the row, on the bottom quarter after the row, on the middle into the
  row (for a container). A drag from the hierarchy to the canvas moves the
  element into the container under the pointer. An element that godot-uxml does not know stays in the
  tree with the mark `(unknown)` and a diagnostic.
- **Structure commands.** The **Edit** menu and the shortcuts cut, copy,
  paste, duplicate, delete, wrap in a VisualElement, unwrap, and move up
  or down. Copy takes the exact source of each element and the namespace
  declarations in scope. Paste and duplicate give a copied `name` a `-copy` suffix
  when the name is already in the document. The inspector **Element**
  field (F2) renames the element type in the open and close tags.
- **Source view.** Edit the text directly. A pause in typing makes one
  patch. The other views then show the change.
- **Inspector.** Edit, add and remove attributes and inline style
  declarations. Unset style fields show the computed value and the origin
  of the value (a stylesheet, the theme, or a parent).
- **Undo.** One history records the edits of all views.
- **Save.** A save writes only the changed files. Before the write, the
  editor compares the file on disk with the version that the editor read.
  When another program changed the file, the editor asks before an
  overwrite.
- **Diagnostics.** The panel shows godot-uxml diagnostics and the parse
  problems of the editor.

`docs/roadmap.md` lists the next milestones: the provenance inspector,
recovery, pseudo-state preview, the transition timeline, the
state-machine panel and the web export.

## Screenshots

| File | Shows |
| --- | --- |
| `docs/screenshots/m2-library-insert.png` | The library filtered by "button" and a RepeatButton inserted at the selection. |
| `docs/screenshots/m2-drag-library-to-canvas.png` | A Toggle dragged from the library over the canvas, with the drop hint. |
| `docs/screenshots/m2-drag-hierarchy.png` | A button dragged in the hierarchy, with the drop line. |
| `docs/screenshots/m2-multi-select-duplicate.png` | Two buttons selected and duplicated with unique names. |
| `docs/screenshots/m3-resize-snap.png` | A resize in progress with a snap guide; the inline width and height in the inspector. |
| `docs/screenshots/m3-preview.png` | Preview mode with text typed in a document field. |

## Requirements

- Godot 4.7.1 (standard build, not .NET).
- Windows x64 for the native core of godot-uxml. Other platforms use the
  GDScript path of godot-uxml. The results are the same.
- Python 3.10 or later, only to update godot-uxml.

## Run the editor

1. Import the project one time:

   ```
   godot --headless --path . --import
   ```

2. Start the editor:

   ```
   godot --path .
   ```

3. Click **Open Project…** and select the project directory.

To open a project at start, add options after `--`:

```
godot --path . -- --project=fixtures/projects/menu --open=Assets/UI/Menu.uxml
```

| Option | Function |
| --- | --- |
| `--project=<dir>` | Open the project directory. |
| `--open=<path>` | Open the UXML document (path in the project). |
| `--select=<name>` | Select the element with this `name` attribute. |
| `--theme=<auto\|runtime\|editor-dark\|editor-light>` | Set the canvas theme. |
| `--preset=<index>` | Set the screen size (0 = 1920 × 1080). |
| `--screenshot=<file.png>` | Save a screenshot, then stop the editor. |
| `--demo=<name>` | Before the screenshot, stage a documentation state: `palette`, `drag-canvas`, `drag-hierarchy`, `resize`, `multi` or `preview`. |

## Keyboard shortcuts

| Keys | Function |
| --- | --- |
| Ctrl+O | Open a project directory. |
| Ctrl+S | Save the active document and its stylesheets. |
| Ctrl+Shift+S | Save all changed files. |
| Ctrl+Z | Undo. |
| Ctrl+Y or Ctrl+Shift+Z | Redo. |
| Ctrl+= and Ctrl+- | Zoom in and zoom out. |
| Ctrl+P | Turn preview on or off. |
| F (canvas) | Fit the screen in the canvas. |
| Mouse wheel (canvas) | Zoom at the pointer. Ctrl+wheel in preview. |
| Middle drag, or Space or Alt with a drag (canvas) | Pan. Middle drag only in preview. |
| Arrow keys, Shift+arrow keys (canvas) | Nudge by 1 px or 10 px. |
| Escape (canvas, during a drag) | Cancel the drag and undo the changes of the drag. |
| Ctrl+X, Ctrl+C, Ctrl+V | Cut, copy, paste elements. |
| Ctrl+D | Duplicate the selected elements. |
| Delete | Remove the selected elements. |
| Ctrl+G, Ctrl+Shift+G | Wrap in a VisualElement, unwrap. |
| Alt+Up, Alt+Down | Move the selection up or down among the siblings. |
| F2 | Edit the element type in the inspector. |

The structure shortcuts work when no text field has the keyboard focus.

## Test

```
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
godot --headless --path . -s res://tests/run_tests.gd -- --gdscript
```

The second command uses the native core of godot-uxml. The third command
uses the GDScript path. Add `--filter=<text>` to run only the tests with
that text in the file or test name. The exit code is the number of failed
tests.

## Update godot-uxml

The editor uses a copy of `addons/godot_uxml` from one godot-uxml commit.
`godot-uxml.pin` records the commit. Do not change the copy. To move the
pin:

```
python tools/update_godot_uxml.py --ref <commit> [--source <checkout-or-url>]
```

Then run the tests on both paths. `docs/godot-uxml-requests.md` lists the
godot-uxml APIs that the editor needs.

## Documentation

- [docs/architecture.md](docs/architecture.md): layers, rendering, the
  history, the window.
- [docs/godot-uxml-requests.md](docs/godot-uxml-requests.md): API requests
  for godot-uxml.
- [docs/roadmap.md](docs/roadmap.md): the next milestones.
- [docs/adr/](docs/adr/): decision records.

## License

Apache-2.0. See [LICENSE](LICENSE) and
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
