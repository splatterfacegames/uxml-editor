#!/usr/bin/env node
// Smoke test of the web export in a real browser (milestone 8).
//
//   npm install playwright-core            (once, anywhere on NODE_PATH)
//   godot --headless --path . --export-release Web build/web/index.html
//   node tools/web_smoke.cjs [--browser=<chrome.exe>] [--out=<dir>]
//        [--web=<dir>] [--url=<editor url>] [--scale=<n>] [--sample=<name>]
//
// The script serves build/web (or --web) on a local port (no cross-origin
// isolation headers: the export has no threads), or uses --url (for example
// https://uxml-editor.splatterfacegames.com/editor/), opens it in Chrome or
// Edge (headless) at a device scale factor of --scale (default 1) and checks
// three paths:
//
// 1. Zip fallback (`?host=zip`): a zip of fixtures/projects/menu goes into
//    the zip input, the editor opens it, an element is duplicated through the
//    command palette, and Ctrl+S downloads the project zip. The script reads
//    the zip and checks the edit.
// 2. File System Access API: showDirectoryPicker returns a directory of the
//    origin private file system with the menu fixture. Open, edit, save: the
//    file on "disk" has the edit. Then a change on disk before a save: the
//    editor refuses to overwrite it and asks.
//
// 3. The sample project (`?sample=<name>`, default "sample"; skipped when
//    the export has no samples folder): it opens, the editor draws at the
//    device scale (window.devicePixelRatio), and the source view has room.
//
// Screenshots go to --out (default docs/screenshots). Exit code 0 when every
// check passes.
"use strict";
const fs = require("fs");
const path = require("path");
const http = require("http");
const zlib = require("zlib");
const { chromium } = require("playwright-core");

const REPO = path.resolve(__dirname, "..");
const args = Object.fromEntries(process.argv.slice(2).map((a) => {
  const i = a.indexOf("=");
  return i < 0 ? [a.replace(/^--/, ""), "true"] : [a.slice(0, i).replace(/^--/, ""), a.slice(i + 1)];
}));
const WEB = path.resolve(args.web || path.join(REPO, "build", "web"));
const URL_BASE = args.url || "";
const SCALE = Number(args.scale || 1);
const SAMPLE = args.sample || "sample";
const FIXTURE = path.join(REPO, "fixtures", "projects", "menu");
const OUT = path.resolve(args.out || path.join(REPO, "docs", "screenshots"));
const BROWSERS = [
  args.browser,
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
].filter(Boolean);

let failures = 0;
function check(ok, msg) {
  console.log((ok ? "ok   " : "FAIL ") + msg);
  if (!ok) failures++;
}

// --- a minimal zip writer (stored + deflate) ---------------------------------
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function makeZip(files) {
  const parts = [], central = [];
  let offset = 0;
  for (const [name, data] of files) {
    const nameBuf = Buffer.from(name);
    const comp = zlib.deflateRawSync(data);
    const crc = crc32(data);
    const h = Buffer.alloc(30);
    h.writeUInt32LE(0x04034b50, 0); h.writeUInt16LE(20, 4); h.writeUInt16LE(0, 6); h.writeUInt16LE(8, 8);
    h.writeUInt32LE(0, 10); h.writeUInt32LE(crc, 14); h.writeUInt32LE(comp.length, 18); h.writeUInt32LE(data.length, 22);
    h.writeUInt16LE(nameBuf.length, 26); h.writeUInt16LE(0, 28);
    parts.push(h, nameBuf, comp);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(0, 8); c.writeUInt16LE(8, 10);
    c.writeUInt32LE(0, 12); c.writeUInt32LE(crc, 16); c.writeUInt32LE(comp.length, 20); c.writeUInt32LE(data.length, 24);
    c.writeUInt16LE(nameBuf.length, 28); c.writeUInt32LE(offset, 42);
    central.push(c, nameBuf);
    offset += 30 + nameBuf.length + comp.length;
  }
  const cd = Buffer.concat(central);
  const e = Buffer.alloc(22);
  e.writeUInt32LE(0x06054b50, 0); e.writeUInt16LE(files.length, 8); e.writeUInt16LE(files.length, 10);
  e.writeUInt32LE(cd.length, 12); e.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, cd, e]);
}
function readZip(buf) {
  const out = {};
  let i = buf.length - 22;
  while (i >= 0 && buf.readUInt32LE(i) !== 0x06054b50) i--;
  const count = buf.readUInt16LE(i + 10);
  let p = buf.readUInt32LE(i + 16);
  for (let k = 0; k < count; k++) {
    const method = buf.readUInt16LE(p + 10), csize = buf.readUInt32LE(p + 20);
    const nlen = buf.readUInt16LE(p + 28), elen = buf.readUInt16LE(p + 30), clen = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.slice(p + 46, p + 46 + nlen).toString();
    const lnlen = buf.readUInt16LE(local + 26), lelen = buf.readUInt16LE(local + 28);
    const data = buf.slice(local + 30 + lnlen + lelen, local + 30 + lnlen + lelen + csize);
    out[name] = method === 8 ? zlib.inflateRawSync(data) : data;
    p += 46 + nlen + elen + clen;
  }
  return out;
}

