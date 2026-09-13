# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
