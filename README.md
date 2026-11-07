# UXML Editor

UXML Editor is a visual editor for Unity UI Toolkit documents (UXML) and
stylesheets (USS). The editor is a Godot 4.7 application.
[godot-uxml](https://github.com/jethac/godot-uxml) renders the documents.

> The `godot` branch holds the Godot rebuild. The `main` branch holds the
> previous React and Tauri editor.

![The editor with the menu fixture: project and hierarchy on the left, the
canvas with the selected button in the center, the source view and the
diagnostics below, the inspector on the right](docs/screenshots/m1-menu-selection.png)

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
  editor, also before a save. Select an element with a click. Pan and zoom
  the view. Select a screen size and a theme: auto, runtime, editor dark
  or editor light.
- **Hierarchy.** The tree shows the authored elements. A selection in the
  tree, the canvas or the source view selects the same element in all
  views.
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

`docs/roadmap.md` lists the next milestones: the palette, drag and resize,
the provenance inspector, recovery, pseudo-state preview, the transition
timeline, the state-machine panel and the web export.

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

## Keyboard shortcuts

| Keys | Function |
| --- | --- |
| Ctrl+O | Open a project directory. |
| Ctrl+S | Save the active document and its stylesheets. |
| Ctrl+Shift+S | Save all changed files. |
| Ctrl+Z | Undo. |
| Ctrl+Y or Ctrl+Shift+Z | Redo. |
| Ctrl+= and Ctrl+- | Zoom in and zoom out. |
| F (canvas) | Fit the screen in the canvas. |
| Mouse wheel (canvas) | Zoom at the pointer. |
| Middle drag, or Space or Alt with a drag (canvas) | Pan. |
| Delete (canvas) | Remove the selected element. |

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
