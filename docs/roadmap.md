# Roadmap

Milestone 1 (done on the `godot` branch): the Godot project with godot-uxml
pinned, the ported source-backed core with its tests, the canvas with live
render, pan, zoom, selection and hit-test, the hierarchy, the source view
in sync, one undo history, inspector v1 (attributes and inline styles),
revision-checked saves.

Milestones 2 and 3 (done on the `godot` branch, against godot-uxml
`0c8b6cd` with workarounds): see the two sections below. Screenshots:
`docs/screenshots/m2-*.png` and `m3-*.png`.

The milestones after M3 are a proposal. Each milestone ends with the headless
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

Not done: a context menu in the hierarchy (the Edit menu and the
shortcuts cover the commands); attribute lists per element in the
inspector (request R9).

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
`align` and `distribute`); the rotated outline of a transformed element
(the overlay draws the unrotated rectangle); a write-target picker for a
canvas gesture (M4 adds the picker to the inspector).

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

## M4. Provenance inspector

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

## M5. Diagnostics and recovery

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

## M6. Pseudo-states and the transition timeline

- **State preview**: toggles for `:hover`, `:active`, `:focus`,
  `:checked`, `:disabled` on the selected element. Request R6 makes the
  state stay on whatever the pointer does. Transitions play on each
  toggle.
- **Transition timeline** (old issues #6-#11, #18): run the document with
  `transitions_manual = true`; show one track per running transition
  (element, property, delay, duration, easing); play, pause, step and
  scrub. Needs request R7 for seek and the snapshot.
- Inspector support for `transition-*` with an easing curve preview.

## M7. State-machine panel

- A panel that lists the interaction states of a control (normal, hover,
  pressed, focused, checked, disabled) as nodes, and the USS rules that
  style each state as edges. Selecting a node forces the state (R6) and
  opens the rules in the provenance inspector. Selecting an edge plays the
  transition between the two states on the timeline (M6).

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
