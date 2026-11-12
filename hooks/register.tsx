import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { Chooser } from '../types'

import { draw, drawChooser, FRAME_MS, FRAMES, moves } from './draw'
import type { ChooserActions } from './draw'
import { compose, findRoot, parseStageLines, readChoices, take, whyNotStart } from './take'
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

// The story chooser the ready row opens: the stories it lists, the page, the
// pick, and why the last start was refused. Session memory only, so a stored
// value an older version left reads as absent.
const CLOSED: Chooser = { mode: '', own: '', choices: [], picked: 0, start: 0, earlier: [], reason: '' }
export const chooser = atom({ plugin: 'craft', key: 'chooser' } as const, CLOSED, { shape: 'chooser-1' })

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
let waiting = 0
const validators = new Set<string>()
let lastFacts: DiskFacts | null = null
// Set by a press on the chooser's start and cleared when the band next redraws,
// the main turn the start began ends, or a new session starts, so a double press
// submits once and a story-implement that ends with no story picked leaves start
// pressable.
let pressLocked = false
// Set while start checks the story and the slot and runs story-implement, cleared
// only when the start handler returns: a redraw or a turn end during the file
// reads must not let a second start through.
let starting = false

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
      { waiting, validating: validators.size > 0 },
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

// The ready row's control: turns the band into the story chooser, listing the
// row's own story first and then the active cycle's ready stories. It runs
// nothing; the list is read here, on the press, never on the band's refresh.
async function openChooser($: EngineInterface): Promise<void> {
  try {
    const snap = await read($, progress)
    if (!snap || snap.stage !== 'ready' || snap.slotHolder !== '') return
    const root = lastFacts?.root || (await findRoot($))
    if (!root) return
    const choices = await readChoices($, root, snap.path)
    if (choices.length === 0) return
    await update($, chooser, (): Chooser => ({ mode: 'list', own: snap.path, choices, picked: 0, start: 0, earlier: [], reason: '' }))
  } catch {
    // A failed read leaves the ready row as it was.
  }
}

// The chooser's start: checks the picked story and the slot against the disk
// once more, closes the chooser, then runs /craft:story-implement on the
// story's project-relative path so the command opens that story and no other.
async function startChosen($: EngineInterface): Promise<void> {
  if (starting || pressLocked) return
  starting = true
  pressLocked = true
  try {
    const held = await read($, chooser)
    const choice = held.mode === 'confirm' ? held.choices[held.picked] : undefined
    const root = lastFacts?.root || (await findRoot($))
    if (!choice || !root || !choice.path.startsWith(`${root}/`)) {
      pressLocked = false
      return
    }
    const reason = await whyNotStart($, root, held.own, choice)
    if (reason) {
      // Nothing runs: the list is read again from page one so it shows what is startable now.
      const choices = await readChoices($, root, held.own)
      await update($, chooser, (): Chooser => ({ mode: 'list', own: held.own, choices, picked: 0, start: 0, earlier: [], reason }))
      pressLocked = false
      return
    }
    await update($, chooser, () => CLOSED)
    try {
      await $.command.run({ command: 'craft:story-implement', args: choice.path.slice(root.length + 1) })
    } catch {
      // A rejected run reopens the list, read again, with line 1 saying so, and start is pressable again.
      pressLocked = false
      const choices = await readChoices($, root, held.own)
      const reason = `${choice.label} didn't start, try again`
      await update($, chooser, (): Chooser => ({ mode: 'list', own: held.own, choices, picked: 0, start: 0, earlier: [], reason }))
    }
  } catch {
    // A failed read or write leaves start pressable again.
    pressLocked = false
  } finally {
    starting = false
  }
}

const chooserActions = ($: EngineInterface): ChooserActions => ({
  pick: index => void update($, chooser, (v): Chooser => ({ ...v, mode: 'confirm', picked: index, reason: '' })),
  page: start => void update($, chooser, (v): Chooser => ({ ...v, start, earlier: [...v.earlier, v.start] })),
  earlier: () =>
    void update($, chooser, (v): Chooser => ({ ...v, start: v.earlier[v.earlier.length - 1] ?? 0, earlier: v.earlier.slice(0, -1) })),
  cancel: () => void update($, chooser, () => CLOSED),
  back: () => void update($, chooser, (v): Chooser => ({ ...v, mode: 'list' })),
  start: () => void startChosen($),
})

// Remembers the stories the planning-stage script names, so the band knows which
// are this session's. The set is written only when it changes.
async function rememberOwn($: EngineInterface, stdout: string): Promise<void> {
  const { set, cleared } = parseStageLines(stdout)
  const root = lastFacts?.root || (await findRoot($))
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
    waiting = 0
    validators.clear()
    lastFacts = null
    starting = false
    pressLocked = false
    stop(refreshTicker)
    stop(frameTicker)
    live = e.surface !== null
    if (live) {
      await Promise.all([startRefresh($), startFrames($)])
      await requestRefresh($)
    }
    await update($, chooser, () => CLOSED)

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
      waiting = 0
      await publish($)
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (!live) return next(e)
    await revive($)
    if (e.agentId === undefined) {
      pressLocked = false
      return next(e)
    }
    validators.delete(e.agentId)
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
    if (e.props.hasSurvey || (await read($, progressHidden))) return next(e)
    // An open chooser draws until start or cancel, even when the band's own view has moved on.
    const held = await read($, chooser)
    if (held.mode !== '') return drawChooser($.ui.resolve(e), held, e.props.bodyColumns, chooserActions($))
    const snap = await read($, progress)
    if (!snap) return next(e)
    return draw($.ui.resolve(e), snap, await read($, progressFrame), () => {
      void openChooser($)
    })
  })
}
