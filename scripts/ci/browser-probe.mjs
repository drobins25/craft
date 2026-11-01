// browser-probe.mjs - drive the real dashboard page in headless Chrome, in
// real time, and print one JSON verdict for browser-check.sh to judge.
//
// Usage: node browser-probe.mjs <chrome-binary> <page-url> <profile-dir>
//
// The page runs its own render loop exactly as it does for a user: this probe
// never calls the page's frame callback and never runs under an artificial
// clock. It only reads the page, dispatches the same mouse events a user's
// drag sends, and waits on real conditions (each with a cap). No packages:
// Chrome is driven over its DevTools protocol with node's built-in WebSocket.
//
// The verdict is printed even when something goes wrong ({"error": ...}), so
// browser-check.sh always has a line to judge; this script exits 0 unless its
// own arguments are missing.

import { spawn } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const [chromeBin, pageUrl, profileDir] = process.argv.slice(2);
if (!chromeBin || !pageUrl || !profileDir) {
  console.error('usage: node browser-probe.mjs <chrome-binary> <page-url> <profile-dir>');
  process.exit(2);
}

const WIDTH = 1400;
const HEIGHT = 900;
const HARD_CAP_MS = 60000;
const sleep = ms => new Promise(r => setTimeout(r, ms));
const result = {};
let chrome = null;
let ws = null;

// Chrome runs in its own process group so one signal reaches its helpers
// (zygote, renderers, crashpad) too. Killing only the main process leaves
// them writing into the profile dir while the caller deletes it.
const CHROME_EXIT_WAIT_MS = 5000;
const stopChrome = async () => {
  if (!chrome || !chrome.pid) return;
  const gone = chrome.exitCode !== null || chrome.signalCode !== null
    ? Promise.resolve()
    : new Promise(resolve => chrome.once('exit', resolve));
  try { process.kill(-chrome.pid, 'SIGKILL'); } catch (e) {
    try { chrome.kill('SIGKILL'); } catch (e2) { /* already gone */ }
  }
  await Promise.race([gone, sleep(CHROME_EXIT_WAIT_MS)]);
};

// finish never returns to its caller: it prints the verdict and exits, so
// `await finish()` ends the script even while Chrome is still being reaped.
let finishing = null;
const finish = () => {
  if (!finishing) {
    finishing = (async () => {
      try { if (ws) ws.close(); } catch (e) { /* already closed */ }
      await stopChrome();
      console.log(JSON.stringify(result));
      process.exit(0);
    })();
  }
  return new Promise(() => {});
};
setTimeout(() => { result.error = result.error || 'probe exceeded ' + HARD_CAP_MS + 'ms'; finish(); }, HARD_CAP_MS).unref();

// --- launch Chrome on a free port it chooses itself --------------------------
chrome = spawn(chromeBin, [
  '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
  '--remote-debugging-port=0', '--user-data-dir=' + profileDir,
  '--window-size=' + WIDTH + ',' + HEIGHT, 'about:blank'
], { stdio: 'ignore', detached: true });
chrome.on('error', e => { result.error = 'chrome did not start: ' + e.message; finish(); });

const portFile = join(profileDir, 'DevToolsActivePort');
let port = null;
// 30s at 100 ms: a cold CI runner can take more than 10s to start Chrome.
const PORT_WAIT_POLLS = 300;
for (let i = 0; i < PORT_WAIT_POLLS && !port; i++) {
  if (existsSync(portFile)) port = readFileSync(portFile, 'utf8').split('\n')[0].trim() || null;
  if (!port) await sleep(100);
}
if (!port) { result.error = 'chrome never opened its debugging port'; await finish(); }

let target = null;
for (let i = 0; i < 50 && !target; i++) {
  try {
    const list = await (await fetch('http://127.0.0.1:' + port + '/json')).json();
    target = list.find(t => t.type === 'page') || null;
  } catch (e) { /* not listening yet */ }
  if (!target) await sleep(100);
}
if (!target) { result.error = 'no page target in chrome'; await finish(); }

ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; })
  .catch(async () => { result.error = 'could not attach to the page'; await finish(); });
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
// waitFor <expr> <capMs> - polls a page expression until it is truthy; returns ms waited or -1
const waitFor = async (expr, capMs) => {
  const start = Date.now();
  while (Date.now() - start < capMs) {
    if (await evaluate(expr)) return Date.now() - start;
    await sleep(50);
  }
  return -1;
};

