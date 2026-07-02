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

test('tier-1 records the declaration span (signature through closing brace)', async () => {
  const p = tmpFile('S.cs', 'class C {\n  int M(int a) {\n    return a;\n  }\n}\n');
  const res = await lib.extract(p);
  const m = res.anchors.find((a) => sym(a.anchor) === 'C.M(int)');
  assert.ok(m, res.anchors.map((a) => a.anchor).join(' | '));
  assert.strictEqual(m.startLine, 2, 'span starts at the declaration line, not the name line');
  assert.strictEqual(m.endLine, 4, 'span ends at the closing brace');
});

test('class span encloses its method spans', async () => {
  const p = tmpFile('S.cs', 'class C {\n  int M(int a) {\n    return a;\n  }\n}\n');
  const res = await lib.extract(p);
  const cls = res.anchors.find((a) => sym(a.anchor) === 'C');
  const m = res.anchors.find((a) => sym(a.anchor) === 'C.M(int)');
  assert.ok(cls.startLine <= m.startLine && cls.endLine >= m.endLine, `class [${cls.startLine},${cls.endLine}] must contain method [${m.startLine},${m.endLine}]`);
});

test('markdown heading span runs to the next equal-or-shallower heading, including subsections', async () => {
  const md = tmpFile('s.md', '# T\n## H1\ntext\n### sub\ntext2\n## H2\nend\n');
  const res = await lib.extract(md);
  const bySym = Object.fromEntries(res.anchors.map((a) => [sym(a.anchor), a]));
  assert.strictEqual(bySym['t/h1'].startLine, 2);
  assert.strictEqual(bySym['t/h1'].endLine, 5, 'H1 spans through its ### sub and stops above H2');
  assert.strictEqual(bySym['t/h1/sub'].endLine, 5, 'sub is closed by the shallower H2');
});

test('last markdown heading spans to EOF (fixture ends in a trailing newline)', async () => {
  const src = '# T\n## H1\ntext\n### sub\ntext2\n## H2\nend\n';
  assert.ok(src.endsWith('\n'), 'fixture must exercise the phantom empty-element case');
  const res = await lib.extract(tmpFile('s.md', src));
  const bySym = Object.fromEntries(res.anchors.map((a) => [sym(a.anchor), a]));
  assert.strictEqual(bySym['t/h2'].endLine, 7, 'EOF span ends at the last non-empty line, not the phantom line');
  assert.strictEqual(bySym['t'].endLine, 7, 'the enclosing # section also runs to EOF');
});

test('shell emits startLine and null endLine (never-lie floor for spans)', async () => {
  const sh = await lib.extract(path.join(__dirname, '..', 'map-run.sh'));
  const fn = sh.anchors[0];
  assert.ok(Number.isInteger(fn.startLine) && fn.startLine >= 1, 'shell function carries a real startLine');
  assert.strictEqual(fn.endLine, null, 'no reliable end without a grammar');
});

test('spans are additive: anchor/kind/line fields are unperturbed across tiers', async () => {
  const cs = await lib.extract(path.join(FIX, 'Sample.cs'));
  for (const a of cs.anchors) {
    assert.ok(a.anchor.includes('#') && a.kind && Number.isInteger(a.line), 'base fields intact');
    assert.ok(Number.isInteger(a.startLine) && a.startLine >= 1);
    assert.ok(a.endLine === null || (Number.isInteger(a.endLine) && a.endLine >= a.startLine));
  }
});
