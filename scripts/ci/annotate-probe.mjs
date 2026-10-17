// annotate-probe.mjs - drive the real annotate loop in headless Chrome, in real
// time, and print one JSON verdict for annotate-check.sh to judge.
//
// Usage: node annotate-probe.mjs <chrome> <profile-dir> <chrome-pid-file>
//          <annotate-run.sh> <annotate-channel.py> <project-root> <session-id> <page-url>
//
// The page runs its own render loop exactly as it does for a user, and the
// overlay is operated through real mouse and keyboard input so its own handlers
// run. The CLI steps (begin, loader, watch, apply, announce) are the real verbs,
// spawned from here so page and CLI steps interleave in one ordered script.
// Every value compared against a verb's output is read from the page through
// Runtime.evaluate or from the session's files, never from that output. No
// packages: Chrome is driven over its DevTools protocol with node's built-in
// WebSocket. The verdict is printed even when something goes wrong; this
// script exits 0 unless its own arguments are missing.

import { spawn, execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, statSync, openSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';

const [chromeBin, profileDir, chromePidFile, runSh, channelPy, root, session, pageUrl] = process.argv.slice(2);
if (!pageUrl) {
  console.error('usage: node annotate-probe.mjs <chrome> <profile-dir> <chrome-pid-file> <annotate-run.sh> <annotate-channel.py> <root> <session> <page-url>');
  process.exit(2);
}

const WIDTH = 1400;
const HEIGHT = 900;
const HARD_CAP_MS = 110000;
const QUIET_MS = 1500;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const sessionDir = join(root, '.craft', 'annotations', session);
const asserts = [];
const watches = [];
let verdictError = null;
let chrome = null;
let ws = null;

const finish = () => {
  try { if (ws) ws.close(); } catch (e) { /* already closed */ }
  for (const w of watches) { try { w.proc.kill('SIGKILL'); } catch (e) { /* already gone */ } }
  try { if (chrome) process.kill(-chrome.pid, 'SIGKILL'); } catch (e) { /* already gone */ }
  console.log(JSON.stringify({ error: verdictError, asserts, chromeStart }));
  process.exit(0);
};
setTimeout(() => { verdictError = verdictError || 'probe exceeded ' + HARD_CAP_MS + 'ms'; finish(); }, HARD_CAP_MS).unref();

const check = (n, text, ok, detail) => { asserts.push({ n, text, ok: !!ok, detail: ok ? '' : String(detail || '') }); };

// --- launch Chrome on a debugging port it chooses itself ----------------------
let chromeStart = null;
const diagLog = join(profileDir, '..', 'chrome-stderr.log');
const diagFd = openSync(diagLog, 'w');
const diagT0 = Date.now();
chrome = spawn(chromeBin, [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
  '--remote-debugging-port=0', '--user-data-dir=' + profileDir,
  // A name that is not local, served by this machine: lets the run open a page on a foreign origin.
  '--host-resolver-rules=MAP external.test 127.0.0.1',
  '--enable-logging=stderr', '--v=1',
  '--window-size=' + WIDTH + ',' + HEIGHT, 'about:blank'
], { stdio: ['ignore', diagFd, diagFd], detached: true });
let diagExit = null;
chrome.on('exit', (code, signal) => { diagExit = { code, signal, atMs: Date.now() - diagT0 }; });
chrome.on('error', e => { verdictError = 'chrome did not start: ' + e.message; finish(); });
if (chrome.pid) writeFileSync(chromePidFile, String(chrome.pid));

const portFile = join(profileDir, 'DevToolsActivePort');
// DIAG (throwaway): wait up to 60s, record how long the port took and what Chrome did.
let port = null;
for (let i = 0; i < 600 && !port; i++) {
  if (existsSync(portFile)) port = readFileSync(portFile, 'utf8').split('\n')[0].trim() || null;
  if (!port) await sleep(100);
}
const diagTail = () => { try { return readFileSync(diagLog, 'utf8').split('\n').slice(-40).join('\n'); } catch (e) { return 'no stderr log: ' + e.message; } };
chromeStart = { portMs: port ? Date.now() - diagT0 : null, wouldFail10s: !port || Date.now() - diagT0 > 10000, exit: diagExit, stderrTail: (!port || Date.now() - diagT0 > 3000) ? diagTail() : '' };
if (!port) { verdictError = 'chrome never opened its debugging port'; finish(); }

let target = null;
for (let i = 0; i < 50 && !target; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:' + port + '/json')).json();
    target = list.find(t => t.type === 'page') || null;
  } catch (e) { /* not listening yet */ }
  if (!target) await sleep(100);
}
if (!target) { verdictError = 'no page target in chrome'; finish(); }

ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; })
  .catch(() => { verdictError = 'could not attach to the page'; finish(); });
