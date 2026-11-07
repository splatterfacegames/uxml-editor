extends EdAppTestCase
## Crash recovery in the editor: the journal follows the edits, a new
## session offers the unsaved edits, and a killed editor process loses no
## edit.

const RECOVERED := "Recovered after a kill"
## The child editor can start slowly on a loaded machine: the wait ends
## as soon as the child is ready, so a long limit costs nothing when all
## is well. The child ends itself only long after the wait, so a test
## that stops early leaves no process behind.
const CHILD_START_MS := 600000
const CHILD_LIFETIME_S := 900

var _rdir := ""


func _recovery_dir() -> String:
	_rdir = ProjectSettings.globalize_path("user://test-recovery-app-%d" % Time.get_ticks_usec())
	return _rdir


func teardown() -> void:
	await super()
	if not _rdir.is_empty():
		_rm(_rdir)


## An editor on the project at `dir` (no copy), with journals in `rdir`.
func _editor_on(dir: String, rdir: String) -> EdMain:
	tree.root.size = Vector2i(1600, 1000)
	var m: EdMain = load("res://src/app/main.tscn").instantiate()
	m.state.recovery_base = rdir
	add_node(m)
	await frames()
	m.state.open_project(dir)
	await frames()
	return m


func test_the_journal_follows_edits_and_saves() -> void:
	var dir := copy_fixture("menu")
	var m := await _editor_on(dir, _recovery_dir())
	ok(m.state.journal != null and m.state.journal.is_open(), "a journal per project")
	m.state.execute(EdUxmlCommands.set_attribute(m.state.session, EdLocator.create(node_named(m, "play-button")), "text", "Journaled"), "test")
	var r := EdRecoveryJournal.read(m.state.journal.dir)
	ok(r["ok"])
	ok(r["files"].has(MENU) and r["files"][MENU]["text"] == m.state.workspace.text(MENU), "the edit is on disk at once")
	m.state.save([MENU])
	eq(EdRecoveryJournal.read(m.state.journal.dir)["files"], {}, "a save leaves nothing to recover")
	var jp := m.state.journal.file_path()
	ok(FileAccess.file_exists(jp))
	m.state.close_project()
	ok(not FileAccess.file_exists(jp), "a clean close deletes the journal")


func test_a_new_session_offers_the_unsaved_edits() -> void:
	var dir := copy_fixture("menu")
	var rdir := _recovery_dir()
	var a := EdEditorState.new()
	a.recovery_base = rdir
	a.open_project(dir)
	a.open_document(MENU)
	var disk := FileAccess.get_file_as_bytes(dir + "/" + MENU)
	a.execute(EdUxmlCommands.set_attribute(a.session, EdLocator.create(_named(a, "play-button")), "text", "Unsaved"), "test")
	a.execute(EdUxmlCommands.set_attribute(a.session, EdLocator.create(_named(a, "quit-button")), "text", "Also unsaved"), "test")
	var edited := a.workspace.text(MENU)
	# No close: the session ends as a crash would end it.
	a.journal.close()
	var m := await _editor_on(dir, rdir)
	ok(m._asking != null, "the recovery question is open")
	ok(m._asking != null and m._asking.dialog_text.contains(MENU), "it names the file")
	ok(m.answer(true), "Recover")
	await frames()
	eq(m.state.workspace.text(MENU), edited, "the exact unsaved text")
	ok(m.state.workspace.is_dirty(MENU), "dirty")
	eq(FileAccess.get_file_as_bytes(dir + "/" + MENU), disk, "the disk file did not change")
	ok(m.canvas.host.rect_of(node_named(m, "play-button").id).has_area(), "the recovered text renders")
	eq(m.state.save([MENU]), 1, "a save writes the recovered text")
	eq(FileAccess.get_file_as_bytes(dir + "/" + MENU), m.state.workspace.buffer(MENU).to_bytes())


