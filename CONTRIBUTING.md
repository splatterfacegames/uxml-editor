# Contributing

## Setup

Install Godot 4.7.1 (standard build). Then import the project:

```
godot --headless --path . --import
```

Run the import again after you add a script with a new `class_name`.

## Before pushing

```
godot --headless --path . -s res://tests/run_tests.gd
godot --headless --path . -s res://tests/run_tests.gd -- --gdscript
```

Both runs must report 0 failed tests.

## Rules

- **Write the test first.** Expected values come from Unity documentation,
  Unity dumps, the godot-uxml parity data, or the old TypeScript suites on
  `main`, never from the output of the code being written.
- **Source fidelity is non-negotiable.** Edits are patches against the
  exact text. Comments, attribute order, quote style and line endings must
  survive. An edit that cannot be exact is refused, not approximated.
- **Never reimplement rendering or layout.** godot-uxml owns both. When the
  editor needs something from godot-uxml, record it in
  `docs/godot-uxml-requests.md` and use a workaround until godot-uxml adds
  it.
- **Do not edit `addons/godot_uxml`.** Change godot-uxml, then move the
  pin with `tools/update_godot_uxml.py`.
- **Keep the span parsers aligned with godot-uxml.** `EdUxmlSource` and
  `EdUssSource` must find the same elements and items as godot-uxml;
  `tests/unit/test_source_parsers.gd` checks this for every fixture.
- **`src/core` stays headless.** No Godot UI node and no godot-uxml class
  in `src/core`.
- **Editor chrome is UXML first.** Author the editor window in
  `src/app/ui/*.uxml` and `*.uss`. Use a native Godot control only where
  godot-uxml is the wrong tool, and list it in `docs/architecture.md`.
- **USS is not CSS.** `flex-direction` defaults to `column`, the box model
  is always border-box, there is no `z-index`, and there are no
  `@keyframes`.
- **No third-party UI assets.** Do not copy Unity UI Builder code, icons or
  assets. Do not commit Nintendo or Game UI Database assets.
