# ADR 0007: godot-uxml Pinned as a Synced Copy

> **Status: accepted (2026-11-07).**

## Decision

`addons/godot_uxml` is a byte-exact copy of one godot-uxml commit, native
DLL included. `godot-uxml.pin` records the commit, its date and the
source. `tools/update_godot_uxml.py --ref <commit>` replaces the copy and
the pin, and copies the godot-uxml parity cases of the same commit to
`tests/fixtures/godot-uxml-parity` (round-trip fixtures).

## Evidence

- godot-uxml commits the Windows DLL inside `addons/godot_uxml/bin`. A
  copy makes a plain `git clone` of the editor runnable; a submodule needs
  `--recurse-submodules` and a second clone of the whole godot-uxml
  repository (benchmarks, Unity dump project, native sources).
- The update script exports with `git archive <commit>`, so the copy comes
  from a commit and never from a working tree with local changes.
- `.gitattributes` marks the copy `-text`, so no line ending conversion
  changes it.

## Rejected alternatives

### Git submodule at `addons/godot_uxml`

Rejected: godot-uxml keeps the addon in a subdirectory, so a submodule at
the addon path is not possible without a sparse checkout, and a submodule
of the whole repository puts the addon at the wrong path for Godot.

## Rules

- Do not edit files under `addons/godot_uxml`. A change goes to godot-uxml
  first; then move the pin.
- After a pin update, run the test suite on the native and the GDScript
  paths and check `docs/godot-uxml-requests.md` for workarounds that can
  go.
