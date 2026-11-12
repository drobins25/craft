import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'
import { CLEARED_LINE, SET_LINE } from './fixtures/planning-stage-stdout'
type Files = Map<string, string>
declare function setTimeout(run: () => void, ms: number): unknown

const ROOT = '/work/p'
const CYCLE = `${ROOT}/.craft/cycles/c`
const BUILD_BASE = 'green_FOR_SUBAGENTS_ONLY'
const BUILD_SWEEP = 'success'
const WORD = ['B', 'u', 'i', 'l', 'd', 'i', 'n', 'g']
// Line one is the star, the view word's eight letters, a space, the label, a
// separator and the state, so the title and the first ball sit at fixed places.
const STATE = 12
const TITLE = 13
const BALLS = 14

// The engine answers every call the module makes on `$`; each hook here stands
// for that answer. Registered before the first `$` call.
function stubEngine(on: On) {
  const registered: { name: string; description: string }[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => {
    registered.push({ name: e.name, description: e.description })
    return { value: { command: e.name } }
  })
  on('turn.start', (_, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_, e) => ({ text: e.answer }))
  return registered
}

// The ids the next spawned subagents get, and the question cards held open:
// each held card is a call that stays pending until the test releases it.
function stubAgents(on: On) {
  const ids: string[] = []
  const cards: (() => void)[] = []
  on('agent.spawn', () => ({ model: 'm', agentId: ids.shift() ?? 'a1' }))
  on('tool.call', { tool: 'AskUserQuestion' }, () => {
    return new Promise(resolve => {
      cards.push(() => resolve({ result: { questions: [], answers: {} } }))
    })
  })
  return { ids, cards }
}

// A shared latch for the cycle's global state file, so a test can hold a read
// pass open and see whether a second one starts beside it.
type Latch = { gate: Promise<void> | null; active: number; most: number }

// A file system made of absolute paths. Every folder implied by a path exists.
// Returns the calls made, so a test can show what was (not) read.
function stubFiles(on: On, files: Files, sessionRoot: string, latch?: Latch) {
  const calls = { read: [] as string[], exists: [] as string[], list: [] as string[] }
  const isDir = (path: string) => [...files.keys()].some(key => key.startsWith(`${path}/`))
  on('fs.read', async (_, e) => {
    calls.read.push(e.path)
    if (latch?.gate && e.path.endsWith('/.global-state')) {
      latch.active += 1
      latch.most = Math.max(latch.most, latch.active)
      await latch.gate
      latch.active -= 1
    }
    const text = files.get(e.path)
    return text === undefined ? { deny: `no such file ${e.path}` } : { value: text }
  })
  on('fs.exists', (_, e) => {
    calls.exists.push(e.path)
    return { value: files.has(e.path) || isDir(e.path) }
  })
  on('fs.list', (_, e) => {
    calls.list.push(e.path)
    const names = new Map<string, 'file' | 'dir'>()
    for (const key of files.keys()) {
      if (!key.startsWith(`${e.path}/`)) continue
      const rest = key.slice(e.path.length + 1)
      const name = rest.split('/')[0] ?? ''
      names.set(name, rest.includes('/') ? 'dir' : 'file')
    }
    // The stamp follows the content, so a changed file reads as changed.
    const entries = [...names].map(([name, kind]) => {
      const text = kind === 'file' ? (files.get(`${e.path}/${name}`) ?? '') : ''
      const mtimeMs = [...text].reduce((sum, ch) => (sum * 31 + ch.charCodeAt(0)) % 1_000_000_007, 7)
      return { name, kind, size: text.length, mtimeMs, isLink: false }
    })
    return { value: entries }
  })
  on('session.root', () => ({ value: sessionRoot }))
  return calls
}

type StoryOptions = {
  status?: string
  number?: string
  title?: string
  total?: number
  complete?: number
  headings?: number
  stage?: string
}

function storyFile(o: StoryOptions = {}): string {
  const headings = Array.from({ length: o.headings ?? 3 }, (_, i) => `### Chunk ${i + 1}: part ${i + 1}\n`)
  return [
    '---',
    'name: s',
    `title: "${o.title ?? 'First title'}"`,
    'type: technical',
    `status: ${o.status ?? 'active'}`,
    ...(o.stage ? [`planning_stage: ${o.stage}`] : []),
    `story_number: ${o.number ?? '5'}`,
    `chunks_total: ${o.total ?? 3}`,
    `chunks_complete: ${o.complete ?? 0}`,
    '---',
    '',
    '## Chunks',
    ...headings,
  ].join('\n')
}

function seedProject(files: Files, root: string, cycleState: { story: string; chunk?: number }) {
  files.set(`${root}/.craft/.global-state`, 'LAST_ACTIVITY="x"\nACTIVE_CYCLE="c"\nCURRENT_STORY=""\n')
  setCycleState(files, root, cycleState)
}

function setCycleState(files: Files, root: string, s: { story: string; chunk?: number }) {
  files.set(
    `${root}/.craft/cycles/c/.state`,
    `CYCLE_NAME="c"\nCURRENT_STORY="${s.story}"\nCURRENT_CHUNK="${s.chunk ?? (s.story ? 1 : 0)}"\nTOTAL_CHUNKS="${s.story ? 3 : 0}"\n`,
  )
}

type World = {
  clock: ReturnType<typeof mock.clock>
  calls: ReturnType<typeof stubFiles>
  // The plugin state keys written, in order.
  writes: string[]
  ids: string[]
  cards: (() => void)[]
  latch: Latch
  // The subagent ids the engine lists as running.
  running: string[]
  // What the planning-stage script's Bash call answers, and the commands it ran.
  bash: { stdout: string; commands: string[] }
}

// Stubs the engine, the files, the clock and the environment, then starts a terminal session.
async function open(
  $: Engine,
  on: On,
  files: Files,
  options: {
    sessionRoot?: string
    env?: Record<string, string>
    surface?: 'terminal' | null
    beforeStart?: () => void
  } = {},
): Promise<World> {
  stubEngine(on)
  const latch: Latch = { gate: null, active: 0, most: 0 }
  const calls = stubFiles(on, files, options.sessionRoot ?? ROOT, latch)
  const { ids, cards } = stubAgents(on)
  const clock = mock.clock(on)
  mock.env(on, options.env ?? {})
  const writes: string[] = []
  on('state.set', (_, e, next) => {
    writes.push(e.key)
    return next(e)
  })
  const running: string[] = []
  on('agent.list', () => ({
    value: running.map(id => ({ id, description: '', type: 'x', status: 'running' as const })),
  }))
  // Beneath the plugin, standing for the engine's own drawing of the band's place.
  on('ui.render', ($e, e) => {
    const { Text } = $e.ui.resolve(e)
    return h(Text, null, 'engine') as RenderElement
  })
  const bash = { stdout: '', commands: [] as string[] }
  on('tool.call', { tool: 'Bash' }, (_, e) => {
    bash.commands.push(e.command)
    return { result: { stdout: bash.stdout, stderr: '', interrupted: false } }
  })
  options.beforeStart?.()
  const surface = options.surface === undefined ? 'terminal' : options.surface
  await $.session.start({ cwd: options.sessionRoot ?? ROOT, surface, isInteractive: surface !== null })
  return { clock, calls, writes, ids, cards, latch, running, bash }
}

type Drawn = { text: string; color: unknown; bold: unknown }[]

const BAND_PROPS = {
  isWorking: false,
  isCollapsed: false,
  maxRows: 10,
  bodyColumns: 80,
  scroll: { offset: 0, bodyRows: 8 },
  view: {},
}

async function draw($: Engine, hasSurvey = false): Promise<Drawn> {
  const ui = await $.ui.mount({
    plugin: 'craft',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey, ...BAND_PROPS },
  })
  const found = await ui.findAll({ type: 'Text' })
  await ui.unmount()
  return found.map(el => ({ text: el.text, color: el.props.color, bold: el.props.bold }))
}

const texts = (drawn: Drawn) => drawn.map(d => d.text)

// The engine's command.run takes the whole event, origin and presentation
// included; a test stands in for the user typing the command at the prompt.
const runCommand = ($: Engine, command: string) =>
  $.command.run({ command, args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } })
const ENGINE = ['engine']

let turnCounter = 0
const startTurn = ($: Engine, agentId?: string) =>
  $.turn.start({ text: 'go', turnId: `t${(turnCounter += 1)}`, ...(agentId ? { agentId } : {}) })
const endTurn = ($: Engine, agentId?: string) =>
  $.turn.complete({
    answer: 'done',
    durationMs: 1,
    isAborted: false,
    reason: 'answer',
    turnId: `t${turnCounter}`,
    ...(agentId ? { agentId } : {}),
  })
const spawn = ($: Engine, subagentType: string) =>
  $.agent.spawn({
    tool_use_id: 'u1',
    prompt: 'go',
    description: 'go',
    subagentType,
    provider: { plugin: 'craft', tier: 'plugin' },
  } as unknown as Parameters<Engine['agent']['spawn']>[0])

// A question card the test holds open: closing it resolves the pending call.
function openCard($: Engine, cards: (() => void)[]) {
  const pending = $.tool.call({ tool: 'AskUserQuestion', questions: [], answers: {} } as Parameters<Engine['tool']['call']>[0])
  return {
    async close() {
      cards.shift()?.()
      await pending
    },
  }
}

function buildingWorld(files: Files, o: { story?: StoryOptions; chunk?: number } = {}) {
  seedProject(files, ROOT, { story: 's', ...(o.chunk ? { chunk: o.chunk } : {}) })
  files.set(`${CYCLE}/stories/s.md`, storyFile(o.story))
}

const count = (writes: string[], key: string) => writes.filter(k => k === key).length

