# Compatibility

What this editor's preview can and cannot reproduce, and how confident each
answer is. The same facts are visible in-app in the Diagnostics panel's
**Preview fidelity** section; this document is the check-in-readable form.

## Engine

| Fact | Value |
|---|---|
| Engine | `uxml-preview`, vendored at `vendor/uxml-preview/` |
| Engine version | 0.5.0 (tag `v0.5.0`, upstream `8cbd5cb`), plus in-tree additions recorded in `vendor/uxml-preview/PROVENANCE.md` |
| Measured against | Unity **6000.0.40f1** — geometry and built-in theme values dumped from a running editor |
| Documented against | Unity **6000.3** — control structure taken from Unity's published `ussClassName` constants and manual diagrams, never measured |

"Measured" and "documented" are different grades of truth and are never
conflated — in this table, in `UxmlPreviewAdapter.fidelityProfile()`, and in
the inspector's style-provenance labels.

## Controls

| Control | Support | Evidence |
|---|---|---|
| `VisualElement` | rendered | measured |
| `Label` | rendered | measured |
| `Button` | rendered | measured |
| `Image` | rendered | measured |
| `ScrollView` | rendered, incl. three implicit levels | measured |
| `Toggle` | rendered (label + checkmark parts) | documented |
| `Foldout` | rendered | documented |
| `DropdownField` | rendered | documented |
| `TextField` | rendered | documented |
| `IntegerField` | rendered | documented |
| `FloatField` | rendered | documented |
| `Slider` | rendered | documented |
| `SliderInt` | rendered | documented |
| everything else (`ListView`, `MinMaxSlider`, `Vector3Field`, custom elements, …) | fallback box | reported per element |

A control with no renderer draws as a plain box that lays its children out —
its own styles and children still render, and one diagnostic is reported per
element. Nothing is dropped and nothing is rewritten; the fallback exists so
one unfamiliar tag cannot blank half a screen.

Documented controls are structurally rendered — captions, parts, and Unity's
documented class names, so `.unity-base-field__label`-style selectors reach
them — but no coordinate has ever been checked against a running Unity. The
diagnostics panel lists them separately for exactly that reason.

## Templates

| Feature | Status |
|---|---|
| `<ui:Template src="…">` / `<ui:Instance>` | measured; nested expansion capped at 32 |
| `<AttributeOverrides>` | measured; `style` overrides ignored with a diagnostic (Unity ignores them on import) |
| Cyclic templates | blocked fail-closed, `template-cycle` diagnostic |
| Slots | unsupported, `template-slot-unsupported` diagnostic; slot children are not placed |

## USS

| Surface | Supported | Not supported |
|---|---|---|
| Selectors | universal `*`, type, class `.x`, name `#x`, pseudo `:state`, descendant, child `>` | sibling `+`/`~`, attribute `[…]`, functional pseudo `:not()`/`:nth-child(…)`/etc., `::pseudo-elements`, `@media` |
| Pseudo states | `:hover`, `:active`, `:focus`, `:disabled`, `:checked`, `:selected`, `:inactive` — applied as explicit per-element input, never from pointer events | functional pseudo-classes |
| Length units | `px`, `%`, `auto`, `none`, `initial`, bare numbers | `em`, `rem`, `vh`, `vw`, `vmin`, `vmax`, `pt`, `cm`, `in`, `calc()` — each reports a diagnostic rather than being misread as pixels |
| Properties | the flex family, box model, position, margin/padding, colors, opacity, visibility, typography, transforms, `background-image` with `url()`/`resource()` | `display` modes, `position: fixed/sticky`, `float`, `z-index`, `box-shadow`, `filter`, `mask`, `line-height`, `text-decoration`, `transform: skew()`, 3D transforms, `@keyframes`, `-unity-slice-*`, `-unity-background-image-tint-color`, `-unity-text-outline-*` |

A rule containing an unsupported selector fragment is dropped **whole** with
one diagnostic naming the fragment — it still round-trips intact in source.

For the property-by-property matrix with grades and per-item status, see the
engine's own `vendor/uxml-preview/docs/supported.en.md`; divergent
measurements are enumerated in `vendor/uxml-preview/docs/accuracy.en.md`.

## Asset references

| Form | Resolution |
|---|---|
| `url("relative/path")` | relative to the declaring file |
| `url("project://database/Assets/…")`, `url("/Assets/…")` | project-root-fixed |
| `project://database/Packages/…` | resolved when the package physically exists under `<projectRoot>/Packages/` |
| `resource("…")` | Resources lookup; editor built-ins cannot be resolved by a disk-only host — a placeholder is drawn and a diagnostic reported |
| `Library/PackageCache/…` | never searched; reports `package-path-not-searched` |

## Known divergences

These are confirmed differences between the preview and Unity that cannot be
closed from inside this repository. Identifiers are stable — diagnostics key
off them.

| ID | Kind | Summary |
|---|---|---|
| `text-metrics` | unreproducible | Text-dependent layout can be a few pixels off Unity — the browser measures with its own font stack, Unity with its font asset. 10 of 16 measured divergent values trace here. |
| `wrap-container-height` | unspecified | A wrapping container's height can differ — Unity's own rule for this case is not identified, so there is no target to match. |
| `yoga-percent-without-parent-size` | upstream | A main-axis percentage against an unsized parent can resolve differently — the difference lives in the yoga-layout dependency, deterministic and pinned to a measured case. |

## Source fidelity

Compatibility limits affect **preview**, never the file. Unknown controls,
unknown properties, comments, attribute order, formatting, and newline style
are preserved byte-for-byte; an open/save cycle with no edits is
byte-identical. Edits are localized, deterministic patches, and edits the
editor cannot express unambiguously are refused with a diagnostic rather than
approximated in source.
