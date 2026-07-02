'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const lib = require('../runner.js');
const MAP_FRESHNESS = path.join(__dirname, '..', 'map-freshness.sh');
const MAP_RUN = path.join(__dirname, '..', 'map-run.sh');

function tmpProject() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'craftmap-area-'));
  return root;
}
function write(root, rel, content) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content);
  return abs;
}

test('one directory: that directory\'s own files only, no parent/child, no full-repo index', async () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');
  write(root, 'area/sub/b.py', 'def b():\n    return 2\n');
  write(root, 'other.py', 'def other():\n    return 3\n');

  const res = await lib.assembleArea('area', root);
  assert.strictEqual(res.fileCount, 1, 'only the directory\'s direct file');
  assert.match(res.slice, /area\/a\.py/);
  assert.ok(!res.slice.includes('sub/b.py'), 'no child-directory expansion');
  assert.ok(!res.slice.includes('other.py'), 'no sibling/parent expansion');

  const index = JSON.parse(fs.readFileSync(path.join(root, '.craft', 'map', 'index.json'), 'utf8'));
  assert.deepStrictEqual(Object.keys(index.areas), ['area'], 'only the requested area is indexed - no full-repo index');
});

test('assembled slice parses as the locked indented outline and fits the budget', async () => {
  const root = tmpProject();
  write(root, 'area/x.py', 'class Foo:\n    def bar(self):\n        return 1\n');
  const res = await lib.assembleArea('area', root);
  const lines = res.slice.split('\n').filter(Boolean);
  assert.strictEqual(lines[0], 'area/x.py', 'first line is the file header at column 0');
  assert.ok(/^ {2}Foo {2}\[off=1,lim=3\]$/.test(lines[1]), `class indented one level with paste-ready range: "${lines[1]}"`);
  assert.ok(/^ {4}bar {2}\[off=2,lim=2\]$/.test(lines[2]), `method indented under its class with its own range: "${lines[2]}"`);
  assert.ok(res.tokenEstimate <= res.budget, 'slice fits the token budget');
});

test('stored anchor keys come from the index, not the rendered slice', async () => {
  const root = tmpProject();
  write(root, 'area/o.cs', 'class C { int M(int a, string b) { return a; } int M(int a) { return a; } }');
  await lib.assembleArea('area', root);
  const index = JSON.parse(fs.readFileSync(path.join(root, '.craft', 'map', 'index.json'), 'utf8'));
  const anchors = index.areas.area.files['area/o.cs'].anchors.map((a) => a.anchor);
  assert.ok(anchors.includes('area/o.cs#C.M(int,string)'), anchors.join(' | '));
  assert.ok(anchors.includes('area/o.cs#C.M(int)'), 'overload-distinct canonical keys live in the index');
});

test('content-hash cache: unchanged serves cache; only the changed file re-derives', async () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');
  write(root, 'area/b.py', 'def b():\n    return 2\n');

  const first = await lib.assembleArea('area', root);
  assert.strictEqual(first.rederived.length, 2, 'first build derives all');

  const second = await lib.assembleArea('area', root);
  assert.strictEqual(second.rederived.length, 0, 'unchanged build serves all from cache');
  assert.strictEqual(second.cached.length, 2);

  write(root, 'area/a.py', 'def a():\n    return 99\n');
  const third = await lib.assembleArea('area', root);
  assert.deepStrictEqual(third.rederived, ['area/a.py'], 'only the changed file re-derives');
});

test('change is detected by content hash even when mtime is back-dated', async () => {
  const root = tmpProject();
  const f = write(root, 'area/a.py', 'def a():\n    return 1\n');
  await lib.assembleArea('area', root);

  fs.writeFileSync(f, 'def a():\n    return 2\n'); // new content
  const old = new Date('2000-01-01T00:00:00Z');
  fs.utimesSync(f, old, old); // back-date mtime to before the build
  const res = await lib.assembleArea('area', root);
  assert.deepStrictEqual(res.rederived, ['area/a.py'], 'content hash catches the change, mtime ignored');
});

test('map.token_budget override tightens the trim', async () => {
  const root = tmpProject();
  // many definitions so a tiny budget forces a trim
  let src = '';
  for (let i = 0; i < 40; i++) src += `def fn_${i}():\n    return ${i}\n\n`;
  write(root, 'area/big.py', src);
  write(root, '.craft/settings.yaml', 'map:\n  enabled: true\n  token_budget: 20\n');

  const res = await lib.assembleArea('area', root);
  assert.strictEqual(res.budget, 20, 'budget read from settings');
  assert.ok(res.tokenEstimate <= 20, 'slice trimmed to the override budget');
});