test("a reload's progress-1 value is ignored and the band redraws from disk", async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const stale = {
    path: `${CYCLE}/stories/gone.md`,
    label: 'Story 1',
    title: 'Stale title',
    storyStatus: 'active',
    chunks: [{ n: 1, state: 'building' }],
    error: '',
  }
  let answered = false
  await open($, on, files, {
    beforeStart: () => {
      // The value the old code left, kept under its own shape tag. Only the
      // first read gets it, standing for the store as the reload found it.
      on('state.get', { plugin: 'craft', key: 'progress' }, (_, e, next) => {
        if (answered) return next(e)
        answered = true
        return { value: { value: { shape: 'progress-1', value: stale }, version: 1 } }
      })
    },
  })

  const drawn = texts(await draw($))

  expect(answered).toBe(true)
  expect(drawn.slice(0, 2)).toEqual(['✶ ', 'B'])
  expect(drawn[TITLE]).toBe(' · First title')
  expect(drawn.join('')).not.toContain('Stale')
})

// A held complete row, as a session left it, handed back by the first read of
// the band's snapshot under the given shape tag. A free story slot and a complete
// story on disk mean the row is drawn only if the stored value is accepted.
async function reloadWithHeldRow($: Engine, on: On, shape: string) {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: '' })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
  let answered = false
  await open($, on, files, {
    beforeStart: () => {
      on('state.get', { plugin: 'craft', key: 'progress' }, (_, e, next) => {
        if (answered) return next(e)
        answered = true
        const held = {
          view: 'building',
          path: `${CYCLE}/stories/s.md`,
          label: 'Story 5',
          title: 'First title',
          storyStatus: 'complete',
          chunks: [{ n: 1, state: 'done' }],
          error: '',
        }
        return { value: { value: { shape, value: held }, version: 1 } }
      })
    },
  })
  expect(answered).toBe(true)
  return texts(await draw($))
}

test('a stored value under the current shape is read, so the held row draws', async ($, on) => {
  const drawn = await reloadWithHeldRow($, on, 'progress-2')

  expect(drawn[STATE]).toBe('complete')
})

test("a reload's progress-1 held row is ignored and nothing draws", async ($, on) => {
  expect(await reloadWithHeldRow($, on, 'progress-1')).toEqual(ENGINE)
})

test('kit smoke: the kit loads the module and runs only this file', async ($, on) => {
  stubEngine(on)
  const started = await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  expect(started.cwd).toBe('/work')
})

test('session.start registers craft-progress with a one-line description', async ($, on) => {
  const registered = stubEngine(on)

  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })

  expect(registered).toHaveLength(1)
  expect(registered[0]?.name).toBe('craft-progress')
  const description = registered[0]?.description ?? ''
  expect(description).toBe("Show or hide craft's progress band above the prompt")
  expect(description).not.toContain('\n')
})

test('/craft-progress hides, then shows', async ($, on) => {
  stubEngine(on)
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })

  const first = await runCommand($, 'craft-progress')
  const second = await runCommand($, 'craft-progress')

  expect(first.text).toBe('Craft progress hidden.')
  expect(second.text).toBe('Craft progress shown.')
})

// The hidden flag lives in session state with no store behind it (the wiring test
// pins the absence of $.store), so a fresh session can only start shown.
test('a fresh session starts with the band shown', async ($, on) => {
  stubEngine(on)
  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })

  const first = await runCommand($, 'craft-progress')

  expect(first.text).toBe('Craft progress hidden.')
})

test('no craft folder: nothing drawn, no error', async ($, on) => {
  await open($, on, new Map())

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('active cycle, no current story, fresh session: nothing drawn', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: '' })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
  await open($, on, files)

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('story start: Building, building, star and green word, first ring', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn)).toEqual([
    '✶ ',
    ...WORD,
    ' ',
    'Story 5',
    ' · ',
    'building',
    ' · First title',
    '○',
    '○',
    '○',
    ' chunk 1 of 3',
  ])
  // A building story sweeps with no turn running: frame 0 puts the head on the first letter.
  expect(drawn[0]?.color).toBe(BUILD_BASE)
  expect(drawn[1]?.color).toBe(BUILD_SWEEP)
  expect(drawn.slice(2, 9).map(d => d.color)).toEqual(Array(7).fill(BUILD_BASE))
  expect(drawn[STATE]?.color).toBe(BUILD_BASE)
  expect(drawn[TITLE]?.color).toBe('subtle')
  expect(drawn.slice(BALLS, BALLS + 3).map(d => d.color)).toEqual(['success', 'inactive', 'inactive'])
  expect(drawn.some(d => d.color === 'warning')).toBe(false)
})

test('the ball row is indented two columns', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  await open($, on, files)

  const ui = await $.ui.mount({
    plugin: 'craft',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, ...BAND_PROPS },
  })
  const boxes = await ui.findAll({ type: 'Box' })
  await ui.unmount()

  const indented = boxes.filter(b => b.props.paddingLeft === 2)
  expect(indented).toHaveLength(1)
  const fixed = boxes.filter(b => b.props.gap === 1 && b.props.flexShrink === 0)
  expect(fixed).toHaveLength(1)
  expect(fixed[0]?.text).toBe('○○○ chunk 1 of 3')
  expect(indented[0]?.text).toBe('○○○ chunk 1 of 3')
})

test('the building view\'s line two is all fixed', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  await open($, on, files)

  const ui = await mountBand($)
  const boxes = await ui.findAll({ type: 'Box' })
  await ui.unmount()

  const line = boxes.find(b => b.props.paddingLeft === 2)
  expect(line?.children).toHaveLength(1)
})

test('a long title can give way, but the label and status never shrink', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, {
    story: { title: 'A very long story title that runs well past the width of the terminal row' },
  })
  await open($, on, files)

  const ui = await $.ui.mount({
    plugin: 'craft',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, ...BAND_PROPS },
  })
  const boxes = await ui.findAll({ type: 'Box' })
  const title = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  const fixed = boxes.filter(b => b.props.flexShrink === 0 && b.text.startsWith('✶'))
  expect(fixed).toHaveLength(1)
  expect(fixed[0]?.text).toBe('✶ Building Story 5 · building')
  expect(fixed[0]?.children.every(c => typeof c !== 'string' && (c as { type: string }).type === 'Text')).toBe(true)
  expect(fixed[0]?.children).toHaveLength(13)
  expect(fixed[0]?.text).not.toContain('A very long')
  const titleText = title.find(t => t.text.includes('A very long'))
  expect(titleText?.props.wrap).toBe('truncate-end')
})

test('chunk passes: ball 1 filled, ring 2 green, chunk 2 of 3', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const { clock } = await open($, on, files)

  setCycleState(files, ROOT, { story: 's', chunk: 2 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ complete: 1 }))
  await clock.advance(3000)
  const drawn = await draw($)

  expect(texts(drawn).slice(BALLS)).toEqual(['●', '○', '○', ' chunk 2 of 3'])
  expect(drawn.slice(BALLS, BALLS + 3).map(d => d.color)).toEqual(['success', 'success', 'inactive'])
})

test('complete is success green and holds', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'complete', complete: 3 }, chunk: 4 })
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn).slice(STATE)).toEqual(['complete', ' · First title', '●', '●', '●', ' all 3 chunks done'])
  expect(drawn[STATE]?.color).toBe('success')
  expect(drawn.slice(0, 9).map(d => d.color)).toEqual(Array(9).fill(BUILD_BASE))
  expect(drawn.slice(BALLS, BALLS + 3).map(d => d.color)).toEqual(['success', 'success', 'success'])
})

test('complete row holds after the current story clears', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'complete', complete: 3 }, chunk: 4 })
  const { clock } = await open($, on, files)
  const before = texts(await draw($))

  setCycleState(files, ROOT, { story: '' })
  await clock.advance(3000)

  expect(texts(await draw($))).toEqual(before)
  expect(before[STATE]).toBe('complete')
})

test('next story replaces the held row', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'complete', complete: 3 }, chunk: 4 })
  const { clock } = await open($, on, files)

  files.set(`${CYCLE}/stories/t.md`, storyFile({ number: '6', title: 'Second title' }))
  setCycleState(files, ROOT, { story: 't' })
  await clock.advance(3000)
  const drawn = texts(await draw($))

  expect(drawn.slice(10, 14)).toEqual(['Story 6', ' · ', 'building', ' · Second title'])
  expect(drawn.join('')).not.toContain('First title')
})

test('held row drops when the held file is no longer complete', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'complete', complete: 3 }, chunk: 4 })
  const { clock } = await open($, on, files)
  setCycleState(files, ROOT, { story: '' })

  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'active', complete: 3 }))
  await clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)

  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
  await clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)
})

test('held row drops when the held file is unreadable', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'complete', complete: 3 }, chunk: 4 })
  const { clock } = await open($, on, files)
  expect(texts(await draw($))[STATE]).toBe('complete')

  setCycleState(files, ROOT, { story: '' })
  files.delete(`${CYCLE}/stories/s.md`)
  await clock.advance(3000)

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('mid-build story in a fresh session draws building on CURRENT_CHUNK', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { complete: 1 }, chunk: 2 })
  await open($, on, files)

  const drawn = texts(await draw($))

  expect(drawn[STATE]).toBe('building')
  expect(drawn.slice(BALLS)).toEqual(['●', '○', '○', ' chunk 2 of 3'])
})

test('final checks read building, not active', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'active', complete: 3 }, chunk: 4 })
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn).slice(STATE)).toEqual(['building', ' · First title', '●', '●', '●', ' 3 of 3 chunks done'])
  expect(drawn[STATE]?.color).toBe(BUILD_BASE)
  expect(texts(drawn)).not.toContain('active')
})

test('ball count follows chunks_total, not headings', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { total: 3, headings: 5 } })
  await open($, on, files)

  const balls = texts(await draw($)).filter(t => t === '○' || t === '●')

  expect(balls).toHaveLength(3)
})

