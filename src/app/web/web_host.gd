class_name EdWebHost
extends Node
## The project host of the web export (milestone 8).
##
## A browser has no directory path for EdProjectStore. The host copies the
## project into the Godot file system (`user://web-projects/<name>`), and the
## editor opens that copy with the same store, workspace, journal and render
## code as on the desktop. `web_host.js` (JavaScriptBridge) moves the files
## between the copy and the files of the user:
##
## - **File System Access API** (mode "fs"): the user picks a directory. Before
##   a save the host reads the files again: a file that changed on disk gets
##   its new bytes in the copy, so the revision check of EdProjectStore.save
##   refuses the save as on the desktop ("stale-revision", then the question
##   to overwrite). After the save the host writes the file to disk; the
##   script checks lastModified and size again just before the write. A file
##   that changed in between is not written: the copy gets the disk bytes, the
##   buffer is unsaved again, and the external-change check asks Reload or
##   Keep. The watch timer polls the disk the same way.
## - **Zip** (mode "zip", without the API or with `?host=zip`): the user picks
##   a zip. Saves go to the copy (the same revision check), and each save
##   downloads the project as a zip.
## - **Sample** (`?sample=<name>`): at the start the host fetches
##   `samples/<name>.zip` next to the page and opens it as a zip. The project
##   site bundles one, so a visitor needs no file of their own.
##
## Without the web feature (tests, the desktop) `bridge` is a Callable fake:
## see `use_bridge()`.

signal opened(mode: String, name: String)
signal disk_checked
signal pushed(results: Array)

const BASE := "user://web-projects"
const JS := "res://src/app/web/web_host.js"

var main: Node = null
## "fs", "zip" or "" (no project).
var mode := ""
var project_name := ""
## Root of the copy (an absolute path in the Godot file system).
var root := ""
## project-relative path -> {mtime, size} of the disk file (mode "fs").
var disk: Dictionary = {}
## The answers of the last push (tests).
var last_push: Array = []
## Number of zip downloads (tests).
var downloads := 0
## Last zip bytes offered for download (tests).
var last_zip := PackedByteArray()

var _js: JavaScriptObject = null
var _callbacks: Array = []
## A fake of the JavaScript side for tests: bridge.call(method, args_json,
## answer: Callable).
var _bridge: Callable = Callable()


func _init(owner_main: Node = null) -> void:
	main = owner_main


func _ready() -> void:
	if not OS.has_feature("web") or _bridge.is_valid():
		return
	var src := FileAccess.get_file_as_string(JS)
	JavaScriptBridge.eval(src, true)
	_js = JavaScriptBridge.get_interface("uxmlHost")
	if _js == null:
		push_error("web host: web_host.js did not load")
		return
	_js.listenZip(_cb(_on_zip))
	# The hook of tools/web_smoke.cjs: "select <name>" selects an element.
	var w := JavaScriptBridge.get_interface("window")
	w.uxmlSmoke = _cb(smoke)
	if main != null:
		main.state.external_conflicts.connect(func(paths): log_line("asked reload or keep " + ", ".join(PackedStringArray(paths))))
		main.canvas.host.rendered.connect(func(): log_line("rendered " + main.canvas.host.entry_path))
	var sample := String(_js.sampleRequest())
	if not sample.is_empty():
		open_sample(sample)


## A line of the browser console that tools/web_smoke.cjs waits for.
static func log_line(msg: String) -> void:
	print("web: " + msg)


## The smoke hook: "select <name>" selects the element with that name.
func smoke(command: String) -> void:
	var parts := command.split(" ", false, 1)
	if parts.size() == 2 and parts[0] == "select" and main != null and main.state.session != null:
		for n in main.state.session.root().walk():
			if n.get_attribute("name") == parts[1]:
				main.state.select_node(n, "smoke")
				log_line("selected " + parts[1])
				return


## Use `fake` instead of web_host.js: fake.call(method: String, json: String,
## answer: Callable). For tests on the desktop.
func use_bridge(fake: Callable) -> void:
	_bridge = fake


func has_fs_access() -> bool:
	if _bridge.is_valid():
		return bool(_bridge.call("hasFsAccess", "", Callable()))
	return _js != null and bool(_js.hasFsAccess())


## The Open command: a directory picker, or the zip input.
func pick_project() -> void:
	if has_fs_access():
		_call("pickDirectory", "", _on_files)
	else:
		_call("pickZip", "", Callable())


## Open the zip input (also with the File System Access API).
func pick_zip() -> void:
	_call("pickZip", "", Callable())


## Fetch the sample project `sample_name` (samples/<name>.zip next to the
## page) and open it as a zip.
func open_sample(sample_name: String) -> void:
	log_line("opening sample " + sample_name)
	_call("fetchSample", sample_name, _on_sample)


func _on_sample(json: String) -> void:
	var r = JSON.parse_string(json)
	if not r is Dictionary or not r.get("ok", false):
		_status("The sample project did not open: %s" % (str(r.get("error", "unknown error")) if r is Dictionary else "no answer"), true)
		return
	_on_zip(json)


