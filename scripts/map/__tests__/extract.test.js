'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const lib = require('../runner.js');
const TAGS_DIR = path.join(__dirname, '..', 'tags');
const FIX = path.join(__dirname, '..', '__fixtures__');
const CURRENCY = path.join(__dirname, '..', 'grammar-currency');

const sym = (anchor) => (anchor.includes('#') ? anchor.slice(anchor.indexOf('#') + 1) : null);
const syms = (res) => res.anchors.map((a) => sym(a.anchor));

function tmpFile(name, content) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'craftmap-x-'));
  const p = path.join(dir, name);
  fs.writeFileSync(p, content);
  return p;
}

test('every vendored tags.scm compiles against its grammar and has @definition captures', async () => {
  await lib.initParser();
  for (const languageId of Object.keys(lib.GRAMMAR_WASM)) {
    const lang = await lib.loadLanguage(languageId);
    const scm = fs.readFileSync(path.join(TAGS_DIR, `${languageId}.scm`), 'utf8');
    const q = lang.query(scm); // throws if it does not compile
    const caps = new Set(q.captureNames);
    assert.ok(
      [...caps].some((c) => c.startsWith('definition.')),
      `${languageId}.scm should carry @definition.* captures`
    );
  }
});

test('C# two-overload file yields two distinct GenerateIds anchors', async () => {
  const res = await lib.extract(path.join(FIX, 'Sample.cs'));
  const s = syms(res);
  assert.ok(s.includes('LoadOrders.GenerateIds(int,string)'), s.join(' | '));
  assert.ok(s.includes('LoadOrders.GenerateIds(int)'), s.join(' | '));
});

test('param rename and default-value edit do NOT move the overload anchor', async () => {
  const a = tmpFile('A.cs', 'class C { int M(int count) { return count; } }');
  const b = tmpFile('B.cs', 'class C { int M(int renamed = 5) { return renamed; } }');
  const sa = syms(await lib.extract(a));
  const sb = syms(await lib.extract(b));
  assert.ok(sa.includes('C.M(int)'), sa.join(' | '));
  assert.deepStrictEqual(sa.sort(), sb.sort(), 'rename + default change must not move the anchor');
});

test('ref/out modifier DOES distinguish the overload', async () => {
  const a = tmpFile('R.cs', 'class C { void M(ref int x) {} void M(int x) {} }');
  const s = syms(await lib.extract(a));
  assert.ok(s.includes('C.M(ref int)'), s.join(' | '));
  assert.ok(s.includes('C.M(int)'), s.join(' | '));
});

test('shell yields path#name; a grammarless-nesting language floors to file-level', async () => {
  const sh = await lib.extract(path.join(__dirname, '..', 'map-run.sh'));
  assert.strictEqual(sh.tier, 'floor-flat');
  assert.ok(sh.anchors.some((a) => /#\w/.test(a.anchor)), 'shell function gets a path#name anchor');

  const rs = tmpFile('lib.rs', 'mod inner { fn foo() {} }');
  const rust = await lib.extract(rs);
  assert.strictEqual(rust.tier, 'floor');
  assert.strictEqual(rust.anchors.length, 0, 'nesting language without a grammar emits no symbol anchor, only file-level');
});

test('markdown slug: I/O deletes the slash (never a hyphen), space becomes a hyphen', async () => {
  const md = tmpFile('d.md', '## Routing\n\n### I/O Operations\n');
  const s = syms(await lib.extract(md));
  assert.ok(s.includes('routing/io-operations'), s.join(' | '));
  assert.ok(!s.some((x) => x.includes('i-o')), 'the slash must not become a hyphen');
});

test('markdown slug: empty-strip heading gets a positional slug; duplicates get -N', async () => {
  const md = tmpFile('e.md', '## ---\n\n## Dup\n\n## Dup\n');
  const s = syms(await lib.extract(md));
  assert.ok(s.some((x) => /^section-\d+$/.test(x)), `empty-strip -> section-N: ${s.join(' | ')}`);
  assert.ok(s.includes('dup'), s.join(' | '));
  assert.ok(s.includes('dup-1'), `duplicate slug gets -1: ${s.join(' | ')}`);
});

test('C# 12 primary-constructor floors the file; a clean sibling still emits', async () => {
  const bad = await lib.extract(path.join(CURRENCY, 'PrimaryCtor.cs'));
  assert.strictEqual(bad.floored, true);
  assert.strictEqual(bad.tier, 'floor');
  assert.strictEqual(bad.anchors.length, 0, 'no mislabeled symbol (no ILogger) is emitted');

  const clean = await lib.extract(path.join(FIX, 'Sample.cs'));
  assert.strictEqual(clean.floored, false);
  assert.ok(clean.anchors.length > 0, 'a clean sibling in the same language still emits symbols');
});

test('the 3-gate grammar QA harness passes (npm run grammar-check)', () => {
  const out = execFileSync('node', [path.join(CURRENCY, 'currency-check.js')], { encoding: 'utf8' });
  assert.match(out, /grammar-check passed/);
});