test('chunk headings stand in when chunks_total is absent', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { total: 0, headings: 4 } })
  await open($, on, files)

  const balls = texts(await draw($)).filter(t => t === '○' || t === '●')

  expect(balls).toHaveLength(4)
})

test('a story file is found by name when its basename differs', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 'build-band' })
  files.set(`${CYCLE}/stories/29-build-band.md`, storyFile({ number: '29' }))
  await open($, on, files)

  expect(texts(await draw($))[10]).toBe('Story 29')
})

test('unreadable story file: one error-color line naming it', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 'gone' })
  files.set(`${CYCLE}/stories/other.md`, storyFile())
  await open($, on, files)

  const drawn = await draw($)

  expect(drawn).toEqual([{ text: "Can't read story file gone.md", color: 'error', bold: undefined }])
})

test('survey yields', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  await open($, on, files)

  expect(texts(await draw($, true))).toEqual(ENGINE)
})

test('hidden band draws nothing', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  await open($, on, files)

  await runCommand($, 'craft-progress')
  expect(texts(await draw($))).toEqual(ENGINE)

  await runCommand($, 'craft-progress')
  expect(texts(await draw($))[STATE]).toBe('building')
})

test('CRAFT_PROJECT_ROOT wins over the walk-up', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, '/work/p', { story: 's' })
  files.set('/work/p/.craft/cycles/c/stories/s.md', storyFile({ title: 'From the setting' }))
  seedProject(files, '/work/q', { story: 's' })
  files.set('/work/q/.craft/cycles/c/stories/s.md', storyFile({ title: 'From the walk' }))
  await open($, on, files, { sessionRoot: '/work/q/sub', env: { CRAFT_PROJECT_ROOT: '/work/p/' } })

  expect(texts(await draw($))[TITLE]).toBe(' · From the setting')
})

test('the walk-up finds the nearest project when no setting names one', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, '/work/q', { story: 's' })
  files.set('/work/q/.craft/cycles/c/stories/s.md', storyFile({ title: 'From the walk' }))
  await open($, on, files, { sessionRoot: '/work/q/deep/er', env: { CRAFT_PROJECT_ROOT: '/nowhere' } })

  expect(texts(await draw($))[TITLE]).toBe(' · From the walk')
})

test('active cycle with no cycle state file: nothing drawn', async ($, on) => {
  const files: Files = new Map()
  files.set(`${ROOT}/.craft/.global-state`, 'ACTIVE_CYCLE="c"\nCURRENT_STORY=""\n')
  files.set(`${CYCLE}/stories/s.md`, storyFile())
  await open($, on, files)

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('the ball count is capped so a bad chunks_total cannot flood the band', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { total: 1000000 } })
  await open($, on, files)

  const drawn = texts(await draw($))

  expect(drawn).toHaveLength(BALLS + 99 + 1)
  expect(drawn[drawn.length - 1]).toBe(' chunk 1 of 99')
})

test('control characters in a title never reach the drawn text', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { title: 'Safe\u001b]0;pwned\u0007 title' } })
  await open($, on, files)

  const drawn = texts(await draw($))

  expect(drawn[TITLE]).toBe(' · Safe]0;pwned title')
  expect(drawn.join('')).not.toMatch(/[\u0000-\u001f\u007f]/)
})

function seedMonorepo(files: Files, activeSubs: string[]) {
  files.set('/work/mono/.craft/.global-state', 'ACTIVE_CYCLE=""\n')
  for (const name of ['a', 'b']) {
    files.set(`/work/mono/.craft/projects/${name}.md`, `---\nname: ${name}\npath: apps/${name}\n---\n`)
    const root = `/work/mono/apps/${name}`
    if (activeSubs.includes(name)) {
      seedProject(files, root, { story: 's' })
      files.set(`${root}/.craft/cycles/c/stories/s.md`, storyFile({ title: `Project ${name}` }))
    } else {
      files.set(`${root}/.craft/.global-state`, 'ACTIVE_CYCLE=""\n')
    }
  }
}

test('monorepo top follows the pinned project', async ($, on) => {
  const files: Files = new Map()
  seedMonorepo(files, ['a', 'b'])
  files.set('/work/mono/.craft/.pinned-project', '/work/mono/apps/b\nb\n')
  await open($, on, files, { sessionRoot: '/work/mono' })

  expect(texts(await draw($))[TITLE]).toBe(' · Project b')
})

test('monorepo top with no pin follows the one active sub-project', async ($, on) => {
  const files: Files = new Map()
  seedMonorepo(files, ['a'])
  await open($, on, files, { sessionRoot: '/work/mono' })

  expect(texts(await draw($))[TITLE]).toBe(' · Project a')
})

test('monorepo top with two active sub-projects and no pin draws nothing', async ($, on) => {
  const files: Files = new Map()
  seedMonorepo(files, ['a', 'b'])
  await open($, on, files, { sessionRoot: '/work/mono' })

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('a -p session reads nothing and starts no timer', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files, { surface: null })

  await world.clock.advance(3000)
  await world.clock.advance(3000)
  await startTurn($)
  await spawn($, 'craft:chunk-validator')
  openCard($, world.cards)
  await world.clock.settle()
  await endTurn($)

  expect(world.calls).toEqual({ read: [], exists: [], list: [] })
  expect(world.writes.filter(k => k.startsWith('progress'))).toEqual([])
  const answer = await runCommand($, 'craft-progress')
  expect(answer.text).toBe('Craft progress hidden.')
})

test('a question card adds waiting on you', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)

  const card = openCard($, world.cards)
  await world.clock.settle()
  const during = texts(await draw($))
  await card.close()
  const after = texts(await draw($))

  expect(during.slice(STATE, STATE + 3)).toEqual(['building', ' · waiting on you', ' · First title'])
  expect(after.slice(STATE, STATE + 2)).toEqual(['building', ' · First title'])
})

test('waiting on you is drawn in the text color', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)

  const card = openCard($, world.cards)
  await world.clock.settle()
  const during = await draw($)
  await card.close()

  expect(during[STATE + 1]?.color).toBe('text')
})

test('a chunk validator makes it validating, its end returns building', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  world.ids.push('v1')

  await spawn($, 'craft:chunk-validator')
  const during = await draw($)
  await endTurn($, 'v1')
  const after = await draw($)

  expect(during[STATE]?.text).toBe('validating')
  expect(during[STATE]?.color).toBe(BUILD_BASE)
  expect(after[STATE]?.text).toBe('building')
})

test('the claims auditor reads validating', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  world.ids.push('c1')

  await spawn($, 'craft:claims-auditor')

  expect((await draw($))[STATE]?.text).toBe('validating')
})

test('any other agent leaves the band on building', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  world.ids.push('x1', 'x2')

  await spawn($, 'craft:implementer')
  await spawn($, 'not-a-chunk-validator-at-all')

  expect((await draw($))[STATE]?.text).toBe('building')
})

test('a validator the agent list no longer reports is dropped on the next period', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  world.ids.push('v1')
  world.running.push('v1')
  await spawn($, 'craft:chunk-validator')

  await world.clock.advance(3000)
  expect((await draw($))[STATE]?.text).toBe('validating')

  world.running.length = 0
  await world.clock.advance(3000)

  expect((await draw($))[STATE]?.text).toBe('building')
})

test('event hooks read no disk', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  world.ids.push('v1')
  const size = () => world.calls.read.length + world.calls.exists.length + world.calls.list.length
  const before = size()

  await startTurn($)
  const card = openCard($, world.cards)
  await world.clock.settle()
  const waiting = texts(await draw($))
  await card.close()
  await spawn($, 'craft:chunk-validator')
  const validating = texts(await draw($))
  await endTurn($, 'v1')
  await endTurn($)

  expect(size()).toBe(before)
  expect(waiting[STATE + 1]).toBe(' · waiting on you')
  expect(validating[STATE]).toBe('validating')
})

test('two overlapping refresh requests make one read pass and one publish', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  stubEngine(on)
  const calls = stubFiles(on, files, ROOT)
  stubAgents(on)
  mock.clock(on)
  mock.env(on, {})
  const writes: string[] = []
  on('state.set', (_, e, next) => {
    writes.push(e.key)
    return next(e)
  })
  const start = () => $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  await Promise.all([start(), start()])

  expect(calls.read.filter(p => p.endsWith('/.global-state'))).toHaveLength(1)
  expect(count(writes, 'progress')).toBe(1)
})

test('a request during a pass runs one more pass, never two at once', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  const reads = () => world.calls.read.filter(p => p.endsWith('/.global-state')).length
  const before = reads()
  let release = () => {}
  world.latch.gate = new Promise<void>(resolve => {
    release = resolve
  })

  await world.clock.advance(3000)
  await world.clock.advance(3000)
  world.latch.gate = null
  release()
  await world.clock.settle()
  await world.clock.settle()

  expect(world.latch.most).toBe(1)
  expect(reads() - before).toBe(2)
})

test('an aborted card does not stick', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)

  openCard($, world.cards)
  await world.clock.settle()
  expect(texts(await draw($))[STATE + 1]).toBe(' · waiting on you')

  await startTurn($)

  expect(texts(await draw($))[STATE + 1]).toBe(' · First title')
})

test('session.start resets validators', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  world.ids.push('v1')
  await startTurn($)
  await spawn($, 'craft:chunk-validator')
  expect((await draw($))[STATE]?.text).toBe('validating')

  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  const drawn = await draw($)

  expect(drawn[STATE]?.text).toBe('building')
})

