extends EdTestCase
## The recovery journal (ADR 0005): records, the chain check, truncation,
## corruption and compaction.

var _dirs: Array = []


func _journal() -> EdRecoveryJournal:
	var dir := ProjectSettings.globalize_path("user://test-journal-%d" % Time.get_ticks_usec())
	_dirs.append(dir)
	var j := EdRecoveryJournal.new(dir, "C:/project")
	j.start()
	return j


func teardown() -> void:
	for d in _dirs:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d + "/" + f)
		DirAccess.remove_absolute(d)
	_dirs.clear()
	await super()


static func _base(text: String) -> Dictionary:
	return {"text": text, "bom": false, "revision": {"exists": true, "size": text.length(), "mtime": 1, "sha256": "aa"}}


func test_records_replay_to_the_unsaved_text() -> void:
	var j := _journal()
	var base := _base("<a>\r\n</a>\r\n")
	j.record("A.uxml", "<a x=\"1\">\r\n</a>\r\n", true, base)
	j.record("A.uxml", "<a x=\"12\">\r\n</a>\r\n", true, base)
	j.record("B.uss", ".b { }", true, _base(".a { }"))
	var r := EdRecoveryJournal.read(j.dir)
	ok(r["ok"], "a valid chain")
	eq(r["project"], "C:/project")
	eq(r["files"].keys().size(), 2)
	eq(r["files"]["A.uxml"]["text"], "<a x=\"12\">\r\n</a>\r\n", "every byte, CRLF kept")
	eq(r["files"]["A.uxml"]["base_text"], "<a>\r\n</a>\r\n")
	eq(r["files"]["A.uxml"]["revision"]["sha256"], "aa")
	eq(r["files"]["B.uss"]["text"], ".b { }")


func test_a_clean_file_leaves_the_journal() -> void:
	var j := _journal()
	var base := _base("x")
	j.record("A.uxml", "xy", true, base)
	j.record("A.uxml", "x", false, base)
	var r := EdRecoveryJournal.read(j.dir)
	ok(r["ok"])
	eq(r["files"], {}, "undone to the saved text: nothing to recover")
	j.record("A.uxml", "xz", true, base)
	eq(EdRecoveryJournal.read(j.dir)["files"]["A.uxml"]["text"], "xz", "a new base after clean")


func test_a_cut_last_record_is_dropped() -> void:
	var j := _journal()
	var base := _base("abc")
	j.record("A.uxml", "abcd", true, base)
	j.close()
	var f := FileAccess.open(j.file_path(), FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string("{\"v\":1,\"seq\":3,\"prev\":\"")
	f.close()
	var r := EdRecoveryJournal.read(j.dir)
	ok(r["ok"], "the records before the cut are valid")
	ok(r["truncated"], "the cut is reported")
	eq(r["files"]["A.uxml"]["text"], "abcd")


func test_a_changed_record_breaks_the_chain() -> void:
	var j := _journal()
	var base := _base("abc")
	j.record("A.uxml", "abcd", true, base)
	j.record("A.uxml", "abcde", true, base)
	j.close()
	var lines := FileAccess.get_file_as_string(j.file_path()).split("\n")
	lines[2] = lines[2].replace("\"d\"", "\"D\"")
	var f := FileAccess.open(j.file_path(), FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	var r := EdRecoveryJournal.read(j.dir)
	ok(not r["ok"], "a corrupt chain")
	eq(r["files"], {}, "nothing replays")
	ok(r["error"].contains("chain"), r["error"])


func test_an_other_version_is_not_replayed() -> void:
	var j := _journal()
	j.record("A.uxml", "ab", true, _base("a"))
	j.close()
	var text := FileAccess.get_file_as_string(j.file_path()).replace("\"v\":1", "\"v\":9")
	var f := FileAccess.open(j.file_path(), FileAccess.WRITE)
	f.store_string(text)
	f.close()
	ok(not EdRecoveryJournal.read(j.dir)["ok"])


func test_compaction_keeps_the_state_and_bounds_the_file() -> void:
	var j := _journal()
	var base := _base("")
	var t := ""
	for i in 300:
		t += "line %d\n" % i
		j.record("A.uxml", t, true, base)
	j.record("B.uss", "b", true, _base("a"))
	var before := FileAccess.get_file_as_bytes(j.file_path()).size()
	j.compact()
	var after := FileAccess.get_file_as_bytes(j.file_path()).size()
	ok(after < before / 10, "compact: %d -> %d bytes" % [before, after])
	var r := EdRecoveryJournal.read(j.dir)
	ok(r["ok"])
	eq(r["files"]["A.uxml"]["text"], t)
	eq(r["files"]["B.uss"]["text"], "b")
	# Records after the compaction continue the chain.
	j.record("B.uss", "bb", true, _base("a"))
	eq(EdRecoveryJournal.read(j.dir)["files"]["B.uss"]["text"], "bb")


func test_diff_keeps_the_common_prefix_and_suffix() -> void:
	eq(EdRecoveryJournal.diff("abcdef", "abXYef"), [2, 4, "XY"])
	eq(EdRecoveryJournal.diff("abc", "abc"), null)
	eq(EdRecoveryJournal.diff("", "x"), [0, 0, "x"])
	eq(EdRecoveryJournal.diff("aaa", "aaaa"), [3, 3, "a"])
	ok(EdRecoveryJournal.dir_for("C:/r", "C:/P/x") == EdRecoveryJournal.dir_for("C:/r", "c:/p/x/"), "one directory per project root")