try {
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: WIDTH, height: HEIGHT, deviceScaleFactor: 1, mobile: false });
  // Count real frames and the page's own ticks from the first script onward,
  // without changing what the loop does: one counting rAF chain of our own,
  // and a pass-through wrapper on the instance's tick once it exists.
  await send('Page.addScriptToEvaluateOnNewDocument', { source: `
    window.__probeFrames = 0; window.__probeTicks = 0;
    (function count() { window.__probeFrames++; requestAnimationFrame(count); })();
  ` });
  await send('Page.navigate', { url: pageUrl });

  // 1-2b: the data reached the page and the view consumed it
  if (await waitFor(`!!(window.GraphInstance && window.GraphInstance.sim && window.GraphInstance.sim.nodes && window.GraphInstance.sim.nodes.length)`, 15000) < 0) {
    result.graphNodeCount = await evaluate(`((window.CRAFT_GRAPH || {}).nodes || []).length`);
    result.error = 'GraphInstance.sim.nodes not reachable';
    await finish();
  }
  await evaluate(`(() => {
    const gi = window.GraphInstance, own = gi.tick;
    gi.tick = function (now) { window.__probeTicks++; return own.call(gi, now); };
    // the loop holds the bound tick it booked; wrap that path too
    return true;
  })()`);
  Object.assign(result, await evaluate(`(() => {
    const gi = window.GraphInstance, g = window.CRAFT_GRAPH || {};
    let nonFinite = 0;
    for (const n of gi.sim.nodes) if (!isFinite(n.x) || !isFinite(n.y) || !isFinite(n.homeX) || !isFinite(n.homeY)) nonFinite++;
    return { graphNodeCount: (g.nodes || []).length, simNodeCount: gi.sim.nodes.length, nonFiniteNodes: nonFinite };
  })()`));

  // The page settles on its own: the loop parks once the swirl is at rest
  // and the heat and card-reveal fades are done.
  result.restMs = await waitFor(`window.GraphInstance.rafId === null && window.GraphInstance.sim.isAtRest()`, 15000);

  // 3-4: selecting a node renders its card
  Object.assign(result, await evaluate(`(() => {
    const gi = window.GraphInstance, n = gi.sim.nodes[0];
    gi.goTo(n);
    return { expected: n ? n.label : null, probedHasSummary: !!(n && n.summary) };
  })()`));
  await waitFor(`(() => { const t = document.querySelector('#panel .p-title'); return t && t.textContent.length > 0; })()`, 3000);
  await sleep(400);
  Object.assign(result, await evaluate(`(() => {
    const gi = window.GraphInstance, t = document.querySelector('#panel .p-title'), p = document.querySelector('#panel'), s = document.querySelector('#panel .p-summary');
    return { titleText: t ? t.textContent : null, panelLen: p ? p.textContent.length : 0, summaryChildren: s ? s.childElementCount : -1,
             heatW: gi.heatCanvas ? gi.heatCanvas.width : -1, innerW: window.innerWidth };
  })()`));

  // 5-7: a real drag pins the node where it is dropped, and the loop parks again.
  // The panel the selection opened is closed first, as a user would before dragging.
  await evaluate(`(() => { const gi = window.GraphInstance; gi.selectedNode = null; gi.setPanelVisible(false); return true; })()`);
  await waitFor(`window.GraphInstance.rafId === null`, 5000);
  Object.assign(result, await evaluate(`(() => {
    const gi = window.GraphInstance, canvas = document.getElementById('canvas'), target = gi.sim.nodes[0];
    const w = window.innerWidth, h = window.innerHeight;
    const sx = (target.x - gi.camera.x) * gi.camera.scale + w / 2;
    const sy = (target.y - gi.camera.y) * gi.camera.scale + h / 2;
    const mev = (type, x, y) => new MouseEvent(type, { clientX: x, clientY: y, bubbles: true, cancelable: true });
    canvas.dispatchEvent(mev('mousedown', sx, sy));
    canvas.dispatchEvent(mev('mousemove', sx + 12, sy + 8));
    canvas.dispatchEvent(mev('mousemove', sx + 30, sy + 18));
    window.__probeDragged = gi.dragNode;
    window.dispatchEvent(mev('mouseup', sx + 30, sy + 18));
    return { dragEngaged: !!window.__probeDragged };
  })()`));
  const settleMs = await waitFor(`window.GraphInstance.rafId === null`, 9000);
  result.loopParked = settleMs >= 0;
  result.settleMs = settleMs >= 0 ? settleMs : 9000;

  // 8-10: the cards and their leaders, and how many loops ran
  Object.assign(result, await evaluate(`(() => {
    const gi = window.GraphInstance, d = window.__probeDragged;
    let leaders = 0, finiteLeaders = 0;
    (gi.cardMeta || []).forEach(m => {
      if (!m.leader) return;
      leaders++;
      const L = m.leader;
      if ([L.x1, L.y1, L.tx, L.ty, L.cx, L.cy].every(isFinite)) finiteLeaders++;
    });
    return { pinnedFx: !!(d && d.fx != null), pinnedAtDrop: !!(d && d.fx != null && d.fx === d.x),
             cardCount: (gi.cardMeta || []).length, leaders, finiteLeaders,
             frames: window.__probeFrames, ticks: window.__probeTicks };
  })()`));
} catch (e) {
  result.error = String(e && e.message || e);
}
await finish();