// A clock the test owns, so it can refuse one period the way the engine may.
// Each held dispatch records whether its timer was cancelled.
function stubClock(on: On) {
  let now = 0
  const refuse = new Set<number>()
  const held: { ms: number; due: number; resolve: () => void; aborted: boolean }[] = []
  on('clock.now', () => ({ value: now }))
  on('clock.every', (_, e, next) => {
    if (refuse.delete(e.ms)) return { deny: 'refused' }
    return new Promise<{ value: undefined }>(resolve => {
      const entry = { ms: e.ms, due: now + e.ms, resolve: () => resolve({ value: undefined }), aborted: false }
      next.signal.addEventListener('abort', () => {
        entry.aborted = true
      })
      held.push(entry)
    })
  })
  const flush = () => new Promise<void>(resolve => setTimeout(resolve, 0))
  return {
    refuse,
    live: (ms: number) => held.filter(h => h.ms === ms && !h.aborted).length,
    async tick(ms: number) {
      const target = now + ms
      for (;;) {
        const due = held.filter(h => h.due <= target && !h.aborted).sort((a, b) => a.due - b.due)[0]
        if (!due) break
        held.splice(held.indexOf(due), 1)
        now = due.due
        due.resolve()
        await flush()
      }
      now = target
      await flush()
    },
  }
}

test('a refused period does not freeze the band', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  stubEngine(on)
  stubFiles(on, files, ROOT)
  stubAgents(on)
  const clock = stubClock(on)
  mock.env(on, {})
  on('ui.render', ($e, e) => h($e.ui.resolve(e).Text, null, 'engine') as RenderElement)
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  clock.refuse.add(3000)
  await clock.tick(3000)
  files.set(`${CYCLE}/stories/s.md`, storyFile({ title: 'Changed title' }))
  await clock.tick(10000)
  expect(texts(await draw($))[TITLE]).toBe(' · First title')

  await startTurn($)
  await clock.tick(3000)

  expect(texts(await draw($))[TITLE]).toBe(' · Changed title')
})

test('a second session.start leaves one refresh interval and one frame interval', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  stubEngine(on)
  stubFiles(on, files, ROOT)
  stubAgents(on)
  const clock = stubClock(on)
  mock.env(on, {})

  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })

  expect(clock.live(3000)).toBe(1)
  expect(clock.live(200)).toBe(1)
})

// The word's letters, then the rest of line one, so a test can compare the parts
// that must hold still while the word moves.
const letters = (drawn: Drawn) => drawn.slice(1, 9)
const apartFromWord = (drawn: Drawn) => [drawn[0], ...drawn.slice(9)]

test('the sweep: head bold in sweep, tail plain sweep, rest base', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const { clock } = await open($, on, files)

  await startTurn($)
  await clock.advance(200)
  const drawn = await draw($)

  expect(texts(letters(drawn))).toEqual(WORD)
  expect(letters(drawn).map(d => d.color)).toEqual([
    BUILD_SWEEP,
    BUILD_SWEEP,
    BUILD_BASE,
    BUILD_BASE,
    BUILD_BASE,
    BUILD_BASE,
    BUILD_BASE,
    BUILD_BASE,
  ])
  expect(letters(drawn).map(d => d.bold === true)).toEqual([false, true, false, false, false, false, false, false])
})

test('the sweep starts on the first letter and leaves the last letter behind the head', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const { clock } = await open($, on, files)

  await startTurn($)
  const first = await draw($)
  await clock.advance(200 * 8)
  const last = await draw($)

  expect(letters(first).map(d => d.bold === true)).toEqual([true, false, false, false, false, false, false, false])
  expect(letters(first)[0]?.color).toBe(BUILD_SWEEP)
  expect(letters(last).map(d => d.color)).toEqual([...Array(7).fill(BUILD_BASE), BUILD_SWEEP])
  expect(letters(last).some(d => d.bold)).toBe(false)
})

test('frames 9 to 11 rest, and frame 12 starts the sweep again', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const { clock } = await open($, on, files)
  await startTurn($)

  await clock.advance(200 * 9)
  for (const frame of [9, 10, 11]) {
    const drawn = await draw($)
    expect(letters(drawn).map(d => d.color), `frame ${frame}`).toEqual(Array(8).fill(BUILD_BASE))
    expect(letters(drawn).some(d => d.bold)).toBe(false)
    await clock.advance(200)
  }

  expect((await draw($))[1]?.bold).toBe(true)
})

test('only the view word moves', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const { clock } = await open($, on, files)
  await startTurn($)

  const early = await draw($)
  await clock.advance(200 * 3)
  const later = await draw($)

  expect(letters(early)).not.toEqual(letters(later))
  expect(apartFromWord(later)).toEqual(apartFromWord(early))
})

function frameWrites(world: World) {
  return count(world.writes, 'progressFrame')
}

test('a moving band writes frames', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  await startTurn($)

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBeGreaterThan(0)
})

test('a building story sweeps with no turn running', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBeGreaterThan(0)
})

test('the sweep keeps moving after the main turn ends, while the implementer runs in the background', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  await startTurn($)
  await startTurn($, 'impl1')
  await endTurn($)

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBeGreaterThan(0)
})

test('still band writes no frame: a card is up', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  await startTurn($)
  const card = openCard($, world.cards)
  await world.clock.settle()

  await world.clock.advance(2400)
  const held = await draw($)
  await card.close()

  expect(frameWrites(world)).toBe(0)
  expect(letters(held).map(d => d.color)).toEqual(Array(8).fill(BUILD_BASE))
})

test('still band writes no frame: the story is complete', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'complete', complete: 3 }, chunk: 4 })
  const world = await open($, on, files)
  await startTurn($)

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBe(0)
  expect(letters(await draw($)).map(d => d.color)).toEqual(Array(8).fill(BUILD_BASE))
})

test('still band writes no frame: motion is switched off', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  files.set(`${ROOT}/.craft/settings.yaml`, 'taste_pass_enabled: true\nprogress_band_motion: false\n')
  const world = await open($, on, files)
  await startTurn($)

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBe(0)
  expect(letters(await draw($)).map(d => d.color)).toEqual(Array(8).fill(BUILD_BASE))
})

test('still band writes no frame: the band is hidden', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  await startTurn($)
  await runCommand($, 'craft-progress')

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBe(0)
})

const MOTION_ON = [
  null,
  'taste_pass_enabled: true\n',
  'progress_band_motion: true\n',
  'progress_band_motion: no\n',
  'progress_band_motion: False\n',
  'progress_band_motion:\n',
  '# progress_band_motion: false\n',
]
for (const text of MOTION_ON) {
  test(`motion absent or any other value means on: ${JSON.stringify(text)}`, async ($, on) => {
    const files: Files = new Map()
    buildingWorld(files)
    if (text !== null) files.set(`${ROOT}/.craft/settings.yaml`, text)
    const world = await open($, on, files)
    await startTurn($)

    await world.clock.advance(1000)

    expect(frameWrites(world)).toBeGreaterThan(0)
  })
}

test('motion off reads the first key and strips quotes', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  files.set(`${ROOT}/.craft/settings.yaml`, 'progress_band_motion: "false"\nprogress_band_motion: true\n')
  const world = await open($, on, files)
  await startTurn($)

  await world.clock.advance(1000)

  expect(frameWrites(world)).toBe(0)
})

test('the module never writes the motion key into a settings file', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const world = await open($, on, files)
  await startTurn($)
  await world.clock.advance(3000)

  expect(files.has(`${ROOT}/.craft/settings.yaml`)).toBe(false)
})

test('hidden stays hidden while the story changes', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const { clock } = await open($, on, files)
  await runCommand($, 'craft-progress')

  files.set(`${CYCLE}/stories/t.md`, storyFile({ number: '6' }))
  setCycleState(files, ROOT, { story: 't' })
  await clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)

  await runCommand($, 'craft-progress')
  expect(texts(await draw($))[10]).toBe('Story 6')
})

// ---- The planning view ----

const PLAN_BASE = 'claudeBlue_FOR_SYSTEM_SPINNER'
const PLAN_SWEEP = 'claudeBlueShimmer_FOR_SYSTEM_SPINNER'
const PLAN_WORD = ['P', 'l', 'a', 'n', 'n', 'i', 'n', 'g']
const SCRIPT = '/plugin/hooks/scripts/planning-stage.sh'
const READY = 'ready to implement'
const HINT = ' · enter to choose a story (ctrl+x tab to focus)'
const T_FILE = `${CYCLE}/stories/t.md`
const U_FILE = `${CYCLE}/stories/u.md`

// A project with no story running, and these story files.
function planningWorld(files: Files, stories: Record<string, StoryOptions>) {
  seedProject(files, ROOT, { story: '' })
  for (const [name, o] of Object.entries(stories)) files.set(`${CYCLE}/stories/${name}.md`, storyFile(o))
}

// This session runs the planning-stage script on a story file; the engine answers with the
// script's own line.
async function stageCall($: Engine, world: World, path: string, line = SET_LINE) {
  world.bash.stdout = line.replace('/work/p/.craft/cycles/c/stories/t.md', path)
  await $.tool.call({ tool: 'Bash', command: `${SCRIPT} ${path} planner` } as Parameters<Engine['tool']['call']>[0])
  await world.clock.settle()
}

const ownWrites = (world: World) => count(world.writes, 'ownPlanning')

// Drawn line two without line one, for rows whose line one is checked on its own.
const afterTitle = (drawn: Drawn) => texts(drawn).slice(BALLS)

test('a staged story draws the planning view', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '5', stage: 'planner' } })
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn)).toEqual([
    '✶ ',
    ...PLAN_WORD,
    ' ',
    'Story 5',
    ' · ',
    'planner',
    ' · First title',
    '●',
    '●',
    '●',
    '○',
    '○',
    '○',
    ' step 4 of 6 · 0m',
    ' · next: plan check',
  ])
  expect(drawn.slice(0, 9).map(d => d.color)).toEqual(Array(9).fill(PLAN_BASE))
  expect(drawn[STATE]?.color).toBe(PLAN_BASE)
  expect(drawn[STATE]?.bold).toBe(true)
  expect(drawn.slice(BALLS, BALLS + 6).map(d => d.color)).toEqual([
    'success',
    'success',
    'success',
    'success',
    'inactive',
    'inactive',
  ])
  expect(drawn.slice(BALLS + 6).map(d => d.color)).toEqual([undefined, 'inactive'])
  expect(texts(drawn).join('')).not.toContain('◐')
})

