# Architecture

A Tauri 2 desktop host around a browser-first React editor core. The editor
core runs unchanged in a real browser (the e2e suite exercises it there); the
Rust host supplies native file IO, menus, watching, and atomic saves.

## Layers

```
┌─────────────────────────────────────────────────────────┐
│ src/features/        React workbench: palette, hierarchy, │
│                      canvas, inspector, diagnostics,      │
│                      source (CodeMirror), workspace shell │
├─────────────────────────────────────────────────────────┤
│ src/core/store/      EditorStore + CommandRegistry — the  │
│                      observable application boundary      │
├─────────────────────────────────────────────────────────┤
│ src/core/documents/  DocumentSession: parsed document +   │
│ src/core/commands/   source buffer, span patches, undo    │
├─────────────────────────────────────────────────────────┤
│ src/core/adapter/    UxmlPreviewPort — the only type the  │
│                      app knows; UxmlPreviewAdapter maps   │
│                      the vendored engine onto it          │
├─────────────────────────────────────────────────────────┤
│ vendor/uxml-preview/ The preview engine (see ADR 0002)    │
├─────────────────────────────────────────────────────────┤
│ src/core/host/       HostPort: MemoryHost (tests),        │
│                      BrowserHost (File System Access),    │
│                      TauriHost (desktop)                  │
├─────────────────────────────────────────────────────────┤
│ src-tauri/           Rust: scoped fs, atomic save, watch, │
│                      native menus, app-data paths         │
└─────────────────────────────────────────────────────────┘
```

## Source fidelity is the invariant

`DocumentSession` holds the parsed document *and* the exact source text of
every file it came from. Every edit — canvas drag, inspector commit,
hierarchy reparent, palette insert — becomes a `SourcePatch`
(start/end/replacement in UTF-16 code units) applied to the source buffer,
after which the affected file is reparsed. There is no serialize-the-model
path, so opening and saving a file without edits is byte-identical:
comments, unknown controls and properties, attribute order, formatting, and
newline style are all preserved by never being round-tripped at all.

Edits that cannot be expressed unambiguously are refused with a diagnostic
rather than approximated. See `docs/adr/0003-source-backed-editing.md`.

## Style write targets

When the inspector writes a style value it must choose *where* the value
lands: an inline `style="…"` attribute, an existing authored rule, or a new
rule. `src/core/documents/StyleTarget.ts` models the choices; when more than
one is valid the user picks explicitly, and the choice is pinned to the
selection it was computed for so a stale commit cannot write to a target that
no longer matches. See `docs/adr/0004-style-write-targets.md`.

## Persistence and recovery

`SaveCoordinator` drives atomic saves through the host (write-temp-then-
rename in `src-tauri/src/atomic_save.rs`). `RecoveryJournal` keeps a bounded,
validated record chain of transactions and file snapshots so a crash or a
failed replacement can restore the pre-edit state. See
`docs/adr/0005-recovery.md`.

## Diagnostics

Parse warnings, render warnings, and editor refusals share one
`EditorDiagnostic` union and one panel. Diagnostics carry source spans so
activating one selects the element and opens the exact file range. The
panel's **Preview fidelity** section surfaces
`adapter.fidelityProfile()` — engine version, measured vs documented Unity
versions, per-control evidence, and known divergences — so compatibility
claims are visible where the user already looks. See `docs/compatibility.md`.

## Desktop host

`TauriHost` implements `HostPort` over Tauri commands. The Rust side enforces
project-root scoping (`scoped_fs.rs`), atomic replacement (`atomic_save.rs`),
file watching (`watch.rs`), and native menus that route through
`DesktopCommandBridge` into the same `CommandRegistry` the web UI uses — so a
menu item and its toolbar/palette twin cannot diverge.

## Testing

- `npm test` — Vitest unit/integration suite, **including the vendored
  engine's own tests** (golden layout cases measured against Unity).
- `npm run test:e2e` — Playwright against the real browser build.
- `npm run test:rust` — host-side unit tests.
- `scripts/check-licenses.mjs` — third-party notice completeness.
- `scripts/check-goal.mjs` — maps the 13 definition-of-done items in the
  product goal to concrete evidence and exits non-zero on gaps.
