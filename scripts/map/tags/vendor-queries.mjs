// Maintainer step: vendor tags.scm for each curated grammar. Fetches the upstream
// query, splits it into individual patterns, keeps only the patterns that compile
// against the bundled grammar (dropping ones that reference node types a different
// grammar version exposes), and writes the pruned query to tags/<lang>.scm.
//
// This is the "reuse a catalog, cherry-pick where weak" path: we never hand-author
// extraction, we keep exactly the upstream patterns this grammar version supports.
// Run with `node tags/vendor-queries.mjs` after a grammar bump. Needs network +
// the build-time node_modules; output (tags/*.scm) is committed, the user clones it.

import Parser from 'web-tree-sitter';
import { writeFileSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const MAP_DIR = path.join(DIR, '..');
const GRAMMAR_DIR = path.join(MAP_DIR, 'grammars');

// languageId -> { wasm, urls[] }. TypeScript and TSX inherit JavaScript's tags
// (class/method/function patterns live in the JS query), so their queries are the
// JS patterns plus the TS-specific ones, in that order.
const JS_TAGS = 'https://raw.githubusercontent.com/tree-sitter/tree-sitter-javascript/master/queries/tags.scm';
const TS_TAGS = 'https://raw.githubusercontent.com/tree-sitter/tree-sitter-typescript/master/queries/tags.scm';
const SOURCES = {
  c_sharp: {
    wasm: 'tree-sitter-c_sharp.wasm',
    urls: ['https://raw.githubusercontent.com/tree-sitter/tree-sitter-c-sharp/master/queries/tags.scm'],
  },
  typescript: { wasm: 'tree-sitter-typescript.wasm', urls: [JS_TAGS, TS_TAGS] },
  tsx: { wasm: 'tree-sitter-tsx.wasm', urls: [JS_TAGS, TS_TAGS] },
  java: {
    wasm: 'tree-sitter-java.wasm',
    urls: ['https://raw.githubusercontent.com/tree-sitter/tree-sitter-java/master/queries/tags.scm'],
  },
  python: {
    wasm: 'tree-sitter-python.wasm',
    urls: ['https://raw.githubusercontent.com/tree-sitter/tree-sitter-python/master/queries/tags.scm'],
  },
  javascript: { wasm: 'tree-sitter-javascript.wasm', urls: [JS_TAGS] },
};

// Split a tags.scm into top-level pattern units. A unit begins at a depth-0 '(' or
// '[' and runs until the next depth-0 pattern start. A depth-0 '(#predicate ...)'
// attaches to the preceding unit rather than starting a new one.
function splitPatterns(scm) {
  const units = [];
  let depth = 0;
  let start = -1;
  let inStr = false;
  for (let i = 0; i < scm.length; i++) {
    const c = scm[i];
    if (inStr) {
      if (c === '\\') i++;
      else if (c === '"') inStr = false;
      continue;
    }
    if (c === '"') { inStr = true; continue; }
    if (c === ';' && depth === 0) {
      // line comment - skip to end of line
      while (i < scm.length && scm[i] !== '\n') i++;
      continue;
    }
    if (c === '(' || c === '[') {
      if (depth === 0) {
        const isPredicate = c === '(' && scm[i + 1] === '#';
        if (start === -1 || !isPredicate) {
          if (start !== -1) units.push(scm.slice(start, i).trim());
          start = i;
        }
      }
      depth++;
    } else if (c === ')' || c === ']') {
      depth--;
    }
  }
  if (start !== -1) units.push(scm.slice(start).trim());
  return units.filter(Boolean);
}

async function main() {
  await Parser.init({ locateFile: () => path.join(GRAMMAR_DIR, 'tree-sitter.wasm') });
  const summary = [];
  for (const [langId, { wasm, urls }] of Object.entries(SOURCES)) {
    const lang = await Parser.Language.load(path.join(GRAMMAR_DIR, wasm));
    let raw = '';
    for (const url of urls) {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`fetch ${url} -> ${res.status}`);
      raw += '\n' + (await res.text());
    }
    const patterns = splitPatterns(raw);
    const kept = [];
    let dropped = 0;
    for (const p of patterns) {
      try {
        lang.query(p);
        kept.push(p);
      } catch {
        dropped++;
      }
    }
    // Sanity: the whole kept set must compile together.
    const body = kept.join('\n\n');
    lang.query(body);
    const header = `; Vendored from:\n${urls.map((u) => '; ' + u).join('\n')}\n; Pruned to the patterns this grammar version supports (${kept.length} kept, ${dropped} dropped).\n; Regenerate with: node tags/vendor-queries.mjs\n\n`;
    writeFileSync(path.join(DIR, `${langId}.scm`), header + body + '\n');
    const defs = kept.filter((p) => /@definition\./.test(p)).length;
    summary.push({ langId, kept: kept.length, dropped, definitions: defs });
  }
  console.table(summary);
}

main().catch((e) => {
  console.error('vendor-queries failed:', e.message);
  process.exit(1);
});