function fixtureFiles() {
  const out = [];
  const walk = (dir, rel) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const r = rel ? rel + "/" + e.name : e.name;
      if (e.isDirectory()) walk(path.join(dir, e.name), r);
      else out.push([r, fs.readFileSync(path.join(dir, e.name))]);
    }
  };
  walk(FIXTURE, "");
  return out;
}

function serve() {
  const types = { ".html": "text/html", ".js": "application/javascript", ".wasm": "application/wasm", ".pck": "application/octet-stream", ".png": "image/png" };
  const server = http.createServer((req, res) => {
    const u = decodeURIComponent(req.url.split("?")[0]);
    const f = path.join(WEB, u === "/" ? "index.html" : u);
    if (!f.startsWith(WEB) || !fs.existsSync(f)) {
      res.writeHead(404);
      res.end();
      return;
    }
    res.writeHead(200, { "Content-Type": types[path.extname(f)] || "application/octet-stream" });
    fs.createReadStream(f).pipe(res);
  });
  return new Promise((resolve) => server.listen(0, "127.0.0.1", () => resolve(server)));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitLog(logs, text, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (logs.some((l) => l.includes(text))) return true;
    await sleep(250);
  }
  return false;
}

async function boot(browser, url, init) {
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 900 }, deviceScaleFactor: SCALE, acceptDownloads: true });
  if (init) await ctx.addInitScript(init);
  const page = await ctx.newPage();
  const logs = [];
  page.on("console", (m) => logs.push(m.text()));
  page.on("pageerror", (e) => logs.push("pageerror: " + e.message));
  await page.goto(url);
  const started = await waitLog(logs, "UXML Editor ready", 120000);
  await sleep(1500);
  // Focus the canvas of the page (the status bar: no element there).
  await page.mouse.click(800, 893);
  return { ctx, page, logs, started };
}

// The editor draws everything in its canvas: keys go to the canvas. The
// selection comes from the smoke hook of the web host (window.uxmlSmoke),
// the edit from the command palette as a user types it.
async function duplicateSelection(page) {
  await page.keyboard.press("Control+Shift+P");
  await sleep(500);
  await page.keyboard.type("dupl", { delay: 60 });
  await sleep(400);
  await page.keyboard.press("Enter");
  await sleep(800);
}

