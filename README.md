# UXML Editor

UXML Editor is a visual editor for Unity UI Toolkit documents (UXML) and
stylesheets (USS). The editor is a Godot 4.7 application.
[godot-uxml](https://github.com/splatterfacegames/godot-uxml) renders the documents.

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
- **Tabs.** Each UXML document opens in a tab over the canvas. A click on
  a tab shows the document; the × button or Ctrl+W closes the tab;
  Ctrl+Tab shows the next tab. Each tab keeps its selection. A closed tab
  keeps its unsaved edits in the project.
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
- **Write targets of a drag.** During a drag, a layout value goes to the
  declaration that sets the current value: the USS rule or the inline
  style. A value from the theme or from no declaration goes into the
  inline style (`docs/adr/0004-style-write-targets.md`). When more than one
  target is valid, a menu asks for the target at the end of the drag. The
  editor keeps the choice with the choices of the inspector. Another
  target gets the end of the drag instead. The drag stays one undo step.
  **Cancel** undoes the drag.
- **Snapping.** Edges and centres snap to the siblings and the parent and
  show a guide. Other edges snap to the pixel grid. **Snap** turns
  snapping on and off; the grid menu sets the grid. Alt or Ctrl during a
  drag turns snapping off for that drag. Shift keeps the aspect ratio of a
  corner resize.
- **Preview.** **Preview** (Ctrl+P) sends the mouse and the keyboard to the
  document. Buttons, toggles, fields, sliders and scroll views work as at
  runtime. Preview changes no source text. The end of preview renders the
  document from the source again.
- **Library.** The library lists every element of the godot-uxml
  catalog, runtime (`ui:`) and editor (`uie:`), in five groups. Type in the search
  field to filter the list. A double-click on an element (or Enter)
  inserts the element at the selection: into a selected container, or
  after another selected element. A drag to the canvas or the hierarchy
  inserts the element at the drop position. When the document has no
  prefix for the namespace of the element, the same edit declares
  `xmlns:ui` or `xmlns:uie` on the root element.
- **Hierarchy.** The tree shows the authored elements. A selection in the
  tree, the canvas or the source view selects the same element in all
  views. Shift+click and Ctrl+click select more than one element. Drag
  rows to reorder elements: a drop on the top or bottom 5 pixels of a row
  goes between the rows. A drop on the rest of a container row goes into
  the container. A drop on the rest of another row goes before the row
  (upper half) or after the row (lower half). A drag from the hierarchy to
  the canvas moves the element into the container under the pointer. An element that
  godot-uxml does not know stays in the tree with the mark `(unknown)` and
  a diagnostic. A right-click on a row opens a menu with the Edit commands
  for the selection.
- **Structure commands.** The **Edit** menu and the shortcuts cut, copy,
  paste, duplicate, delete, wrap in a VisualElement, unwrap, and move up
  or down. Copy takes the exact source of each element and the namespace
  declarations in scope. Paste and duplicate give a copied `name` a `-copy` suffix
  when the name is already in the document. The inspector **Element**
  field (F2) renames the element type in the open and close tags.
- **Source view.** Edit the text directly. A pause in typing makes one
  patch. The other views then show the change.
- **Inspector.** Edit, add and remove attributes and style
  declarations. Unset style fields show the computed value and the origin
  of the value (a stylesheet, the theme, or a parent). Unset attributes
  show the choices or the default value from the godot-uxml catalog. The
  **▾** button of the add row lists the attributes of the element.
- **Declarations.** Put the keyboard focus in a style field. The
  **Declarations** section lists every declaration of the property: the
  status (winner, overridden, dropped, inherited, default), the value and
  the file and line. Click a declaration to select the declaration in the
  source view. Click an inherited value to select the parent.
- **Style write targets.** A style edit goes to one target: an authored
  rule that applies to the element, the inline style, or a new rule
  (`#name` or `.class`) in a stylesheet of the document
  (`docs/adr/0004-style-write-targets.md`). When more than one target is
  valid, a menu asks for the target. The editor keeps the choice for the
  property until the selection changes. A choice after a change of the
  source stops with a message. An empty value removes the declaration.
- **Typed style fields.** The editor checks each value for the type of
  the property before the edit: length, number, colour, keyword, asset,
  angle, scale, translate, time, easing. The button before a field opens
  a keyword menu, a unit menu, the colour picker or a menu of the project
  assets. An asset outside the project stops with a message.
- **Classes.** The **Classes** section lists the classes of the element.
  Each class shows the rules that name the class; ✓ marks a rule that
  applies now. Click the rules to show the first rule in the source view.
  Add and remove classes; the edit changes only the `class` value.
- **State preview.** The **State preview** toggles force `:hover`,
  `:active`, `:focus`, `:checked`, `:selected` and `:disabled` on the
  selected element. The canvas shows the state. The declarations and the
  write targets then show the rules of the state.
- **Transitions on the canvas.** A state toggle of the state preview or
  a class edit in the **Classes** section plays the `transition-*` values
  of the change on the canvas.
- **Timeline.** The panel under the canvas has one track for each
  transitioning property of the selection, or of the whole document
  (**Selection** or **Document**). Each bar shows the delay, the duration
  and the easing. **▶** plays and pauses, **|◀** goes back to the start,
  **Loop** plays again, and the menu sets the speed. A drag on the ruler
  scrubs the canvas. **From** and **To** set the states of the run: type
  a state such as `.a.b:hover`, or use the menu. A run changes no source
  text.
- **Edits on the timeline.** A drag of a bar changes `transition-delay`.
  A drag of the right end of a bar changes `transition-duration`. A
  double-click on a bar opens the easing picker. The edit uses the write
  targets of the inspector and is one undo step. Alt or Ctrl during a drag
  turns off the snap to 0.05 s. Escape cancels the drag.
- **Easing.** The inspector shows the curve of
  `transition-timing-function`. A click on the curve or on the **∿** button
  opens a picker with the curve of every Unity easing keyword.
- **Panel layout.** Drag a split line to change the size of a pane. The
  editor keeps the sizes for the user (`user://settings.cfg`, or
  `--settings=<file>`). A long text ends in `...`, and its tooltip shows
  the whole text.
- **Undo.** One history records the edits of all views and all tabs.
  An undo of an edit in another document shows the tab of that document
  (`docs/adr/0008-tabs-and-history.md`).
- **Save.** A save writes only the changed files. Before the write, the
  editor compares the file on disk with the version that the editor read.
  When another program changed the file, the editor asks before an
  overwrite.
- **Changes on disk.** Every 2 seconds and when the window gets focus,
  the editor compares the open files with disk. A file without unsaved
  edits reloads. For a file with unsaved edits, the editor asks: **Reload
  from disk** or **Keep editor text**.
- **Recovery.** The editor writes each unsaved edit to a recovery journal
  at once. After a crash or a killed process, the next open of the project
  asks: **Recover** or **Discard**. A recovered file that changed on disk
  in the meantime needs a confirmation before a save overwrites the disk
  file (`docs/adr/0005-recovery.md`).
- **Diagnostics.** The panel shows the diagnostics of godot-uxml (import),
  the parse problems of the editor, unknown elements and refused edits,
  for every open document. Filter the list by severity, file and source.
  Select a diagnostic to select its range in the source view and its
  element in the canvas and the hierarchy.

`docs/roadmap.md` lists the next milestones: the state-machine panel and
the web export.

## Screenshots

| File | Shows |
| --- | --- |
| `docs/screenshots/m2-library-insert.png` | The library filtered by "button" and a RepeatButton inserted at the selection. |
| `docs/screenshots/m2-drag-library-to-canvas.png` | A Toggle dragged from the library over the canvas, with the drop hint. |
| `docs/screenshots/m2-drag-hierarchy.png` | A button dragged in the hierarchy, with the drop line. |
| `docs/screenshots/m2-multi-select-duplicate.png` | Two buttons selected and duplicated with unique names. |
| `docs/screenshots/m3-resize-snap.png` | A resize in progress with a snap guide; the inline width and height in the inspector. |
| `docs/screenshots/m3-preview.png` | Preview mode with text typed in a document field. |
| `docs/screenshots/m4-provenance.png` | The declarations of `background-color`: the winning rule and the theme value. The source view shows the declaration. |
| `docs/screenshots/m4-target-picker.png` | The write-target menu of a `min-width` edit. |
| `docs/screenshots/m4-state-preview.png` | `:hover` forced on a button. The `:hover` rule wins in the canvas and the inspector. |
| `docs/screenshots/m4-classes.png` | The class editor with the rules of each class. |
| `docs/screenshots/m5-diagnostics-jump.png` | A diagnostic selected in the list: the range in the source view, the element in the canvas, the hierarchy and the inspector. |
| `docs/screenshots/m5-tabs.png` | Two documents in tabs; the active tab has unsaved edits. |
| `docs/screenshots/m5-recovery.png` | The recovery question after a session that ended with unsaved edits. |
| `docs/screenshots/m5-conflict.png` | The question for a file that changed on disk and in the editor. |
| `docs/screenshots/m5-context-menu.png` | The hierarchy context menu. |
| `docs/screenshots/m6-timeline.png` | A `:hover` toggle paused at 0.6 s: three tracks with delay, duration and easing, and the easing curve in the inspector. |
| `docs/screenshots/m6-timeline-classes.png` | A run from `.menu-button` to `.menu-button.alt`, document scope. |
| `docs/screenshots/m6-easing-picker.png` | The easing picker with the curve of every Unity keyword. |
| `docs/screenshots/m6-canvas-target-picker.png` | The write-target menu at the end of a canvas drag. |
| `docs/screenshots/m6-narrow-inspector.png` | A narrow inspector: long class rules and value origins end in `...`. |

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
| `--demo=<name>` | Before the screenshot, stage a documentation state: `palette`, `drag-canvas`, `drag-hierarchy`, `resize`, `multi`, `preview`, `diagnostics`, `tabs`, `recovery`, `conflict`, `context-menu`, `provenance`, `picker`, `states`, `classes`, `timeline`, `timeline-classes`, `easing`, `canvas-picker` or `narrow`. |
| `--gdscript` | Use the GDScript path of godot-uxml (no native core). |
| `--recovery-dir=<dir>` | Keep the recovery journals in this directory (default `user://recovery`). |
| `--watch-interval=<seconds>` | Set the time between disk checks (default 2; 0 turns the timer off). |
| `--settings=<file>` | Keep the pane sizes and the timeline options in this file (default `user://settings.cfg`). |
| `--ready-file=<path>` | Write this file after the options ran (tests). |
| `--exit-after=<seconds>` | Stop the editor after this time (tests). |

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
| Ctrl+W | Close the active tab. |
| Ctrl+Tab, Ctrl+Shift+Tab | Show the next or the previous tab. |
| Right-click (hierarchy) | Open the Edit commands for the selection. |
| Space, Home (timeline, after a click on the tracks) | Play or pause; go back to the start. |
| Alt or Ctrl with a bar drag (timeline) | Turn off the snap to 0.05 s. |
| Escape (timeline, during a bar drag) | Cancel the drag. |

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
tests. One recovery test starts an editor in a child process and stops
the process by its process ID.

The full suite took 2 to 6 minutes on a machine with some load, and 18
minutes on a machine at full load. Do not give the command a time limit of
less than 1 hour. Each line of the output gives the time of one test file.

## Measure the frame cost

```
godot --headless --path . -s res://bench/frame_cost.gd
godot --headless --path . -s res://bench/frame_cost.gd -- --gdscript
godot --headless --path . -s res://bench/frame_cost.gd -- --fixture=large
```

The benchmark runs the editor and measures each frame for idle, hover,
selection, typing, the commit of typing, a canvas drag, and the timeline:
idle with a run, scrub, play, and a bar drag. Add `--only-timeline` to
measure only the timeline. The table
gives the median, the 95th percentile and the maximum in milliseconds,
and the number of full renders, render patches and inspector builds of
each scenario. `--fixture=large` uses a generated document of about 500
elements.

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