test('a replan starts at step 1, whatever the chunk count and the status say', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { status: 'ready', total: 3, complete: 3, stage: 'content-check' } })
  await open($, on, files)

  const drawn = await draw($)

  expect(drawn[STATE]?.text).toBe('content check')
  expect(afterTitle(drawn)).toEqual(['○', '○', '○', '○', '○', '○', ' step 1 of 6 · 0m', ' · next: alignment check'])
  expect(drawn.slice(BALLS, BALLS + 6).map(d => d.color)).toEqual([
    'success',
    'inactive',
    'inactive',
    'inactive',
    'inactive',
    'inactive',
  ])
})

test('triage names ready to implement next', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'triage' } })
  await open($, on, files)

  const drawn = texts(await draw($))

  expect(drawn[STATE]).toBe('triage')
  expect(drawn.slice(-2)).toEqual([' step 6 of 6 · 0m', ' · next: ready to implement'])
})

test('an unknown stage value is no stage', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'bogus' } })
  await open($, on, files)

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('several staged, none own: Planning N stories', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '5', stage: 'planner' }, u: { number: '6', stage: 'triage' } })
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn)).toEqual(['✶ ', ...PLAN_WORD, ' ', '2 stories', '○', '○', ' 0m'])
  expect(drawn.slice(11, 13).map(d => d.color)).toEqual(['success', 'success'])
})

test('this session\'s story wins over the build', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  files.set(T_FILE, storyFile({ number: '6', stage: 'planner' }))
  const world = await open($, on, files)
  expect(texts(await draw($))[STATE]).toBe('building')

  await stageCall($, world, T_FILE)
  const drawn = texts(await draw($))

  expect(drawn.slice(1, 9)).toEqual(PLAN_WORD)
  expect(drawn[10]).toBe('Story 6')
  expect(drawn[STATE]).toBe('planner')
})

test('the build wins over another session\'s planning', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  files.set(T_FILE, storyFile({ number: '6', stage: 'planner' }))
  await open($, on, files)

  const drawn = texts(await draw($))

  expect(drawn.slice(1, 9)).toEqual(WORD)
  expect(drawn[STATE]).toBe('building')
})

test('a story planned from the backlog draws with no active cycle', async ($, on) => {
  const files: Files = new Map()
  files.set(`${ROOT}/.craft/.global-state`, 'LAST_ACTIVITY="x"\nACTIVE_CYCLE=""\n')
  const backlog = `${ROOT}/.craft/backlog/b.md`
  files.set(backlog, storyFile({ number: '9', stage: 'direction' }))
  const world = await open($, on, files)
  expect(texts(await draw($))).toEqual(ENGINE)

  await stageCall($, world, backlog)
  const drawn = texts(await draw($))

  expect(drawn[10]).toBe('Story 9')
  expect(drawn[STATE]).toBe('direction')
})

test('planning replaces the held complete row, and the row does not return', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files, { story: { status: 'complete', complete: 3 }, chunk: 4 })
  const { clock } = await open($, on, files)
  expect(texts(await draw($))[STATE]).toBe('complete')

  setCycleState(files, ROOT, { story: '' })
  files.set(T_FILE, storyFile({ number: '6', stage: 'planner' }))
  await clock.advance(3000)
  expect(texts(await draw($))[STATE]).toBe('planner')

  files.set(T_FILE, storyFile({ number: '6', status: 'ready' }))
  await clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)
})

test('hidden stays hidden across views', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  const { clock } = await open($, on, files)
  await runCommand($, 'craft-progress')

  setCycleState(files, ROOT, { story: '' })
  files.set(T_FILE, storyFile({ number: '6', stage: 'planner' }))
  await clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)

  await runCommand($, 'craft-progress')
  expect(texts(await draw($))[STATE]).toBe('planner')
})

test('the clock counts minutes and restarts on a story change', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '5', stage: 'planner' } })
  const { clock } = await open($, on, files)

  await clock.advance(300000)
  expect(texts(await draw($))).toContain(' step 4 of 6 · 5m')

  files.set(T_FILE, storyFile({ number: '5', status: 'ready' }))
  files.set(U_FILE, storyFile({ number: '6', stage: 'planner' }))
  await clock.advance(3000)

  const drawn = texts(await draw($))
  expect(drawn[10]).toBe('Story 6')
  expect(drawn).toContain(' step 4 of 6 · 0m')
})

test('the scan re-reads only changed files', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '5', stage: 'planner' }, u: { number: '6', stage: 'triage' } })
  const world = await open($, on, files)
  const reads = (path: string) => world.calls.read.filter(p => p === path).length

  await world.clock.advance(9000)
  expect([reads(T_FILE), reads(U_FILE)]).toEqual([1, 1])

  files.set(U_FILE, storyFile({ number: '6', stage: 'plan-check' }))
  await world.clock.advance(3000)

  expect([reads(T_FILE), reads(U_FILE)]).toEqual([1, 2])
  expect(texts(await draw($))).toContain('2 stories')
})

test('the scan does not run while the build is shown', async ($, on) => {
  const files: Files = new Map()
  buildingWorld(files)
  files.set(T_FILE, storyFile({ number: '6', stage: 'planner' }))
  const world = await open($, on, files)

  await world.clock.advance(3000)

  expect(world.calls.list.filter(p => p.endsWith('/stories'))).toEqual([])
  expect(world.calls.read).not.toContain(T_FILE)
})

// ---- This session's own set ----

test('a non-matching Bash call is passed through untouched', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, {})
  const world = await open($, on, files)
  const before = structuredClone(world.calls)

  world.bash.stdout = SET_LINE
  await $.tool.call({ tool: 'Bash', command: 'ls -la' } as Parameters<Engine['tool']['call']>[0])

  expect(world.calls).toEqual(before)
  expect(ownWrites(world)).toBe(0)
  expect(world.bash.commands).toEqual(['ls -la'])
})

test('the own set writes only on a planning-stage call', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files)
  await world.clock.advance(6000)
  expect(ownWrites(world)).toBe(0)

  await stageCall($, world, T_FILE)
  expect(ownWrites(world)).toBe(1)

  await stageCall($, world, T_FILE)
  await world.clock.advance(6000)
  expect(ownWrites(world)).toBe(1)

  await stageCall($, world, T_FILE, CLEARED_LINE)
  expect(ownWrites(world)).toBe(2)
})

test('a path outside the project is ignored', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, {})
  const world = await open($, on, files)

  await stageCall($, world, '/elsewhere/.craft/cycles/c/stories/t.md')
  await stageCall($, world, `${ROOT}/notes/t.md`)

  expect(ownWrites(world)).toBe(0)
})

test('a cleared line forgets the story', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files)
  await stageCall($, world, T_FILE)
  await startTurn($)
  await world.clock.advance(200)
  expect(frameWrites(world)).toBeGreaterThan(0)
  const before = frameWrites(world)

  await stageCall($, world, T_FILE, CLEARED_LINE)
  await world.clock.advance(2400)

  expect(frameWrites(world)).toBe(before)
})

test('the own set survives a fresh session.start', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files)
  await stageCall($, world, T_FILE)

  await $.session.start({ cwd: ROOT, surface: 'terminal', isInteractive: true })
  await world.clock.settle()
  await startTurn($)
  await world.clock.advance(200)

  const drawn = await draw($)
  expect(drawn[STATE]?.text).toBe('planner')
  expect(letters(drawn)[1]?.bold).toBe(true)
})

test('a -p session reads nothing when its own story goes ready', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files, { surface: null })

  await stageCall($, world, T_FILE)
  files.set(T_FILE, storyFile({ status: 'ready' }))
  await world.clock.advance(6000)

  expect(world.calls).toEqual({ read: [], exists: [], list: [] })
  expect(ownWrites(world)).toBe(0)
  expect(world.writes.filter(k => k.startsWith('progress'))).toEqual([])
})

// ---- The sheen on the planning view ----

test('a planning view sweeps in blue', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files)
  await stageCall($, world, T_FILE)
  await startTurn($)

  await world.clock.advance(200)
  const drawn = await draw($)

  expect(letters(drawn).map(d => d.color)).toEqual([
    PLAN_SWEEP,
    PLAN_SWEEP,
    PLAN_BASE,
    PLAN_BASE,
    PLAN_BASE,
    PLAN_BASE,
    PLAN_BASE,
    PLAN_BASE,
  ])
  expect(letters(drawn).map(d => d.bold === true)).toEqual([false, true, false, false, false, false, false, false])
  expect(drawn[0]?.color).toBe(PLAN_BASE)
})

test('another session\'s planning view never moves', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files)
  await startTurn($)

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBe(0)
  expect(letters(await draw($)).map(d => d.color)).toEqual(Array(8).fill(PLAN_BASE))
})

test('an own several-stories view moves, another session\'s never does', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '5', stage: 'planner' }, u: { number: '6', stage: 'triage' } })
  const world = await open($, on, files)
  await startTurn($)
  await world.clock.advance(2400)
  expect(frameWrites(world)).toBe(0)

  await stageCall($, world, T_FILE)
  await stageCall($, world, U_FILE)
  await world.clock.advance(200)

  const drawn = await draw($)
  expect(texts(drawn)).toContain('2 stories')
  expect(frameWrites(world)).toBeGreaterThan(0)
  expect(letters(drawn)[1]?.bold).toBe(true)
})

