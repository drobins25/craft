'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const lib = require('../runner.js');
const MAP_CAP = path.join(__dirname, '..', 'map-capability.sh');
const MAP_DIR = path.join(__dirname, '..');
const REPO_ROOT = path.join(__dirname, '..', '..', '..');

function tmpProject() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'craftmap-ux-'));
}
function write(root, rel, content) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content);
  return abs;
}

test('opt-out flag: absent settings builds (default-on); enabled:false skips the build, no error', async () => {
  const on = tmpProject();
  write(on, 'area/a.py', 'def a():\n    return 1\n');
  const onRes = await lib.assembleArea('area', on);
  assert.ok(!onRes.disabled, 'absent settings -> enabled by default');
  assert.strictEqual(onRes.fileCount, 1);

  const off = tmpProject();
  write(off, 'area/a.py', 'def a():\n    return 1\n');
  write(off, '.craft/settings.yaml', 'map:\n  enabled: false\n');
  const offRes = await lib.assembleArea('area', off);
  assert.strictEqual(offRes.disabled, true, 'enabled:false -> no build');
  assert.ok(!fs.existsSync(path.join(off, '.craft', 'map', 'index.json')), 'no index written when disabled');
});

test('capability is probed once and cached; the second call reads the cache', () => {
  const root = tmpProject();
  const first = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8' });
  assert.match(first, /"mode":"full"/);
  // Overwrite the cache with a sentinel; a re-probe would clobber it, a cached read returns it.
  fs.writeFileSync(path.join(root, '.craft', 'map', 'capability.json'), '{"mode":"sentinel"}\n');
  const second = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8' });
  assert.match(second, /"mode":"sentinel"/, 'probe-once: second call read the cache, did not re-probe');
});

test('capability honors the opt-out flag (disabled), still exit 0', () => {
  const root = tmpProject();
  write(root, '.craft/settings.yaml', 'map:\n  enabled: false\n');
  const out = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8' });
  assert.match(out, /"mode":"disabled"/);
});

test('capability degrades to floor when node is absent, never errors', () => {
  const root = tmpProject();
  const out = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' } });
  assert.match(out, /"mode":"floor"|"tier":"floor"|node-missing/);
});

test('a single unreadable file floors to file-level; the area still assembles', async () => {
  const root = tmpProject();
  write(root, 'area/good.py', 'def good():\n    return 1\n');
  const bad = write(root, 'area/bad.py', 'def bad():\n    return 2\n');
  fs.chmodSync(bad, 0o000); // make it unreadable
  try {
    const res = await lib.assembleArea('area', root);
    assert.strictEqual(res.fileCount, 2, 'both files accounted for');
    assert.ok(res.slice.includes('area/good.py'), 'the readable file still emits');
  } finally {
    fs.chmodSync(bad, 0o644);
  }
});

test('exactly one mode-tuned FYI on the first build, none after', async () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');
  const first = await lib.assembleArea('area', root);
  assert.strictEqual(first.firstBuild, true);
  assert.match(first.fyi, /structural map|basic mode/);

  const second = await lib.assembleArea('area', root);
  assert.strictEqual(second.firstBuild, false);
  assert.strictEqual(second.fyi, null, 'FYI is once, ever');
});

test('status is pull-only: no toast/notify emitter exists in the map source', () => {
  const srcFiles = fs.readdirSync(path.join(MAP_DIR, 'src')).map((f) => fs.readFileSync(path.join(MAP_DIR, 'src', f), 'utf8'));
  const blob = srcFiles.join('\n');
  assert.ok(!/\b(toast|notify|push_notification|pushNotification)\b/i.test(blob), 'no in-flow notification path in the map');
});

test('trigger: no per-file-access hook intercepts Read/Grep/Glob for the map', () => {
  const hooks = fs.readFileSync(path.join(REPO_ROOT, 'hooks', 'hooks.json'), 'utf8');
  // No hook should wire the map into a per-tool-call interception of file reads.
  const hasMapReadHook = /map-run|scripts\/map/.test(hooks) && /"(Read|Grep|Glob)"/.test(hooks);
  assert.ok(!hasMapReadHook, 'the map is pull + cold-start push only, never a file-access hook');
});

test('the reference doc and status surface exist', () => {
  assert.ok(fs.existsSync(path.join(REPO_ROOT, 'commands', 'references', 'map.md')), 'reference md present');
  const status = fs.readFileSync(path.join(REPO_ROOT, 'commands', 'craft-status.md'), 'utf8');
  assert.match(status, /Map status/, 'craft-status renders a map line');
  assert.match(status, /pulled here, never pushed/i, 'status is pull-only by contract');
});
