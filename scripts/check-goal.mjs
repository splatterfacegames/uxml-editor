#!/usr/bin/env node
// Audits UXML_GOAL.md's thirteen Definition of Done items against repository
// evidence. Each item lists the files, scripts, and test coverage that prove
// it; anything absent prints as a GAP and the script exits nonzero. This is
// the machine-readable half of the release audit — evidence it cannot check
// (screenshot inspection, a real packaged launch) must be reported alongside
// its output.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const read = (path) => (existsSync(join(root, path)) ? readFileSync(join(root, path), 'utf8') : null);
const has = (path) => existsSync(join(root, path));

function* textFiles(dir, suffixes) {
  const base = join(root, dir);
  if (!existsSync(base)) return;
  for (const entry of readdirSync(base, { withFileTypes: true, recursive: true })) {
    if (entry.isFile() && suffixes.some((suffix) => entry.name.endsWith(suffix))) {
      yield join(entry.parentPath ?? entry.path, entry.name);
    }
  }
}

const anyMatch = (files, pattern) =>
  files.some((path) => pattern.test(readFileSync(path, 'utf8')));

const srcTests = [...textFiles('src', ['.test.ts', '.test.tsx'])];
const e2eSpecs = [...textFiles('tests/e2e', ['.spec.ts'])];
const workflowYml = read('.github/workflows/ci.yml') ?? '';

const packageJson = JSON.parse(read('package.json') ?? '{}');
const scripts = packageJson.scripts ?? {};