(async () => {
  const exe = BROWSERS.find((b) => fs.existsSync(b));
  if (!exe) {
    console.error("no Chrome or Edge found; pass --browser=<path>");
    process.exit(2);
  }
  if (!URL_BASE && !fs.existsSync(path.join(WEB, "index.html"))) {
    console.error(WEB + "/index.html is missing: export the Web preset first");
    process.exit(2);
  }
  fs.mkdirSync(OUT, { recursive: true });
  const server = URL_BASE ? null : await serve();
  const base = URL_BASE || "http://127.0.0.1:" + server.address().port + "/";
  const withQuery = (q) => base + (base.includes("?") ? "&" : "?") + q;
  const hasSample = URL_BASE || fs.existsSync(path.join(WEB, "samples", SAMPLE + ".zip"));
  const browser = await chromium.launch({ executablePath: exe, headless: true, args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
  console.log("browser " + exe + ", " + base + ", device scale " + SCALE);
  const files = fixtureFiles();
  try {
    // ---- 1. zip fallback -------------------------------------------------
    {
      const { ctx, page, logs, started } = await boot(browser, withQuery("host=zip"));
      check(started, "the editor starts in the browser (GDScript core, Compatibility renderer)");
      const ready = logs.find((l) => l.includes("UXML Editor ready")) || "";
      check(ready.includes("core GDScript"), "the GDScript core runs: " + ready);
      check(ready.includes("scale " + SCALE.toFixed(2)), "the content scale is the device pixel ratio " + SCALE);
      await page.screenshot({ path: path.join(OUT, "m8-web-start.png") });
      const zip = makeZip(files.map(([r, d]) => ["menu/" + r, d]));
      const zipPath = path.join(REPO, "build", "menu-smoke.zip");
      fs.writeFileSync(zipPath, zip);
      await page.setInputFiles("#uxml-zip-input", zipPath);
      check(await waitLog(logs, "web: opened menu (zip)", 20000), "the zip opens as a project");
      check(await waitLog(logs, "web: rendered Assets/UI/Menu.uxml", 20000), "the canvas renders Menu.uxml");
      await sleep(1000);
      await page.evaluate(() => window.uxmlSmoke && window.uxmlSmoke("select quit-button"));
      await sleep(800);
      await duplicateSelection(page);
      check(await waitLog(logs, "web: history Duplicate Button", 10000), "Ctrl+Shift+P, \"dupl\", Enter duplicates the element (one undo step)");
      await page.screenshot({ path: path.join(OUT, "m8-web-edited.png") });
      const dl = page.waitForEvent("download", { timeout: 20000 });
      await page.keyboard.press("Control+S");
      const download = await dl;
      const saved = path.join(REPO, "build", "menu-saved.zip");
      await download.saveAs(saved);
      const entries = readZip(fs.readFileSync(saved));
      const menu = entries["menu/Assets/UI/Menu.uxml"];
      check(!!menu && menu.toString().includes("quit-button-copy"), "Ctrl+S downloads the zip with the edit (" + download.suggestedFilename() + ")");
      const original = files.find(([r]) => r === "Assets/UI/Menu.uss")[1];
      check(entries["menu/Assets/UI/Menu.uss"] && Buffer.compare(entries["menu/Assets/UI/Menu.uss"], original) === 0, "an unedited file keeps its exact bytes (CRLF)");
      await ctx.close();
    }
    // ---- 2. File System Access API (origin private file system) ----------
    {
      const init = `window.showDirectoryPicker = async () => {
        const root = await navigator.storage.getDirectory();
        return await root.getDirectoryHandle("menu");
      };`;
      const { ctx, page, logs, started } = await boot(browser, base, init);
      check(started, "the editor starts with the File System Access API");
      // Put the fixture into the origin private file system.
      await page.evaluate(async (list) => {
        const root = await navigator.storage.getDirectory();
        try { await root.removeEntry("menu", { recursive: true }); } catch (e) {}
        const dir = await root.getDirectoryHandle("menu", { create: true });
        for (const [rel, b64] of list) {
          const parts = rel.split("/");
          let d = dir;
          for (const p of parts.slice(0, -1)) d = await d.getDirectoryHandle(p, { create: true });
          const h = await d.getFileHandle(parts[parts.length - 1], { create: true });
          const w = await h.createWritable();
          await w.write(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0)));
          await w.close();
        }
      }, files.map(([r, d]) => [r, d.toString("base64")]));
      await page.keyboard.press("Control+O");
      check(await waitLog(logs, "web: opened menu (fs)", 20000), "Ctrl+O opens the directory through showDirectoryPicker");
      check(await waitLog(logs, "web: rendered Assets/UI/Menu.uxml", 20000), "the canvas renders Menu.uxml");
      await sleep(800);
      await page.evaluate(() => window.uxmlSmoke && window.uxmlSmoke("select quit-button"));
      await sleep(800);
      await duplicateSelection(page);
      check(await waitLog(logs, "web: history Duplicate Button", 10000), "the edit");
      await page.keyboard.press("Control+S");
      const wrote = await waitLog(logs, "web: wrote Assets/UI/Menu.uxml", 15000);
      check(wrote, "Ctrl+S writes the file");
      if (!wrote) console.log("  last log lines:\n    " + logs.slice(-15).join("\n    "));
      const onDisk = await page.evaluate(async () => {
        const root = await navigator.storage.getDirectory();
        const d = await (await (await root.getDirectoryHandle("menu")).getDirectoryHandle("Assets")).getDirectoryHandle("UI");
        return await (await (await d.getFileHandle("Menu.uxml")).getFile()).text();
      });
      check(onDisk.includes("quit-button-copy"), "the disk file has the edit");
      await page.screenshot({ path: path.join(OUT, "m8-web-fs-saved.png") });
      // An edit, then a change on disk, then a save: the editor asks before
      // an overwrite (or, when the watch timer reads the disk first, asks
      // Reload or Keep). Nothing overwrites the disk change.
      await page.evaluate(() => window.uxmlSmoke && window.uxmlSmoke("select play-button"));
      await sleep(500);
      await duplicateSelection(page);
      await page.evaluate(async () => {
        const root = await navigator.storage.getDirectory();
        const d = await (await (await root.getDirectoryHandle("menu")).getDirectoryHandle("Assets")).getDirectoryHandle("UI");
        const h = await d.getFileHandle("Menu.uxml");
        const text = await (await h.getFile()).text();
        const w = await h.createWritable();
        await w.write(text.replace("quit-button-copy", "changed-outside"));
        await w.close();
      });
      await page.keyboard.press("Control+S");
      const asked = await waitLog(logs, "web: asked", 15000);
      check(asked, "a change on disk stops the save: the editor asks (" + (logs.filter((l) => l.includes("web: asked")).join("; ") || "no question") + ")");
      const still = await page.evaluate(async () => {
        const root = await navigator.storage.getDirectory();
        const d = await (await (await root.getDirectoryHandle("menu")).getDirectoryHandle("Assets")).getDirectoryHandle("UI");
        return await (await (await d.getFileHandle("Menu.uxml")).getFile()).text();
      });
      check(still.includes("changed-outside"), "the disk change stays");
      await page.screenshot({ path: path.join(OUT, "m8-web-conflict.png") });
      await ctx.close();
    }
    // ---- 3. the sample project, the device scale and the panes -----------
    if (hasSample) {
      const { ctx, page, logs, started } = await boot(browser, withQuery("sample=" + SAMPLE));
      check(started, "the editor starts with ?sample=" + SAMPLE);
      check(await waitLog(logs, "web: opened " + SAMPLE + " (zip)", 30000), "the sample project opens");
      check(await waitLog(logs, "web: rendered ", 20000), "the canvas renders a document of the sample");
      await sleep(1000);
      const canvas = await page.evaluate(() => {
        const c = document.querySelector("canvas");
        return c ? { w: c.width, cw: c.clientWidth, dpr: window.devicePixelRatio } : null;
      });
      check(!!canvas && Math.abs(canvas.w - canvas.cw * SCALE) <= 2, "the canvas has device pixels: " + JSON.stringify(canvas));
      await page.evaluate(() => window.uxmlSmoke && window.uxmlSmoke("layout"));
      await waitLog(logs, "web: layout ", 5000);
      const layout = logs.find((l) => l.includes("web: layout ")) || "";
      const m = layout.match(/scale ([\d.]+) view (\d+)x(\d+) source (\d+) inspector (\d+)/);
      check(!!m && Math.abs(Number(m[1]) - SCALE) < 0.01 && Number(m[2]) === 1600, "the editor draws at the CSS size: " + layout);
      check(!!m && Number(m[4]) >= 300, "the source view has room: " + layout);
      await page.screenshot({ path: path.join(OUT, "web-sample" + (SCALE !== 1 ? "@" + SCALE + "x" : "") + ".png") });
      // The size of the editor in the project site (1240 x 698 CSS px).
      await page.setViewportSize({ width: 1240, height: 698 });
      await sleep(1500);
      logs.length = 0;
      await page.evaluate(() => window.uxmlSmoke && window.uxmlSmoke("layout"));
      await waitLog(logs, "web: layout ", 5000);
      const small = logs.find((l) => l.includes("web: layout ")) || "";
      const ms = small.match(/source (\d+)/);
      check(!!ms && Number(ms[1]) >= 300, "at 1240 x 698 the source view keeps room: " + small);
      await page.screenshot({ path: path.join(OUT, "web-sample-1240" + (SCALE !== 1 ? "@" + SCALE + "x" : "") + ".png") });
      await ctx.close();
    }
  } catch (e) {
    console.error(e);
    failures++;
  } finally {
    await browser.close();
    if (server) server.close();
  }
  console.log(failures === 0 ? "web smoke: all checks passed" : "web smoke: " + failures + " failed");
  process.exit(failures === 0 ? 0 : 1);
})();
