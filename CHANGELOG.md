# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.8.0] - 2026-11-08

### Changed (Godot rebuild, branch `godot`)

- The editor is a Godot 4.7 application. godot-uxml renders the edited
  document and the editor window; the React/Tauri app and the vendored
  `uxml-preview` engine are removed from this branch (ADR 0006).
- godot-uxml is pinned as a synced copy (`godot-uxml.pin`,
  `tools/update_godot_uxml.py`, ADR 0007).
- The source-backed core is ported to GDScript (`src/core/`) with its
  tests, a round trip of 211 fixtures, and parser alignment checks
  against godot-uxml.
- Milestone 1 views: canvas (live render, pan, zoom, screen presets,
  themes, selection, hit-test), hierarchy, source view, inspector v1
  (attributes and inline styles), one undo history, revision-checked
  saves, reload of clean files changed on disk.

### Changed (pin `5a51b92`)

- godot-uxml moved to `5a51b92` (requests R30, R31 and R32 done; a cross-pass
  native layout cache; quiet restyles; the single flex child of Yoga). The
  round trip has 213 fixtures (2 new parity cases).
- The winner row of the declaration list is bold again. A font change of the
  row lays out only the row (R31). Forcing a state lays out no inspector. The
  bold row adds about 0.7 ms native on the menu fixture and about 0.9 ms on
  the large document, and no time on the GDScript path.
- Typing in the library search: 15.8 -> 13.3 ms native on the menu fixture
  and 17.4 -> 13.0 ms on the large document. Forcing a state on the large
  document: 21.6 -> 17.7 ms native. Selection and the hierarchy scroll did
  not change. The A/B figures are in `docs/roadmap.md`.
- `EdMain._mount()` does not set `clip_contents` on the host control.
  `.host` has `overflow: hidden`, so godot-uxml clips.
- The demo script writes the preview field and the command palette search
  through `set_field_value`, not through `LineEdit.text`.
- `test_forcing_states_lays_out_no_inspector` also checks that the winner
  row is bold.
- New godot-uxml requests R33 (the hidden pooled rows of a collection view
  make the library more than a third of the window, so a new source lays out
  the window) and R34 (the cancel button of a search field lays out the
  window). R30-R32 are done (`docs/godot-uxml-requests.md`).

### Changed (pin `f4ffe6e`)

- godot-uxml moved to `f4ffe6e` (requests R17, R27, R28 and R29 done; selector
  and rule edits reload in place).
- The library search and the command palette search are live TextFields
  (no `is-delayed`). godot-uxml keeps the caret (R27); the editor reads the
  text through `value_changed`. The workaround `EdUi.live_text()` is removed.
- The inspector sets placeholders with `set_field_placeholder` (R28), and
  godot-uxml elides them (R18, `text-overflow: ellipsis` on `.field`).
  `EdUi.elided_placeholder()`, `EdUi.set_silent()` and the refit at a pane
  resize are removed.
- A scroll of the hierarchy lays out only the rows (R29). The hierarchy still
  scrolls after a frame without another selection: the rebind of the rows
  costs about 16 ms native and 50 ms GDScript on the large document.
- `EdRenderHost.last_modes` records the reload mode of each changed file,
  `"rules"` included. Every mode of `reload_stylesheet` keeps the controls
  and the forced states.
- The toolbar and the status line show the folder name of the project, not
  the path. The tooltip of the toolbar label shows the path.
- `bench/frame_cost.gd` measures typing in the library search and two
  hierarchy scrolls.
- Forcing a state in the state-machine panel lays out no inspector: the
  winner row of the declaration list is no longer bold (a font change is not
  paint-only, request R31). GDScript: 65.7 -> 16.2 ms on the menu fixture,
  207 -> 108 ms on the large document. A scroll of the hierarchy on the large
  document: 61 -> 1 window layouts in 60 frames, 48.6 -> 8.2 ms GDScript.
  Selection costs 4-5 ms more native (`set_field_placeholder`, request R30).
  The figures are in `docs/roadmap.md`.
- New godot-uxml requests R30-R32 (`docs/godot-uxml-requests.md`).

### Fixed

- Web: the editor did not scale on a high-DPI screen. The content scale of
  the window is now `window.devicePixelRatio`.