func _cb(f: Callable) -> JavaScriptObject:
	var cb := JavaScriptBridge.create_callback(func(args: Array): f.call(String(args[0]) if not args.is_empty() else "{}"))
	_callbacks.append(cb)
	return cb


func _call(method: String, json: String, answer: Callable) -> void:
	if _bridge.is_valid():
		_bridge.call(method, json, answer)
		return
	if _js == null:
		return
	match method:
		"pickDirectory":
			_js.pickDirectory(_cb(answer))
		"pickZip":
			_js.pickZip()
		"fetchSample":
			_js.fetchSample(json, _cb(answer))
		"stat":
			_js.stat(json, _cb(answer))
		"write":
			_js.write(json, _cb(answer))


# ---------------------------------------------------------------------------
# Open
# ---------------------------------------------------------------------------

func _on_files(json: String) -> void:
	var r = JSON.parse_string(json)
	if not r is Dictionary or not r.get("ok", false):
		_status("The project did not open: %s" % (str(r.get("error", "unknown error")) if r is Dictionary else "no answer"), r is Dictionary and r.get("error") != "canceled")
		return
	_prepare(String(r.get("name", "project")))
	mode = "fs"
	disk.clear()
	for f in r.get("files", []):
		var rel := String(f["path"])
		_write_copy(rel, Marshalls.base64_to_raw(String(f["data"])))
		disk[rel] = {"mtime": int(f["mtime"]), "size": int(f["size"])}
	_open()


func _on_zip(json: String) -> void:
	var r = JSON.parse_string(json)
	if not r is Dictionary or not r.get("ok", false):
		_status("The zip did not open: %s" % (str(r.get("error", "unknown error")) if r is Dictionary else "no answer"), true)
		return
	var bytes := Marshalls.base64_to_raw(String(r.get("data", "")))
	var err := open_zip_bytes(String(r.get("name", "project.zip")), bytes)
	if err != OK:
		_status("The zip did not open (%s)." % error_string(err), true)


## Open the zip `bytes` as a project (mode "zip"). A zip with one top folder
## opens that folder.
func open_zip_bytes(zip_name: String, bytes: PackedByteArray) -> int:
	var tmp := ProjectSettings.globalize_path("user://web-import.zip")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(bytes)
	f.close()
	var z := ZIPReader.new()
	var err := z.open(tmp)
	if err != OK:
		return err
	var names := z.get_files()
	var prefix := _common_folder(names)
	_prepare(zip_name.get_basename() if prefix.is_empty() else prefix.trim_suffix("/"))
	mode = "zip"
	disk.clear()
	var count := 0
	for n in names:
		if n.ends_with("/"):
			continue
		var rel := n.substr(prefix.length())
		if rel.is_empty() or rel.begins_with("__MACOSX/") or rel.contains("../"):
			continue
		_write_copy(rel, z.read_file(n))
		count += 1
	z.close()
	DirAccess.remove_absolute(tmp)
	if count == 0:
		return ERR_FILE_CORRUPT
	_open()
	return OK


static func _common_folder(names: PackedStringArray) -> String:
	var top := ""
	for n in names:
		if n.begins_with("__MACOSX/"):
			continue
		var slash := n.find("/")
		if slash < 0:
			return ""
		var first := n.substr(0, slash + 1)
		if top.is_empty():
			top = first
		elif top != first:
			return ""
	return top


func _prepare(nm: String) -> void:
	project_name = _safe(nm)
	root = ProjectSettings.globalize_path(BASE + "/" + project_name)
	if main != null and main.state.has_project():
		main.state.close_project()
	_rm(root)
	DirAccess.make_dir_recursive_absolute(root)


func _open() -> void:
	if main != null and main.state.open_project(root):
		var ws: EdWorkspace = main.state.workspace
		ws.history.history_changed.connect(func(): log_line("history " + ws.history.undo_label()))
		# The first UXML document opens (a browser has no project list of
		# its own yet).
		var docs: Array = ws.paths_with_extension(".uxml")
		docs.sort()
		if not docs.is_empty():
			main.state.open_document(docs[0])
		EdUi.set_label(main.shell, "document-label", "%s  (%s)" % [project_name, "File System Access" if mode == "fs" else "zip"])
	opened.emit(mode, project_name)
	log_line("opened %s (%s)" % [project_name, mode])
	_status("Opened %s (%s)." % [project_name, "File System Access" if mode == "fs" else "zip; a save downloads the project"], false)


func _write_copy(rel: String, bytes: PackedByteArray) -> void:
	var p := root + "/" + rel
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


static func _safe(nm: String) -> String:
	var out := ""
	for ch in nm:
		out += ch if ch.is_valid_identifier() or ch.is_valid_int() or ch == "-" or ch == "." else "_"
	return "project" if out.strip_edges().is_empty() or out.begins_with(".") else out


# ---------------------------------------------------------------------------
# Disk checks and saves
# ---------------------------------------------------------------------------