test('a planning view freezes while a card is up', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files)
  await stageCall($, world, T_FILE)
  await startTurn($)
  const card = openCard($, world.cards)
  await world.clock.settle()

  await world.clock.advance(2400)
  const held = await draw($)
  await card.close()

  expect(frameWrites(world)).toBe(0)
  expect(texts(held).slice(STATE, STATE + 3)).toEqual(['planner', ' · waiting on you', ' · First title'])
  expect(letters(held).map(d => d.color)).toEqual(Array(8).fill(PLAN_BASE))
})

// ---- The held ready row and its control ----

// This session's story reaches triage, then the flip clears its stage and marks it ready.
async function readyRow($: Engine, on: On, files: Files, o: { slot?: string } = {}) {
  planningWorld(files, { t: { number: '6', stage: 'triage' } })
  if (o.slot) {
    setCycleState(files, ROOT, { story: o.slot })
    files.set(`${CYCLE}/stories/${o.slot}.md`, storyFile({ number: '29', title: 'Running title' }))
  }
  const runs: { command: string; args: string }[] = []
  const world = await open($, on, files, {
    beforeStart: () => {
      on('command.run', { command: 'craft:story-implement' }, (_, e) => {
        runs.push({ command: e.command, args: e.args })
        return { text: '' }
      })
    },
  })
  await stageCall($, world, T_FILE)
  files.set(T_FILE, storyFile({ number: '6', status: 'ready' }))
  await world.clock.advance(3000)
  return { world, runs }
}

async function mountBand($: Engine) {
  return $.ui.mount({
    plugin: 'craft',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, ...BAND_PROPS },
  })
}

test('the ready hint reads the new copy', async ($, on) => {
  const files: Files = new Map()
  await readyRow($, on, files)

  const drawn = await draw($)

  expect(drawn[drawn.length - 1]?.text).toBe(' · enter to choose a story (ctrl+x tab to focus)')
})

// Line two's balls and words never shrink; only the grey hint gives way.
async function lineTwoOf($: Engine) {
  const ui = await mountBand($)
  const boxes = await ui.findAll({ type: 'Box' })
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()
  const line = boxes.find(b => b.props.paddingLeft === 2)
  const inner = boxes.filter(b => b.props.gap === 1 && b.props.flexShrink === 0 && line?.text.startsWith(b.text))
  expect(inner).toHaveLength(1)
  return { line, fixed: inner[0] as (typeof boxes)[number], last: text[text.length - 1] }
}

test('line two\'s balls and words never shrink; the hint truncates (ready row)', async ($, on) => {
  const files: Files = new Map()
  await readyRow($, on, files)

  const { line, fixed, last } = await lineTwoOf($)

  expect(fixed.props.gap).toBe(1)
  expect(fixed.props.flexShrink).toBe(0)
  expect(fixed.text).toBe('●●●●●● all 6 steps done')
  expect(line?.children).toHaveLength(2)
  expect(last?.text).toBe(HINT)
  expect(last?.props.wrap).toBe('truncate-end')
  expect(last?.props.color).toBe('inactive')
})

test('line two\'s balls and words never shrink; the hint truncates (step row)', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '5', stage: 'planner' } })
  await open($, on, files)

  const { fixed, last } = await lineTwoOf($)

  expect(fixed.props.flexShrink).toBe(0)
  expect(fixed.text).toBe('●●●○○○ step 4 of 6 · 0m')
  expect(last?.text).toBe(' · next: plan check')
  expect(last?.props.wrap).toBe('truncate-end')
  expect(last?.props.color).toBe('inactive')
})

test('the held ready row appears when this session\'s story goes ready', async ($, on) => {
  const files: Files = new Map()
  await readyRow($, on, files)

  const drawn = await draw($)

  expect(texts(drawn)).toEqual([
    '✶ ',
    ...PLAN_WORD,
    ' ',
    'Story 6',
    ' · ',
    READY,
    ' · First title',
    '●',
    '●',
    '●',
    '●',
    '●',
    '●',
    ' all 6 steps done',
    HINT,
  ])
  expect(letters(drawn).map(d => d.color)).toEqual(Array(8).fill(PLAN_BASE))
  expect(drawn.slice(BALLS, BALLS + 6).map(d => d.color)).toEqual(Array(6).fill('success'))
  expect(drawn[drawn.length - 1]?.color).toBe('inactive')
})

test('no ready row for a story another session planned', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'triage' } })
  const { clock } = await open($, on, files)
  expect(texts(await draw($))[STATE]).toBe('triage')

  files.set(T_FILE, storyFile({ status: 'ready' }))
  await clock.advance(3000)

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('no ready row for an own story that lost its stage without going ready', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'planner' } })
  const world = await open($, on, files)
  await stageCall($, world, T_FILE)
  expect(texts(await draw($))[STATE]).toBe('planner')

  files.set(T_FILE, storyFile({ status: 'backlog' }))
  await world.clock.advance(3000)

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('the control is present and green when the slot is free', async ($, on) => {
  const files: Files = new Map()
  await readyRow($, on, files)

  const ui = await mountBand($)
  const buttons = await ui.findAll({ type: 'Button' })
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  expect(buttons).toHaveLength(1)
  expect(buttons[0]?.props.label).toBe(READY)
  expect(buttons[0]?.props.plain).toBe(true)
  for (const banned of ['hotkey', 'action', 'autoFocus', 'dimColor', 'hover', 'variant']) {
    expect(buttons[0]?.props, banned).not.toHaveProperty(banned)
  }
  const inside = text.find(t => t.text === READY)
  expect(inside?.props.color).toBe('success')
  expect(inside?.props.bold).toBe(true)
  expect(text[text.length - 1]?.text).toBe(HINT)
  expect(text[text.length - 1]?.props.color).toBe('inactive')
})

test('the row waits behind a running story', async ($, on) => {
  const files: Files = new Map()
  await readyRow($, on, files, { slot: '29-build-progress-band' })

  const ui = await mountBand($)
  const buttons = await ui.findAll({ type: 'Button' })
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  expect(buttons).toHaveLength(0)
  const names = text.map(t => t.text)
  expect(names[STATE]).toBe(`${READY} · after Story 29`)
  expect(text[STATE]?.props.color).toBe('success')
  expect(text[STATE]?.props.bold).toBe(true)
  expect(names).not.toContain(HINT)
  expect(names.slice(-1)).toEqual([' all 6 steps done'])
  expect(names.slice(1, 9)).toEqual(PLAN_WORD)
})

test('a slot without leading digits shows its raw name', async ($, on) => {
  const files: Files = new Map()
  await readyRow($, on, files, { slot: 'plain-name' })

  expect(texts(await draw($))[STATE]).toBe(`${READY} · after plain-name`)
})

test('the gated row turns pressable when the slot frees', async ($, on) => {
  const files: Files = new Map()
  const { world } = await readyRow($, on, files, { slot: '29-build-progress-band' })
  expect(texts(await draw($))).not.toContain(HINT)

  setCycleState(files, ROOT, { story: '' })
  await world.clock.advance(3000)

  const ui = await mountBand($)
  const buttons = await ui.findAll({ type: 'Button' })
  await ui.unmount()
  expect(buttons).toHaveLength(1)
  expect(texts(await draw($))).toContain(HINT)
})

test('a new story in the slot shows the building view, and the ready row is gone', async ($, on) => {
  const files: Files = new Map()
  const { world } = await readyRow($, on, files, { slot: '29-build-progress-band' })

  files.set(`${CYCLE}/stories/30-next.md`, storyFile({ number: '30', title: 'Next' }))
  setCycleState(files, ROOT, { story: '30-next' })
  await world.clock.advance(3000)
  expect(texts(await draw($))[STATE]).toBe('building')

  setCycleState(files, ROOT, { story: '' })
  await world.clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)
})

test('the ready row leaves when building starts', async ($, on) => {
  const files: Files = new Map()
  const { world } = await readyRow($, on, files)

  files.set(`${CYCLE}/stories/s.md`, storyFile())
  setCycleState(files, ROOT, { story: 's' })
  await world.clock.advance(3000)
  expect(texts(await draw($))[STATE]).toBe('building')

  setCycleState(files, ROOT, { story: '' })
  await world.clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)
})

test('the ready row leaves when planning starts elsewhere', async ($, on) => {
  const files: Files = new Map()
  const { world } = await readyRow($, on, files)

  files.set(U_FILE, storyFile({ number: '7', stage: 'planner' }))
  await world.clock.advance(3000)
  const drawn = texts(await draw($))
  expect(drawn[10]).toBe('Story 7')
  expect(drawn[STATE]).toBe('planner')

  files.set(U_FILE, storyFile({ number: '7', status: 'ready' }))
  await world.clock.advance(3000)
  expect(texts(await draw($))).toEqual(ENGINE)
})

// ---- The story chooser: open, list, page, confirm, start ----

const BACKLOG_X = `${ROOT}/.craft/backlog/x.md`

// The mounted band on the band's own props, optionally narrower.
async function mountAt($: Engine, bodyColumns = BAND_PROPS.bodyColumns) {
  return $.ui.mount({
    plugin: 'craft',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, ...BAND_PROPS, bodyColumns },
  })
}

const labelsOf = (found: { props: Record<string, unknown> }[]) => found.map(b => b.props.label)

// A ready row beside two more ready stories (2 and 9), one still planning (3)
// and a ready backlog story that is not the row's own.
async function chooserRow($: Engine, on: On, files: Files, o: { slot?: string } = {}) {
  files.set(`${CYCLE}/stories/a.md`, storyFile({ number: '2', status: 'ready', title: 'Second' }))
  files.set(`${CYCLE}/stories/b.md`, storyFile({ number: '9', status: 'ready', title: 'Ninth' }))
  files.set(`${CYCLE}/stories/p.md`, storyFile({ number: '3', status: 'planning' }))
  files.set(BACKLOG_X, storyFile({ number: '8', status: 'ready' }))
  return readyRow($, on, files, o)
}