- Web: a poll of the watch timer that ended during a save woke the save
  without its answer, so the save stopped ("no answer") or asked before an
  overwrite. Each request now waits for its own answer.
- In a small window (the editor in the project site), the source view was a
  few characters wide. The fixed panes now get smaller in a small window
  (`EdMain._fit_splits`); the saved sizes stay.
- Site: the editor in the page is wider (up to 1600 px), and the hero
  screenshot shows the sample project without a local path.

### Added (Godot rebuild, milestone 8)

- Command palette (Ctrl+Shift+P): every editor command with a fuzzy search.
  Up and Down choose, Enter runs, Escape closes. A godot-uxml document of its
  own that loads at the first open.
- Shortcut map (Ctrl+/): the current bindings of every command and the keys
  of the canvas, the hierarchy, the state-machine panel and the palette.
- `EdCommandRegistry`: one table of commands and key bindings for the key
  handlers, the Edit menu, the palette and the map. The settings section
  `[shortcuts]` changes a binding.
- Export presets: Windows (with the native core of godot-uxml), Linux, macOS
  and Web (GDScript path, custom feature `gdscript_core`). `--smoke` checks a
  packaged build.
- Web export: the Compatibility renderer, no threads (no cross-origin
  isolation headers), and a project host (`EdWebHost`, `web_host.js`): the
  File System Access API with the revision checks of the desktop, or a zip
  that opens from a file input and downloads at each save.
  `tools/web_smoke.cjs` checks both in headless Chrome or Edge.
- CI (`.github/workflows/ci.yml`): the GDScript path on Linux, both paths on
  Windows, and a check of the godot-uxml copy against the pin.
- `tools/update_godot_uxml.py --verify`; the pin has `addon_sha256`.

### Changed (Godot rebuild, pin `1167eb1`)

- godot-uxml moved to `1167eb1` (requests R17-R26). The update script now
  copies the bytes of the commit: before, `core.autocrlf` gave the copy CRLF
  line endings.
- The render after a timeline bar edit uses the partial stylesheet reload
  (R25): 317 -> 59 ms native and 1079 -> 480 ms GDScript on the 507-element
  document. The 0.4 s pause before the render is gone; the release of a bar
  drag writes and renders.
- Field values go through `set_field_value` (R17); the timeline run uses
  `set_author_classes`, `finish_transitions` and `clear_completed_transitions`
  (R19, R23); the pane sizes save on `split_changed` (R21); the inspector text
  lines need no `.line` rows (R22); the selected-row rule of `.panel-list` is
  gone (R24).
- The state-machine panel takes the timing of each arrow from
  `preview_transitions` (R26): a property that only the theme changes through
  `transition-property: all` counts now.
- The hierarchy scrolls to a selection only when its row is outside the view,
  and only after a frame without another selection (request R29).

### Fixed

- Typing into the library search reversed the characters: godot-uxml puts the
  caret of a TextField that is not `is-delayed` at the start at each change
  (request R27). `EdUi.live_text` keeps the caret.
- An edge of the state-machine panel ran no transition after an earlier run
  of the same element ended with an instant change (R23).

### Added (Godot rebuild, milestone 7)

- State-machine panel, with the **States** toggle of the toolbar: the
  interaction states of the selection as nodes, the state changes as arrows.
  A state without rules has a dashed outline. An arrow with a transition is
  solid, an instant change is dashed.
- A click on a state forces it on the canvas and shows the declarations of its
  rules in the inspector. A click on an arrow plays the change on the timeline.
  Another selection, closing the panel, preview and another document give the
  state preview its states back.
- `EdStateMachine` builds the graph from the cascade of godot-uxml.

### Changed (Godot rebuild, pin `dc2c081`)

- godot-uxml moved to `dc2c081` (requests R15, R16, R11).
- The hierarchy menu and the menus of the inspector are godot-uxml context menus
  in the editor skin, with separators. The anchor controls are gone.
- The diagnostics use the severity and the range of godot-uxml.
- Text goes through `set_text`. The direct writes to the Label controls and the
  copy of the elision are gone.
- A change of the number of classes or extra rows needs no layout of the
  inspector: the content below moves with `translate`. Selection on the menu
  fixture: 16.2 -> 10.0 ms native, 111 -> 16.6 ms GDScript.
