# Roadmap

Milestone 1 (done on the `godot` branch): the Godot project with godot-uxml
pinned, the ported source-backed core with its tests, the canvas with live
render, pan, zoom, selection and hit-test, the hierarchy, the source view
in sync, one undo history, inspector v1 (attributes and inline styles),
revision-checked saves.

Milestones 2, 3, 4, 5, 6 and 7 (done on the `godot` branch): see the sections
below. Screenshots: `docs/screenshots/m2-*.png`, `m3-*.png`, `m4-*.png`,
`m5-*.png`, `m6-*.png` and `m7-*.png`. Milestone 5 came before milestone 4, after a frame-cost
pass (see "Frame cost" below). Before milestone 4 the pin moved to
godot-uxml `6137987` (requests R1-R14), and the editor replaced every
workaround with the godot-uxml editor APIs (see "Re-pin" below). Before
milestone 7 the pin moved to `dc2c081` (R15, R16, R11).

The milestones that are not done are a proposal. Each milestone ends with the headless
suite green on both godot-uxml paths and a screenshot set. godot-uxml
requests (`docs/godot-uxml-requests.md`) are named where a milestone
depends on one; each request lands in godot-uxml first, then the pin moves.

## M2. Structure editing and the palette (done)

Done: the library (every element that godot-uxml renders, five groups,
search, insert at the selection, drag to the canvas or the hierarchy,
namespace declaration in the same edit), hierarchy drag to reorder and
reparent, multi-selection (Shift/Ctrl in the hierarchy, Shift+click in the
canvas), rename of the element type, duplicate, wrap, unwrap, cut, copy,
paste, delete, move up and down, all one undo step each. The library is a
static table behind `EdElementCatalog` until request R9; drag and drop
reads list rows through public calls until request R12.

Not done: attribute lists per element in the inspector (request R9). The
hierarchy context menu came with milestone 5.

The proposal was:

- **Palette** of every element that godot-uxml supports, runtime
  (`ui:`) and editor (`uie:`), grouped as in the Unity library (containers,
  controls, inputs, collections, editor). Click inserts into the selection;
  drag inserts at the drop position. Insertion uses
  `EdUxmlCommands.insert_element`, and the namespace prefix comes from the
  document bindings (the command refuses an unbound prefix). Source of the
  list: request R9; until then a static catalog generated from the
  godot-uxml part trees.
- **Hierarchy editing**: drag to reorder and reparent (`move_elements`),
  rename, duplicate, wrap in a VisualElement, delete, multi-selection of
  contiguous siblings. Each action already exists in the core with tests.
- **Copy and paste** of element source (port of `ClipboardService`).

## M3. Canvas manipulation (done)

Done: move and resize handles, one coalesced undo step per drag, Escape
cancels; nudge with the arrow keys (a run of keys is one step); write
targets after ADR 0004 (the winning rule or inline declaration; theme and
default values go inline; pseudo-state winners and overridden longhands
are refused); snapping to sibling and parent edges and centres with
guides, a pixel grid, Shift keeps the ratio, Alt or Ctrl turns snapping
off; hit-test through Control transforms (the R8 workaround); preview
mode that sends the mouse and the keyboard to the document.

Not done: alignment and distribution of several elements (the TypeScript
`align` and `distribute`). Done later: the rotated outline of a transformed
element (the re-pin) and a write-target picker for a canvas gesture (M6).

The proposal was:

- **Drag and resize handles** on the selection. A gesture writes one
  coalesced transaction: `left`/`top` for absolute elements, `width`/
  `height`, margins for relative elements (port of `layoutCommands.ts`
  and `layoutStyleWritePlanner.ts`). The write target is the inline style
  by default, or the chosen rule (M4).
- Snap to the pixel grid and to sibling edges; Shift keeps the ratio.
- Hit-test with transforms (request R8).
- **Preview mode**: forward input to the SubViewport so buttons, fields
  and lists of the edited document react.

## Re-pin to godot-uxml 6137987 (done)

