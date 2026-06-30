'use strict';

// CLI entry. Bundled to runner.js and reached only through map-run.sh. Dispatches
// one command per invocation and prints a single JSON result to stdout. Kept
// separate from the library so the library can be required without running main().

const lib = require('./index.js');
const { extract } = require('./extract.js');
const { assembleArea } = require('./assemble-area.js');

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

// Capability probe: node runs, the runtime wasm loads, each grammar loads. Reports
// the landed mode so the map can tell the truth about what it can parse.
async function cmdProbe() {
  try {
    await lib.initParser();
  } catch (e) {
    return { node: true, runtime: 'failed', mode: 'floor', grammars: {}, error: String((e && e.message) || e) };
  }
  const grammars = {};
  for (const languageId of Object.keys(lib.GRAMMAR_WASM)) {
    try {
      await lib.loadLanguage(languageId);
      grammars[languageId] = true;
    } catch {
      grammars[languageId] = false;
    }
  }
  const loaded = Object.values(grammars).filter(Boolean).length;
  const total = Object.keys(grammars).length;
  const mode = loaded === 0 ? 'floor' : loaded < total ? 'partial' : 'full';
  return { node: true, runtime: 'loaded', mode, grammars };
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
    case 'assemble': {
      // Parse an optional `--root <path>` out of the assemble args, order-independent
      // with the area-key. A consuming agent derives its project root from the file it
      // is working on - in a monorepo that is NOT cwd - so the root must be passable;
      // without --root, assembleArea falls back to cwd (unchanged behavior).
      const args = rest.slice();
      let root;
      const ri = args.indexOf('--root');
      if (ri !== -1) {
        root = args[ri + 1];
        args.splice(ri, 2);
      }
      result = await assembleArea(args[0], root);
      break;
    }
    default:
      process.stderr.write(`unknown command: ${cmd}\n`);
      process.exit(2);
  }
  process.stdout.write(JSON.stringify(result) + '\n');
}

// Re-export the library so the bundle stays usable as a module (tests, callers).
module.exports = { ...lib, extract, assembleArea };

if (require.main === module) {
  main().catch((e) => {
    process.stderr.write(`runner error: ${String((e && e.message) || e)}\n`);
    process.exit(1);
  });
}