func test_discard_and_a_changed_disk_file() -> void:
	var dir := copy_fixture("menu")
	var rdir := _recovery_dir()
	var a := EdEditorState.new()
	a.recovery_base = rdir
	a.open_project(dir)
	a.open_document(MENU)
	a.execute(EdUxmlCommands.set_attribute(a.session, EdLocator.create(_named(a, "play-button")), "text", "Unsaved"), "test")
	a.journal.close()
	# Another program changes the file before the next start.
	var f := FileAccess.open(dir + "/" + MENU, FileAccess.WRITE)
	f.store_string(FileAccess.get_file_as_string(dir + "/" + MENU).replace("Main Menu", "Changed outside"))
	f.close()
	var b := EdEditorState.new()
	b.recovery_base = rdir
	var found: Array = []
	b.recovery_found.connect(func(info): found.append(info))
	b.open_project(dir)
	eq(found.size(), 1, "recovery offered")
	eq(found[0]["conflicts"], [MENU], "the external change is a conflict")
	b.recover()
	ok(b.workspace.text(MENU).contains("Unsaved"), "recovered")
	is_error(b.store.save(MENU, b.workspace.buffer(MENU), b.workspace.revision(MENU)), "stale-revision", "a save asks before an overwrite")
	b.journal.close()
	# Discard: the next start offers nothing.
	var c := EdEditorState.new()
	c.recovery_base = rdir
	var found2: Array = []
	c.recovery_found.connect(func(info): found2.append(info))
	c.open_project(dir)
	eq(found2.size(), 1, "the recovered edits are journaled again")
	c.discard_recovery()
	ok(not c.workspace.is_dirty(MENU), "discard keeps the disk text")
	c.close_project()
	var d := EdEditorState.new()
	d.recovery_base = rdir
	var found3: Array = []
	d.recovery_found.connect(func(info): found3.append(info))
	d.open_project(dir)
	eq(found3.size(), 0, "nothing after a discard")
	d.close_project()


## The editor in a child process makes an edit; the test kills the process
## by its PID; the next editor recovers the edit.
func test_edits_survive_a_killed_editor_process() -> void:
	var dir := copy_fixture("menu")
	var rdir := _recovery_dir()
	var ready := rdir + "-ready.txt"
	var disk := FileAccess.get_file_as_bytes(dir + "/" + MENU)
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--",
		"--project=" + dir, "--open=" + MENU, "--select=play-button", "--script-edit=text=" + RECOVERED,
		"--recovery-dir=" + rdir, "--ready-file=" + ready, "--exit-after=%d" % CHILD_LIFETIME_S, "--watch-interval=0"]
	if not UxmlParser.use_native:
		args.append("--gdscript")
	var pid := OS.create_process(OS.get_executable_path(), args)
	ok(pid > 0, "the child editor started")
	if pid <= 0:
		return
	var t0 := Time.get_ticks_msec()
	while not FileAccess.file_exists(ready) and Time.get_ticks_msec() - t0 < CHILD_START_MS and OS.is_process_running(pid):
		await tree.process_frame
	if not ok(FileAccess.file_exists(ready), "the child made the edit (%d s)" % ((Time.get_ticks_msec() - t0) / 1000)):
		if OS.is_process_running(pid):
			OS.kill(pid)
		return
	ok(OS.is_process_running(pid), "the child still runs (its lifetime is far past the wait)")
	eq(OS.kill(pid), OK, "kill the child by its PID")
	t0 = Time.get_ticks_msec()
	while OS.is_process_running(pid) and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame
	ok(not OS.is_process_running(pid), "the child is gone")
	DirAccess.remove_absolute(ready)
	eq(FileAccess.get_file_as_bytes(dir + "/" + MENU), disk, "the child did not save")
	var m := await _editor_on(dir, rdir)
	ok(m._asking != null, "recovery offered after the kill")
	m.answer(true)
	await frames()
	ok(m.state.workspace.text(MENU).contains("text=\"" + RECOVERED + "\""), "the edit of the killed process is back")
	eq(m.state.workspace.text(MENU).replace("text=\"" + RECOVERED + "\"", "text=\"Play &amp; Go\""), EdSourceBuffer.from_bytes(MENU, disk).text, "and nothing else changed")


func _named(s: EdEditorState, n: String) -> EdUxmlNode:
	for x in s.session.root().walk():
		if x.get_attribute("name") == n:
			return x
	return null


func test_a_journaled_text_equal_to_the_disk_is_not_offered() -> void:
	var dir := copy_fixture("menu")
	var rdir := _recovery_dir()
	var a := EdEditorState.new()
	a.recovery_base = rdir
	a.open_project(dir)
	a.open_document(MENU)
	a.execute(EdUxmlCommands.set_attribute(a.session, EdLocator.create(_named(a, "play-button")), "text", "Saved"), "test")
	# The file reaches the disk, then the process ends before `clean`.
	var f := FileAccess.open(dir + "/" + MENU, FileAccess.WRITE)
	f.store_buffer(a.workspace.buffer(MENU).to_bytes())
	f.close()
	a.journal.close()
	var b := EdEditorState.new()
	b.recovery_base = rdir
	var found: Array = []
	b.recovery_found.connect(func(info): found.append(info))
	b.open_project(dir)
	eq(found.size(), 0, "nothing to recover")
	b.close_project()
