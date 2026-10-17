// chrome-start-diag.mjs - THROWAWAY diagnostics for the CI Chrome start flake.
// Never merged. Starts headless Chrome three times with the probes' flags plus
// verbose logging, each on a fresh profile, and reports how long the debugging
// port took, whether the process stayed alive, how it exited, and its stderr.
import { spawn, execFileSync } from 'node:child_process';
import { existsSync, readFileSync, mkdtempSync, openSync, closeSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir, cpus, loadavg, freemem, totalmem } from 'node:os';

const chromeBin = process.argv[2];
if (!chromeBin) { console.log('usage: node chrome-start-diag.mjs <chrome-binary>'); process.exit(0); }
const sleep = ms => new Promise(r => setTimeout(r, ms));
const sh = (cmd, args) => { try { return execFileSync(cmd, args, { encoding: 'utf8', timeout: 15000 }).trim(); } catch (e) { return 'ERR ' + e.message.split('\n')[0]; } };

console.log('=== chrome-start-diag ===');
console.log('chrome --version:', sh(chromeBin, ['--version']));
console.log('cpus:', cpus().length, cpus()[0] && cpus()[0].model);
console.log('loadavg:', loadavg().map(n => n.toFixed(2)).join(' '));
console.log('mem free/total MB:', Math.round(freemem() / 1048576), '/', Math.round(totalmem() / 1048576));
console.log('df tmp:', sh('df', ['-h', tmpdir()]).split('\n').pop());
console.log('dbus session:', process.env.DBUS_SESSION_BUS_ADDRESS || '(unset)');

for (let run = 1; run <= 3; run++) {
  const dir = mkdtempSync(join(tmpdir(), 'chrome-diag-'));
  const profile = join(dir, 'profile');
  const logPath = join(dir, 'stderr.log');
  const fd = openSync(logPath, 'w');
  const t0 = Date.now();
  let exitInfo = null;
  const chrome = spawn(chromeBin, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    '--remote-debugging-port=0', '--user-data-dir=' + profile,
    '--enable-logging=stderr', '--v=1', '--window-size=1400,900', 'about:blank'
  ], { stdio: ['ignore', fd, fd], detached: true });
  chrome.on('exit', (code, signal) => { exitInfo = { code, signal, atMs: Date.now() - t0 }; });
  chrome.on('error', e => { exitInfo = { error: e.message, atMs: Date.now() - t0 }; });
  const portFile = join(profile, 'DevToolsActivePort');
  let portMs = null;
  const aliveTrace = [];
  let lastSecond = -1;
  while (Date.now() - t0 < 60000) {
    if (existsSync(portFile) && readFileSync(portFile, 'utf8').split('\n')[0].trim()) { portMs = Date.now() - t0; break; }
    const s = Math.floor((Date.now() - t0) / 1000);
    if (s !== lastSecond) { lastSecond = s; aliveTrace.push(s + 's:' + (exitInfo ? 'dead' : 'alive')); }
    if (exitInfo) break;
    await sleep(50);
  }
  console.log(`--- run ${run}: port ${portMs === null ? 'NEVER' : 'after ' + portMs + ' ms'}${portMs !== null && portMs > 10000 ? ' (would FAIL the 10s wait)' : ''}; exit ${exitInfo ? JSON.stringify(exitInfo) : 'still running'}`);
  if (portMs === null || portMs > 3000) console.log('alive trace:', aliveTrace.join(' '));
  try { process.kill(-chrome.pid, 'SIGKILL'); } catch (e) { /* gone */ }
  await sleep(300);
  closeSync(fd);
  const lines = readFileSync(logPath, 'utf8').split('\n');
  const showAll = portMs === null || portMs > 3000 || run === 1;
  const shown = showAll ? lines.slice(0, 200) : lines.slice(-15);
  console.log(`stderr (${lines.length} lines, showing ${showAll ? 'first 200' : 'last 15'}):`);
  for (const l of shown) console.log('  | ' + l);
  rmSync(dir, { recursive: true, force: true });
}
console.log('=== end chrome-start-diag ===');
process.exit(0);
