// Maintainer build step. Run `npm run build` after a web-tree-sitter or grammar
// bump. Produces the two committed artifacts the user ships:
//   1. runner.js          - the single self-contained bundle (web-tree-sitter inlined)
//   2. grammars/*.wasm     - the runtime wasm + the curated grammar wasms (data assets)
// node_modules is build-time only and never committed.

import * as esbuild from 'esbuild';
import { copyFileSync, mkdirSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const DIR = path.dirname(fileURLToPath(import.meta.url));
const GRAMMAR_DIR = path.join(DIR, 'grammars');

// 1. Vendor the wasm data assets from build-time node_modules into grammars/.
mkdirSync(GRAMMAR_DIR, { recursive: true });
const WASM = [
  ['node_modules/web-tree-sitter/tree-sitter.wasm', 'tree-sitter.wasm'],
  ['node_modules/tree-sitter-wasms/out/tree-sitter-c_sharp.wasm', 'tree-sitter-c_sharp.wasm'],
  ['node_modules/tree-sitter-wasms/out/tree-sitter-typescript.wasm', 'tree-sitter-typescript.wasm'],
  ['node_modules/tree-sitter-wasms/out/tree-sitter-tsx.wasm', 'tree-sitter-tsx.wasm'],
  ['node_modules/tree-sitter-wasms/out/tree-sitter-java.wasm', 'tree-sitter-java.wasm'],
  ['node_modules/tree-sitter-wasms/out/tree-sitter-python.wasm', 'tree-sitter-python.wasm'],
  ['node_modules/tree-sitter-wasms/out/tree-sitter-javascript.wasm', 'tree-sitter-javascript.wasm'],
];
for (const [src, dest] of WASM) {
  copyFileSync(path.join(DIR, src), path.join(GRAMMAR_DIR, dest));
}

// 2. Bundle the runner to a single committed file. Node builtins stay external
//    (default for platform node); web-tree-sitter is inlined and loads its wasm
//    at runtime via the locateFile override in the source.
await esbuild.build({
  entryPoints: [path.join(DIR, 'src/cli.js')],
  outfile: path.join(DIR, 'runner.js'),
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node18',
});

console.log('build complete: runner.js + grammars/*.wasm (' + WASM.length + ' wasm assets)');
