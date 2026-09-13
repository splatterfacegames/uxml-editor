# ADR 0003: Source-Backed Editing

## Decision

Every authoring operation edits the source text directly as a localized
`SourcePatch` and reparses the affected file; the parsed document is never
serialized back. An operation that cannot be expressed unambiguously is
refused with a diagnostic and mutates neither source nor history.

## Evidence

- `src/core/commands/SourcePatch.ts` validates patch sets — rejecting
  out-of-range spans, surrogate-boundary cuts, overlaps, and ambiguous
  same-start pairs — so a malformed edit fails closed instead of corrupting
  bytes. An exhaustive round-trip test applies every valid patch combination
  over small sources and compares against naive slicing.
- `tests/e2e/editor.spec.ts` and the `DocumentSession`/`SourceBuffer` unit
  tests assert byte-identical open/save round trips, CRLF/LF preservation,
  and localized diffs for canvas, inspector, and hierarchy edits.
- Invalid edits — a disallowed move/resize, an out-of-range color, an unsafe
  asset path, a missing namespace — are covered by non-mutation oracles at
  both unit and e2e level: source and undo history are checked unchanged,
  not merely re-rendered.
- The alternative (a canonical serializer) was rejected because any
  normalization — attribute order, quote style, whitespace, comment
  placement, unknown elements — silently rewrites files the user never
  touched. With patches, "preserve everything" is the default rather than a
  feature that can regress.
