#!/usr/bin/env node
/**
 * Packaged-application workflow smoke test.
 *
 * Launches the real built executable (WebView2) with `--open <project>`,
 * attaches over the Chrome DevTools Protocol, and drives the shipped UI
 * through a full open → inspect → no-op save → edit → save → relaunch cycle
 * against real files on disk. This is the definition-of-done evidence that
 * the packaged app — not the dev harness — opens realistic Unity projects,
 * resolves UXML/USS, edits with localized source writes, and preserves byte
 * fidelity on a clean save.
 *
 * Windows-only: the executable exposes CDP when UXML_EDITOR_CDP_PORT is set
 * (wry always sets AdditionalBrowserArguments, which makes WebView2 ignore
 * WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS — so the app opts in explicitly).
 *
 * Usage: node scripts/smoke-packaged-app.mjs [path-to-exe]
 *   exe defaults to src-tauri/target/release/uxml-editor.exe
 */
import { spawn, execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { chromium } from '@playwright/test';

const root = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const exePath = process.argv[2]
  ?? join(root, 'src-tauri', 'target', 'release', 'uxml-editor.exe');
const fixtureDir = join(root, 'fixtures', 'projects', 'menu');
const UXML = join('Assets', 'UI', 'Menu.uxml');

const failures = [];
const fail = (message) => { failures.push(message); console.error(`FAIL  ${message}`); };
const pass = (message) => console.log(`PASS  ${message}`);
const assert = (condition, message) => (condition ? pass(message) : fail(message));

function freePort() {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close(() => resolve(port));
    });
  });
}

async function launchApp(projectDir) {
  const port = await freePort();
  const child = spawn(exePath, ['--open', projectDir], {
    env: {
      ...process.env,
      UXML_EDITOR_CDP_PORT: String(port),
    },
    stdio: 'ignore',
  });
  const endpoint = `http://127.0.0.1:${port}`;
  const deadline = Date.now() + 90_000;
  let browser = null;
  while (Date.now() < deadline) {
    if (child.exitCode !== null) break;
    try {
      browser = await chromium.connectOverCDP(endpoint);
      break;
    } catch {
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }
  if (browser === null) {
    killTree(child);
    throw new Error('WebView2 CDP endpoint never came up — app did not launch.');
  }
  const page = await waitForAppPage(browser, deadline);
  return { child, browser, page };
}

async function waitForAppPage(browser, deadline) {
  while (Date.now() < deadline) {
    for (const context of browser.contexts()) {
      for (const page of context.pages()) {
        const url = page.url();
        if (/tauri\.localhost|tauri:\/\/|localhost/.test(url)) return page;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error('CDP attached but no application page appeared.');
}

function killTree(child) {
  try {
    if (process.platform === 'win32') {
      execFileSync('taskkill', ['/pid', String(child.pid), '/T', '/F'], { stdio: 'ignore' });
    } else {
      child.kill('SIGKILL');
    }
  } catch {
    // already gone
  }
}

async function removeDir(dir) {
  for (let attempt = 0; attempt < 5; attempt += 1) {
    try {
      rmSync(dir, { recursive: true, force: true });
      return;
    } catch {
      // Windows file handles (WebView2, antivirus) release asynchronously.
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
  }
  rmSync(dir, { recursive: true, force: true });
}

async function settled(page) {
  await page.waitForLoadState('networkidle').catch(() => {});
  await page.waitForTimeout(250);
}

if (process.platform !== 'win32') {
  console.log('SKIP  packaged workflow smoke requires Windows (WebView2 CDP).');
  process.exit(0);
}

const scratch = mkdtempSync(join(tmpdir(), 'uxml-packaged-app-'));
const projectDir = join(scratch, 'menu-project');
cpSync(fixtureDir, projectDir, { recursive: true });
const uxmlPath = join(projectDir, UXML);

let child = null;
let browser = null;
try {
  // --- Phase 1: launch with --open and verify the real project loads. ---
  ({ child, browser } = await launchApp(projectDir));
  const page = await waitForAppPage(browser, Date.now() + 90_000);
  await page.waitForSelector('[role="application"]', { timeout: 60_000 });
  pass('application shell rendered in packaged build');

  const hierarchy = page.getByRole('tree', { name: 'Document hierarchy' });
  await hierarchy.getByRole('treeitem', { name: 'menu-root' }).waitFor({ timeout: 60_000 });
  for (const name of ['menu-title', 'play-button', 'quit-button']) {
    await hierarchy.getByRole('treeitem', { name }).waitFor({ timeout: 10_000 });
  }
  pass('--open launched the menu project; hierarchy shows all fixture elements');
  await page.getByTestId('canvas-renderer').getByText('Main Menu').waitFor({ timeout: 15_000 });
  pass('canvas rendered fixture content (Main Menu)');

  // --- Phase 2: clean save must be byte-identical (source fidelity). ---
  const before = readFileSync(uxmlPath);
  await page.getByRole('button', { name: 'Save' }).click();
  await settled(page);
  const afterCleanSave = readFileSync(uxmlPath);
  assert(before.equals(afterCleanSave), 'clean save left Menu.uxml byte-identical on disk');

  // --- Phase 3: localized edit through inspector → inline style → save. ---
  await hierarchy.getByRole('treeitem', { name: 'menu-title' }).click();
  const width = page.getByRole('textbox', { name: 'Width', exact: true });
  await width.waitFor({ timeout: 15_000 });
  await width.fill('240px');
  await width.press('Enter');
  const writeMenu = page.getByRole('menu', { name: 'Write width to' });
  await writeMenu.getByRole('menuitem', { name: 'Inline style' }).click();
  await settled(page);
  await page.getByRole('button', { name: 'Save' }).click();
  await settled(page);

  const edited = readFileSync(uxmlPath, 'utf8');
  assert(edited.includes('width: 240px'), 'inline width edit was written to Menu.uxml');
  assert(edited.includes('keep-between-buttons'), 'source comments survived the edit round-trip');
  assert(
    edited.includes('text="Main Menu"') && edited.includes('menu-title'),
    'untouched attributes and elements survived the localized edit',
  );

  // --- Phase 4: relaunch — the saved edit persists and the project reopens. ---
  await browser.close();
  killTree(child);
  ({ child, browser } = await launchApp(projectDir));
  const reopened = await waitForAppPage(browser, Date.now() + 90_000);
  await reopened.waitForSelector('[role="application"]', { timeout: 60_000 });
  await reopened
    .getByRole('tree', { name: 'Document hierarchy' })
    .getByRole('treeitem', { name: 'menu-title' })
    .waitFor({ timeout: 60_000 });
  const persisted = readFileSync(uxmlPath, 'utf8');
  assert(persisted.includes('width: 240px'), 'relaunch: edited file persisted on disk');
  assert(persisted.includes('keep-between-buttons'), 'relaunch: comments still intact');
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
} finally {
  try { await browser?.close(); } catch { /* already closed */ }
  if (child !== null) killTree(child);
  await removeDir(scratch);
}

if (failures.length > 0) {
  console.error(`\n${failures.length} packaged-app workflow failure(s).`);
  process.exit(1);
}
console.log('\nPackaged-app workflow smoke passed.');