Done: the pin moved from `0c8b6cd` to `6137987`. The render host loads
with the buffer resolver (R1), reads elements through the handle lookups
(R2), skips template clones with `instance_of()` (R3, R10), hits with
`element_at()` (R8), measures with `get_element_rect()` and
`get_element_transform()` (R14), and updates with `reload_stylesheet()`
and `replace_source()` (R4). The library reads `UxmlControls.catalog()`
(R9); drag and drop uses the collection drag of godot-uxml (R12). No code
reads a private field of godot-uxml or copies its code.

`bench/frame_cost.gd`, median of 3 runs per path, in ms per frame:
before the re-pin -> after the re-pin -> with milestone 4 (`12ac74c`).

| Scenario | menu, native | menu, GDScript | large, native | large, GDScript |
| --- | --- | --- | --- | --- |
| selection | 12.5 -> 10.5 -> 9.3 | 21.9 -> 20.4 -> 15.5 | 25.6 -> 22.3 -> 18.2 | 155.7 -> 71.8 -> 79.2 |
| drag (move) | 14.6 -> 14.7 -> 11.3 | 15.0 -> 18.7 -> 14.2 | 76.3 -> 66.0 -> 33.9 | 79.2 -> 44.3 -> 35.8 |
| hover canvas | 0.18 -> 0.16 -> 0.10 | 0.16 -> 0.17 -> 0.10 | 2.7 -> 1.5 -> 0.8 | 3.0 -> 0.9 -> 0.8 |
| typing | 1.7 -> 1.6 -> 0.9 | 1.6 -> 1.6 -> 0.9 | 2.4 -> 2.1 -> 1.1 | 3.2 -> 2.1 -> 1.2 |
| commit of typing (max frame) | 35-154 -> 31-86 -> 31-37 | 75-155 -> 14-115 -> 68-76 | 981-2045 -> 301-505 -> 280-309 | 2238-33102 -> 830-950 -> 367-774 |
| idle | 0.02 | 0.02-0.03 | 0.03-0.04 | 0.03-0.04 |

The commit of a typing pause now goes through `replace_source()` instead
of a full load. Other agents loaded the machine during the runs, less so
during the milestone 4 runs; the spread between runs is large (for
example, selection on the large document, GDScript, 92-199 ms before).
The first milestone 4 inspector cost 88 ms per selection on the menu
fixture (GDScript): rows of the Classes section changed `display`, and
a display change lays out the whole inspector. The rows now change
`visibility` only.

## M4. Provenance inspector (done)

Done:

- **Declarations** of the focused style property from `explain_style`
  (R5): status, value as written, origin with file and line; a click
  selects the declaration in the source view, an inherited row selects
  the parent.
- **Write targets** after ADR 0004 (`EdStyleTargets`): the matching
  authored rules with the same states, inline, and a new rule for `#name`
  or `.class` in each sheet of the document. One target commits at once;
  more targets open a picker; the choice stays for the property until the
  selection changes; a stale choice is refused.
- **Typed fields** (`EdStyleTypes`): a check per value kind (length,
  number, colour, enum from godot-uxml, asset, angle, scale, translate,
  origin, time, easing, property list) and a helper per fixed row
  (keyword menu, unit menu, colour picker, asset menu with project path
  validation).
- **Class editor**: add and remove classes (exact patches of the `class`
  value) and the rules of each class, with a mark for the rules that
  apply now.
- **State preview** with forced states (R6): `:hover`, `:active`,
  `:focus`, `:checked`, `:selected`, `:disabled`. The canvas shows the
  state; the declarations and the targets show and edit the state rules.
- **Attributes**: enum choices and defaults of the catalog (R9) as
  placeholders, a menu of the catalog attributes; no gap from the spare
  rows.

Not done: a USS rule view of a whole sheet (the source view shows the
sheet); per-row typed controls that show the current value (request R17).
M6 added the write-target picker for canvas gestures and the easing curve
previews.

The proposal was:

- For each property: the computed value, the declaration that wins, the
  declarations it overrides, and "inherited from" / "theme default".
  The winning origin is available now (computed style `origin`); the
  candidate list needs request R5.