- A timeline bar drag writes once, at its end. The run shows the value during
  the drag, and the stylesheet reload waits for a pause. A frame of a bar drag on
  the large document: p95 425 -> 32 ms native.
- The timeline header wraps in a narrow pane, and the From and To fields keep a
  readable width.

### Fixed (Godot rebuild, pin `dc2c081`)

- The easing label of a timeline bar has a band under the text: the curve no
  longer crosses the label.
- A forced state stays with its element when an edit changes the node ids.
- The selected row of a list without focus is readable (workaround of R24).

### Added (Godot rebuild, milestone 6 and panel layout)

- Transitions play on the canvas: a state toggle of the state preview or
  a class edit starts the `transition-*` values of the change (godot-uxml
  `get_transitions`, `seek_transitions`).
- Timeline panel: one track per transitioning property of the selection or
  of the document, with bars for the delay, the duration and the easing;
  play, pause, loop, speed and scrub; a From and a To state (classes and
  pseudo-states). A run changes no source text.
- Timeline edits: a drag of a bar changes the delay, a drag of its right
  end the duration, a double-click opens the easing picker. Each gesture is
  one undo step through the write targets of the inspector.
- Easing curve of `transition-timing-function` in the inspector, and a
  picker with the curve of every Unity easing keyword.
- The write-target picker for canvas drags, at the end of the drag, with
  the same memory as the inspector.
- Pane sizes are kept per user (`EdSettings`, `--settings=<file>`). The
  default inspector is wider: 440 px.
- Long texts end in `...` with the whole text as the tooltip: declaration
  lines, class rules, value origins, list rows, window labels. The Classes
  section has the height of its content.
- `bench/frame_cost.gd`: timeline scenarios and `--only-timeline`.

### Fixed (Godot rebuild, milestone 6)

- A write-target choice no longer ends with a write to the `style` or
  `class` attribute of the element. The memory key held the attribute
  values.
- `--watch-interval=0` printed a timer error.
- The test runner printed an error for a recovery directory that does not
  exist, and prints the time of each test file.
- The crash recovery test tolerates a slow start of its child editor on a
  busy machine.

### Added (Godot rebuild, milestone 4)

- Provenance inspector: the declarations of the focused style property
  from godot-uxml `explain_style` (status, value, file and line) with a
  jump to the source.
- Style write targets after ADR 0004: the authored rules that apply,
  the inline style, or a new `#name` or `.class` rule; a picker when
  more than one target is valid; stale choices are refused.
- Typed style fields: a value check per USS property type and helper
  buttons (keyword menu from godot-uxml, unit menu, colour picker, asset
  menu with project path validation).
- Class editor: add and remove classes with exact patches, and the rules
  of each class with a mark for the rules that apply.
- State preview: `:hover`, `:active`, `:focus`, `:checked`, `:selected`
  and `:disabled` forced on the selection (godot-uxml forced states).
- Attribute hints and an attribute menu from the godot-uxml catalog; the
  Attributes section has no gap from spare rows.
- Tests: 21 new tests (181 in total, 1781 checks) on both godot-uxml
  paths; screenshots `docs/screenshots/m4-*.png`.

### Changed (Godot rebuild, godot-uxml 6137987)

- godot-uxml is pinned at `6137987` (github.com/splatterfacegames/godot-uxml),
  with the editor APIs R1-R14. Every workaround that read private fields
  of godot-uxml or copied its code is gone: loads with the buffer
  resolver, element handles, `element_at`, `get_element_rect`,
  `UxmlControls.catalog()`, the collection drag and drop, and partial
  updates with `reload_stylesheet` and `replace_source`.
- A USS edit restyles the canvas without a full load; the commit of a
  typing pause on a 507-element document costs about 300-500 ms (native)
  instead of 1-2 s.
- An `<Instance>` element maps to its rendered TemplateContainer: a click
  on template content selects the instance.
- The canvas draws the outline of a rotated or scaled element along its
  transform.

### Added (Godot rebuild, milestone 5)

- Diagnostics panel: godot-uxml diagnostics of every open document, the
  editor parse problems, unknown elements and refused edits, with filters
  by severity, file and source. A selection selects the range in the
  source view and the element in the canvas and the hierarchy.
