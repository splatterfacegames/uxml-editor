# ADR 0005: Recovery Journal

## Decision

Unsaved editor state is journaled as a bounded, versioned, validated record
chain so a crash — or a failed atomic replacement mid-save — can restore the
exact pre-failure state rather than a best-effort approximation.

## Evidence

- `src/core/persistence/RecoveryJournal.ts` writes serialized transactions
  and file snapshots through `RecoveryJournalCodec`, which bounds the journal
  size and validates the record chain on read; a corrupt or truncated chain
  is detected, not replayed.
- `src-tauri/src/atomic_save.rs` implements host-side write-temp-then-rename,
  and `SaveCoordinator` sequences journal flush → file replacement → journal
  clear so a failure at any step leaves a consistent journal behind.
- `RecoveryJournal.test.ts` (23 cases) and `SaveCoordinator.test.ts`
  (49 cases) cover crash-during-save, failed replacement, stale journals,
  and truncation; the e2e suite exercises recovery after a replacement
  failure through the real workflow.
- Recovery is a property of the journal, not of the host: `MemoryHost` tests
  prove the same guarantees the Tauri host relies on, which keeps the
  coverage host-independent.