let nextId = 0;
const pending = new Map();
ws.onmessage = m => {
  const d = JSON.parse(m.data);
  if (pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); }
};
const send = (method, params = {}) => new Promise(resolve => {
  const id = ++nextId;
  pending.set(id, resolve);
  ws.send(JSON.stringify({ id, method, params }));
});
const evaluate = async expr => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.result && r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.text + ' ' + (r.result.exceptionDetails.exception?.description || ''));
  return r.result && r.result.result ? r.result.result.value : undefined;
};
// waitFor <expr> <capMs> - polls a page expression until truthy; ms waited or -1. A page that is
// mid-navigation throws; that is just "not yet".
const waitFor = async (expr, capMs) => {
  const start = Date.now();
  while (Date.now() - start < capMs) {
    try { if (await evaluate(expr)) return Date.now() - start; } catch (e) { /* context gone: retry */ }
    await sleep(50);
  }
  return -1;
};
const until = async (fn, capMs) => {
  const start = Date.now();
  while (Date.now() - start < capMs) {
    if (await fn()) return true;
    await sleep(50);
  }
  return false;
};

// --- the real verbs -----------------------------------------------------------
const verb = (args, input = '') => new Promise(resolve => {
  const proc = spawn('bash', [runSh, ...args, '--root', root, '--session', session], { stdio: ['pipe', 'pipe', 'pipe'] });
  let out = '';
  let err = '';
  const timer = setTimeout(() => proc.kill('SIGKILL'), 30000);
  proc.stdout.on('data', d => { out += d; });
  proc.stderr.on('data', d => { err += d; });
  proc.on('close', code => { clearTimeout(timer); resolve({ code, out, err }); });
  proc.stdin.end(input);
});

const startWatch = (extra = []) => {
  const proc = spawn('bash', [runSh, 'watch', '--root', root, '--session', session, ...extra], { stdio: ['ignore', 'pipe', 'ignore'] });
  const w = { proc, lines: [], buf: '', exited: null };
  proc.stdout.on('data', d => {
    w.buf += d;
    let i;
    while ((i = w.buf.indexOf('\n')) >= 0) { w.lines.push(w.buf.slice(0, i)); w.buf = w.buf.slice(i + 1); }
  });
  proc.on('close', code => { w.exited = code; });
  watches.push(w);
  return w;
};
const lineFor = (w, prefix) => w.lines.find(l => l.startsWith(prefix));
const waitLine = async (w, prefix, capMs) => (await until(() => !!lineFor(w, prefix), capMs)) ? lineFor(w, prefix) : null;

// --- reads that never go through the verbs' output ---------------------------
const listenerBase = () => 'http://127.0.0.1:' + readFileSync(join(sessionDir, 'port'), 'utf8').trim();
// The listener's own session token, read from the file it writes (never from a verb's output).
const sessionToken = () => { try { return readFileSync(join(sessionDir, 'token'), 'utf8').trim(); } catch (e) { return ''; } };
const withToken = path => path + (path.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(sessionToken());
const healthClients = async () => (await (await fetch(listenerBase() + withToken('/health'))).json()).clients;
const postSheet = async id => (await (await fetch(listenerBase() + withToken('/sheet'), {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, measure: [], targets: [] })
})).json()).delivered;
// The flow's in-page listener check, read out of the flow's own text so the probe runs exactly what the flow sends.
const inPageCheck = () => {
  const doc = readFileSync(join(dirname(runSh), '..', '..', 'commands', 'references', 'annotate-inline.md'), 'utf8').split('\n');
  const at = doc.findIndex(l => l.startsWith('Then probe the listener FROM THE PAGE'));
  const open = doc.findIndex((l, i) => at >= 0 && i > at && l === '```js');
  const close = doc.findIndex((l, i) => open >= 0 && i > open && l === '```');
  if (close < 0) throw new Error('the flow has no in-page listener check');
  return doc.slice(open + 1, close).join('\n');
};
const readJson = name => { try { return JSON.parse(readFileSync(join(sessionDir, name), 'utf8')); } catch (e) { return null; } };
const readText = name => { try { return readFileSync(join(sessionDir, name), 'utf8'); } catch (e) { return ''; } };
const logSize = () => { try { return statSync(join(sessionDir, 'changes.jsonl')).size; } catch (e) { return 0; } };

// --- page reads and real input ------------------------------------------------
const rectOf = sel => evaluate(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); if (!e) return null;
  const r = e.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()`);
const pageBox = sel => evaluate(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); if (!e) return null;
  const r = e.getBoundingClientRect(); return { x: Math.round(r.left + window.scrollX), y: Math.round(r.top + window.scrollY),
  w: Math.round(r.width), h: Math.round(r.height), count: document.querySelectorAll(${JSON.stringify(sel)}).length }; })()`);