test('AUTOMATED RANKING GATE: the ranker runs end-to-end and the slice fits 4096 tokens', async () => {
  const root = tmpProject();
  let src = '';
  for (let i = 0; i < 60; i++) src += `def helper_${i}(x):\n    return x\n\n`;
  src += 'def helper_0_caller():\n    return ' + Array.from({ length: 30 }, (_, i) => `helper_${i}(1)`).join(' + ') + '\n';
  write(root, 'area/m.py', src);
  const res = await lib.assembleArea('area', root);
  assert.ok(res.tokenEstimate <= 4096, 'slice fits the default 4096-token budget');
  assert.ok(res.slice.length > 0, 'the ranker produced a non-empty slice');
});

test('map-freshness.sh: fresh on matching hash, stale on changed content', () => {
  const root = tmpProject();
  const f = write(root, 'a.py', 'def a():\n    return 1\n');
  const hash = execFileSync('bash', [MAP_FRESHNESS, f], { encoding: 'utf8' }).trim();
  assert.match(hash, /^[0-9a-f]{64}$/, 'prints a sha256');
  assert.strictEqual(execFileSync('bash', [MAP_FRESHNESS, f, hash], { encoding: 'utf8' }).trim(), 'fresh');
  fs.writeFileSync(f, 'def a():\n    return 2\n');
  assert.strictEqual(execFileSync('bash', [MAP_FRESHNESS, f, hash], { encoding: 'utf8' }).trim(), 'stale');
});

// --root passthrough: a consumer derives its project root from the file it works on,
// which in a monorepo is not cwd. The assemble seam must target the given root, not cwd.
// These run the real map-run.sh path (which uses the committed bundle), so they also
// prove the bundle carries the parse.

function runAssemble(cwd, args) {
  const out = execFileSync('bash', [MAP_RUN, 'assemble', ...args], { cwd, encoding: 'utf8' });
  return JSON.parse(out);
}

test('--root targets the given root from a foreign cwd, not cwd', () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');
  const foreign = tmpProject(); // a different cwd with no .craft and no area/

  const res = runAssemble(foreign, ['area', '--root', root]);
  assert.match(res.slice, /area\/a\.py/, 'slice came from <root>/area, not foreign cwd');
  assert.ok(
    fs.existsSync(path.join(root, '.craft', 'map', 'index.json')),
    'index written under the given root, not the foreign cwd'
  );
  assert.ok(
    !fs.existsSync(path.join(foreign, '.craft', 'map', 'index.json')),
    'nothing written under the foreign cwd'
  );
});

test('without --root the assemble seam stays cwd-relative (backward compat)', () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');

  const res = runAssemble(root, ['area']); // cwd = root, no --root
  assert.match(res.slice, /area\/a\.py/);
  assert.ok(fs.existsSync(path.join(root, '.craft', 'map', 'index.json')), 'index under cwd root');
});

test('--root is order-independent with the area-key', () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');
  const foreign = tmpProject();

  const before = runAssemble(foreign, ['--root', root, 'area']); // flag before key
  const after = runAssemble(foreign, ['area', '--root', root]); // flag after key
  assert.strictEqual(before.slice, after.slice, 'same slice regardless of --root position');
  assert.match(before.slice, /area\/a\.py/);
});

test('gating is preserved under --root: map.enabled:false returns disabled, writes no index', () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');
  write(root, '.craft/settings.yaml', 'map:\n  enabled: false\n');
  const foreign = tmpProject();

  const res = runAssemble(foreign, ['area', '--root', root]);
  assert.strictEqual(res.disabled, true, 'disabled flag honored when targeting via --root');
  assert.ok(
    !fs.existsSync(path.join(root, '.craft', 'map', 'index.json')),
    'no index written when disabled'
  );
});

// Per-anchor spans: persistence through index.json, content-hash invalidation, and
// the v2 schema migration (a pre-span v1 index must never be served from cache).

const INDEX = (root) => JSON.parse(fs.readFileSync(path.join(root, '.craft', 'map', 'index.json'), 'utf8'));

