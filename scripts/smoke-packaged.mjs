#!/usr/bin/env node
/**
 * Packaged-application smoke test.
 *
 * Runs against the output of `tauri build` (or `tauri build --no-bundle`).
 * Proves the produced binary is a real, loadable application rather than a
 * compile artifact nobody launched:
 *
 *   1. the app executable exists and is non-trivially sized;
 *   2. `uxml-editor --version-file <f>` runs and writes the Cargo package
 *      version — the release binary is a GUI-subsystem executable, so this
 *      file handshake replaces stdout;
 *   3. when bundling ran, installer artifacts exist under bundle/ and any
 *      SHA-256 manifest next to them verifies;
 *   4. the binary exits promptly — a hang here means a launch failure.
 *
 * Usage: node scripts/smoke-packaged.mjs [target-dir]
 *   target-dir defaults to src-tauri/target/release
 */
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const targetDir = process.argv[2] ?? join(root, 'src-tauri', 'target', 'release');
const exeName = process.platform === 'win32' ? 'uxml-editor.exe' : 'uxml-editor';
const exePath = join(targetDir, exeName);
const failures = [];

function fail(message) {
  failures.push(message);
  console.error(`FAIL  ${message}`);
}

function pass(message) {
  console.log(`PASS  ${message}`);
}

if (!existsSync(exePath)) {
  fail(`executable not found: ${exePath}`);
} else {
  const size = statSync(exePath).size;
  if (size < 1_000_000) {
    fail(`executable suspiciously small (${size} bytes) — expected a bundled webview app`);
  } else {
    pass(`executable exists (${(size / 1_048_576).toFixed(1)} MiB)`);
  }

  const dir = mkdtempSync(join(tmpdir(), 'uxml-smoke-'));
  const versionFile = join(dir, 'version.txt');
  try {
    execFileSync(exePath, ['--version-file', versionFile], { timeout: 30_000 });
    const written = readFileSync(versionFile, 'utf8').trim();
    const expected = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).version;
    if (written === expected) {
      pass(`--version-file handshake reports ${written}`);
    } else {
      fail(`--version-file wrote "${written}", expected "${expected}"`);
    }
  } catch (error) {
    fail(`--version-file run failed: ${error.message}`);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const bundleDir = join(targetDir, 'bundle');
if (!existsSync(bundleDir)) {
  console.log('SKIP  no bundle/ directory — build ran with --no-bundle');
} else {
  const artifacts = [];
  for (const kind of readdirSync(bundleDir)) {
    const kindDir = join(bundleDir, kind);
    if (!statSync(kindDir).isDirectory()) continue;
    for (const file of readdirSync(kindDir)) {
      if (/\.(msi|exe|zip|appimage|deb|rpm|dmg|AppImage|sig)$/i.test(file)) {
        artifacts.push(join(kindDir, file));
      }
    }
  }
  const installers = artifacts.filter((p) => !/\.sig$/i.test(p));
  if (installers.length === 0) {
    fail('bundle/ exists but contains no installer or portable artifact');
  } else {
    for (const artifact of installers) {
      const size = statSync(artifact).size;
      if (size < 100_000) fail(`artifact suspiciously small: ${artifact} (${size} bytes)`);
      else pass(`artifact ${artifact.split(/[\\/]/).slice(-2).join('/')} (${(size / 1_048_576).toFixed(1)} MiB)`);
    }
  }

  // Verify a checksum manifest when one sits next to the artifacts.
  const manifest = join(bundleDir, 'SHA256SUMS.txt');
  if (existsSync(manifest)) {
    const lines = readFileSync(manifest, 'utf8').split(/\r?\n/).filter(Boolean);
    for (const line of lines) {
      const match = /^([0-9a-f]{64})  (.+)$/i.exec(line);
      if (!match) continue;
      const file = join(bundleDir, match[2]);
      if (!existsSync(file)) {
        fail(`checksum entry missing file: ${match[2]}`);
        continue;
      }
      const digest = createHash('sha256').update(readFileSync(file)).digest('hex');
      if (digest === match[1].toLowerCase()) pass(`checksum verified: ${match[2]}`);
      else fail(`checksum mismatch: ${match[2]}`);
    }
  }
}

if (failures.length > 0) {
  console.error(`\n${failures.length} packaged-smoke failure(s).`);
  process.exit(1);
}
console.log('\nPackaged smoke test passed.');