- Recovery journal (ADR 0005): every unsaved edit is written at once to a
  hash-chained, versioned journal per project. The next open after a
  crash asks Recover or Discard, after a check for external changes.
- Changes on disk are checked every 2 seconds (`--watch-interval`) as
  well as on focus. Clean files reload; a file with unsaved edits asks
  Reload from disk or Keep editor text.
- Document tabs over the canvas with one history for all tabs (ADR
  0008). Ctrl+W closes a tab, Ctrl+Tab shows the next tab.
- Hierarchy context menu (right-click) with the Edit commands.
- `bench/frame_cost.gd`: frame cost of the editor on both godot-uxml
  paths; `--gdscript`, `--recovery-dir`, `--ready-file` and
  `--exit-after` options.
- Tests: 22 new tests (160 in total, 1375 checks) on both godot-uxml
  paths, among them a test that kills a child editor process by its PID
  and recovers its edit.

### Changed (Godot rebuild, frame cost)

- The inspector builds its godot-uxml document once and changes it in
  place. A selection change on the menu fixture costs about 9 ms (native)
  and 17 ms (GDScript) instead of about 250 ms and 880 ms.
- A `style` or `class` change of rendered elements patches the canvas
  render through the godot-uxml model instead of a full reload. A canvas
  drag frame costs about 8 ms (native) and 14 ms (GDScript) instead of
  about 335 ms and 935 ms.
- Window lists, menus and labels skip updates with unchanged data;
  labels that change often have a size that does not depend on the text.
- The hierarchy keeps a row index, the hit-test tries the deepest element
  first, and the source view replaces only the changed text.
- The inspector shows the element and its `name` in one title line; the
  common attributes and style properties keep fixed rows.

### Fixed (Godot rebuild)

- A pause in typing in the source view now makes a transaction. The pause
  timer called `flush()`, which returned at once because a one-shot timer
  is already stopped when it times out.
- An insert into a self-closing parent writes `<VisualElement>`, not
  `<VisualElement >`. A line break before `/>` stays.

### Added (Godot rebuild, milestones 2 and 3)

- Library panel: every element that godot-uxml renders, runtime and
  editor, in five groups, with search. Double-click or Enter inserts at
  the selection; a drag inserts at the drop position on the canvas or in
  the hierarchy. A missing `xmlns:ui` or `xmlns:uie` is declared on the
  root in the same undo step.
- Hierarchy drag and drop to reorder and reparent; multi-selection in the
  hierarchy (Shift, Ctrl) and the canvas (Shift+click).
- Edit menu and shortcuts: cut, copy, paste, duplicate, delete, wrap in a
  VisualElement, unwrap, move up and down. Copy keeps the exact source and
  the namespace declarations; paste and duplicate make copied names
  unique. The inspector **Element** field (F2) renames the element type.
- New core commands: `EdStructureCommands` (insert from the library,
  unwrap, remove and move several elements, placement), `EdClipboard`
  (port of `ClipboardService`), `EdStepComposer` (several command steps as
  one transaction).
- Canvas move and resize handles, keyboard nudge, snapping to siblings,
  the parent and a pixel grid, with guides. Each drag and each run of
  arrow keys is one undo step. Layout values go to the declaration that
  wins today (USS rule or inline), after ADR 0004 (`EdLayoutCommands`,
  port of `layoutCommands.ts` and `layoutStyleWritePlanner.ts`).
- Preview mode (Ctrl+P): the canvas sends the mouse and the keyboard to
  the document.
- Hit-test through rotate, scale and translate (Control transforms).
- `--demo=<name>` stages a documentation state before `--screenshot`.
- Tests: 39 new tests (138 in total, 1249 checks) on both godot-uxml
  paths, with end-to-end input through the window.

### Added (Tauri editor, `main`)

- `--open <project-dir>` (or a bare directory argument) opens a Unity project
  on launch. The native host claims the path once through
  `host_take_initial_project`; the frontend opens it through the normal file
  workflow.
- `UXML_EDITOR_CDP_PORT` opts the main window's WebView2 into Chrome DevTools
  Protocol remote debugging for that launch only — the packaged workflow smoke
  test drives the real UI over it.