// Each check returns the evidence it could not find. An empty array is a pass.
const ITEMS = [
  {
    goal: 1,
    title: 'Apache-2.0 licensing and complete third-party notices',
    check() {
      const missing = [];
      const license = read('LICENSE') ?? '';
      if (!license.includes('Apache License')) missing.push('LICENSE is not Apache-2.0');
      if (!has('THIRD-PARTY-NOTICES.md')) missing.push('THIRD-PARTY-NOTICES.md missing');
      const notices = read('THIRD-PARTY-NOTICES.md') ?? '';
      for (const name of ['uxml-preview', 'yoga-layout']) {
        if (!notices.includes(name)) missing.push(`THIRD-PARTY-NOTICES.md lacks ${name}`);
      }
      return missing;
    },
  },
  {
    goal: 2,
    title: 'Fresh clone installs, tests, builds, and launches on documented commands',
    check() {
      const missing = [];
      for (const script of ['dev', 'typecheck', 'test', 'test:e2e', 'test:rust', 'build', 'tauri:build']) {
        if (!(script in scripts)) missing.push(`package.json lacks "${script}"`);
      }
      const readme = (read('README.md') ?? '') + (read('CONTRIBUTING.md') ?? '');
      for (const needle of ['npm ci', 'npm test', 'npm run build', 'tauri']) {
        if (!readme.includes(needle)) missing.push(`docs never mention "${needle}"`);
      }
      return missing;
    },
  },
  {
    goal: 3,
    title: 'uxml-preview pinned immutably behind a tested adapter',
    check() {
      const missing = [];
      const provenance = read('vendor/uxml-preview/PROVENANCE.md') ?? '';
      if (!/Commit\s*\|\s*`[0-9a-f]{40}`/.test(provenance)) {
        missing.push('PROVENANCE.md does not pin an upstream commit');
      }
      if (!has('src/core/adapter/UxmlPreviewAdapter.ts')) missing.push('adapter missing');
      if (!anyMatch(srcTests, /UxmlPreviewAdapter/)) missing.push('no adapter test asserts the pin');
      return missing;
    },
  },
  {
    goal: 4,
    title: 'Packaged application resolves UXML, USS, images, imports, Assets, Packages',
    check() {
      const missing = [];
      for (const project of ['menu', 'options', 'nested-styles', 'assets', 'resolution']) {
        if (!has(`fixtures/projects/${project}`)) missing.push(`fixtures/projects/${project} missing`);
      }
      if (!anyMatch(e2eSpecs, /Packages|Resources/)) missing.push('no e2e resolves package/resource paths');
      const smoke = read('scripts/smoke-packaged.mjs') ?? '';
      if (smoke === '' || !/execFileSync|--version-file/.test(smoke)) {
        missing.push('no packaged-application smoke test exists');
      }
      return missing;
    },
  },
  {
    goal: 5,
    title: 'Structural authoring through palette, hierarchy, canvas, and inspector',
    check() {
      const missing = [];
      for (const feature of ['palette/PalettePanel', 'hierarchy/HierarchyPanel', 'canvas/PreviewCanvas', 'inspector/InspectorPanel']) {
        if (!has(`src/features/${feature}.tsx`)) missing.push(`src/features/${feature} missing`);
      }
      if (!anyMatch(e2eSpecs, /palette|hierarchy|inspector/)) missing.push('no e2e authors structure');
      return missing;
    },
  },
  {
    goal: 6,
    title: 'Selection, manipulation, reparenting, styles, clipboard, undo, diagnostics, source sync',
    check() {
      const missing = [];
      const cases = [
        [/multi-?selection|Shift/i, 'multi-selection'],
        [/copy|paste|clipboard/i, 'clipboard'],
        [/undo|redo/i, 'undo/redo'],
        [/diagnostic/i, 'diagnostics'],
        [/reparent|wrap/i, 'reparent/wrap'],
      ];
      for (const [pattern, label] of cases) {
        if (!anyMatch([...srcTests, ...e2eSpecs], pattern)) missing.push(`no coverage for ${label}`);
      }
      return missing;
    },
  },
  {
    goal: 7,
    title: 'Byte-identical no-op round trip; edits produce localized diffs',
    check() {
      const missing = [];
      if (!anyMatch(e2eSpecs, /exact bytes|byte-identical|preserv/i)) {
        missing.push('no e2e asserts exact preserved bytes');
      }
      if (!anyMatch(srcTests, /localized|minimal.?diff|span/i)) {
        missing.push('no unit test asserts localized edits');
      }
      return missing;
    },
  },
  {
    goal: 8,
    title: 'Unknown or unsupported content survives round trips and is reported',
    check() {
      const missing = [];
      for (const project of ['malformed', 'unsupported']) {
        if (!has(`fixtures/projects/${project}`)) missing.push(`fixtures/projects/${project} missing`);
      }
      if (!anyMatch([...srcTests, ...e2eSpecs], /unsupported-control|unsupported-property|unsupported-selector/)) {
        missing.push('no coverage reports unsupported content');
      }
      return missing;
    },
  },
  {
    goal: 9,
    title: 'Atomic saving and crash recovery tested with failure cases',
    check() {
      const missing = [];
      if (!has('src/core/persistence/RecoveryJournal.test.ts')) missing.push('RecoveryJournal.test.ts missing');
      if (!has('src/core/persistence/SaveCoordinator.test.ts')) missing.push('SaveCoordinator.test.ts missing');
      if (!anyMatch(srcTests, /recovery|journal|replay/i)) missing.push('no recovery/replay coverage');
      if (!anyMatch(srcTests, /fail|failure|interrupt|stale/i)) missing.push('no failure-case save coverage');
      return missing;
    },
  },
  {
    goal: 10,
    title: 'Required suites and packaged smoke tests run in CI; screenshots inspected',
    check() {
      const missing = [];
      for (const step of ['npm run typecheck', 'npm test', 'test:e2e', 'npm run build', 'cargo test', 'check:licenses']) {
        if (!workflowYml.includes(step)) missing.push(`ci.yml never runs "${step}"`);
      }
      if (!workflowYml.includes('tauri build')) missing.push('ci.yml never builds the desktop app');
      if (!anyMatch(e2eSpecs, /toHaveScreenshot|screenshot/)) {
        missing.push('no visual-regression screenshot assertions exist');
      }
      return missing;
    },
  },
  {
    goal: 11,
    title: 'Compatibility matrix and fidelity limits visible in repo and diagnostics',
    check() {
      const missing = [];
      if (!has('docs/compatibility.md')) missing.push('docs/compatibility.md missing');
      const panel = read('src/features/diagnostics/DiagnosticsPanel.tsx') ?? '';
      if (!/fidelity|compatib/i.test(panel)) {
        missing.push('DiagnosticsPanel does not surface engine fidelity');
      }
      return missing;
    },
  },
  {
    goal: 12,
    title: 'Versioned Windows installer/portable release with checksums, SBOM, notes',
    check() {
      const missing = [];
      const release = read('.github/workflows/release.yml') ?? '';
      if (release === '') missing.push('.github/workflows/release.yml missing');
      if (!/nsis|msi|bundle/i.test(release)) missing.push('release.yml builds no installer/bundle');
      if (!/sha256|checksum/i.test(release)) missing.push('release.yml emits no checksums');
      if (!/sbom|cyclonedx|spdx/i.test(release)) missing.push('release.yml emits no SBOM');
      if ((packageJson.version ?? '0.0.0') === '0.0.0') missing.push('package.json still at 0.0.0');
      return missing;
    },
  },
  {
    goal: 13,
    title: 'No stub, placeholder, or TODO-only feature left in shipped surfaces',
    check() {
      const missing = [];
      const shipped = [...textFiles('src', ['.ts', '.tsx']), ...textFiles('src-tauri/src', ['.rs'])];
      const offenders = shipped.filter((path) =>
        !/\.test\.[tj]sx?$/.test(path)
          && /\bTODO\b|\bFIXME\b|not implemented|unimplemented!|todo!/i.test(readFileSync(path, 'utf8')),
      );
      for (const path of offenders) missing.push(`stub marker in ${path}`);
      return missing;
    },
  },
];

let gaps = 0;
for (const item of ITEMS) {
  const missing = item.check();
  if (missing.length === 0) {
    console.log(`PASS ${String(item.goal).padStart(2)}  ${item.title}`);
  } else {
    gaps += 1;
    console.log(`GAP  ${String(item.goal).padStart(2)}  ${item.title}`);
    for (const evidence of missing) console.log(`       - ${evidence}`);
  }
}
console.log(gaps === 0 ? 'All 13 goal items have evidence.' : `${gaps} of 13 goal items lack evidence.`);
process.exit(gaps === 0 ? 0 : 1);
