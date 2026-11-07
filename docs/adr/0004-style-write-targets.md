# ADR 0004: Style Write Targets

> **Status: accepted, implemented in the Godot app (milestone 4).** Style
> targets (`EdUssCommands.inline_target`, `rule_target`, `new_rule_target`)
> freeze the source and the exact spans, and a stale commit is refused.
> The inspector derives the valid targets from the godot-uxml cascade
> candidates (`explain_style`, request R5) in `EdStyleTargets`: the
> authored rules that apply with the same pseudo-states, the inline style
> (no state), and a new `#name` or `.class` rule in each stylesheet of the
> document. One valid target commits at once; more open a picker. The
> choice stays for the property until the selection or the state preview
> changes. Theme, inherited and default values have no authored
> destination and are never offered. Milestone 3 canvas gestures
> (`EdLayoutCommands`) still write each layout property to the declaration
> that wins (or a new inline declaration for a theme or default value)
> without a picker; a pseudo-state winner and an overridden longhand are
> refused there. The `evidence` (measured/documented) labels below came
> from `uxml-preview`; godot-uxml theme values are all measured in Unity
> 6000.3.


## Decision

Inspector style edits are written to an explicit, user-visible destination —
the inline `style` attribute, an existing authored USS rule, or a new rule —
chosen by a target picker whenever more than one destination is valid. The
chosen target is frozen against the selection it was computed for, and a
commit arriving after the session or selection moved on is refused rather
than redirected.

## Evidence

- `src/core/documents/StyleTarget.ts` derives the valid target set from the
  cascade candidates the adapter reports, so a write never lands somewhere
  the winner did not come from.
- `InspectorPanel` tests pin the behaviors that make this safe: the picker is
  required only when ambiguous, one safe destination commits directly, a
  stale choice is refused without another mutation, and every commit is one
  undoable transaction.
- Inherited, default, and built-in theme origins are described without
  invented file paths — a built-in value has no authored destination, and the
  UI says so instead of offering to "edit" a theme constant.
- Built-in theme origins now carry `evidence` from the engine: values
  measured against a running Unity 6000.0.40f1 are labeled as measured, and
  values reconstructed from Unity 6000.3 documentation are labeled
  documented-but-unmeasured in both label and tooltip.
