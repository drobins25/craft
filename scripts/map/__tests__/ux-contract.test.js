'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const lib = require('../runner.js');
const MAP_CAP = path.join(__dirname, '..', 'map-capability.sh');
const MAP_DIR = path.join(__dirname, '..');
const REPO_ROOT = path.join(__dirname, '..', '..', '..');

function tmpProject() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'craftmap-ux-'));
}
function write(root, rel, content) {
  const abs = path.join(root, rel);
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, content);
  return abs;
}

test('opt-out flag: absent settings builds (default-on); enabled:false skips the build, no error', async () => {
  const on = tmpProject();
  write(on, 'area/a.py', 'def a():\n    return 1\n');
  const onRes = await lib.assembleArea('area', on);
  assert.ok(!onRes.disabled, 'absent settings -> enabled by default');
  assert.strictEqual(onRes.fileCount, 1);

  const off = tmpProject();
  write(off, 'area/a.py', 'def a():\n    return 1\n');
  write(off, '.craft/settings.yaml', 'map:\n  enabled: false\n');
  const offRes = await lib.assembleArea('area', off);
  assert.strictEqual(offRes.disabled, true, 'enabled:false -> no build');
  assert.ok(!fs.existsSync(path.join(off, '.craft', 'map', 'index.json')), 'no index written when disabled');
});

test('capability is probed once and cached; the second call reads the cache', () => {
  const root = tmpProject();
  const first = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8' });
  assert.match(first, /"mode":"full"/);
  // Overwrite the cache with a sentinel; a re-probe would clobber it, a cached read returns it.
  fs.writeFileSync(path.join(root, '.craft', 'map', 'capability.json'), '{"mode":"sentinel"}\n');
  const second = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8' });
  assert.match(second, /"mode":"sentinel"/, 'probe-once: second call read the cache, did not re-probe');
});

test('capability honors the opt-out flag (disabled), still exit 0', () => {
  const root = tmpProject();
  write(root, '.craft/settings.yaml', 'map:\n  enabled: false\n');
  const out = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8' });
  assert.match(out, /"mode":"disabled"/);
});

test('capability degrades to floor when node is absent, never errors', () => {
  const root = tmpProject();
  const out = execFileSync('bash', [MAP_CAP, root], { encoding: 'utf8', env: { PATH: '/usr/bin:/bin' } });
  assert.match(out, /"mode":"floor"|"tier":"floor"|node-missing/);
});

test('a single unreadable file floors to file-level; the area still assembles', async () => {
  const root = tmpProject();
  write(root, 'area/good.py', 'def good():\n    return 1\n');
  const bad = write(root, 'area/bad.py', 'def bad():\n    return 2\n');
  fs.chmodSync(bad, 0o000); // make it unreadable
  try {
    const res = await lib.assembleArea('area', root);
    assert.strictEqual(res.fileCount, 2, 'both files accounted for');
    assert.ok(res.slice.includes('area/good.py'), 'the readable file still emits');
  } finally {
    fs.chmodSync(bad, 0o644);
  }
});

test('exactly one mode-tuned FYI on the first build, none after', async () => {
  const root = tmpProject();
  write(root, 'area/a.py', 'def a():\n    return 1\n');
  const first = await lib.assembleArea('area', root);
  assert.strictEqual(first.firstBuild, true);
  assert.match(first.fyi, /structural map|basic mode/);

  const second = await lib.assembleArea('area', root);
  assert.strictEqual(second.firstBuild, false);
  assert.strictEqual(second.fyi, null, 'FYI is once, ever');
});

test('status is pull-only: no toast/notify emitter exists in the map source', () => {
  const srcFiles = fs.readdirSync(path.join(MAP_DIR, 'src')).map((f) => fs.readFileSync(path.join(MAP_DIR, 'src', f), 'utf8'));
  const blob = srcFiles.join('\n');
  assert.ok(!/\b(toast|notify|push_notification|pushNotification)\b/i.test(blob), 'no in-flow notification path in the map');
});

test('trigger: no per-file-access hook intercepts Read/Grep/Glob for the map', () => {
  const hooks = fs.readFileSync(path.join(REPO_ROOT, 'hooks', 'hooks.json'), 'utf8');
  // No hook should wire the map into a per-tool-call interception of file reads.
  const hasMapReadHook = /map-run|scripts\/map/.test(hooks) && /"(Read|Grep|Glob)"/.test(hooks);
  assert.ok(!hasMapReadHook, 'the map is pull + cold-start push only, never a file-access hook');
});

test('the reference doc and status surface exist', () => {
  assert.ok(fs.existsSync(path.join(REPO_ROOT, 'commands', 'references', 'map.md')), 'reference md present');
  const status = fs.readFileSync(path.join(REPO_ROOT, 'commands', 'craft-status.md'), 'utf8');
  assert.match(status, /Map status/, 'craft-status renders a map line');
  assert.match(status, /pulled here, never pushed/i, 'status is pull-only by contract');
});

const AGENT_DOC = path.join(REPO_ROOT, 'commands', 'references', 'map-for-agents.md');
const PLAN_AGENT = path.join(REPO_ROOT, 'agents', 'plan-chunks-agent.md');

