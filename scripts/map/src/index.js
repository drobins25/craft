'use strict';

// Living Map parser library. Loads bundled web-tree-sitter grammars, parses files,
// enumerates the tree with ripgrep, and detects language by extension. The CLI entry
// (cli.js) and the extraction tiers build on these primitives; this file holds no
// command dispatch so it can be required without running anything.

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');
const Parser = require('web-tree-sitter');

const RUNNER_DIR = __dirname;
const GRAMMAR_DIR = path.join(RUNNER_DIR, 'grammars');
const LANG_DETECT_PATH = path.join(RUNNER_DIR, 'lang-detect.json');

// languageIds that have a bundled tree-sitter grammar. Anything else resolves to
// the floor (file-level) or to a non-grammar tier handled elsewhere.
const GRAMMAR_WASM = {
  c_sharp: 'tree-sitter-c_sharp.wasm',
  typescript: 'tree-sitter-typescript.wasm',
  tsx: 'tree-sitter-tsx.wasm',
  java: 'tree-sitter-java.wasm',
  python: 'tree-sitter-python.wasm',
  javascript: 'tree-sitter-javascript.wasm',
};

let _initPromise = null;
function initParser() {
  if (!_initPromise) {
    _initPromise = Parser.init({
      locateFile: () => path.join(GRAMMAR_DIR, 'tree-sitter.wasm'),
    });
  }
  return _initPromise;
}

const _langCache = {};
async function loadLanguage(languageId) {
  if (_langCache[languageId]) return _langCache[languageId];
  const wasm = GRAMMAR_WASM[languageId];
  if (!wasm) throw new Error(`no bundled grammar for languageId: ${languageId}`);
  const lang = await Parser.Language.load(path.join(GRAMMAR_DIR, wasm));
  _langCache[languageId] = lang;
  return lang;
}

function loadLangDetect() {
  return JSON.parse(fs.readFileSync(LANG_DETECT_PATH, 'utf8'));
}

// Resolve a file to a languageId by extension only. A miss returns 'floor' - no
// content sniffing; an ambiguous extension simply degrades to the file-level floor.
function detectLanguage(file) {
  const map = loadLangDetect();
  const ext = path.extname(file).toLowerCase();
  return map[ext] || 'floor';
}

// Parse a file and return the raw tree. This is the seam extraction builds on:
// tree in, anchors out.
async function parseFile(absFilePath, languageId) {
  await initParser();
  const lang = await loadLanguage(languageId);
  const parser = new Parser();
  parser.setLanguage(lang);
  const source = fs.readFileSync(absFilePath, 'utf8');
  const tree = parser.parse(source);
  return { tree, language: languageId, source };
}

// True if the first slice of the file contains a NUL byte (the standard binary
// heuristic). The ripgrep walker honors ignore files and skips hidden entries;
// it does not skip binary by content, so the walk filters those out here.
function isBinary(absPath) {
  let fd;
  try {
    fd = fs.openSync(absPath, 'r');
    const buf = Buffer.alloc(8000);
    const bytes = fs.readSync(fd, buf, 0, 8000, 0);
    for (let i = 0; i < bytes; i++) {
      if (buf[i] === 0) return true;
    }
    return false;
  } catch {
    return false;
  } finally {
    if (fd !== undefined) fs.closeSync(fd);
  }
}

// Enumerate files under dir using ripgrep as the single walk: honors the project's
// own .gitignore/.ignore with or without a .git directory, skips hidden entries,
// applies no craft-authored ignore list. Binary files are filtered out here.
function enumerate(dir) {
  const out = execFileSync('rg', ['--files', '--no-require-git'], {
    cwd: dir,
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  return out
    .split('\n')
    .filter(Boolean)
    .filter((rel) => !isBinary(path.join(dir, rel)));
}

module.exports = {
  initParser,
  loadLanguage,
  parseFile,
  detectLanguage,
  enumerate,
  GRAMMAR_WASM,
  GRAMMAR_DIR,
};