async function pressInto($: Engine, ui: Awaited<ReturnType<typeof mountBand>>, ...keys: string[]) {
  for (const key of keys) await ui.press({ key })
  return ui
}

test("the open chooser's tree draws with its hover, reveal and hotkey props", async ($, on) => {
  const files: Files = new Map()
  await chooserRow($, on, files)
  const ui = await mountBand($)

  await ui.press({ key: READY })
  const text = await ui.findAll({ type: 'Text' })
  const buttons = await ui.findAll({ type: 'Button' })
  const tree = await ui.drawn()
  const nodes: { type?: string; props?: Record<string, unknown>; hover?: unknown }[] = []
  const walk = (node: unknown) => {
    if (typeof node !== 'object' || node === null) return
    const el = node as { type?: string; props?: { children?: unknown }; hover?: unknown; children?: unknown }
    if (el.type) nodes.push(el)
    const kids = el.children ?? el.props?.children
    for (const kid of Array.isArray(kids) ? kids : [kids]) walk(kid)
  }
  walk(tree)

  expect(text.map(t => t.text).slice(0, 4)).toEqual(['✶ ', 'Implement', ' which story?', ' · 3 ready'])
  const rings = nodes.filter(n => n.type === 'Box' && n.props?.position === 'absolute')
  expect(rings.map(r => [r.props?.display, r.hover])).toEqual([
    ['none', { scope: 'choose-0', display: 'flex' }],
    ['none', { scope: 'choose-1', display: 'flex' }],
    ['none', { scope: 'choose-2', display: 'flex' }],
  ])
  const hovers = nodes.filter(n => n.type === 'Button' && n.hover).map(n => n.hover)
  expect(hovers).toEqual([{ scope: 'choose-0' }, { scope: 'choose-1' }, { scope: 'choose-2' }])
  expect(buttons.find(b => b.key === 'cancel')?.props.hotkey).toBe('x')

  await ui.press({ key: 'story-0' })
  const confirm = await ui.findAll({ type: 'Text' })
  await ui.unmount()
  expect(confirm.map(t => t.text).slice(0, 5)).toEqual(['✶ ', 'Start', ' Story 6', ' · First title', '?'])
})

test('pressing ready opens the chooser and runs nothing', async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)

  await ui.press({ key: READY })
  await world.clock.settle()
  const text = await ui.findAll({ type: 'Text' })
  const buttons = await ui.findAll({ type: 'Button' })
  await ui.unmount()

  expect(runs).toEqual([])
  expect(text.slice(0, 4).map(t => t.text)).toEqual(['✶ ', 'Implement', ' which story?', ' · 3 ready'])
  expect(text.slice(0, 3).every(t => t.props.bold === true)).toBe(true)
  expect(text[3]?.props.color).toBe('subtle')
  expect(labelsOf(buttons)).toEqual(['Story 6', 'Story 2', 'Story 9', 'cancel'])
})

test("the row's own story is first and bold, then the cycle's ready stories by number", async ($, on) => {
  const files: Files = new Map()
  await chooserRow($, on, files)
  const ui = await mountBand($)

  await ui.press({ key: READY })
  const buttons = await ui.findAll({ type: 'Button' })
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  expect(buttons.filter(b => b.key?.startsWith('story-')).map(b => b.key)).toEqual(['story-0', 'story-1', 'story-2'])
  expect(text.find(t => t.text === 'Story 6')?.props.bold).toBe(true)
  expect(text.find(t => t.text === 'Story 2')?.props.bold).not.toBe(true)
  expect(text.find(t => t.text === 'Story 9')?.props.color).toBe('success')
})

test('planning, active and backlog stories are never listed', async ($, on) => {
  const files: Files = new Map()
  await chooserRow($, on, files)
  files.set(`${CYCLE}/stories/q.md`, storyFile({ number: '4', status: 'active' }))
  const ui = await mountBand($)

  await ui.press({ key: READY })
  const buttons = await ui.findAll({ type: 'Button' })
  await ui.unmount()

  expect(labelsOf(buttons)).not.toContain('Story 3')
  expect(labelsOf(buttons)).not.toContain('Story 4')
  expect(labelsOf(buttons)).not.toContain('Story 8')
})

// A story planned from the backlog with no active cycle: the row names it.
async function backlogOwnRow($: Engine, on: On, files: Files) {
  files.set(`${ROOT}/.craft/.global-state`, 'LAST_ACTIVITY="x"\n')
  files.set(BACKLOG_X, storyFile({ number: '4', stage: 'triage' }))
  const runs: { command: string; args: string }[] = []
  const world = await open($, on, files, {
    beforeStart: () => {
      on('command.run', { command: 'craft:story-implement' }, (_, e) => {
        runs.push({ command: e.command, args: e.args })
        return { text: '' }
      })
    },
  })
  await stageCall($, world, BACKLOG_X)
  files.set(BACKLOG_X, storyFile({ number: '4', status: 'ready' }))
  await world.clock.advance(3000)
  return { world, runs }
}

test("with no active cycle the list is the row's own story", async ($, on) => {
  const files: Files = new Map()
  await backlogOwnRow($, on, files)
  const ui = await mountBand($)

  await ui.press({ key: READY })
  const buttons = await ui.findAll({ type: 'Button' })
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  expect(labelsOf(buttons)).toEqual(['Story 4', 'cancel'])
  expect(text[3]?.text).toBe(' · 1 ready')
})

test('a narrow band pages with +M more and ‹ back, every story once', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '6', stage: 'triage' } })
  for (const n of [1, 2, 3, 4, 5]) files.set(`${CYCLE}/stories/n${n}.md`, storyFile({ number: String(n), status: 'ready' }))
  const runs: unknown[] = []
  const world = await open($, on, files)
  await stageCall($, world, T_FILE)
  files.set(T_FILE, storyFile({ number: '6', status: 'ready' }))
  await world.clock.advance(3000)
  void runs
  const ui = await mountAt($, 40)

  await ui.press({ key: READY })
  const seen: unknown[] = []
  let page = await ui.findAll({ type: 'Button' })
  expect(page.find(b => b.key === 'earlier')).toBeUndefined()
  expect(page.find(b => b.key === 'more')?.text).toBe('+5 more ›')
  for (let guard = 0; guard < 10; guard++) {
    seen.push(...page.filter(b => b.key?.startsWith('story-')).map(b => b.props.label))
    if (!page.some(b => b.key === 'more')) break
    await ui.press({ key: 'more' })
    page = await ui.findAll({ type: 'Button' })
    expect(page[0]?.key).toBe('earlier')
  }
  expect(seen).toEqual(['Story 6', 'Story 1', 'Story 2', 'Story 3', 'Story 4', 'Story 5'])

  await ui.press({ key: 'earlier' })
  const back = await ui.findAll({ type: 'Button' })
  await ui.unmount()
  expect(back.some(b => b.key === 'earlier')).toBe(true)
  expect(labelsOf(back).filter(l => String(l).startsWith('Story'))).toEqual(['Story 4'])
})

test('cancel returns the ready row', async ($, on) => {
  const files: Files = new Map()
  await chooserRow($, on, files)
  const ui = await mountBand($)

  await ui.press({ key: READY })
  await ui.press({ key: 'cancel' })
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  expect(text.map(t => t.text)).toContain(READY)
  expect(text.map(t => t.text)).not.toContain('Implement')
})

test('picking shows Start Story N with the title in normal color', async ($, on) => {
  const files: Files = new Map()
  await chooserRow($, on, files)
  const ui = await mountBand($)

  await ui.press({ key: READY })
  await ui.press({ key: 'story-1' })
  const text = await ui.findAll({ type: 'Text' })
  const buttons = await ui.findAll({ type: 'Button' })
  await ui.unmount()

  expect(text.slice(0, 5).map(t => t.text)).toEqual(['✶ ', 'Start', ' Story 2', ' · Second', '?'])
  expect(text[3]?.props).not.toHaveProperty('color')
  expect(text[3]?.props.wrap).toBe('truncate-end')
  expect(text[2]?.props.bold).toBe(true)
  expect(buttons.map(b => b.key)).toEqual(['start', 'back'])
  expect(text.find(t => t.text === 'start')?.props.color).toBe('success')
})

test('back returns the list on the same page', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { number: '6', stage: 'triage' } })
  for (const n of [1, 2, 3, 4, 5]) files.set(`${CYCLE}/stories/n${n}.md`, storyFile({ number: String(n), status: 'ready' }))
  const world = await open($, on, files)
  await stageCall($, world, T_FILE)
  files.set(T_FILE, storyFile({ number: '6', status: 'ready' }))
  await world.clock.advance(3000)
  const ui = await mountAt($, 40)

  await ui.press({ key: READY })
  await ui.press({ key: 'more' })
  const before = (await ui.findAll({ type: 'Button' })).find(b => b.key?.startsWith('story-'))?.key
  await ui.press({ key: before ?? '' })
  expect((await ui.findAll({ type: 'Button' })).map(b => b.key)).toEqual(['start', 'back'])
  await ui.press({ key: 'back' })
  const after = (await ui.findAll({ type: 'Button' })).find(b => b.key?.startsWith('story-'))?.key
  await ui.unmount()

  expect(after).toBe(before)
})

test('only x and n are hotkeys; start has none', async ($, on) => {
  const files: Files = new Map()
  await chooserRow($, on, files)
  const ui = await mountBand($)

  await ui.press({ key: READY })
  const list = await ui.findAll({ type: 'Button' })
  await ui.press({ key: 'story-0' })
  const confirm = await ui.findAll({ type: 'Button' })
  await ui.unmount()

  const hotkeys = [...list, ...confirm].filter(b => 'hotkey' in b.props).map(b => [b.key, b.props.hotkey])
  expect(hotkeys).toEqual([
    ['cancel', 'x'],
    ['back', 'n'],
  ])
  expect(confirm.find(b => b.key === 'start')?.props).not.toHaveProperty('hotkey')
  expect(confirm.find(b => b.key === 'back')?.props.dimColor).toBe(true)
})

