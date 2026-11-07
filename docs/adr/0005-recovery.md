# ADR 0005: Recovery Journal

> **Status: accepted, implemented in the Godot app (milestone 5).**
> `src/core/recovery_journal.gd` (`EdRecoveryJournal`) and
> `src/app/editor_state.gd` carry the decision; the "Godot app" section
> below lists the details. The evidence section names the files of the
> TypeScript editor on `main`.


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

## Godot app

- **File.** One journal per project: `<recovery dir>/<16 hex digits of the
  SHA-256 of the project root>/journal.jsonl`. The recovery directory is
  `user://recovery` (option `--recovery-dir`).
- **Records.** One JSON line each: `{v, seq, prev, kind, ...}`. `prev` is
  the SHA-256 of the line before, so the records form a chain. Kinds:
  `header` (project, time), `base` (the saved text and revision of a file
  before its first unsaved edit), `patch` (start, end, text), `clean` (the
  file has no unsaved edit: saved, reloaded, or undone to the saved text).
- **Flush.** `EdEditorState` records every buffer change at once: the
  record is appended and the file closed before `record()` returns. A save
  writes the file (temporary file, rename), then records `clean`; a kill
  between the two leaves a journaled text that equals the disk text; the
  replay drops such a file.
- **Bound.** Past 4 MB, `compact()` writes a new journal (temporary file,
  rename) with one `base` and one `patch` per unsaved file.
- **Validation.** `EdRecoveryJournal.read()` accepts a complete chain only.
  A line that does not parse, another version, a gap in `seq`, a wrong
  `prev` or a patch outside its text makes the journal corrupt: nothing
  replays, the file is renamed `journal.jsonl.corrupt`, and the status bar
  says so. A last line without its line break (a write cut by a kill) is
  dropped, and the records before it replay.
- **Replay.** At project open, a journal with unsaved files asks: Recover
  or Discard. Before the question, the external-change check compares the
  disk revision of each file with the `base` revision. Recover puts the
  journaled text into the buffer and keeps the `base` revision, so a file
  that changed on disk is a conflict: a save stops with `stale-revision`
  and asks before an overwrite. Discard starts a new journal.
- **Close.** A close with no unsaved file deletes the journal. A close
  with unsaved files keeps it, so the next start offers the edits.
- **Tests.** `tests/unit/test_recovery_journal.gd` (records, clean,
  truncation, a changed record, another version, compaction, the diff)
  and `tests/unit/test_app_recovery.gd` (the journal follows edits and
  saves; a new session recovers the exact text; a changed disk file is a
  conflict; discard; an editor in a child process makes an edit, the test
  kills the process by its PID, and the next editor recovers the edit).
