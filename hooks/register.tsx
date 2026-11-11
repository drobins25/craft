import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import { draw, FRAME_MS, FRAMES, moves } from './draw'
import { compose, findRoot, parseStageLines, readSlot, take } from './take'
import type { DiskFacts, ScanEntry } from './take'

// The band's session-only values: whether the user hid it, the snapshot it
// draws, the planning stories this session owns, and the sheen's frame. Nothing
// here is written to disk. The shape tag changes whenever the snapshot does, so
// a value an older version left reads as absent and the band redraws from disk.
export const progressHidden = atom({ plugin: 'craft', key: 'progressHidden' } as const, false)
export const progress = atom({ plugin: 'craft', key: 'progress' } as const, null, {
  shape: 'progress-2',
})
export const ownPlanning = atom({ plugin: 'craft', key: 'ownPlanning' } as const, [] as string[], {
  shape: 'progress-2',
})
export const progressFrame = atom({ plugin: 'craft', key: 'progressFrame' } as const, 0)

const REFRESH_MS = 3000
// A timer that has not ticked in this many periods is taken for dead and restarted.
const STALE_PERIODS = 3
const VALIDATORS = /(^|:)(chunk-validator|claims-auditor)$/

// A repeating timer and when it last ticked. `generation` lets a restart that
// began first lose to one that began later.
type Ticker = { timer: Timer | null; lastTickAt: number; generation: number }

const cache = new Map<string, ScanEntry>()
const refreshTicker: Ticker = { timer: null, lastTickAt: 0, generation: 0 }
const frameTicker: Ticker = { timer: null, lastTickAt: 0, generation: 0 }

// Whether this session has a surface to draw on; a -p run or the SDK has none,
// so every hook below only passes through.
let live = false
let working = false
let waiting = 0
const validators = new Set<string>()
let lastFacts: DiskFacts | null = null
// Set by a press on the ready row's control and cleared when the band next
// redraws, so a double press submits once.
let pressLocked = false

let inFlight: Promise<void> | null = null
let readsBegan = false
let again = false
let publishing: Promise<void> = Promise.resolve()

// Stores the composed snapshot only when it changed, since every write redraws
// the band. Publishes queue, so the last one always carries the latest flags.
async function publishNow($: EngineInterface): Promise<void> {
  try {
    const held = await read($, progress)
    const next = compose(
      lastFacts,
      { working, waiting, validating: validators.size > 0 },
      held,
      await $.clock.now(),
    )
    if (JSON.stringify(next) !== JSON.stringify(held)) {
      await update($, progress, () => next)
      pressLocked = false
    }
  } catch {
    // A failed write leaves the band as it was; the next event or tick publishes again.
  }
}

function publish($: EngineInterface): Promise<void> {
  publishing = publishing.then(() => publishNow($))
  return publishing
}

// One read pass: the only disk access besides the planning-stage wrap. Never throws.
async function pass($: EngineInterface): Promise<void> {
  try {
    const held = await read($, progress)
    const own = await read($, ownPlanning)
    readsBegan = true
    lastFacts = await take($, { held, own, cache })
    await publish($)
  } catch {
    // A failed read leaves the band as it was; the next tick tries again.
  }
}

// Requests that arrive before a pass has read anything join it; one that
// arrives later asks for exactly one more pass. Two passes never run at once.
function requestRefresh($: EngineInterface): Promise<void> {
  if (inFlight) {
    if (readsBegan) again = true
    return inFlight
  }
  const run = (async () => {
    do {
      again = false
      readsBegan = false
      await pass($)
    } while (again)
  })()
  inFlight = run.finally(() => {
    inFlight = null
  })
  return inFlight
}

async function start($: EngineInterface, ticker: Ticker, ms: number, tick: () => Promise<void>): Promise<void> {
  ticker.timer?.cancel()
  ticker.timer = null
  const generation = (ticker.generation += 1)
  const at = await $.clock.now()
  if (generation !== ticker.generation) return
  ticker.lastTickAt = at
  ticker.timer = $.clock.every(ms, () => {
    void (async () => {
      try {
        ticker.lastTickAt = await $.clock.now()
        await tick()
      } catch {
        // A failed tick is skipped; the next period tries again.
      }
    })()
  })
}

function stop(ticker: Ticker): void {
  ticker.generation += 1
  ticker.timer?.cancel()
  ticker.timer = null
}

// A validator the engine no longer lists as running ended without its turn
// reaching this module, so it must not hold the band on `validating`.
async function dropEndedValidators($: EngineInterface): Promise<void> {
  if (validators.size === 0) return
  try {
    const running = new Set(
      (await $.agent.list()).filter(a => a.status === 'pending' || a.status === 'running').map(a => a.id),
    )
    const before = validators.size
    for (const id of [...validators]) if (!running.has(id)) validators.delete(id)
    if (validators.size !== before) await publish($)
  } catch {
    // No agent list here: a validator's own turn end still clears it.
  }
}

