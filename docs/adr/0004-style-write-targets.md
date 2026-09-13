# ADR 0004: Style Write Targets

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
