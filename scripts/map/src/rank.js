'use strict';

// Reference-frequency ranking. Each definition is scored by how often its name is
// referenced across the area's source - the more a symbol is used, the higher it
// ranks, so the most load-bearing definitions survive a tight token budget. A
// PageRank-style refinement (personalized over a full reference graph) is the
// tunable precision layer; this degree-frequency count is the deterministic
// baseline the automated gate runs on.

// The last identifier segment of a symbol-path, overload signature removed.
function leafName(symbolPath) {
  if (!symbolPath) return '';
  const noOverload = symbolPath.replace(/\(.*\)$/, '');
  return noOverload.split(/[./]/).pop();
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// perFile: [{ rel, source, result: { anchors:[{anchor,kind,line}] } }]
// Returns the definitions ordered most-referenced first (deterministic ties).
function rankDefinitions(perFile) {
  const corpus = perFile.map((f) => f.source).join('\n');
  const counts = {};
  function refCount(name) {
    if (!name) return 0;
    if (name in counts) return counts[name];
    const m = corpus.match(new RegExp('\\b' + escapeRe(name) + '\\b', 'g'));
    counts[name] = m ? m.length : 0;
    return counts[name];
  }

  const defs = [];
  for (const f of perFile) {
    for (const a of f.result.anchors) {
      const symbolPath = a.anchor.includes('#') ? a.anchor.slice(a.anchor.indexOf('#') + 1) : '';
      const name = leafName(symbolPath);
      defs.push({
        rel: f.rel,
        anchor: a.anchor,
        kind: a.kind,
        line: a.line,
        // span fields ride along so renderSlice can emit ranged-read annotations
        startLine: a.startLine,
        endLine: a.endLine,
        // discount the definition's own occurrence so a never-referenced symbol scores 0
        score: Math.max(0, refCount(name) - 1),
      });
    }
  }
  defs.sort((a, b) => b.score - a.score || a.rel.localeCompare(b.rel) || a.line - b.line);
  return defs;
}

module.exports = { rankDefinitions, leafName };
