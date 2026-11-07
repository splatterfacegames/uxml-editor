# ADR 0008: Document Tabs Share One History

> **Status: accepted (2026-11-07).** Milestone 5 of the Godot app.

## Decision

The editor opens several UXML documents in tabs over the canvas. All tabs
share the one undo history of the project (`EdWorkspace.history`, ADR
0003). Undo and redo take the newest step of the project. When that step
belongs to a document in another tab, the editor shows that tab first, and
the selection of the step comes back there.

Each tab keeps its own selection. Closing a tab does not discard edits:
the buffers belong to the project, the project list marks unsaved files,
and Save All saves them. The history keeps the steps of a closed tab; an
undo of such a step opens the document in a tab again.

## Evidence

- A transaction already records its document (`EdTransaction.document`)
  and may patch several files (a UXML file and its stylesheet). A history
  per tab would split a step that changes a stylesheet two tabs share, and
  the undo of one tab could then change the text under the other tab.
  One history keeps the patches of every file in one order, so each undo
  restores exact bytes (ADR 0003).
- Unity UI Builder has one undo stack for the editor (Unity's global Undo),
  not one per document.
- A reload from disk already drops the steps that touch the reloaded file
  and keeps the others (`EdCommandHistory.forget_path`); the same rule
  works across tabs.
- `tests/unit/test_app_workspace.gd::test_tabs_share_one_history` edits two
  tabs, undoes both (the second undo shows the first tab), redoes, closes a
  tab with its button and with Ctrl+W, and checks the selection per tab.

## Rejected alternatives

### One history per tab

Rejected: a shared stylesheet makes the histories depend on each other.
An undo in tab A of a USS change, after tab B changed the same rule, needs
the patches of B first, or the inverse patches no longer apply to the
text. Making the histories consistent needs a global order, which is the
one history again.

### Close a tab discards its unsaved edits

Rejected: a stylesheet can belong to several open documents, so "the
edits of a tab" has no exact meaning. The recovery journal (ADR 0005)
also keeps the edits of closed tabs.
