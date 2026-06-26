'use strict';

// Pre-ship grammar QA harness. Maintainer/CI-time only, zero user tokens: run
// `npm run grammar-check` before trusting a grammar bump. Three gates guard against
// a stale or wrong grammar shipping:
//
//   Gate 1 - fixture diff vs committed golden: extraction output for every fixture
//            must match the committed golden. A drift means review before ship.
//   Gate 2 - ERROR/MISSING density over the clean corpus: clean fixtures must parse
//            with zero error nodes. Errors on known-good code mean a stale grammar.
//   Gate 3 - structural name sanity: every emitted code name must be a real
//            identifier token - catches silent mis-binds that produce no ERROR node.
//
// The residual risk - a clean parse that is silently wrong with no error signal at
// all - is the irreducible tree-sitter floor, minimized by Gate 2. Run with
// `--update` to regenerate the golden after an intended change.

const fs = require('fs');
const path = require('path');
const lib = require('../runner.js');

const MAP_DIR = path.join(__dirname, '..');
const CLEAN_DIR = path.join(MAP_DIR, '__fixtures__');
const CURRENCY_DIR = __dirname;
const GOLDEN_PATH = path.join(__dirname, 'golden.json');
const IDENTIFIER = /^[A-Za-z_$][A-Za-z0-9_$]*$/;

function listFixtures(dir) {
  return fs
    .readdirSync(dir)
    .filter((f) => /\.(cs|ts|tsx|java|py|js)$/.test(f))
    .map((f) => path.join(dir, f));
}

// last identifier segment of an anchor's symbol-path, overload signature stripped
function leafName(anchor) {
  const hash = anchor.indexOf('#');
  if (hash === -1) return null;
  let sym = anchor.slice(hash + 1).replace(/\(.*\)$/, '');
  const seg = sym.split('.').pop();
  return seg;
}

async function run() {
  const update = process.argv.includes('--update');
  const clean = listFixtures(CLEAN_DIR);
  const currency = listFixtures(CURRENCY_DIR).filter((f) => !f.endsWith('currency-check.js'));
  const all = [...clean, ...currency];

  const results = {};
  for (const abs of all) {
    results[path.relative(MAP_DIR, abs).split(path.sep).join('/')] = await lib.extract(abs, MAP_DIR);
  }

  if (update) {
    fs.writeFileSync(GOLDEN_PATH, JSON.stringify(results, null, 2) + '\n');
    console.log(`golden updated: ${Object.keys(results).length} fixtures`);
    return 0;
  }

  const golden = JSON.parse(fs.readFileSync(GOLDEN_PATH, 'utf8'));
  const failures = [];

  // Gate 1: golden diff
  for (const [key, res] of Object.entries(results)) {
    if (JSON.stringify(res) !== JSON.stringify(golden[key])) {
      failures.push(`Gate1 golden-diff: ${key} extraction changed from golden`);
    }
  }
  for (const key of Object.keys(golden)) {
    if (!(key in results)) failures.push(`Gate1 golden-diff: ${key} missing from current run`);
  }

  // Gate 2: clean corpus must parse with zero error nodes
  for (const abs of clean) {
    const key = path.relative(MAP_DIR, abs).split(path.sep).join('/');
    const languageId = lib.detectLanguage(abs);
    if (!lib.GRAMMAR_WASM[languageId]) continue;
    const { tree } = await lib.parseFile(abs, languageId);
    if (tree.rootNode.hasError) {
      failures.push(`Gate2 error-density: clean fixture ${key} now has parse errors (stale grammar?)`);
    }
  }

  // Gate 3: structural name sanity on clean fixtures
  for (const abs of clean) {
    const key = path.relative(MAP_DIR, abs).split(path.sep).join('/');
    const res = results[key];
    for (const a of res.anchors || []) {
      const name = leafName(a.anchor);
      if (name && !IDENTIFIER.test(name)) {
        failures.push(`Gate3 name-sanity: ${key} emitted a non-identifier name "${name}" (mis-bind?)`);
      }
    }
  }

  if (failures.length) {
    console.error('grammar-check FAILED:');
    for (const f of failures) console.error('  - ' + f);
    return 1;
  }
  console.log(`grammar-check passed: ${clean.length} clean + ${currency.length} currency fixtures, 3 gates`);
  return 0;
}

run().then((code) => process.exit(code)).catch((e) => {
  console.error('grammar-check crashed:', e.message);
  process.exit(2);
});
