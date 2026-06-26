'use strict';

// Tier 3: markdown. No grammar - headings are scanned directly and each heading's
// slug chain becomes the anchor symbol-path. The slug pipeline is the locked,
// pinned five-step sequence; two machines must produce identical slugs.

// 1. delete every char that is not an ASCII letter, digit, space, or hyphen
//    (case-insensitive so letters survive). Deleted, not replaced - a '/' in the
//    heading vanishes, so "I/O Operations" cannot collide with a real "i/o" path.
// 2. lowercase (locale-independent in JS, by Unicode default - no Turkish-I drift)
// 3. spaces -> hyphen (the only char-to-hyphen mapping)
// 4. collapse consecutive hyphens
// 5. strip leading/trailing hyphens
function slugify(text) {
  let s = text.replace(/[^A-Za-z0-9 -]/g, '');
  s = s.toLowerCase();
  s = s.replace(/ /g, '-');
  s = s.replace(/-+/g, '-');
  s = s.replace(/^-+|-+$/g, '');
  return s;
}

function extractTier3(relPath, source) {
  const lines = source.split('\n');
  const stack = []; // enclosing headings: { level, slug }
  const seen = new Map(); // full path -> times seen (document order)
  const anchors = [];
  let headingOrdinal = 0;
  for (let i = 0; i < lines.length; i++) {
    const m = /^(#{1,6})[ \t]+(.*\S)[ \t]*$/.exec(lines[i]);
    if (!m) continue;
    const level = m[1].length;
    headingOrdinal++;
    let slug = slugify(m[2]);
    if (!slug) slug = `section-${headingOrdinal}`; // empty-strip fallback, positional
    while (stack.length && stack[stack.length - 1].level >= level) stack.pop();
    let full = [...stack.map((e) => e.slug), slug].join('/');
    const n = seen.get(full) || 0;
    seen.set(full, n + 1);
    if (n > 0) full = `${full}-${n}`; // in-file collision suffix, document order
    anchors.push({ anchor: `${relPath}#${full}`, kind: 'heading', line: i + 1 });
    stack.push({ level, slug });
  }
  return { anchors };
}

module.exports = { extractTier3, slugify };