test("start runs story-implement with the story's .craft/ path", async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)

  await pressInto($, ui, READY, 'story-1', 'start')
  await world.clock.settle()
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  expect(runs).toEqual([{ command: 'craft:story-implement', args: '.craft/cycles/c/stories/a.md' }])
  expect(text.map(t => t.text)).not.toContain('Start')
})

test("start runs a backlog own story with its .craft/backlog path", async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await backlogOwnRow($, on, files)
  const ui = await mountBand($)

  await pressInto($, ui, READY, 'story-0', 'start')
  await world.clock.settle()
  await ui.unmount()

  expect(runs).toEqual([{ command: 'craft:story-implement', args: '.craft/backlog/x.md' }])
})

test('a double start runs once', async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)

  await pressInto($, ui, READY, 'story-1')
  await Promise.all([ui.press({ key: 'start' }), ui.press({ key: 'start' })])
  await world.clock.settle()
  await ui.unmount()

  expect(runs).toHaveLength(1)
})

test('start with the slot set runs nothing and can start again once it frees', async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)
  await pressInto($, ui, READY, 'story-1')

  files.set(`${CYCLE}/stories/7-next.md`, storyFile({ number: '7' }))
  setCycleState(files, ROOT, { story: '7-next' })
  await ui.press({ key: 'start' })
  await world.clock.settle()
  expect(runs).toEqual([])

  setCycleState(files, ROOT, { story: '' })
  await pressInto($, ui, 'story-1', 'start')
  await world.clock.settle()
  await ui.unmount()

  expect(runs).toHaveLength(1)
})

test('the chooser stays open while files, the slot and the snapshot change', async ($, on) => {
  const files: Files = new Map()
  const { world } = await chooserRow($, on, files)
  const ui = await mountBand($)
  await ui.press({ key: READY })

  files.set(`${CYCLE}/stories/7-next.md`, storyFile({ number: '7' }))
  setCycleState(files, ROOT, { story: '7-next' })
  await world.clock.advance(3000)
  const stillOpen = (await ui.findAll({ type: 'Text' })).map(t => t.text)

  expect(stillOpen).toContain('Implement')
  expect(texts(await draw($))).toContain('Implement')

  await ui.press({ key: 'cancel' })
  const closed = (await ui.findAll({ type: 'Text' })).map(t => t.text)
  await ui.unmount()
  expect(closed).toContain('building')
  expect(closed).not.toContain('Implement')
})

// Holds start's file re-check open on the cycle's global state, so the test can
// do what the engine does meanwhile and then press start again.
async function startHeld($: Engine, world: World, ui: Awaited<ReturnType<typeof mountBand>>) {
  await pressInto($, ui, READY, 'story-1')
  let release = () => {}
  world.latch.gate = new Promise<void>(resolve => {
    release = resolve
  })
  await ui.press({ key: 'start' })
  return () => {
    world.latch.gate = null
    release()
  }
}

test("a publish during start's check does not let a second start run", async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)
  const free = await startHeld($, world, ui)
  const before = count(world.writes, 'progress')

  await startTurn($)
  const card = openCard($, world.cards)
  await world.clock.settle()
  expect(count(world.writes, 'progress')).toBeGreaterThan(before)
  await ui.press({ key: 'start' })
  free()
  await world.clock.settle()
  await card.close()
  await ui.unmount()

  expect(runs).toHaveLength(1)
})

test("a turn ending during start's check does not let a second start run", async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)
  const free = await startHeld($, world, ui)

  await startTurn($)
  await endTurn($)
  await ui.press({ key: 'start' })
  free()
  await world.clock.settle()
  await ui.unmount()

  expect(runs).toHaveLength(1)
})

test('the sheen never touches the control', async ($, on) => {
  const files: Files = new Map()
  const { world } = await readyRow($, on, files)
  await startTurn($)
  const before = frameWrites(world)

  await world.clock.advance(2400)
  const ui = await mountBand($)
  const text = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  expect(frameWrites(world)).toBe(before)
  const control = text.find(t => t.text === READY)
  expect(control?.props.color).toBe('success')
  expect(control?.props.bold).toBe(true)
  expect(text.slice(1, 9).map(t => t.props.color)).toEqual(Array(8).fill(PLAN_BASE))
})

test('the ready row writes no frame and no snapshot while a turn runs', async ($, on) => {
  const files: Files = new Map()
  const { world } = await readyRow($, on, files)
  await startTurn($)
  await world.clock.settle()
  const frames = frameWrites(world)
  const snapshots = count(world.writes, 'progress')

  await world.clock.advance(2400)

  expect(frameWrites(world)).toBe(frames)
  expect(count(world.writes, 'progress')).toBe(snapshots)
})

test('the ready row is nothing on disk', async ($, on) => {
  const files: Files = new Map()
  const { world } = await readyRow($, on, files)
  const owned = ownWrites(world)
  const reads = world.calls.read.length

  await world.clock.advance(6000)

  expect(ownWrites(world)).toBe(owned)
  const storyReads = world.calls.read.slice(reads).filter(p => p.includes('/stories/'))
  expect(storyReads.every(p => p === T_FILE)).toBe(true)
})

test('the band holds no focus: no input, no select, no hotkey, no action', async ($, on) => {
  const files: Files = new Map()
  await readyRow($, on, files)
  const ui = await mountBand($)

  for (const type of ['Input', 'Select']) expect(await ui.findAll({ type })).toEqual([])
  const buttons = await ui.findAll({ type: 'Button' })
  await ui.unmount()

  expect(buttons[0]?.props).not.toHaveProperty('autoFocus')
  expect(buttons[0]?.props).not.toHaveProperty('hotkey')
  expect(buttons[0]?.props).not.toHaveProperty('action')
})

test('a planning view draws no control', async ($, on) => {
  const files: Files = new Map()
  planningWorld(files, { t: { stage: 'triage' } })
  await open($, on, files)

  const ui = await mountBand($)
  const buttons = await ui.findAll({ type: 'Button' })
  await ui.unmount()

  expect(buttons).toEqual([])
})

// ---- A refused start explains itself ----

const lineOne = async (ui: Awaited<ReturnType<typeof mountBand>>) => (await ui.findAll({ type: 'Text' })).map(t => t.text)

test("a story that stopped being ready: nothing runs, the list re-reads, line 1 says Story 2 isn't ready anymore", async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)
  await pressInto($, ui, READY, 'story-1')

  files.set(`${CYCLE}/stories/a.md`, storyFile({ number: '2', status: 'planning' }))
  await ui.press({ key: 'start' })
  await world.clock.settle()
  const text = await lineOne(ui)
  const buttons = labelsOf(await ui.findAll({ type: 'Button' }))
  await ui.unmount()

  expect(runs).toEqual([])
  expect(text).toContain("Story 2 isn't ready anymore")
  expect(text).toContain(' · 2 ready')
  expect(text).not.toContain('Implement')
  expect(text).not.toContain('Start')
  expect(buttons).not.toContain('Story 2')
})

test("a story moved out of the active cycle: line 1 says it isn't in the active cycle anymore", async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)
  await pressInto($, ui, READY, 'story-1')

  files.delete(`${CYCLE}/stories/a.md`)
  await ui.press({ key: 'start' })
  await world.clock.settle()
  const text = await lineOne(ui)
  await ui.unmount()

  expect(runs).toEqual([])
  expect(text).toContain("Story 2 isn't in the active cycle anymore")
})

test('another story took the slot: line 1 says Story 7 is building', async ($, on) => {
  const files: Files = new Map()
  const { world, runs } = await chooserRow($, on, files)
  const ui = await mountBand($)
  await pressInto($, ui, READY, 'story-1')

  files.set(`${CYCLE}/stories/7-next.md`, storyFile({ number: '7' }))
  setCycleState(files, ROOT, { story: '7-next' })
  await ui.press({ key: 'start' })
  await world.clock.settle()
  const text = await lineOne(ui)
  await ui.unmount()

  expect(runs).toEqual([])
  expect(text).toContain('Story 7 is building')
  expect(text).toContain(' · 3 ready')
})

test('the own story no longer ready drops from the refreshed list', async ($, on) => {
  const files: Files = new Map()
  const { world } = await chooserRow($, on, files)
  const ui = await mountBand($)
  await pressInto($, ui, READY, 'story-1')

  files.set(T_FILE, storyFile({ number: '6', status: 'planning' }))
  files.set(`${CYCLE}/stories/a.md`, storyFile({ number: '2', status: 'planning' }))
  await ui.press({ key: 'start' })
  await world.clock.settle()
  const buttons = labelsOf(await ui.findAll({ type: 'Button' }))
  await ui.unmount()

  expect(buttons).toEqual(['Story 9', 'cancel'])
  expect(buttons).not.toContain('Story 6')
  expect(buttons).not.toContain('Story 2')
})

test('an empty refreshed list draws only cancel, with 0 ready', async ($, on) => {
  const files: Files = new Map()
  const { world } = await chooserRow($, on, files)
  const ui = await mountBand($)
  await pressInto($, ui, READY, 'story-1')

  for (const file of ['a', 'b']) files.set(`${CYCLE}/stories/${file}.md`, storyFile({ number: '2', status: 'planning' }))
  files.set(T_FILE, storyFile({ number: '6', status: 'planning' }))
  await ui.press({ key: 'start' })
  await world.clock.settle()
  const text = await lineOne(ui)
  const buttons = labelsOf(await ui.findAll({ type: 'Button' }))
  await ui.unmount()

  expect(text).toContain(' · 0 ready')
  expect(buttons).toEqual(['cancel'])
})
