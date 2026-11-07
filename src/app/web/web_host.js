// Project host of the web export (EdWebHost, src/app/web/web_host.gd).
//
// The editor works on a copy of the project in the Godot file system
// (user://web-projects/<name>). This script moves the files between that copy
// and the user's files:
//
// - File System Access API: a directory handle (showDirectoryPicker). The
//   files are read at the open, read again before a save (the revision check
//   of the editor then runs on the fresh bytes), and written with a second
//   check of lastModified and size just before the write.
// - Fallback without the API: a zip from a file input. Saves go to the copy;
//   the editor downloads the project as a zip.
//
// Every call answers through a Godot callback with one JSON string. File
// bytes travel as base64.
(function () {
  "use strict";
  if (window.uxmlHost) {
    return;
  }
  const SKIP = new Set(["Library", "Temp", "Logs", "obj", "UserSettings", "Build", "Builds", "node_modules"]);
  const MAX_BYTES = 64 * 1024 * 1024;
  let root = null;
  let zipCallback = null;
  const handles = new Map();

  function b64(buf) {
    const u = new Uint8Array(buf);
    let s = "";
    for (let i = 0; i < u.length; i += 0x8000) {
      s += String.fromCharCode.apply(null, u.subarray(i, i + 0x8000));
    }
    return btoa(s);
  }

  function unb64(s) {
    const b = atob(s);
    const u = new Uint8Array(b.length);
    for (let i = 0; i < b.length; i++) {
      u[i] = b.charCodeAt(i);
    }
    return u;
  }

  function answer(cb, value) {
    cb(JSON.stringify(value));
  }

  async function walk(dir, prefix, out, state) {
    for await (const [name, h] of dir.entries()) {
      if (name.startsWith(".")) {
        continue;
      }
      const rel = prefix ? prefix + "/" + name : name;
      if (h.kind === "directory") {
        if (!SKIP.has(name)) {
          await walk(h, rel, out, state);
        }
        continue;
      }
      const f = await h.getFile();
      state.total += f.size;
      if (state.total > MAX_BYTES) {
        throw new Error("The project is larger than 64 MB.");
      }
      handles.set(rel, h);
      out.push({ path: rel, data: b64(await f.arrayBuffer()), mtime: f.lastModified, size: f.size });
    }
  }

  async function fileHandle(rel, create) {
    if (handles.has(rel)) {
      return handles.get(rel);
    }
    if (!root) {
      return null;
    }
    const parts = rel.split("/");
    let dir = root;
    for (let i = 0; i < parts.length - 1; i++) {
      dir = await dir.getDirectoryHandle(parts[i], { create: create });
    }
    const h = await dir.getFileHandle(parts[parts.length - 1], { create: create });
    handles.set(rel, h);
    return h;
  }

  async function readAll(dir, cb) {
    root = dir;
    handles.clear();
    const files = [];
    await walk(dir, "", files, { total: 0 });
    answer(cb, { ok: true, mode: "fs", name: dir.name, files: files });
  }

  function zipInput() {
    let input = document.getElementById("uxml-zip-input");
    if (!input) {
      input = document.createElement("input");
      input.type = "file";
      input.id = "uxml-zip-input";
      input.accept = ".zip,application/zip";
      input.style.display = "none";
      document.body.appendChild(input);
    }
    if (!input.dataset.bound) {
      input.dataset.bound = "1";
      input.addEventListener("change", async () => {
        const f = input.files && input.files[0];
        input.value = "";
        if (!f || !zipCallback) {
          return;
        }
        try {
          answer(zipCallback, { ok: true, mode: "zip", name: f.name, data: b64(await f.arrayBuffer()) });
        } catch (e) {
          answer(zipCallback, { ok: false, error: String(e) });
        }
      });
    }
    return input;
  }

  window.uxmlHost = {
    hasFsAccess() {
      const forced = new URLSearchParams(window.location.search).get("host");
      return forced !== "zip" && typeof window.showDirectoryPicker === "function";
    },

    // The zip input calls `cb` for every chosen file (also a file that a
    // test sets on #uxml-zip-input).
    listenZip(cb) {
      zipCallback = cb;
      zipInput();
    },

    pickZip() {
      zipInput().click();
    },

    async pickDirectory(cb) {
      try {
        const dir = await window.showDirectoryPicker({ id: "uxml-editor", mode: "readwrite" });
        await readAll(dir, cb);
      } catch (e) {
        answer(cb, { ok: false, error: e && e.name === "AbortError" ? "canceled" : String(e) });
      }
    },

    // The current state of `paths` on disk: [{path, exists, mtime, size, data}].
    // `data` only for a file whose mtime or size differs from `known`.
    async stat(json, cb) {
      const req = JSON.parse(json);
      const out = [];
      for (const item of req.files) {
        try {
          const h = await fileHandle(item.path, false);
          const f = await h.getFile();
          const entry = { path: item.path, exists: true, mtime: f.lastModified, size: f.size };
          if (f.lastModified !== item.mtime || f.size !== item.size) {
            entry.data = b64(await f.arrayBuffer());
          }
          out.push(entry);
        } catch (e) {
          out.push({ path: item.path, exists: false, mtime: 0, size: 0 });
        }
      }
      answer(cb, { ok: true, tag: req.tag || "", files: out });
    },

    // Write one file if the disk file still has `mtime` and `size` (a new
    // file: `exists` false). A conflict writes nothing and answers the disk
    // state.
    async write(json, cb) {
      const req = JSON.parse(json);
      try {
        let h = null;
        let f = null;
        try {
          h = await fileHandle(req.path, false);
          f = await h.getFile();
        } catch (e) {
          h = null;
        }
        if (!req.force && f && req.exists && (f.lastModified !== req.mtime || f.size !== req.size)) {
          answer(cb, { ok: false, conflict: true, path: req.path, mtime: f.lastModified, size: f.size, data: b64(await f.arrayBuffer()) });
          return;
        }
        if (!req.force && f && !req.exists) {
          answer(cb, { ok: false, conflict: true, path: req.path, mtime: f.lastModified, size: f.size, data: b64(await f.arrayBuffer()) });
          return;
        }
        if (!h) {
          h = await fileHandle(req.path, true);
        }
        const w = await h.createWritable();
        await w.write(unb64(req.data));
        await w.close();
        const after = await h.getFile();
        answer(cb, { ok: true, path: req.path, mtime: after.lastModified, size: after.size });
      } catch (e) {
        answer(cb, { ok: false, conflict: false, path: req.path, error: String(e) });
      }
    },
  };
})();
