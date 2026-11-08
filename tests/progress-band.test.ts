import { expect, mock, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'
import type { On, RenderElement } from 'claude-code'
type Files = Map<string, string>

const ROOT = '/work/p'
const CYCLE = `${ROOT}/.craft/cycles/c`

// The engine answers every call the module makes on `$`; each hook here stands
// for that answer. Registered before the first `$` call.
function stubEngine(on: On) {
  const registered: { name: string; description: string }[] = []
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => {
    registered.push({ name: e.name, description: e.description })
    return { value: { command: e.name } }
  })
  return registered
}

// A file system made of absolute paths. Every folder implied by a path exists.
// Returns the calls made, so a test can show what was (not) read.
function stubFiles(on: On, files: Files, sessionRoot: string) {
  const calls = { read: [] as string[], exists: [] as string[], list: [] as string[] }
  const isDir = (path: string) => [...files.keys()].some(key => key.startsWith(`${path}/`))
  on('fs.read', (_, e) => {
    calls.read.push(e.path)
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
    const entries = [...names].map(([name, kind]) => ({ name, kind, size: 0, mtimeMs: 0, isLink: false }))
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
}

function storyFile(o: StoryOptions = {}): string {
  const headings = Array.from({ length: o.headings ?? 3 }, (_, i) => `### Chunk ${i + 1}: part ${i + 1}\n`)
  return [
    '---',
    'name: s',
    `title: "${o.title ?? 'First title'}"`,
    'type: technical',
    `status: ${o.status ?? 'active'}`,
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
    `CYCLE_NAME="c"\nCURRENT_STORY="${s.story}"\nCURRENT_CHUNK="${s.chunk ?? 1}"\nTOTAL_CHUNKS="3"\n`,
  )
}

type World = {
  clock: ReturnType<typeof mock.clock>
  calls: ReturnType<typeof stubFiles>
}

// Stubs the engine, the files, the clock and the environment, then starts a terminal session.
async function open(
  $: Engine,
  on: On,
  files: Files,
  options: { sessionRoot?: string; env?: Record<string, string>; surface?: 'terminal' | null } = {},
): Promise<World> {
  stubEngine(on)
  const calls = stubFiles(on, files, options.sessionRoot ?? ROOT)
  const clock = mock.clock(on)
  mock.env(on, options.env ?? {})
  // Beneath the plugin, standing for the engine's own drawing of the band's place.
  on('ui.render', ($e, e) => {
    const { Text } = $e.ui.resolve(e)
    return h(Text, null, 'engine') as RenderElement
  })
  const surface = options.surface === undefined ? 'terminal' : options.surface
  await $.session.start({ cwd: options.sessionRoot ?? ROOT, surface, isInteractive: surface !== null })
  return { clock, calls }
}

type Drawn = { text: string; color: unknown }[]

async function draw($: Engine, hasSurvey = false): Promise<Drawn> {
  const ui = await $.ui.mount({
    plugin: 'craft',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: {
      hasSurvey,
      isWorking: false,
      maxRows: 10,
      bodyColumns: 80,
      scroll: { offset: 0, bodyRows: 8 },
      view: {},
    },
  })
  const found = await ui.findAll({ type: 'Text' })
  await ui.unmount()
  return found.map(el => ({ text: el.text, color: el.props.color }))
}

const texts = (drawn: Drawn) => drawn.map(d => d.text)

// The engine's command.run takes the whole event, origin and presentation
// included; a test stands in for the user typing the command at the prompt.
const runCommand = ($: Engine, command: string) =>
  $.command.run({ command, args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: false, columns: 80 } })
const ENGINE = ['engine']

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
  expect(description.length).toBeGreaterThan(0)
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

test('hidden is not remembered across sessions', async ($, on) => {
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

test('story start: label, building, first ring green, chunk 1 of 3', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile())
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn)).toEqual(['Story 5 ', 'building', ' · First title', '○', '○', '○', ' chunk 1 of 3'])
  expect(drawn.map(d => d.color)).toEqual(['claude', 'warning', 'subtle', 'success', 'inactive', 'inactive', undefined])
})

test('a long title can give way, but the label and status never shrink', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ title: 'A very long story title that runs well past the width of the terminal row' }))
  await open($, on, files)

  const ui = await $.ui.mount({
    plugin: 'craft',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 80, scroll: { offset: 0, bodyRows: 8 }, view: {} },
  })
  const boxes = await ui.findAll({ type: 'Box' })
  const title = await ui.findAll({ type: 'Text' })
  await ui.unmount()

  const fixed = boxes.filter(b => b.props.flexShrink === 0)
  expect(fixed).toHaveLength(1)
  expect(fixed[0]?.text).toBe('Story 5 building')
  expect(fixed[0]?.children.map(c => (typeof c === 'string' ? c : (c as { type: string }).type))).toEqual(['Text', 'Text'])
  expect(fixed[0]?.text).not.toContain('A very long')
  const titleText = title.find(t => t.text.includes('A very long'))
  expect(titleText?.props.wrap).toBe('truncate-end')
})

test('chunk passes: ball 1 filled, ring 2 green, chunk 2 of 3', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile())
  const { clock } = await open($, on, files)

  setCycleState(files, ROOT, { story: 's', chunk: 2 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ complete: 1 }))
  await clock.advance(3000)
  const drawn = await draw($)

  expect(texts(drawn).slice(3)).toEqual(['●', '○', '○', ' chunk 2 of 3'])
  expect(drawn.slice(3, 6).map(d => d.color)).toEqual(['success', 'success', 'inactive'])
})

test('story complete: complete, all balls filled, all 3 chunks done', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's', chunk: 3 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn)).toEqual(['Story 5 ', 'complete', ' · First title', '●', '●', '●', ' all 3 chunks done'])
  expect(drawn[1]?.color).toBe('success')
})