- `scripts/smoke-packaged-app.mjs` (`npm run smoke:packaged:app`) launches the
  built executable, attaches over CDP, and verifies a real
  open → clean-save byte-identical → inspector edit → localized write →
  relaunch cycle against files on disk.

### Changed

- The main window is constructed in `run()` instead of `tauri.conf.json` so
  WebView2 browser arguments can be opted into per launch; its label, title,
  and size are unchanged.

## [0.1.0] - 2026-09-13

### Added

- Source-backed editing core: patch engine, document sessions, transactions and
  undo history, stable locators, UXML structural commands, and USS commands
  with provenance.
- Canvas, hierarchy, palette, inspector, diagnostics, and source panels behind
  one transaction history.
- Browser host (File System Access API, IndexedDB project identity, memory
  fallback) and Tauri desktop host (scoped filesystem, atomic save, watcher,
  recovery).
- GitHub Actions CI covering typecheck, unit tests, Playwright, browser build,
  license allowlist, and Linux/Windows host tests.
- `scripts/check-licenses.mjs` dependency license gate.
- `Toggle`, `TextField`, `IntegerField`, `FloatField`, `DropdownField`,
  `Slider`, `SliderInt`, and `Foldout` are drawn with the child elements and USS
  classes Unity documents for them, so their `label`, `text` and `value`
  captions appear and `.unity-base-field__label`-style selectors
  reach the generated elements. Their structure is documented, not measured
  against a running Unity, and each says so once through a `version-dependent`
  diagnostic; declarations they contribute carry `evidence: 'documented'` in
  style provenance so the inspector can tell them from measured theme values.
- Diagnostics for property names Unity's USS importer drops, in stylesheets
  (reported at the declaration span) and in inline `style` attributes
  (reported against the element). Custom `--name` properties are exempt.
- `adapter.fidelityProfile()` and the diagnostics panel's Preview fidelity
  section surface the engine version, measured Unity version (6000.0.40f1),
  documented Unity version (6000.3), per-control evidence, and known
  divergences. `docs/compatibility.md` publishes the same matrix.
- Visual-regression baselines: `tests/e2e/visual.spec.ts` compares the
  menu-fixture workbench and canvas with `toHaveScreenshot`; platform-specific
  baselines are committed and enforced in CI.
- Packaged smoke test: `uxml-editor --version-file <path>` writes the package
  version and exits, and `scripts/smoke-packaged.mjs` verifies the built
  executable, installer artifacts, and checksum manifest after `tauri build`.
- `docs/architecture.md`, `docs/compatibility.md`, and ADRs for source-backed
  editing, style write targets, and recovery.
- `scripts/check-goal.mjs` audits all 13 definition-of-done items and exits
  non-zero on missing evidence.
- `release.yml`: tag-triggered Windows release producing MSI and NSIS
  installers, a portable zip, SHA256SUMS.txt, and a CycloneDX SBOM.

### Changed

- `ExternalChangeDialog` renders through the shared-stack `Modal` (focus trap,
  escape, overlay, focus restore) instead of bespoke `useModalFocus` plumbing.
- Vendor chunks are split so no production bundle exceeds the size budget.
- The preview engine is vendored source under `vendor/uxml-preview/` at
  `uxml-preview` 0.5.0 (Apache-2.0) instead of an npm dependency, so Unity 6.3
  parity, further controls, and transition playback can be implemented in it.
  Its upstream test suite runs as part of `npm test`, and the adapter is still
  the engine's only import site. See
  [ADR 0002](docs/adr/0002-vendored-preview-engine.md).
- Engine warnings are mapped through an exhaustive table, so the nine warning
  kinds 0.5.0 added — template resolution, override, duplicate-name, and
  package-path warnings — are classified instead of cast, and a new kind fails
  the typecheck.

### Fixed

- Host tests that prove Windows-only conditional replacement are gated to
  Windows; the non-Windows contract is asserted explicitly instead of failing.
- Save writes every dirty document instead of only the entry document, so USS
  edits are no longer reported as an incomplete save and left on disk unchanged.
- A failed save names the documents that stayed unsaved and the underlying
  host error.
- While a draft keeps the preview stale, diagnostics for that file come from
  the draft, so newly typed problems appear and locations match what is on
  screen instead of the last good parse.
