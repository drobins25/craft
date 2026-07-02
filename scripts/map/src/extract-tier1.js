'use strict';

// Tier 1: nested-scope code. Runs the vendored tags.scm against the parse tree,
// builds a fully-qualified anchor per definition from its scope ancestry, and
// renders an overload disambiguator where the language allows overloading.
//
// Never-lie floor: a symbol is emitted only if its NAME can be trusted. If an
// ERROR or MISSING node sits at or before a definition's name within that
// definition, the whole file degrades to the file-level floor rather than risk a
// mislabeled name. Detection is generic ERROR/MISSING topology - no per-language code.

const fs = require('fs');
const path = require('path');

const TAGS_DIR = path.join(__dirname, 'tags');

// Languages whose anchors carry an overload disambiguator. C# and Java overload by
// signature; the other curated grammars resolve to name+scope only.
const OVERLOAD_LANGS = {
  c_sharp: { paramsRe: /parameter_list/, paramRe: /^parameter$/ },
  java: { paramsRe: /formal_parameters/, paramRe: /parameter/ },
};
const PARAM_MODIFIERS = new Set(['ref', 'out', 'in', 'params']);

const _queryCache = {};
function loadQuery(lang, languageId) {
  if (_queryCache[languageId]) return _queryCache[languageId];
  const scm = fs.readFileSync(path.join(TAGS_DIR, `${languageId}.scm`), 'utf8');
  const q = lang.query(scm);
  _queryCache[languageId] = q;
  return q;
}

function stripWs(s) {
  return s.replace(/\s+/g, '');
}

function firstTypeChild(paramNode) {
  const nameNode = paramNode.childForFieldName('name');
  for (let i = 0; i < paramNode.namedChildCount; i++) {
    const c = paramNode.namedChild(i);
    if (nameNode && c.startIndex === nameNode.startIndex) continue;
    return c;
  }
  return null;
}

// "(int,string)" from a declaration, source-span types, whitespace-stripped,
// names and defaults excluded, ref/out/in/params modifiers included.
function renderOverload(declNode, cfg) {
  let params = null;
  for (let i = 0; i < declNode.namedChildCount; i++) {
    const c = declNode.namedChild(i);
    if (cfg.paramsRe.test(c.type)) {
      params = c;
      break;
    }
  }
  if (!params) return '()';
  const types = [];
  for (let i = 0; i < params.namedChildCount; i++) {
    const p = params.namedChild(i);
    if (!cfg.paramRe.test(p.type)) continue;
    const typeNode = p.childForFieldName('type') || firstTypeChild(p);
    const typeText = typeNode ? typeNode.text : '';
    const mods = [];
    for (let j = 0; j < p.childCount; j++) {
      const mc = p.child(j);
      if (typeNode && mc.startIndex >= typeNode.startIndex) break;
      if (PARAM_MODIFIERS.has(mc.text)) mods.push(mc.text);
    }
    // Type text is whitespace-stripped; the modifier keeps one space before it,
    // matching the locked rendering (e.g. "ref int").
    const prefix = mods.length ? mods.join(' ') + ' ' : '';
    types.push(prefix + stripWs(typeText));
  }
  return '(' + types.join(',') + ')';
}

// True if an ERROR/MISSING node sits at or before nameNode within declNode.
function errorAtOrBeforeName(declNode, nameNode) {
  if (!declNode.hasError && !nameNode.isMissing) return false;
  if (nameNode.isMissing || nameNode.type === 'ERROR') return true;
  let found = false;
  (function walk(n) {
    if (found) return;
    if ((n.type === 'ERROR' || n.isMissing) && n.startIndex <= nameNode.startIndex) {
      found = true;
      return;
    }
    for (let i = 0; i < n.childCount; i++) walk(n.child(i));
  })(declNode);
  return found;
}

// Collect every definition: its declaration node, name node, and kind. Uses the
// tags.scm @definition.* / @name capture convention via per-match grouping.
function collectDefinitions(query, root) {
  const defs = [];
  const matches = query.matches(root);
  for (const m of matches) {
    let nameCap = null;
    let defCap = null;
    for (const c of m.captures) {
      if (c.name === 'name') nameCap = c;
      else if (c.name.startsWith('definition.')) defCap = c;
    }
    if (!nameCap || !defCap) continue;
    defs.push({
      declNode: defCap.node,
      nameNode: nameCap.node,
      kind: defCap.name.slice('definition.'.length),
      name: nameCap.node.text,
    });
  }
  return defs;
}

// FQN segments: the names of all enclosing definitions, outermost first, plus own.
function fqnFor(def, defs) {
  const ancestors = defs.filter(
    (a) =>
      a !== def &&
      a.declNode.startIndex <= def.declNode.startIndex &&
      a.declNode.endIndex >= def.declNode.endIndex
  );
  ancestors.sort((a, b) => a.declNode.startIndex - b.declNode.startIndex || b.declNode.endIndex - a.declNode.endIndex);
  return [...ancestors.map((a) => a.name), def.name].join('.');
}

// Extract tier-1 anchors. Returns { floored, reason, anchors }.
function extractTier1(relPath, languageId, lang, tree) {
  const query = loadQuery(lang, languageId);
  const defs = collectDefinitions(query, tree.rootNode);
  const overloadCfg = OVERLOAD_LANGS[languageId];

  // Never-lie floor: if any definition's name is untrustworthy, the file degrades.
  for (const d of defs) {
    if (errorAtOrBeforeName(d.declNode, d.nameNode)) {
      return { floored: true, reason: 'untrusted-name', anchors: [] };
    }
  }

  const anchors = defs.map((d) => {
    let symbolPath = fqnFor(d, defs);
    if (overloadCfg && (d.kind === 'method' || d.kind === 'function' || d.kind === 'constructor')) {
      symbolPath += renderOverload(d.declNode, overloadCfg);
    }
    return {
      anchor: `${relPath}#${symbolPath}`,
      kind: d.kind,
      line: d.nameNode.startPosition.row + 1,
      // Span of the whole declaration (not just the name), 1-indexed, so a ranged
      // read gets the full definition body.
      startLine: d.declNode.startPosition.row + 1,
      endLine: d.declNode.endPosition.row + 1,
    };
  });
  return { floored: false, anchors };
}

module.exports = { extractTier1, errorAtOrBeforeName, renderOverload };