test('complete row holds after the current story clears', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's', chunk: 3 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
  const { clock } = await open($, on, files)
  const before = texts(await draw($))

  setCycleState(files, ROOT, { story: '' })
  await clock.advance(3000)

  expect(texts(await draw($))).toEqual(before)
  expect(before[1]).toBe('complete')
})

test('next story replaces the held row', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's', chunk: 3 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
  const { clock } = await open($, on, files)

  files.set(`${CYCLE}/stories/t.md`, storyFile({ number: '6', title: 'Second title' }))
  setCycleState(files, ROOT, { story: 't' })
  await clock.advance(3000)
  const drawn = texts(await draw($))

  expect(drawn.slice(0, 3)).toEqual(['Story 6 ', 'building', ' · Second title'])
  expect(drawn.join('')).not.toContain('First title')
})

test('held row drops when the held file is no longer complete', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's', chunk: 3 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
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
  seedProject(files, ROOT, { story: 's', chunk: 3 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'complete', complete: 3 }))
  const { clock } = await open($, on, files)
  expect(texts(await draw($))[1]).toBe('complete')

  setCycleState(files, ROOT, { story: '' })
  files.delete(`${CYCLE}/stories/s.md`)
  await clock.advance(3000)

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('mid-build story in a fresh session draws building on CURRENT_CHUNK', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's', chunk: 2 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ complete: 1 }))
  await open($, on, files)

  const drawn = texts(await draw($))

  expect(drawn[1]).toBe('building')
  expect(drawn.slice(3)).toEqual(['●', '○', '○', ' chunk 2 of 3'])
})

test('final checks: all filled, first line shows the status word', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's', chunk: 4 })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ status: 'active', complete: 3 }))
  await open($, on, files)

  const drawn = await draw($)

  expect(texts(drawn)).toEqual(['Story 5 ', 'active', ' · First title', '●', '●', '●', ' 3 of 3 chunks done'])
  expect(drawn[1]?.color).toBe('suggestion')
})

test('ball count follows chunks_total, not headings', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ total: 3, headings: 5 }))
  await open($, on, files)

  const balls = texts(await draw($)).filter(t => t === '○' || t === '●')

  expect(balls).toHaveLength(3)
})

test('chunk headings stand in when chunks_total is absent', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile({ total: 0, headings: 4 }))
  await open($, on, files)

  const balls = texts(await draw($)).filter(t => t === '○' || t === '●')

  expect(balls).toHaveLength(4)
})

test('a story file is found by name when its basename differs', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 'build-band' })
  files.set(`${CYCLE}/stories/29-build-band.md`, storyFile({ number: '29' }))
  await open($, on, files)

  expect(texts(await draw($))[0]).toBe('Story 29 ')
})

test('unreadable story file: one error-color line naming it', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 'gone' })
  files.set(`${CYCLE}/stories/other.md`, storyFile())
  await open($, on, files)

  const drawn = await draw($)

  expect(drawn).toEqual([{ text: "Can't read story file gone.md", color: 'error' }])
})

test('survey yields', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile())
  await open($, on, files)

  expect(texts(await draw($, true))).toEqual(ENGINE)
})

test('hidden band draws nothing', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile())
  await open($, on, files)

  await runCommand($, 'craft-progress')
  expect(texts(await draw($))).toEqual(ENGINE)

  await runCommand($, 'craft-progress')
  expect(texts(await draw($))[1]).toBe('building')
})

test('CRAFT_PROJECT_ROOT wins over the walk-up', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, '/work/p', { story: 's' })
  files.set('/work/p/.craft/cycles/c/stories/s.md', storyFile({ title: 'From the setting' }))
  seedProject(files, '/work/q', { story: 's' })
  files.set('/work/q/.craft/cycles/c/stories/s.md', storyFile({ title: 'From the walk' }))
  await open($, on, files, { sessionRoot: '/work/q/sub', env: { CRAFT_PROJECT_ROOT: '/work/p/' } })

  expect(texts(await draw($))[2]).toBe(' · From the setting')
})

test('the walk-up finds the nearest project when no setting names one', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, '/work/q', { story: 's' })
  files.set('/work/q/.craft/cycles/c/stories/s.md', storyFile({ title: 'From the walk' }))
  await open($, on, files, { sessionRoot: '/work/q/deep/er', env: { CRAFT_PROJECT_ROOT: '/nowhere' } })

  expect(texts(await draw($))[2]).toBe(' · From the walk')
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

  expect(texts(await draw($))[2]).toBe(' · Project b')
})

test('monorepo top with no pin follows the one active sub-project', async ($, on) => {
  const files: Files = new Map()
  seedMonorepo(files, ['a'])
  await open($, on, files, { sessionRoot: '/work/mono' })

  expect(texts(await draw($))[2]).toBe(' · Project a')
})

test('monorepo top with two active sub-projects and no pin draws nothing', async ($, on) => {
  const files: Files = new Map()
  seedMonorepo(files, ['a', 'b'])
  await open($, on, files, { sessionRoot: '/work/mono' })

  expect(texts(await draw($))).toEqual(ENGINE)
})

test('a -p session reads nothing and starts no timer', async ($, on) => {
  const files: Files = new Map()
  seedProject(files, ROOT, { story: 's' })
  files.set(`${CYCLE}/stories/s.md`, storyFile())
  const { clock, calls } = await open($, on, files, { surface: null })

  await clock.advance(3000)
  await clock.advance(3000)

  expect(calls).toEqual({ read: [], exists: [], list: [] })
  const answer = await runCommand($, 'craft-progress')
  expect(answer.text).toBe('Craft progress hidden.')
})
