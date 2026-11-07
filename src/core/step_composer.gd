class_name EdStepComposer
extends RefCounted
## Build one transaction from several command steps.
##
## Each step is a Callable(shadow: EdDocumentSession) -> EdTransaction,
## EdError or null. The steps run in order on a shadow copy of the
## workspace, so each step plans against the text that the previous steps
## made. The patches of all steps are then composed into one patch set per
## file against the original text (EdSequentialPatchComposer). The result
## is one undo step. A step error stops the plan; the real buffers never
## change here.
##
## The selection after the transaction is the selection_after of the last
## step that names one.


## A session on a copy of the workspace of `session`. Buffers are shared
## (EdSourceBuffer is immutable; a commit replaces the buffer object), so
## the copy is cheap.
static func shadow_of(session: EdDocumentSession) -> EdDocumentSession:
	var ws := EdWorkspace.new()
	for p in session.workspace.buffers:
		ws.buffers[p] = session.workspace.buffers[p]
		ws.base[p] = session.workspace.base.get(p, {})
	return EdDocumentSession.new(ws, session.entry_path)


static func compose(session: EdDocumentSession, op: String, tx_label: String, steps: Array) -> Variant:
	var shadow := shadow_of(session)
	var composers := {}
	var selection_after = null
	for step in steps:
		var r = (step as Callable).call(shadow)
		if r is EdError:
			return r
		if r == null:
			continue
		var tx: EdTransaction = r
		var c = shadow.workspace.commit(tx)
		if c is EdError:
			return c
		for path in tx.patches_by_file:
			if not composers.has(path):
				composers[path] = EdSequentialPatchComposer.new(session.workspace.text(path))
			if composers[path].apply(tx.patches(path)) != OK:
				return EdError.make("invalid-patch", "A composed step does not fit the text of %s." % path)
		if tx.selection_after != null:
			selection_after = tx.selection_after
	var by_file := {}
	for path in composers:
		var patches: Array = composers[path].patches()
		if not patches.is_empty():
			by_file[path] = patches
	var out := EdTransaction.multi(op, tx_label, by_file)
	out.document = session.entry_path
	out.selection_after = selection_after
	return out