## Read `paths` from disk again (mode "fs"): a changed file gets its disk
## bytes in the copy. Returns the paths that changed. Awaitable.
func refresh(paths: Array) -> Array:
	if mode != "fs":
		return []
	var req := []
	for p in paths:
		if disk.has(p):
			req.append({"path": p, "mtime": disk[p]["mtime"], "size": disk[p]["size"]})
	if req.is_empty():
		return []
	var answer := [null]
	_call("stat", JSON.stringify({"files": req}), func(json: String) -> void:
		answer[0] = json
		disk_checked.emit())
	if answer[0] == null:
		await disk_checked
	var changed: Array = []
	var r = JSON.parse_string(String(answer[0]))
	if not r is Dictionary:
		return changed
	for f in r.get("files", []):
		var rel := String(f["path"])
		if not bool(f.get("exists", false)):
			if disk.has(rel) and FileAccess.file_exists(root + "/" + rel):
				DirAccess.remove_absolute(root + "/" + rel)
				disk.erase(rel)
				changed.append(rel)
			continue
		if f.has("data"):
			_write_copy(rel, Marshalls.base64_to_raw(String(f["data"])))
			changed.append(rel)
		disk[rel] = {"mtime": int(f["mtime"]), "size": int(f["size"])}
	return changed


## The timer check of mode "fs": read the open files again, then the
## external-change check of the editor. Awaitable.
func poll() -> void:
	if mode != "fs" or main == null or not main.state.has_project():
		return
	var changed := await refresh(main.state.workspace.buffers.keys())
	if not changed.is_empty():
		main.state.check_external_changes(true)


## Write the saved files to disk (mode "fs") or download the zip (mode
## "zip"). `bases`: path -> the base of the workspace before the save (an
## unsaved buffer again when the write fails). `force`: write also over a
## disk change (the user chose to overwrite). Awaitable; returns the
## answers.
func push(paths: Array, bases: Dictionary, force: bool = false) -> Array:
	var results: Array = []
	if paths.is_empty():
		return results
	if mode == "zip":
		download_zip()
		return results
	if mode != "fs":
		return results
	for p in paths:
		var bytes := FileAccess.get_file_as_bytes(root + "/" + String(p))
		var known: Dictionary = disk.get(p, {})
		var req := {"path": p, "data": Marshalls.raw_to_base64(bytes), "exists": not known.is_empty(),
			"mtime": int(known.get("mtime", 0)), "size": int(known.get("size", 0)), "force": force}
		var answer := [null]
		_call("write", JSON.stringify(req), func(json: String) -> void:
			answer[0] = json
			disk_checked.emit())
		if answer[0] == null:
			await disk_checked
		var r = JSON.parse_string(String(answer[0]))
		if not r is Dictionary:
			r = {"ok": false, "path": p, "error": "no answer"}
		results.append(r)
		if r.get("ok", false):
			disk[p] = {"mtime": int(r["mtime"]), "size": int(r["size"])}
			log_line("wrote " + String(p))
			continue
		# Not written: the buffer is unsaved again.
		if main != null and bases.has(p) and main.state.workspace.has(p):
			main.state.workspace.base[p] = bases[p]
			main.state.workspace.buffers_changed.emit([p], "save-failed", null)
		if r.get("conflict", false):
			_write_copy(p, Marshalls.base64_to_raw(String(r.get("data", ""))))
			disk[p] = {"mtime": int(r["mtime"]), "size": int(r["size"])}
			_status("Not saved: %s changed on disk during the save." % p, true)
			if main != null:
				main.state.check_external_changes()
		else:
			_status("Not saved: %s could not be written (%s)." % [p, str(r.get("error", ""))], true)
	last_push = results
	pushed.emit(results)
	return results


## The copy as zip bytes (every file of the project directory).
func zip_bytes() -> PackedByteArray:
	var tmp := ProjectSettings.globalize_path("user://web-export.zip")
	var z := ZIPPacker.new()
	if z.open(tmp) != OK:
		return PackedByteArray()
	var files: Array = []
	_list(root, "", files)
	files.sort()
	for rel in files:
		z.start_file(project_name + "/" + rel)
		z.write_file(FileAccess.get_file_as_bytes(root + "/" + rel))
		z.close_file()
	z.close()
	var bytes := FileAccess.get_file_as_bytes(tmp)
	DirAccess.remove_absolute(tmp)
	return bytes


## Offer the project as a zip download.
func download_zip() -> void:
	if root.is_empty():
		_status("Open a project first.", true)
		return
	last_zip = zip_bytes()
	downloads += 1
	if OS.has_feature("web") and not _bridge.is_valid():
		JavaScriptBridge.download_buffer(last_zip, project_name + ".zip", "application/zip")
	_status("Downloaded %s.zip." % project_name, false)


static func _list(dir: String, rel: String, out: Array) -> void:
	var abs_dir := dir if rel.is_empty() else dir + "/" + rel
	for f in DirAccess.get_files_at(abs_dir):
		out.append(f if rel.is_empty() else rel + "/" + f)
	for d in DirAccess.get_directories_at(abs_dir):
		_list(dir, d if rel.is_empty() else rel + "/" + d, out)


static func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		_rm(dir + "/" + d)
	DirAccess.remove_absolute(dir)


func _status(msg: String, err: bool) -> void:
	if main != null:
		main.state.status.emit(msg, err)
