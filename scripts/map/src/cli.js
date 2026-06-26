'use strict';

// CLI entry. Bundled to runner.js and reached only through map-run.sh. Dispatches
// one command per invocation and prints a single JSON result to stdout. Kept
// separate from the library so the library can be required without running main().

const lib = require('./index.js');
const { extract } = require('./extract.js');

function countNodes(node) {
  let n = 1;
  let errors = 0;
  if (node.type === 'ERROR' || node.isMissing) errors++;
  for (let i = 0; i < node.namedChildCount; i++) {
    const r = countNodes(node.namedChild(i));
    n += r.n;
    errors += r.errors;
  }
  return { n, errors };
}

async function cmdParse(argv) {
  const file = argv[0];
  const languageId = argv[1] || lib.detectLanguage(file);
  if (!lib.GRAMMAR_WASM[languageId]) {
    return {
      tier: 'floor',
      reason: languageId === 'floor' ? 'no-grammar-for-extension' : `no-grammar:${languageId}`,
      language: languageId,
      file,
    };
  }
  const { tree } = await lib.parseFile(require('path').resolve(file), languageId);
  const counts = countNodes(tree.rootNode);
  return {
    ok: true,
    tier: 'grammar',
    language: languageId,
    file,
    rootType: tree.rootNode.type,
    hasError: tree.rootNode.hasError,
    nodeCount: counts.n,
    errorCount: counts.errors,
  };
}

function cmdDetect(argv) {
  return { file: argv[0], language: lib.detectLanguage(argv[0]) };
}

function cmdEnumerate(argv) {
  const dir = require('path').resolve(argv[0] || '.');
  return { dir, files: lib.enumerate(dir) };
}

// Capability probe: node runs, the runtime wasm loads, a grammar loads.
async function cmdProbe() {
  try {
    await lib.initParser();
    await lib.loadLanguage('c_sharp');
    return { node: true, runtime: 'loaded', testGrammar: 'loaded' };
  } catch (e) {
    return { node: true, runtime: 'failed', error: String((e && e.message) || e) };
  }
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  let result;
  switch (cmd) {
    case 'parse':
      result = await cmdParse(rest);
      break;
    case 'detect':
      result = cmdDetect(rest);
      break;
    case 'enumerate':
      result = cmdEnumerate(rest);
      break;
    case 'probe':
      result = await cmdProbe();
      break;
    case 'extract':
      result = await extract(rest[0]);
      break;
    default:
      process.stderr.write(`unknown command: ${cmd}\n`);
      process.exit(2);
  }
  process.stdout.write(JSON.stringify(result) + '\n');
}

// Re-export the library so the bundle stays usable as a module (tests, callers).
module.exports = { ...lib, extract };

if (require.main === module) {
  main().catch((e) => {
    process.stderr.write(`runner error: ${String((e && e.message) || e)}\n`);
    process.exit(1);
  });
}