- **Write targets** (ADR 0004): inline style, an authored rule (each USS
  rule that matches), or a new rule in a chosen sheet. The picker appears
  only when more than one target is valid; a stale target is refused.
  `EdUssCommands.set_declaration`, `remove_declaration` and `insert_rule`
  are ready and tested.
- Typed fields: colour picker, length with unit, enum dropdowns, asset
  picker for `url()` / `resource()` with project path validation.
- Class list editor and a USS rule view of the selected sheet.

## Frame cost (done)

`bench/frame_cost.gd` measures the editor frame on both godot-uxml paths.
Each selection change and each render rebuilt the inspector document
(about 300 ms native, 900 ms GDScript), and each canvas drag step reloaded
the document. Now the inspector changes in place, `style` and `class`
edits patch the render, and the window skips unchanged list, menu and
label updates. Menu fixture, median per frame: selection 246 -> 9 ms
native and 879 -> 17 ms GDScript; drag 335 -> 8 ms native and 935 -> 14 ms
GDScript; idle 0.02 ms. Large documents still pay a full reload for
structure and USS edits (requests R4, R15). The bench also found that a
typing pause never committed the source view; that is fixed.

## M5. Diagnostics and recovery (done)

Done:

- **Diagnostics panel**: godot-uxml diagnostics of the last render of each
  open document, the parse problems of the editor, unknown elements and
  the last 20 refused edits. Filters by severity, file and source. A
  selection opens the document, selects the element in the canvas and the
  hierarchy, and selects the range in the source view. The end of the
  range comes from the editor parse (request R11).
- **Recovery journal** (ADR 0005, section "Godot app"): a hash-chained,
  versioned JSON-lines journal per project, a record at each buffer
  change, compaction past 4 MB, Recover or Discard at the next open,
  after the external-change check. A test kills a child editor process
  by its PID and recovers its edit.
- **External changes** on a 2-second timer and on focus, with a cheap
  size and time check. Clean files reload; dirty files ask Reload or Keep.
- **Tabs** over the canvas with one history (ADR 0008); Ctrl+W, Ctrl+Tab.
- Small limits of M2: the hierarchy has a context menu with the Edit
  commands; an insert into `<VisualElement />` writes `<VisualElement>`.

Not done: a compare view for a conflict (the question offers reload or
keep); a lock for two editors on one project (they share one journal);
the editor-skin look of the context menu (request R16).

The proposal was:

- **Diagnostics** per document with filters (kind, file), a jump to the
  exact source range (request R11), and editor refusals in the same list.
  Unsupported controls, properties and selectors from godot-uxml show
  with their location.
- **Recovery journal** (ADR 0005): a bounded, versioned record chain of
  transactions and file snapshots in `user://recovery/`, flushed before
  each save step, replayed on the next start after a crash, with the
  external-change check applied before replay.
- **External-change watching** with a timer as well as on focus, and a
  per-file reload/keep/compare dialog.
- **Multi-document tabs**; the one history stays global.

## M6. Pseudo-states and the transition timeline (done)

Done:

- **Live playback**: a toggle of the state preview and a class edit play
  the transitions of the change on the canvas (R6, R7).
- **Timeline panel**: one track per transitioning property of the selection
  or the document; bars for the delay, the duration and the easing; play,
  pause, loop, speed and scrub through `seek_transitions`; a From and a To
  state (for example normal to `:hover`, or class `a` to class `b`).
- **Edits from the timeline**: a bar drag changes the delay or the
  duration, a double-click the easing, through the write targets of the
  inspector, as one undo step per gesture.
- **Easing**: the curve in the inspector and a picker of the Unity keywords.
- **Panel layout**: pane sizes per user, a wider inspector, long texts that
  elide with a tooltip, a Classes section of the height of its content, and
  the write-target picker for canvas drags.

Not done: a step button (scrub does this); a run of more than one selected
element; a change of the timing function by a drag of curve handles (USS
has keywords only). The inspector shows the computed values of a run at the
last render, and again at the end of the run, not at each frame.

### M6 frame cost