test('agent-facing map doc exists and teaches the four behaviors + kill switch', () => {
  assert.ok(fs.existsSync(AGENT_DOC), 'commands/references/map-for-agents.md present');
  const doc = fs.readFileSync(AGENT_DOC, 'utf8');
  // pull-only invocation
  assert.match(doc, /map-run\.sh assemble/, 'teaches the pull invocation');
  assert.match(doc, /--root/, 'teaches passing the derived root');
  // concept -> directory translation
  assert.match(doc, /concept into director/i, 'teaches concept->directory translation');
  // orientation, not search
  assert.match(doc, /not a search engine/i, 'positions the map as orientation, not search');
  // kill switch
  assert.match(doc, /[Kk]ill switch/, 'states the kill switch (remove the pointer)');
});

test('the slice-read rule is a POSITIVE ranged-read procedure with all load-bearing elements', () => {
  const doc = fs.readFileSync(AGENT_DOC, 'utf8');
  assert.match(doc, /thin slice is not a missing map/i, 'a thin slice is explicitly not a missing map');
  assert.match(doc, /\[off=N,lim=M\]/, 'names the paste-ready annotation');
  assert.match(doc, /offset=N, limit=M/, 'shows the concrete ranged Read call verbatim');
  assert.match(doc, /NARROWEST span/i, 'biases to the narrowest span (a class span can be the whole file)');
  assert.match(doc, /ADJACENT span, never the whole file/i, 'escalation = adjacent span, never whole-file');
  assert.match(doc, /offset=1, limit=/, 'allows the bounded header read for imports');
  assert.match(doc, /no reliable span/i, 'floor: only unspanned symbols fall back to whole-file reads');
});

test('plan-chunks-agent carries the same positive ranged-read instruction', () => {
  const agent = fs.readFileSync(PLAN_AGENT, 'utf8');
  assert.match(agent, /issuing the ranged reads the slice hands you/i, 'positive instruction, not a prohibition');
  assert.match(agent, /NARROWEST span/i, 'narrowest-span bias present');
  assert.match(agent, /ADJACENT span/i, 'adjacent-span escalation present');
  assert.match(agent, /NO `\[off,lim\]` annotation has no reliable span/, 'floor present');
});

test('the directory ceiling routes the scattered remainder to normal research, not a common ancestor', () => {
  const doc = fs.readFileSync(AGENT_DOC, 'utf8');
  assert.match(doc, /do NOT widen to a common-ancestor/i, 'forbids widening to a common-ancestor slice');
  assert.match(doc, /scattered remainder the normal way/i, 'routes the over-scattered remainder to normal research');
});

test('an empty or floored slice degrades to today behavior with no retry, no block', () => {
  const doc = fs.readFileSync(AGENT_DOC, 'utf8');
  assert.match(doc, /empty or floored slice/i, 'names the empty/floored non-result');
  assert.match(doc, /[Dd]o not retry, do not block/, 'no retry, no block on a non-result');
});

test('plan-chunks-agent Phase 1.3 carries the map pointer after baseline context, before story-driven research', () => {
  const agent = fs.readFileSync(PLAN_AGENT, 'utf8');
  const pointerIdx = agent.indexOf('map-for-agents.md');
  const baselineIdx = agent.indexOf('Start with your baseline context');
  const storyNeedsIdx = agent.indexOf("Then follow the story's needs");
  assert.ok(pointerIdx !== -1, 'the pointer to map-for-agents.md is present');
  assert.ok(baselineIdx !== -1 && storyNeedsIdx !== -1, 'the surrounding Phase 1.3 anchors exist');
  assert.ok(pointerIdx > baselineIdx, 'pointer sits after the baseline-context block');
  assert.ok(pointerIdx < storyNeedsIdx, 'pointer sits before story-driven research');
});

test('the agent-facing doc is distinct from the user-facing map.md', () => {
  const agentDoc = fs.readFileSync(AGENT_DOC, 'utf8');
  const userDoc = fs.readFileSync(path.join(REPO_ROOT, 'commands', 'references', 'map.md'), 'utf8');
  // The agent doc carries procedure the user doc does not.
  assert.match(agentDoc, /assemble <directory>/, 'agent doc has the assemble procedure');
  assert.ok(!/--root/.test(userDoc), 'user-facing map.md carries no agent procedure (--root)');
});

test('FORMAT.md section 10 carries the push-superseded note without rewriting the section', () => {
  const format = fs.readFileSync(path.join(REPO_ROOT, 'scripts', 'map', 'FORMAT.md'), 'utf8');
  // The note is present and flags pull-only supersession.
  assert.match(format, /cold-start push.*superseded by pull-only/i, 'dated note flags push superseded by pull-only');
  assert.match(format, /DESIGN CALL A/, 'note points at where pull-only is decided');
  // Note-not-rewrite: the original section 10 text is untouched.
  assert.match(format, /PLUS cold-start push/, 'original cold-start-push bullet still present');
  assert.match(format, /EXPLICITLY REJECTED: per-file-access hook auto-injection/, 'original rejection bullet intact');
});
