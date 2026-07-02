'use strict';

// Tier 2: the ripgrep flat floor. Symbol extraction runs only for a small, explicit
// allowlist of known-flat languages (shell today). Every other grammarless language
// is treated as potentially-nested and degrades to the file-level floor (path only,
// no children) - never a flat guess a future grammar could contradict.

// Known-flat languages: no nesting, so a flat path#name anchor is one a real grammar
// would also produce. Adding a language here is a deliberate edit, not a heuristic.
const FLAT_ALLOWLIST = new Set(['shell']);

// bash/sh function definitions: `name()`, `function name`, `function name()`.
const SHELL_FN = /^[ \t]*(?:function[ \t]+([A-Za-z_][A-Za-z0-9_-]*)[ \t]*(?:\([ \t]*\))?|([A-Za-z_][A-Za-z0-9_-]*)[ \t]*\([ \t]*\))[ \t]*\{/;

function extractTier2(relPath, languageId, source) {
  if (!FLAT_ALLOWLIST.has(languageId)) {
    return { anchors: [] };
  }
  const lines = source.split('\n');
  const anchors = [];
  const seen = new Set();
  for (let i = 0; i < lines.length; i++) {
    const m = SHELL_FN.exec(lines[i]);
    if (!m) continue;
    const name = m[1] || m[2];
    if (name && !seen.has(name)) {
      seen.add(name);
      // No reliable end line without a grammar (no brace matching) - endLine stays
      // null and the slice renders this symbol with no range annotation.
      anchors.push({ anchor: `${relPath}#${name}`, kind: 'function', line: i + 1, startLine: i + 1, endLine: null });
    }
  }
  return { anchors };
}

module.exports = { extractTier2, FLAT_ALLOWLIST };
