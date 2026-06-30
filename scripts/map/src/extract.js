'use strict';

// Orchestrator: detect a file's language and route it to the right extraction tier,
// returning anchors in the one locked identity. Grammar languages go to tier 1,
// markdown to tier 3, shell and everything else to the tier-2 floor.

const fs = require('fs');
const path = require('path');
const { initParser, loadLanguage, parseFile, detectLanguage, GRAMMAR_WASM } = require('./index.js');
const { extractTier1 } = require('./extract-tier1.js');
const { extractTier2, FLAT_ALLOWLIST } = require('./extract-tier2-floor.js');
const { extractTier3 } = require('./extract-tier3-md.js');

function toRel(absFilePath, root) {
  const base = root || process.cwd();
  return path.relative(base, absFilePath).split(path.sep).join('/');
}

async function extract(absFilePath, root) {
  const abs = path.resolve(absFilePath);
  const relPath = toRel(abs, root);
  const languageId = detectLanguage(abs);

  if (GRAMMAR_WASM[languageId]) {
    await initParser();
    const lang = await loadLanguage(languageId);
    const { tree } = await parseFile(abs, languageId);
    const r = extractTier1(relPath, languageId, lang, tree);
    if (r.floored) {
      return { file: relPath, language: languageId, tier: 'floor', floored: true, reason: r.reason, anchors: [] };
    }
    return { file: relPath, language: languageId, tier: 'grammar', floored: false, anchors: r.anchors };
  }

  if (languageId === 'markdown') {
    const source = fs.readFileSync(abs, 'utf8');
    return { file: relPath, language: languageId, tier: 'markdown', floored: false, anchors: extractTier3(relPath, source).anchors };
  }

  const source = fs.readFileSync(abs, 'utf8');
  const r = extractTier2(relPath, languageId, source);
  return {
    file: relPath,
    language: languageId,
    tier: FLAT_ALLOWLIST.has(languageId) ? 'floor-flat' : 'floor',
    floored: false,
    anchors: r.anchors,
  };
}

module.exports = { extract };
