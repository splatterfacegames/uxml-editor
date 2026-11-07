# ADR 0006: Godot Host on godot-uxml

> **Status: accepted (2026-11-07).** Supersedes ADR 0001 and ADR 0002.

## Decision

The editor is a Godot 4.7 application. godot-uxml renders the edited
document in a `SubViewport`, and godot-uxml also renders the editor window
from UXML and USS with the Unity editor dark skin. The source-backed
editing core of the TypeScript editor is ported to GDScript
(`src/core/`). Native Godot controls are used only where godot-uxml is the
wrong tool (CodeEdit for source, a SubViewport for the canvas, the
operating system folder picker, a modal confirmation).

## Evidence

- The previous renderer, a vendored `uxml-preview` 0.5.0, was measured
  against Unity 6000.0. It had no `filter`, `aspect-ratio`, SVG, 9-slice or
  text outline, 13 controls (8 of them from documentation only) and no
  animation.
- godot-uxml at the pinned commit (`godot-uxml.pin`) matches Unity 6000.3
  in 176 of 177 parity cases (structure, geometry, resolved style), with
  99.8% of box pixels exact. godot-uxml has every runtime and editor
  control, the default runtime theme, the editor dark and light skins,
  transitions, templates and data binding. The editor gets all of that
  without a second renderer.
- godot-uxml keeps the open tag offset of each element and the cascade
  origin of each computed value. The editor maps rendered elements and
  winning declarations back to exact source spans with its own span
  parsers, which follow the godot-uxml grammar
  (`tests/unit/test_source_parsers.gd`, 144 UXML and 67 USS fixtures, both
  godot-uxml paths).
- The godot-uxml native core is a Windows x64 DLL. The GDScript path gives
  the same results and runs the whole test suite (`-- --gdscript`). A web
  export needs the GDScript path; the core has no native dependency.

## Rejected alternatives

### Port godot-uxml to a canvas web renderer

Rejected: a second implementation drifts from godot-uxml, the same failure
that ADR 0002 tried to avoid with the adapter boundary.

### Embed a Godot web export in the React editor

Rejected: two runtimes, two input systems and a message bridge for each
selection, hit-test and style query. The editor would still need the Godot
APIs for every view that shows rendered state.

## Consequences

- Godot APIs that the editor needs from godot-uxml are recorded in
  `docs/godot-uxml-requests.md` and land through godot-uxml changes with
  that repository's verification suite. The editor uses workarounds until
  then.
- The TypeScript Vitest and Playwright suites are replaced by the headless
  Godot runner (`tests/run_tests.gd`).
- Desktop packaging (export presets) and the web export are later
  milestones.
