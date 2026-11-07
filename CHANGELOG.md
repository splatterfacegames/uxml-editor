# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