`bench/frame_cost.gd`, in ms per frame: median, with the maximum in
parentheses. Median of 3 runs per path (large, GDScript: 1 run). Other
agents loaded the machine during the runs (about 70% CPU).

| Scenario | menu, native | menu, GDScript | large, native | large, GDScript |
| --- | --- | --- | --- | --- |
| timeline: scrub (one seek per frame) | 3.05 (4.04) | 4.11 (5.79) | 2.28 (3.67) | 3.97 (5.52) |
| timeline: play with loop | 2.26 (3.29) | 3.92 (5.84) | 1.75 (2.93) | 3.29 (4.08) |
| timeline: idle, armed | 0.12 (0.27) | 0.08 (0.19) | 0.08 (0.18) | 0.12 (1.26) |
| timeline: frame of a bar edit (p95) | 23.8 | 35.3 | 356 | 1509 |
| selection | 20.0 (203) | 98.4 (662) | 32.2 (284) | 131 (649) |
| drag (move) | 12.9 (40.5) | 16.1 (128) | 33.3 (289) | 43.7 (696) |

The worst scrub frame of all runs on the menu fixture, native, is 4.11 ms
(the limit is 16 ms). A bar edit on the large document reloads the
stylesheet (requests R4, R15), and the edit also starts the run again.

Selection costs more than in milestone 4 (9.3 ms native, 15.5 ms GDScript;
base commit `cd7fc1c` in this load: 9.85 ms native). The Classes section now
has the height of its content, so a change of the number of classes lays
out the inspector. The scenario `selection, same number of classes` needs no
such layout: 13 ms native, 22 ms GDScript, against 23 ms and 132 ms for
the mixed scenario in the same runs. The two runs show request R15, item 4.

## Re-pin to godot-uxml dc2c081 and two cost fixes (done)

The pin moved from `6137987` to `dc2c081` (R15, R16, R11). The context menus
use `show_context_menu` and `set_context_menu`, the diagnostics the severity
and the range of godot-uxml, and text goes through `set_text`.

`bench/frame_cost.gd`, one run per path, in ms per frame: at the old pin ->
at the new pin -> with the fixes.

| Scenario | menu, native | menu, GDScript | large, native | large, GDScript |
| --- | --- | --- | --- | --- |
| selection, median | 16.2 -> 15.2 -> 10.0 | 111 -> 82.0 -> 16.6 | 20.6 -> 20.0 -> 17.9 | 120 -> 98.3 -> 62.3 |
| selection, same number of classes, median | 9.3 -> 10.9 -> 8.3 | 18.9 -> 49.3 -> 14.1 | 20.1 -> 19.4 -> 17.3 | 121 -> 98.7 -> 62.4 |
| layouts of the inspector per 60 selections (new pin -> fixes) | 106 -> 0 | 106 -> 0 | 93 -> 0 | 93 -> 0 |
| bar drag, frames that write, p95 | 22.2 -> 17.6 -> 4.9 | 33.0 -> 21.2 -> 10.4 | 425 -> 319 -> 31.8 | 1459 -> 1088 -> 294 |
| the release of a bar drag, worst frame (fixes) | 2.0 | 5.4 | 1.8 | 5.5 |
| the render after the pause, worst frame (fixes) | 15.0 | 19.6 | 315 | 1094 |
| timeline: scrub, median | 2.35 -> 2.35 -> 2.33 | 4.95 -> 7.17 -> 6.66 | 2.62 -> 2.14 -> 2.14 | 4.94 -> 5.91 -> 6.34 |
| drag (move), median | 12.3 -> 11.9 -> 12.1 | 17.3 -> 15.6 -> 15.8 | 40.6 -> 28.9 -> 28.7 | 42.3 -> 29.6 -> 29.5 |

The "new pin" column has `set_text` in place of the direct writes: the
same-number case on GDScript went up to 49 ms, because the labels of the
inspector counted as text that can move an element (R22). The fix puts them in
rows.

- **Selection.** A change of the number of classes or extra rows needs no
  layout now: the rows stay in the layout, and the content below moves up with a
  paint-only `translate` (`EdInspectorView._compact`). The first selection of a
  run has the old maximum: the first restyle after a load.