// The ready row's control: starts craft's own story picker. It names no story
// and asks nothing; the slot is read again so a row left up while a story runs
// never submits.
async function press($: EngineInterface): Promise<void> {
  if (pressLocked) return
  pressLocked = true
  try {
    if (await readSlot($)) {
      pressLocked = false
      return
    }
    await $.command.run({ command: 'craft:story-implement' })
  } catch {
    // A rejected run leaves the control pressable again.
    pressLocked = false
  }
}

// Remembers the stories the planning-stage script names, so the band knows which
// are this session's. The set is written only when it changes.
async function rememberOwn($: EngineInterface, stdout: string): Promise<void> {
  const { set, cleared } = parseStageLines(stdout)
  const root = await findRoot($)
  if (!root) return
  const inProject = (path: string) => path.startsWith(`${root}/.craft/`)
  const was = await read($, ownPlanning)
  const now = [...was.filter(path => !cleared.includes(path)), ...set.filter(path => inProject(path) && !was.includes(path))]
  if (now.length === was.length && now.every((path, i) => path === was[i])) return
  await update($, ownPlanning, () => now)
  await requestRefresh($)
}

const refreshTick = ($: EngineInterface) => async () => {
  await dropEndedValidators($)
  await requestRefresh($)
}

const frameTick = ($: EngineInterface) => async () => {
  const snap = await read($, progress)
  if (!snap || !moves(snap) || (await read($, progressHidden))) return
  await update($, progressFrame, n => (n + 1) % FRAMES)
}

const startRefresh = ($: EngineInterface) => start($, refreshTicker, REFRESH_MS, refreshTick($))
const startFrames = ($: EngineInterface) => start($, frameTicker, FRAME_MS, frameTick($))

// Called first by every event hook: a timer the engine refused a period of has
// ended for good, and a session that goes on has to bring it back.
async function revive($: EngineInterface): Promise<void> {
  const now = await $.clock.now()
  if (refreshTicker.timer && now - refreshTicker.lastTickAt > STALE_PERIODS * REFRESH_MS) await startRefresh($)
  if (frameTicker.timer && now - frameTicker.lastTickAt > STALE_PERIODS * FRAME_MS) await startFrames($)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'craft-progress',
      description: "Show or hide craft's progress band above the prompt",
    })
    working = false
    waiting = 0
    validators.clear()
    lastFacts = null
    stop(refreshTicker)
    stop(frameTicker)
    live = e.surface !== null
    if (live) {
      await Promise.all([startRefresh($), startFrames($)])
      await requestRefresh($)
    }

    return next(e)
  })

  on('command.run', { command: 'craft-progress' }, async $ => {
    const hidden = await update($, progressHidden, was => !was)

    return { text: hidden ? 'Craft progress hidden.' : 'Craft progress shown.' }
  })

  on('turn.start', async ($, e, next) => {
    if (!live) return next(e)
    await revive($)
    if (e.agentId === undefined) {
      // A new main-loop turn means no card from an earlier one is still open.
      working = true
      waiting = 0
      await publish($)
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (!live) return next(e)
    await revive($)
    if (e.agentId === undefined) working = false
    else validators.delete(e.agentId)
    await publish($)
    return next(e)
  })

  on('tool.call', { tool: 'AskUserQuestion' }, async ($, e, next) => {
    if (!live) return next(e)
    await revive($)
    waiting += 1
    await publish($)
    try {
      return await next(e)
    } finally {
      waiting = Math.max(0, waiting - 1)
      await publish($)
    }
  }).catch(($, e, next) => next(e))

  on('agent.spawn', async ($, e, next) => {
    if (!live) return next(e)
    await revive($)
    const result = await next(e)
    const id = result.agentId ?? e.resume?.agentId
    if (id && VALIDATORS.test(e.subagentType)) {
      validators.add(id)
      await publish($)
    }
    return result
  }).catch(($, e, next) => next(e))

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    if (!e.command.includes('planning-stage.sh')) return next(e)
    if (!live) return next(e)
    const answer = await next(e)
    const stdout = (answer.result as { stdout?: unknown } | undefined)?.stdout
    if (typeof stdout === 'string') await rememberOwn($, stdout)
    return answer
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, progress)
    if (e.props.hasSurvey || !snap || (await read($, progressHidden))) return next(e)
    return draw($.ui.resolve(e), snap, await read($, progressFrame), () => {
      void press($)
    })
  })
}