const computed = (sel, prop) => evaluate(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); return e ? getComputedStyle(e).getPropertyValue(${JSON.stringify(prop)}) : null; })()`);
const renders = () => evaluate('window.__renders');

const click = async (x, y) => {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
  // Press and release go out back to back, so a re-render cannot land between them
  // and turn the click into one on a common ancestor.
  await Promise.all([
    send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 }),
    send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 })
  ]);
};
const clickEl = async sel => {
  const r = await rectOf(sel);
  if (!r) throw new Error('nothing to click: ' + sel);
  await click(r.l + r.w / 2, r.t + r.h / 2);
};
const clickText = async (scope, text) => {
  const r = await evaluate(`(() => { const b = Array.from(document.querySelectorAll(${JSON.stringify(scope + ' button')})).find(x => x.textContent === ${JSON.stringify(text)});
    if (!b) return null; const r = b.getBoundingClientRect(); return { l: r.left, t: r.top, w: r.width, h: r.height }; })()`);
  if (!r) throw new Error('no ' + text + ' button in ' + scope);
  await click(r.l + r.w / 2, r.t + r.h / 2);
};

const storeKey = () => evaluate(`'ca-annotations:' + location.pathname`);
const storedPins = async () => evaluate(`JSON.parse(localStorage.getItem('ca-annotations:' + location.pathname) || '[]')`);

// Drops a pin through the overlay's own controls: comment mode on, a click on the element at
// (dx, dy) from its top-left (or its center), the text typed, Enter to save. Returns the stored pin.
const makePin = async (sel, at, text) => {
  if (!(await evaluate(`document.body.classList.contains('ca-mode')`))) await clickEl('#ca-toggle');
  const r = await rectOf(sel);
  if (!r) throw new Error('no element for ' + sel);
  const x = at ? r.l + at[0] : r.l + r.w / 2;
  const y = at ? r.t + at[1] : r.t + r.h / 2;
  const before = await evaluate(`document.querySelectorAll('.ca-pin').length`);
  await click(x, y);
  if ((await waitFor(`!!document.querySelector('.ca-box textarea')`, 3000)) < 0) throw new Error('no comment box opened for ' + sel);
  await send('Input.insertText', { text });
  await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
  await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
  if ((await waitFor(`document.querySelectorAll('.ca-pin').length === ${before + 1}`, 3000)) < 0) throw new Error('the pin for ' + sel + ' was not saved');
  const pin = (await storedPins()).find(p => p.text === text);
  if (!pin) throw new Error('the pin for ' + sel + ' is not in storage');
  return pin;
};

// SEND TO CLAUDE through the real button; true once the page shows RETURNED.
const sendPins = async () => {
  await evaluate(`document.getElementById('ca-status').textContent = ''`);
  await clickEl('#ca-send');
  return (await waitFor(`document.getElementById('ca-status').textContent === 'RETURNED'`, 5000)) >= 0;
};

// --- apply output, parsed -----------------------------------------------------
const block = (key, css) => `/* annotate-key ${key} */\n${css}\n`;
const parseApply = out => {
  const lines = out.split('\n').filter(Boolean);
  const head = /^APPLIED \S+ view (-?\d+),(-?\d+) (\d+)x(\d+) page (\d+)x(\d+)$/.exec(lines[0] || '');
  const rules = lines.filter(l => !l.startsWith('APPLIED') && !l.startsWith('SHOT') && !l.endsWith(' dropped')).map(l => {
    const m = /^(\S+) (\S+) x(\d+)(?: box (-?\d+),(-?\d+) (\d+)x(\d+))?(?: (.*))?$/.exec(l);
    if (!m) return { raw: l };
    let rest = m[8] || '';
    let visibility = null;
    const vm = /^(visible|not checked|out of view|covered by .+?): (.*)$/.exec(rest);
    if (vm) { visibility = vm[1]; rest = vm[2]; }
    const values = {};
    rest.split('; ').filter(Boolean).forEach(p => { const i = p.indexOf(' '); values[p.slice(0, i)] = p.slice(i + 1); });
    return { raw: l, key: m[1], selector: m[2], matched: Number(m[3]),
      box: m[4] === undefined ? null : { x: Number(m[4]), y: Number(m[5]), w: Number(m[6]), h: Number(m[7]) }, visibility, values };
  });
  return { lines, view: head ? { x: +head[1], y: +head[2], w: +head[3], h: +head[4] } : null, rules,
    shots: lines.filter(l => l.startsWith('SHOT ')) };
};
const sameBox = (a, b) => !!a && !!b && a.x === b.x && a.y === b.y && a.w === b.w && a.h === b.h;
const fmtBox = b => b ? `${b.x},${b.y} ${b.w}x${b.h}` : 'none';

// What the page itself holds for one selector: count, rect plus scroll, computed values.
const pageFacts = async (sel, props) => {
  const box = await pageBox(sel);
  const values = {};
  for (const p of props) values[p] = await computed(sel, p);
  return { box, values, count: box ? box.count : 0 };
};
const equalsPage = (rule, facts) => {
  if (!rule || rule.matched !== facts.count || !sameBox(rule.box, facts.box)) return false;
  return Object.keys(facts.values).every(p => rule.values[p] === facts.values[p]);
};

// --- the run ------------------------------------------------------------------
let current = 1;
const step = async (n, text, fn) => {
  current = n;
  try {
    const result = await fn();
    check(n, text, result === true || (result && result.ok), result && result.detail ? result.detail : 'condition not met');
  } catch (e) {
    check(n, text, false, String(e && e.message || e));
  }
};

try {
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: WIDTH, height: HEIGHT, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url: pageUrl });
  if ((await waitFor(`document.readyState === 'complete' && window.__renders > 0`, 10000)) < 0) throw new Error('the fixture page did not load');

  const begun = await verb(['begin', '--subject', 'annotate check']);
  if (begun.code !== 0) throw new Error('begin failed: ' + begun.err);
  const loader = await verb(['loader', '--page', pageUrl, '--run']);
  if (loader.code !== 0 || !loader.out.trim()) throw new Error('loader printed nothing: ' + loader.err);
  const loaderLine = loader.out.trim();
  const runId = (() => { const r = readJson('run.json'); return r ? `${r.start_seq}@${r.started_at}` : null; })();
  const loadPage = async () => evaluate(`(${loaderLine})()`);
  const original = { name: null };

  // 1. the page holds /changes while /health stays at zero clients
  await step(1, 'the page holds /changes', async () => {
    const status = await loadPage();
    if (status !== 'LOADED') return { ok: false, detail: 'loader returned ' + status };
    let delivered = 0;
    const held = await until(async () => { delivered = await postSheet('probe-held'); return delivered === 1; }, 6000);
    const clients = await healthClients();
    return { ok: held && clients === 0, detail: `POST /sheet delivered ${delivered}, /health clients ${clients}` };
  });
  if (!asserts[0].ok) throw new Error('the overlay never held its change stream; nothing after this can be trusted');

  original.name = await computed('.name', 'color');
  const watch = startWatch();
  let live = watch;
  let tsA, tsB, tsC;
  let pinA;

  // 2. SEND carries the probe, the pin resolves on receipt
  await step(2, 'SEND carried the probe and the pin resolved on receipt', async () => {
    pinA = await makePin('.name', null, 'make the name red');
    tsA = pinA.ts;
    if (!pinA.selector.includes('.name')) return { ok: false, detail: 'the pin landed on ' + pinA.selector };
    if (!(await sendPins())) return { ok: false, detail: 'SEND never showed RETURNED' };
    const line = await waitLine(watch, `ADDED ${tsA} `, 8000);
    if (!line) return { ok: false, detail: 'the watch printed no ADDED line for ' + tsA + '; saw: ' + watch.lines.join(' | ') };
    const probes = readJson('probes.json') || {};
    const resolutions = readJson('resolutions.json') || {};
    const mapped = Object.values(resolutions.pins || {}).some(by => by && Object.prototype.hasOwnProperty.call(by, String(tsA)));
    const source = (/ source (".*")$/.exec(line) || [])[1] || '';
    return { ok: String(tsA) in probes && source.includes('app.css') && mapped,
      detail: `probes.json has ts: ${String(tsA) in probes}; source ${source}; resolutions.json maps ts: ${mapped}` };
  });

  // 3. two quick SENDs give two changes, a resent SEND gives none
  await step(3, 'two quick SENDs gave two changes and a resent SEND gave none', async () => {
    const pinB = await makePin('.badge', [4, 4], 'badge needs more contrast');
    const pinC = await makePin('.panel', [4, 4], 'panel feels cramped');
    tsB = pinB.ts; tsC = pinC.ts;
    const started = Date.now();
    const sentB = await sendPins();
    const sentC = await sendPins();
    const elapsed = Date.now() - started;
    const gotB = await waitLine(watch, `ADDED ${tsB} `, 8000);
    const gotC = await waitLine(watch, `ADDED ${tsC} `, 8000);
    if (!sentB || !sentC || !gotB || !gotC) return { ok: false, detail: `sent ${sentB}/${sentC}, ADDED ${!!gotB}/${!!gotC}; saw: ${watch.lines.join(' | ')}` };
    await sleep(QUIET_MS);
    const sizeBefore = logSize();
    const linesBefore = watch.lines.length;
    const resent = await sendPins();
    await sleep(QUIET_MS);
    return { ok: resent && elapsed < 1000 && logSize() === sizeBefore && watch.lines.length === linesBefore,
      detail: `two SENDs took ${elapsed}ms; log ${sizeBefore} -> ${logSize()} bytes after the resend; the watch printed ${watch.lines.length - linesBefore} more lines` };
  });

  // 4. a change written while no watch ran arrives on restart through watch --once
  await step(4, 'a change sent while no watch ran arrived when the watch restarted', async () => {
    watch.proc.kill('SIGKILL');
    await until(() => watch.exited !== null, 3000);
    const pinD = await makePin('.card', [330, 4], 'card needs a shadow');
    const tsD = pinD.ts;
    const grew = logSize();
    if (!(await sendPins())) return { ok: false, detail: 'SEND never showed RETURNED' };
    await until(() => logSize() > grew, 3000);
    const once = startWatch(['--once']);
    const exited = await until(() => once.exited !== null, 15000);
    const mine = once.lines.filter(l => l.startsWith(`ADDED ${tsD} `));
    const second = startWatch();
    await sleep(QUIET_MS);
    live = second;
    return { ok: exited && once.exited === 0 && mine.length === 1 && once.lines.length === 1 && second.lines.length === 0,
      detail: `--once exit ${once.exited}, printed ${once.lines.length} lines (${mine.length} for the new pin); the restarted watch printed ${second.lines.length} lines` };
  });

  // 5. apply's report equals the page, and still does after re-renders
  await step(5, "apply's report equals the page", async () => {
    const applied = parseApply((await verb(['apply'], block(tsA, '.name { color: rgb(200, 16, 46); }'))).out);
    const rule = applied.rules.find(r => r.selector === '.name');
    if (!rule) return { ok: false, detail: 'no .name line: ' + applied.lines.join(' | ') };
    const facts = await pageFacts('.name', ['color']);
    const now = await renders();
    const first = equalsPage(rule, facts) && rule.values.color === 'rgb(200, 16, 46)';
    await waitFor(`window.__renders >= ${now + 4}`, 5000);
    const later = await pageFacts('.name', ['color']);
    return { ok: first && equalsPage(rule, later) && applied.shots.length === 0,
      detail: `printed ${rule.raw}; page ${JSON.stringify(facts)}, after re-renders ${JSON.stringify(later)}; SHOT lines: ${applied.shots.join(' | ') || 'none'}` };
  });

  // 6. a covered element is reported covered
  await step(6, 'a covered element was reported covered', async () => {
    const applied = parseApply((await verb(['apply'], block(tsB, '.badge { color: rgb(1, 2, 3); }'))).out);
    const rule = applied.rules.find(r => r.selector === '.badge');
    const cover = await evaluate(`(() => { const e = document.querySelector('.cover'); return e.tagName.toLowerCase() + '.' + Array.from(e.classList).slice(0, 2).join('.'); })()`);
    const shot = applied.shots.some(l => l.startsWith(`SHOT ${tsB} `) && l.includes('covered'));
    return { ok: !!rule && rule.visibility === `covered by ${cover}` && shot,
      detail: `printed ${rule ? rule.raw : applied.lines.join(' | ')}; the cover is ${cover}; SHOT lines: ${applied.shots.join(' | ') || 'none'}` };
  });

  // 7. a container background shows its true height
  await step(7, 'a container background showed its true height', async () => {
    const applied = parseApply((await verb(['apply'], block(tsC, '.panel { background-color: rgb(230, 240, 255); }'))).out);
    const rule = applied.rules.find(r => r.selector === '.panel');
    const facts = await pageBox('.panel');
    const shot = applied.shots.some(l => l.startsWith(`SHOT ${tsC} `) && l.includes('stacking'));
    const ok = !!rule && !!rule.box && !!applied.view && rule.box.h === facts.h && rule.box.h < applied.view.h && shot;
    return { ok, detail: `printed ${rule ? rule.raw : applied.lines.join(' | ')}; page height ${facts.h}, view ${applied.view ? applied.view.h : 'none'}; SHOT lines: ${applied.shots.join(' | ') || 'none'}` };
  });

  // 8. a change below the fold is flagged out of view and the page never scrolls
  await step(8, 'a change below the fold was flagged out of view', async () => {
    const scrolledBefore = await evaluate('window.scrollY');
    const applied = parseApply((await verb(['apply'], block('below', '.below { color: rgb(0, 100, 0); }'))).out);
    const rule = applied.rules.find(r => r.selector === '.below');
    const facts = await pageBox('.below');
    const scrolledAfter = await evaluate('window.scrollY');
    const shot = applied.shots.some(l => l.startsWith('SHOT below ') && l.includes('out of view'));
    return { ok: scrolledBefore === 0 && scrolledAfter === 0 && !!rule && rule.visibility === 'out of view' && sameBox(rule.box, facts) && shot,
      detail: `printed ${rule ? rule.raw : applied.lines.join(' | ')}; page box ${fmtBox(facts)}; scrollY ${scrolledBefore} -> ${scrolledAfter}; SHOT lines: ${applied.shots.join(' | ') || 'none'}` };
  });

  // 9. DELETE then SEND undoes the change; CLEAR PINS undoes nothing
  await step(9, 'DELETE then SEND undid the change; CLEAR undid nothing', async () => {
    const badgeColor = await computed('.badge', 'color');
    await clickEl(`.ca-pin[title="make the name red"]`);
    if ((await waitFor(`!!document.querySelector('.ca-popover')`, 3000)) < 0) return { ok: false, detail: 'the pin popover did not open' };
    await clickText('.ca-popover', 'DELETE');
    if (!(await sendPins())) return { ok: false, detail: 'SEND never showed RETURNED' };
    const undone = await waitLine(live, `UNDONE ${tsA} `, 10000);
    const sheet = readText('session.css');
    const nameBack = (await waitFor(`getComputedStyle(document.querySelector('.name')).color === ${JSON.stringify(original.name)}`, 5000)) >= 0;
    const survives = sheet.includes(`annotate-key ${tsB} `) && (await computed('.badge', 'color')) === badgeColor;
    if (!undone || sheet.includes(`annotate-key ${tsA} `) || !nameBack || !survives) {
      return { ok: false, detail: `UNDONE line ${undone}; key left sheet ${!sheet.includes(`annotate-key ${tsA} `)}; name color back ${nameBack}; other change survives ${survives}` };
    }
    const sheetBefore = readText('session.css');
    const linesBefore = live.lines.length;
    await clickEl('#ca-clear');
    const cleared = await waitFor(`document.getElementById('ca-status').textContent === 'CLEARED'`, 3000);
    await sleep(QUIET_MS);
    const stillShows = (await computed('.badge', 'color')) === badgeColor;
    return { ok: cleared >= 0 && live.lines.length === linesBefore && readText('session.css') === sheetBefore && stillShows,
      detail: `CLEARED ${cleared >= 0}; the watch printed ${live.lines.length - linesBefore} lines; sheet unchanged ${readText('session.css') === sheetBefore}; badge still styled ${stillShows}` };
  });

  // 10 and 11. a reload is restored by the loader line alone; a stale sent pin drops, an unsent pin stays
  const seeded = (n, text, ts, extra) => Object.assign({ n, text, x: 40 + n * 30, y: 300, selector: '#app', nearText: '', ts,
    page: pageUrl, box: { x: 0, y: 0, width: 10, height: 10 }, component: null }, extra);
  const stale = seeded(1, 'stale sent pin', 1700000000001, { sent: true, sentRun: '0@2000-01-01T00:00:00Z' });
  const unsent = seeded(2, 'unsent pin', 1700000000002, { sent: false });
  const mine = seeded(3, 'sent this run', 1700000000003, { sent: true, sentRun: runId });
  await evaluate(`localStorage.setItem(${JSON.stringify(await storeKey())}, ${JSON.stringify(JSON.stringify([stale, unsent, mine]))})`);
  const sheetOnDisk = readText('session.css');
  const colorsBefore = { badge: await computed('.badge', 'color'), panel: await computed('.panel', 'background-color'), below: await computed('.below', 'color') };
  await send('Page.reload');
  await waitFor(`document.readyState === 'complete' && window.__renders > 0`, 10000);
  const reloaded = await loadPage();

  await step(10, 'reload restored every change through the loader line alone', async () => {
    const synced = await waitFor(`(() => { const s = document.getElementById('ca-session-css'); return !!s && s.textContent === ${JSON.stringify(sheetOnDisk)}; })()`, 5000);
    const colorsAfter = { badge: await computed('.badge', 'color'), panel: await computed('.panel', 'background-color'), below: await computed('.below', 'color') };
    return { ok: reloaded === 'LOADED' && sheetOnDisk.length > 0 && synced >= 0 && JSON.stringify(colorsAfter) === JSON.stringify(colorsBefore),
      detail: `loader returned ${reloaded}; page sheet equals file ${synced >= 0}; colors before ${JSON.stringify(colorsBefore)} after ${JSON.stringify(colorsAfter)}` };
  });

  await step(11, 'a stale sent pin dropped and an unsent pin stayed', async () => {
    const titles = await evaluate(`Array.from(document.querySelectorAll('.ca-pin')).map(p => p.title).sort()`);
    const stored = (await storedPins()).map(p => p.text).sort();
    const want = ['sent this run', 'unsent pin'];
    return { ok: JSON.stringify(titles) === JSON.stringify(want) && JSON.stringify(stored) === JSON.stringify(want),
      detail: `pins on the page: ${JSON.stringify(titles)}; pins in storage: ${JSON.stringify(stored)}` };
  });

  // 12. announce never reaches the annotate page
  await step(12, 'announce never reached the annotate page', async () => {
    await evaluate(`window.__annotateMarker = 'still here'`);
    const reply = await verb(['announce']);
    await sleep(QUIET_MS);
    const marker = await evaluate('window.__annotateMarker');
    const clients = await healthClients();
    return { ok: /"delivered": 0\b/.test(reply.out) && marker === 'still here' && clients === 0,
      detail: `announce printed ${reply.out.trim()}; marker ${marker}; /health clients ${clients}` };
  });

  // 13. the canonical clear leaves nothing behind
  await step(13, 'the canonical clear left nothing behind', async () => {
    const clearScript = execFileSync('python3', [channelPy, '--print-clear'], { encoding: 'utf8' });
    await evaluate(clearScript);
    const left = await evaluate(`({ sheet: !!document.getElementById('ca-session-css'), marked: document.querySelectorAll('[data-craft-annotate-injected]').length,
      pins: document.querySelectorAll('.ca-pin').length })`);
    let delivered = -1;
    const quiet = await until(async () => { delivered = await postSheet('probe-after-clear'); return delivered === 0; }, 6000);
    return { ok: !left.sheet && left.marked === 0 && left.pins === 0 && quiet,
      detail: `left on the page: ${JSON.stringify(left)}; POST /sheet delivered ${delivered}` };
  });

  // 14 and 15 start from a clean page: no stored pins, a fresh load, the overlay back through the loader line.
  const freshPage = async () => {
    await evaluate(`localStorage.removeItem(${JSON.stringify(await storeKey())})`);
    await send('Page.reload');
    await waitFor(`document.readyState === 'complete' && window.__renders > 0`, 10000);
    return loadPage();
  };
  const pinState = title => evaluate(`(() => { const n = document.querySelector('.ca-pin[title=' + JSON.stringify(${JSON.stringify(title)}) + ']');
    return n ? { detached: n.classList.contains('ca-detached'), sent: n.classList.contains('ca-sent') } : null; })()`);

  // 14. a pin under a utility-class section with no id above it stays attached
  await step(14, 'a pin under a utility-class section stayed attached after comment mode off and after a reload', async () => {
    if ((await freshPage()) !== 'LOADED') return { ok: false, detail: 'the loader did not load the overlay' };
    const pin = await makePin('.lede', null, 'utility pin');
    const want = 'html > body > section.md\\:flex.w-1\\/2 > p.lede';
    if (pin.selector !== want) return { ok: false, detail: `the pin selector is ${pin.selector}, expected ${want}` };
    await clickEl('#ca-toggle');
    const resolves = () => evaluate(`(() => { try { return document.querySelectorAll(${JSON.stringify(pin.selector)}).length === 1; } catch (e) { return false; } })()`);
    const offResolves = await resolves();
    await send('Page.reload');
    await waitFor(`document.readyState === 'complete' && window.__renders > 0`, 10000);
    const reloaded = await loadPage();
    const back = await waitFor(`!!document.querySelector('.ca-pin[title="utility pin"]')`, 5000);
    await sleep(500);
    const state = await pinState('utility pin');
    return { ok: offResolves && reloaded === 'LOADED' && back >= 0 && !!state && !state.detached && (await resolves()),
      detail: `selector ${pin.selector}; resolves with comment mode off ${offResolves}; after reload loader ${reloaded}, pin ${JSON.stringify(state)}` };
  });

  // 15. a pin saved, and a pin edited, while a SEND is in flight are not marked sent
  await step(15, 'a pin saved and a pin edited while a SEND was in flight were not marked sent', async () => {
    if ((await freshPage()) !== 'LOADED') return { ok: false, detail: 'the loader did not load the overlay' };
    await evaluate(`(() => { const real = window.fetch; window.fetch = (url, opts) => { const out = real.call(window, url, opts);
      return String(url).includes('/pins') ? out.then(res => new Promise(done => setTimeout(() => done(res), 3000))) : out; }; })()`);
    await makePin('.name', null, 'in flight A');
    const listed = await makePin('.badge', [100, 4], 'listed before the send');
    await evaluate(`document.getElementById('ca-status').textContent = ''`);
    await clickEl('#ca-send');
    await makePin('.badge', [4, 4], 'saved in flight B');
    // Edit the already-listed pin through its own popover while the request is still out.
    await clickEl(`.ca-pin[title="listed before the send"]`);
    if ((await waitFor(`!!document.querySelector('.ca-popover')`, 3000)) < 0) return { ok: false, detail: 'the pin popover did not open' };
    await clickText('.ca-popover', 'EDIT');
    if ((await waitFor(`!!document.querySelector('.ca-popover textarea')`, 3000)) < 0) return { ok: false, detail: 'EDIT opened no text box' };
    await evaluate(`document.querySelector('.ca-popover textarea').select()`);
    await send('Input.insertText', { text: 'edited in flight' });
    await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
    await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
    const edited = await waitFor(`!!document.querySelector('.ca-pin[title="edited in flight"]')`, 3000);
    // Both changes must land before the reply, or the step proves nothing.
    const inFlight = await evaluate(`document.getElementById('ca-send').classList.contains('ca-lift') && document.getElementById('ca-status').textContent !== 'RETURNED'`);
    const returned = await waitFor(`document.getElementById('ca-status').textContent === 'RETURNED'`, 8000);
    const stored = await storedPins();
    const a = stored.find(p => p.text === 'in flight A');
    const b = stored.find(p => p.text === 'saved in flight B');
    const e = stored.find(p => p.ts === listed.ts);
    const nodeA = await pinState('in flight A');
    const nodeB = await pinState('saved in flight B');
    const nodeE = await pinState('edited in flight');
    return { ok: returned >= 0 && edited >= 0 && inFlight === true && !!a && a.sent === true && !!nodeA && nodeA.sent && !!b && !b.sent && !!nodeB && !nodeB.sent
        && !!e && e.text === 'edited in flight' && !e.sent && !!nodeE && !nodeE.sent,
      detail: `RETURNED ${returned >= 0}; edit saved ${edited >= 0}; both changes landed while the SEND was in flight ${inFlight}; stored A sent ${a && a.sent}, stored B sent ${b && b.sent}, stored edited pin ${JSON.stringify(e ? { text: e.text, sent: e.sent } : null)}; nodes A ${JSON.stringify(nodeA)} B ${JSON.stringify(nodeB)} edited ${JSON.stringify(nodeE)}` };
  });

  // 16. the listener refuses a page that does not hold the session's token
  await step(16, "the listener refused a request without the token, the flow's in-page check was accepted with the page's token and refused with it changed or removed, and the strip said NOT ARMED for a stale token and for none at all", async () => {
    if ((await freshPage()) !== 'LOADED') return { ok: false, detail: 'the loader did not load the overlay' };
    const probeHealth = query => evaluate(`fetch('http://127.0.0.1:' + window.__craftAnnotatePort + '/health${query}')
      .then(async res => ({ status: res.status, body: await res.text() })).catch(e => ({ error: String(e) }))`);
    const bare = await probeHealth('');
    const stamped = await probeHealth('?token=' + sessionToken());
    const realToken = await evaluate('window.__craftAnnotateToken');
    const check = inPageCheck();
    const runCheck = () => evaluate(`(() => { ${check} })()`).catch(e => 'rejected: ' + e.message);
    const own = await runCheck();
    const changed = String(realToken).replace(/[0-9a-f]/g, c => '0123456789abcdef'[(parseInt(c, 16) + 1) % 16]);
    await evaluate(`window.__craftAnnotateToken = ${JSON.stringify(changed)}`);
    const withChanged = await runCheck();
    await evaluate(`delete window.__craftAnnotateToken`);
    const withRemoved = await runCheck();
    await evaluate(`window.__craftAnnotateToken = ${JSON.stringify(realToken)}`);
    await makePin('.name', null, 'refused pin');
    await evaluate(`window.__craftAnnotateToken = 'stale'; document.getElementById('ca-status').textContent = ''`);
    await clickEl('#ca-send');
    const shown = await waitFor(`document.getElementById('ca-status').textContent !== ''`, 5000);
    const strip = await evaluate(`document.getElementById('ca-status').textContent`);
    // A page baked before tokens existed: the global is gone, not set to some value.
    await evaluate(`delete window.__craftAnnotateToken; document.getElementById('ca-status').textContent = ''`);
    const absent = await evaluate(`!('__craftAnnotateToken' in window)`);
    await clickEl('#ca-send');
    const shownNone = await waitFor(`document.getElementById('ca-status').textContent !== ''`, 5000);
    const stripNone = await evaluate(`document.getElementById('ca-status').textContent`);
    await evaluate(`window.__craftAnnotateToken = ${JSON.stringify(realToken)}`);
    return { ok: bare.status === 403 && /"forbidden"/.test(bare.body || '') && stamped.status === 200 && realToken === sessionToken()
        && own === 200 && withChanged === 403 && withRemoved === 403
        && shown >= 0 && strip === 'NOT ARMED - no craft session listening'
        && absent && shownNone >= 0 && stripNone === 'NOT ARMED - no craft session listening',
      detail: `without the token ${JSON.stringify(bare)}; with it ${stamped.status}; the in-page check answered ${own} with the page's token, ${withChanged} with it changed, ${withRemoved} with it removed; stale-token SEND showed "${strip}"; with no token at all (global gone ${absent}) SEND showed "${stripNone}"` };
  });

  // 17. a page file baked by `bake`, opened over file://, holds its stream and a SEND returns RETURNED
  await step(17, 'a baked page opened over file:// held its stream and its SEND returned', async () => {
    const bakedFile = join(root, 'baked.html');
    writeFileSync(bakedFile, '<!doctype html>\n<html><head><meta charset="utf-8"><title>baked</title></head>\n<body><p id="target" style="margin:40px">baked page</p>\n</body></html>\n');
    const baked = await verb(['bake', '--file', bakedFile]);
    if (baked.code !== 0) return { ok: false, detail: 'bake failed: ' + baked.err };
    await send('Page.navigate', { url: pathToFileURL(bakedFile).href });
    if ((await waitFor(`window.__craftAnnotateInstalled === true && !!document.getElementById('ca-send')`, 10000)) < 0) return { ok: false, detail: 'the baked overlay never installed' };
    const held = await until(async () => (await healthClients()) >= 1, 6000);
    const pin = await makePin('#target', null, 'baked page pin');
    const returned = await sendPins();
    const added = await waitLine(live, `ADDED ${pin.ts} `, 8000);
    return { ok: held && returned && !!added && (await evaluate('location.protocol')) === 'file:',
      detail: `stream held ${held}; SEND RETURNED ${returned}; watch ADDED line ${added ? 'seen' : 'missing'}` };
  });

  // 18. a foreign-origin page takes the paste path, its pins reach Claude tagged EXTERNAL, and the Host check holds
  await step(18, 'a foreign-origin page took the pasted overlay, its pin arrived EXTERNAL, and a foreign Host was refused', async () => {
    const site = new URL(pageUrl);
    const foreignUrl = 'http://external.test:' + site.port + site.pathname;
    await send('Page.navigate', { url: foreignUrl });
    if ((await waitFor(`document.readyState === 'complete' && window.__renders > 0`, 10000)) < 0) return { ok: false, detail: 'the foreign page did not load' };
    const origin = await evaluate('location.origin');
    if (origin !== 'http://external.test:' + site.port) return { ok: false, detail: 'the page origin is ' + origin };
    const loader = await verb(['loader', '--page', foreignUrl, '--run']);
    if (loader.out.split('\n')[0] !== 'EXTERNAL') return { ok: false, detail: 'loader printed ' + JSON.stringify(loader.out) };
    const stamp = await verb(['stamp']);
    if ((await evaluate(`(${stamp.out.trim()})()`)) !== 'STAMPED') return { ok: false, detail: 'the stamp line did not return STAMPED' };
    const overlay = execFileSync('python3', [channelPy, '--print-overlay'], { encoding: 'utf8' });
    await evaluate(`(() => { ${overlay} })()`);
    if ((await waitFor(`window.__craftAnnotateInstalled === true && !!document.getElementById('ca-send')`, 10000)) < 0) return { ok: false, detail: 'the pasted overlay never installed' };
    const pin = await makePin('.name', null, 'foreign page pin');
    const returned = await sendPins();
    const added = await waitLine(live, `EXTERNAL ADDED ${pin.ts} `, 8000);
    const token = await evaluate('window.__craftAnnotateToken');
    const refused = await evaluate(`fetch('http://external.test:' + window.__craftAnnotatePort + '/health?token=' + encodeURIComponent(${JSON.stringify(token)}))
      .then(res => res.status).catch(e => String(e))`);
    return { ok: returned && !!added && refused === 403,
      detail: `SEND RETURNED ${returned}; EXTERNAL ADDED line ${added ? 'seen' : 'missing; saw: ' + live.lines.join(' | ')}; /health by foreign Host answered ${refused}` };
  });
} catch (e) {
  verdictError = `step ${current}: ${String(e && e.message || e)}`;
}
finish();