- **Bar drag.** The write cost, on the large document, native: the edit and the
  patch under 4 ms, `reload_stylesheet` and the element map 157 ms, the arm of
  the run with the restyle 128 ms. A drag now writes once, at its end, and the
  run shows the value through the model during the drag. The render waits for a
  pause of 0.4 s (`EdMain.RELOAD_PAUSE`). Targets: under 16 ms on the menu
  fixture (reached: 4.9 ms in the drag, 2.0 ms at the release, 15.0 ms for the
  render); no frame over 100 ms on the large document in the gesture (reached:
  35 ms in the drag, 1.8 ms at the release). The render after the pause is over
  the target on the large document: 315 ms, with no gesture running. The cost is
  in `reload_stylesheet` (request R25).

## M7. State-machine panel (done)

Done:

- **Panel.** The **States** toggle of the toolbar opens the panel beside the
  timeline. The state of the panel and its width are kept per user. The panel
  is closed by default and costs nothing while it is closed.
- **Nodes.** normal, hover, pressed, focused, checked, disabled. A state with
  rules is filled and has the number of rules; a state without rules has a
  dashed outline. A dot marks the state that the canvas shows. `:selected` is
  the old name of `:checked`, so one node has both.
- **Edges.** One arrow per direction, for normal and hover, hover and pressed,
  normal and focused, normal and checked, normal and disabled, when the far
  state has rules. A solid blue arrow has a transition, with its time when lit;
  a dashed grey arrow is instant; a faint arrow changes no value. The transition
  comes from the state that the change goes to.
- **Selection.** A click on a node forces the state (R6) and shows the
  declarations of its rules in the declaration list of the inspector, with the
  status of each and a jump to the source. A click on an arrow plays the change
  on the timeline (`EdTimelineView.run`). Up and Down step through the states.
  A click on the empty graph or Escape ends the selection.
- **Sync.** A render builds the graph again, so a source edit, an undo and a
  redo show at once. The forced state stays with its element when an edit of
  the source changes the ids. Another selection, closing the panel, preview and
  another document give the state preview its states back. A toggle of the state
  preview takes the state over.

Not done: a graph edit (a new state rule from the panel); an edge between two
states other than the listed pairs (a state with two forced states is a run of
the timeline, with From and To as text); states on an ancestor
(`.a:hover .b`).

### M7 frame cost

`bench/frame_cost.gd`, median (p95), in ms per frame.

| Scenario | menu, native | menu, GDScript | large, native | large, GDScript |
| --- | --- | --- | --- | --- |
| states: idle, open | 0.08 (0.09) | 0.07 (0.08) | 0.08 (0.12) | 0.08 (0.09) |
| states: selection, panel open | 11.3 (15.8) | | 18.2 (21.5) | |
| states: selection, panel closed | 9.81 (16.4) | | 16.2 (19.6) | |
| states: one build of the graph | 2.76 (3.34) | | 2.86 (3.08) | |
| states: force a node, one per frame | 13.2 (15.8) | 60.2 (68.7) | 20.5 (24.2) | 202 (213) |
| states: play an edge, one per frame | 11.5 (13.1) | 21.9 (24.2) | 24.3 (27.0) | 160 (164) |
| states: hover over the graph | 0.19 (1.00) | 0.18 (3.96) | 0.19 (1.11) | 0.19 (4.24) |

A build waits for a frame without a change, so a run of selections builds once.
A node costs one layout of the inspector through the state toggles (R17).

## M8. Packaging and the web export

- **Desktop**: export presets for Windows (with the native core) and for
  Linux and macOS (GDScript path); a CI job that downloads Godot 4.7.1 and
  runs the suite on the GDScript path on Linux and on both paths on
  Windows.
- **Web export**: the GDScript path (the native DLL does not load in a
  browser), the Compatibility renderer, and a project host for the browser
  (File System Access API through `JavaScriptBridge`, with the same
  revision checks; fallback: open and download a zip). The core has no
  native dependency today, so the work is the host and the file picker.
- Command palette and a keyboard shortcut map.