test('spans persist through index.json and the index carries version 2', async () => {
  const root = tmpProject();
  write(root, 'area/x.py', 'class Foo:\n    def bar(self):\n        return 1\n');
  await lib.assembleArea('area', root);
  const index = INDEX(root);
  assert.strictEqual(index.version, 2, 'index schema version is 2');
  for (const a of index.areas.area.files['area/x.py'].anchors) {
    assert.ok(Number.isInteger(a.startLine) && a.startLine >= 1, `startLine persisted on ${a.anchor}`);
    assert.ok(Number.isInteger(a.endLine) && a.endLine >= a.startLine, `endLine persisted on ${a.anchor}`);
  }
});

test('spans re-derive on content change and only for the changed file', async () => {
  const root = tmpProject();
  write(root, 'area/x.py', 'def a():\n    return 1\n');
  await lib.assembleArea('area', root);
  const before = INDEX(root).areas.area.files['area/x.py'].anchors[0];
  write(root, 'area/x.py', '# moved\n\ndef a():\n    return 1\n');
  const res = await lib.assembleArea('area', root);
  assert.deepStrictEqual(res.rederived, ['area/x.py']);
  const after = INDEX(root).areas.area.files['area/x.py'].anchors[0];
  assert.strictEqual(after.startLine, before.startLine + 2, 'span reflects the edited source');
});

test('cached spans are served unchanged when content is unchanged', async () => {
  const root = tmpProject();
  write(root, 'area/x.py', 'class Foo:\n    def bar(self):\n        return 1\n');
  await lib.assembleArea('area', root);
  const first = INDEX(root).areas.area.files['area/x.py'].anchors;
  const res = await lib.assembleArea('area', root);
  assert.strictEqual(res.rederived.length, 0, 'second run is a pure cache hit');
  assert.deepStrictEqual(INDEX(root).areas.area.files['area/x.py'].anchors, first, 'cached spans identical');
});

test('spanned symbols carry annotations; shell renders bare (floor intact)', async () => {
  const root = tmpProject();
  write(root, 'area/x.py', 'class Foo:\n    def bar(self):\n        return 1\n');
  write(root, 'area/run.sh', '#!/bin/bash\nmy_fn() {\n  echo hi\n}\n');
  const res = await lib.assembleArea('area', root);
  const lines = res.slice.split('\n').filter(Boolean);
  const pyLines = lines.filter((l) => /Foo|bar/.test(l));
  for (const l of pyLines) assert.match(l, /\[off=\d+,lim=\d+\]$/, `grammar symbol annotated: "${l}"`);
  const shLine = lines.find((l) => /my_fn/.test(l));
  assert.ok(shLine, 'shell function appears in the slice');
  assert.ok(!/\[off=/.test(shLine), `shell line has NO annotation (no reliable span): "${shLine}"`);
});

test('over-long symbol name truncates; the annotation survives intact', async () => {
  const root = tmpProject();
  const longName = 'x'.repeat(120);
  write(root, 'area/long.py', `def ${longName}():\n    return 1\n`);
  const res = await lib.assembleArea('area', root);
  const line = res.slice.split('\n').find((l) => l.includes('xxx'));
  assert.ok(line, 'long symbol rendered');
  assert.ok(line.length <= 100, `line respects the 100-char cap: ${line.length}`);
  assert.match(line, /\[off=1,lim=2\]$/, `annotation preserved intact at the end: "${line.slice(-30)}"`);
  assert.ok(!line.includes('x'.repeat(120)), 'the NAME is what got truncated');
});

test('a v1 (pre-span) index is never served, even on a hash match', async () => {
  const root = tmpProject();
  write(root, 'area/x.py', 'class Foo:\n    def bar(self):\n        return 1\n');
  await lib.assembleArea('area', root);

  // Seed the poisoned state: same REAL content hashes (so the hash gate alone would
  // serve them), anchors stripped of spans, version rolled back to 1.
  const index = INDEX(root);
  index.version = 1;
  for (const f of Object.values(index.areas.area.files)) {
    f.anchors = f.anchors.map(({ anchor, kind, line }) => ({ anchor, kind, line }));
  }
  fs.writeFileSync(path.join(root, '.craft', 'map', 'index.json'), JSON.stringify(index, null, 2) + '\n');

  const res = await lib.assembleArea('area', root);
  assert.deepStrictEqual(res.rederived, ['area/x.py'], 'version mismatch forces full re-derive despite matching hashes');
  const migrated = INDEX(root);
  assert.strictEqual(migrated.version, 2, 'written index is back on the current schema');
  for (const a of migrated.areas.area.files['area/x.py'].anchors) {
    assert.ok(Number.isInteger(a.startLine), 'migrated anchors carry spans again');
  }
});
