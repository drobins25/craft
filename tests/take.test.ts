import { expect, test } from 'claude-code/testing'
import {
  blockReason,
  compose,
  describeChoice,
  field,
  frontmatter,
  motionOn,
  orderChoices,
  parseStageLines,
  readyToStart,
  stageOf,
  stateField,
  take,
  whoHolds,
} from '../hooks/take'
import type { BuildingFacts, DiskFacts, SessionFlags, StagedStory } from '../hooks/take'
import type { Choice, ProgressSnapshot } from '../types'
import { CLEARED_LINE, SET_LINE } from './fixtures/planning-stage-stdout'

const IDLE: SessionFlags = { waiting: 0, validating: false }

const building = (over: Partial<BuildingFacts> = {}): BuildingFacts => ({
  path: '/work/p/.craft/cycles/c/stories/s.md',
  label: 'Story 5',
  title: 'First title',
  storyStatus: 'active',
  chunks: [
    { n: 1, state: 'building' },
    { n: 2, state: 'waiting' },
  ],
  error: '',
  ...over,
})

const facts = (over: Partial<DiskFacts> = {}): DiskFacts => ({
  root: '/work/p',
  own: [],
  building: null,
  staged: [],
  heldComplete: null,
  heldReady: null,
  slot: '',
  motion: true,
  ...over,
})

test('a sibling module loads', () => {
  expect(typeof compose).toBe('function')
  expect(typeof take).toBe('function')
})

test('compose: no facts draws nothing', () => {
  expect(compose(null, IDLE, null, 0)).toBeNull()
})

test('compose: a project with nothing running draws nothing', () => {
  expect(compose(facts(), IDLE, null, 0)).toBeNull()
})

test('compose: the building view carries the story and the session flags', () => {
  const snap = compose(
    facts({ building: building(), slot: 's', motion: false }),
    { waiting: 2, validating: true },
    null,
    0,
  )

  expect(snap).toEqual({
    view: 'building',
    path: '/work/p/.craft/cycles/c/stories/s.md',
    label: 'Story 5',
    title: 'First title',
    storyStatus: 'active',
    chunks: [
      { n: 1, state: 'building' },
      { n: 2, state: 'waiting' },
    ],
    stage: '',
    stages: [],
    owned: false,
    slotHolder: 's',
    holdSlot: '',
    validating: true,
    waitingOnUser: true,
    motion: false,
    since: 0,
    minutes: 0,
    error: '',
  })
})

test('compose: waiting counts cards, so zero is not waiting', () => {
  const snap = compose(facts({ building: building() }), { ...IDLE, waiting: 0 }, null, 0)

  expect(snap?.waitingOnUser).toBe(false)
})

test('compose: a read error draws the error line and nothing else', () => {
  const snap = compose(
    facts({ building: building({ path: '', label: '', title: '', storyStatus: '', chunks: [], error: "Can't read story file x.md" }) }),
    IDLE,
    null,
    0,
  )

  expect(snap?.error).toBe("Can't read story file x.md")
  expect(snap?.chunks).toEqual([])
})

test('compose: with the story slot free, the finished story keeps its complete row', () => {
  const done = building({ storyStatus: 'complete', chunks: [{ n: 1, state: 'done' }] })

  const snap = compose(facts({ heldComplete: done }), IDLE, null, 0)

  expect(snap?.view).toBe('building')
  expect(snap?.storyStatus).toBe('complete')
  expect(snap?.slotHolder).toBe('')
})

test('compose: a story that is running wins over a held complete row', () => {
  const snap = compose(
    facts({ building: building(), heldComplete: building({ label: 'Story 4', storyStatus: 'complete' }) }),
    IDLE,
    null,
    0,
  )

  expect(snap?.label).toBe('Story 5')
})

test('compose is pure: the same inputs give equal snapshots', () => {
  const input = facts({ building: building() })

  expect(compose(input, IDLE, null, 5)).toEqual(compose(input, IDLE, null, 5))
})

test('frontmatter reads the leading block only', () => {
  expect(frontmatter('---\na: 1\n---\nbody\n---\nb: 2\n---')).toBe('a: 1')
  expect(frontmatter('no block here')).toBe('')
})

test('field strips quotes and control characters', () => {
  expect(field('title: "Hello\u001b there"', 'title')).toBe('Hello there')
  expect(field('title: x', 'missing')).toBe('')
})

test('stateField reads a shell assignment', () => {
  expect(stateField('A="1"\nCURRENT_STORY="s"\n', 'CURRENT_STORY')).toBe('s')
  expect(stateField('CURRENT_STORY=""\n', 'CURRENT_STORY')).toBe('')
  expect(stateField('', 'CURRENT_STORY')).toBe('')
})

test('motionOn: only a first key of exactly false turns motion off', () => {
  expect(motionOn('')).toBe(true)
  expect(motionOn('progress_band_motion: false\n')).toBe(false)
  expect(motionOn("progress_band_motion: 'false'\n")).toBe(false)
  expect(motionOn('progress_band_motion: true\n')).toBe(true)
  expect(motionOn('progress_band_motion: False\n')).toBe(true)
  expect(motionOn('progress_band_motion: false\nprogress_band_motion: true\n')).toBe(false)
  expect(motionOn('progress_band_motion: true\nprogress_band_motion: false\n')).toBe(true)
  expect(motionOn('  progress_band_motion: false\n')).toBe(true)
  expect(motionOn('# progress_band_motion: false\n')).toBe(true)
  expect(motionOn('progress_band_motion: false  # keep still\n')).toBe(false)
  expect(motionOn('progress_band_motion: true # on\n')).toBe(true)
})

const T_PATH = '/work/p/.craft/cycles/c/stories/t.md'
const staged = (name: string, stage: StagedStory['stage'] = 'planner'): StagedStory => ({
  path: `/work/p/.craft/cycles/c/stories/${name}.md`,
  label: `Story ${name}`,
  title: `Title ${name}`,
  stage,
})
const readyRow = { path: T_PATH, label: 'Story 6', title: 'Ready title' }

// The snapshot the band last drew: a planning view of this session's own story.
const heldOwn = (over: Partial<ProgressSnapshot> = {}): ProgressSnapshot => ({
  view: 'planning',
  path: T_PATH,
  label: 'Story 6',
  title: 'Ready title',
  storyStatus: '',
  chunks: [],
  stage: 'triage',
  stages: ['triage'],
  owned: true,
  slotHolder: '',
  holdSlot: '',
  validating: false,
  waitingOnUser: false,
  motion: true,
  since: 100,
  minutes: 0,
  error: '',
  ...over,
})

test('the parser reads the script\'s real lines', () => {
  expect(parseStageLines(`noise\n${SET_LINE}\nmore`)).toEqual({
    set: ['/work/p/.craft/cycles/c/stories/t.md'],
    cleared: [],
  })
  expect(parseStageLines(CLEARED_LINE)).toEqual({ set: [], cleared: ['/work/p/.craft/cycles/c/stories/t.md'] })
  expect(parseStageLines(`${SET_LINE}\r\n${CLEARED_LINE}\r\n`)).toEqual({
    set: ['/work/p/.craft/cycles/c/stories/t.md'],
    cleared: ['/work/p/.craft/cycles/c/stories/t.md'],
  })
})

test('the parser ignores lines that only look like the script\'s', () => {
  expect(parseStageLines('Planning stage set to Planner: /a.md')).toEqual({ set: [], cleared: [] })
  expect(parseStageLines('echo Planning stage cleared: /a.md')).toEqual({ set: [], cleared: [] })
  expect(parseStageLines('')).toEqual({ set: [], cleared: [] })
})

test('stageOf: only the six stage values are a stage', () => {
  expect(stageOf('---\nplanning_stage: triage\n---\n')).toBe('triage')
  expect(stageOf('---\nplanning_stage: "plan-check"\n---\n')).toBe('plan-check')
  expect(stageOf('---\nplanning_stage: bogus\n---\n')).toBeNull()
  expect(stageOf('---\nplanning_stage: ready\n---\n')).toBeNull()
  expect(stageOf('---\nstatus: ready\n---\nplanning_stage: planner\n')).toBeNull()
  expect(stageOf('---\nstatus: ready\n---\n')).toBeNull()
})

test('compose: one own story draws its planning view, owned', () => {
  const snap = compose(facts({ own: [staged('t', 'triage')] }), IDLE, null, 500)

  expect(snap).toMatchObject({
    view: 'planning',
    path: staged('t').path,
    label: 'Story t',
    title: 'Title t',
    stage: 'triage',
    stages: ['triage'],
    owned: true,
    chunks: [],
    since: 500,
    minutes: 0,
  })
})

test('compose: several own stories draw the many view over them, owned, in file order', () => {
  const snap = compose(facts({ own: [staged('b', 'triage'), staged('a')] }), IDLE, null, 0)

  expect(snap).toMatchObject({
    view: 'planning-many',
    label: '2 stories',
    title: '',
    path: '',
    stage: '',
    stages: ['planner', 'triage'],
    owned: true,
  })
})

test('compose: this session\'s story wins over the build', () => {
  const snap = compose(facts({ own: [staged('t')], building: building(), slot: 's' }), IDLE, null, 0)

  expect(snap?.view).toBe('planning')
  expect(snap?.owned).toBe(true)
  expect(snap?.slotHolder).toBe('s')
})

test('compose: the build wins over another session\'s planning', () => {
  const snap = compose(facts({ building: building(), staged: [staged('t')], slot: 's' }), IDLE, null, 0)

  expect(snap?.view).toBe('building')
})

test('compose: one staged story draws planning, not owned', () => {
  const snap = compose(facts({ staged: [staged('t', 'direction')] }), IDLE, null, 0)

  expect(snap).toMatchObject({ view: 'planning', stage: 'direction', owned: false })
})

test('compose: several staged stories with none owned draw Planning N stories, not owned', () => {
  const snap = compose(facts({ staged: [staged('b'), staged('a', 'triage')] }), IDLE, null, 0)

  expect(snap).toMatchObject({ view: 'planning-many', label: '2 stories', owned: false, stages: ['triage', 'planner'] })
})

test('compose: planning replaces the held complete row', () => {
  const done = building({ storyStatus: 'complete', chunks: [{ n: 1, state: 'done' }] })

  expect(compose(facts({ heldComplete: done }), IDLE, null, 0)?.view).toBe('building')
  expect(compose(facts({ heldComplete: done, staged: [staged('t')] }), IDLE, null, 0)?.view).toBe('planning')
})

test('compose: the clock restarts when the story shown changes and carries when it does not', () => {
  const first = compose(facts({ staged: [staged('t')] }), IDLE, null, 1000)
  const sameStory = compose(facts({ staged: [staged('t', 'triage')] }), IDLE, first, 1000 + 5 * 60000 + 59999)
  const otherStory = compose(facts({ staged: [staged('u')] }), IDLE, sameStory, 1000 + 5 * 60000 + 59999)

  expect(first).toMatchObject({ since: 1000, minutes: 0 })
  expect(sameStory).toMatchObject({ since: 1000, minutes: 5 })
  expect(otherStory).toMatchObject({ since: 1000 + 5 * 60000 + 59999, minutes: 0 })
})

test('compose: the many view keys its clock on the group, not a story', () => {
  const first = compose(facts({ staged: [staged('a'), staged('b')] }), IDLE, null, 1000)
  const again = compose(facts({ staged: [staged('a'), staged('c')] }), IDLE, first, 61000)

  expect(again).toMatchObject({ view: 'planning-many', since: 1000, minutes: 1 })
})

test('compose: the building view starts no clock', () => {
  const snap = compose(facts({ building: building(), slot: 's' }), IDLE, heldOwn(), 999)

  expect(snap).toMatchObject({ view: 'building', since: 0, minutes: 0 })
})

test('compose: the held ready row, from a live own step, with the slot free', () => {
  const snap = compose(facts({ heldReady: readyRow }), IDLE, heldOwn(), 900)

  expect(snap).toMatchObject({
    view: 'planning',
    stage: 'ready',
    owned: true,
    path: T_PATH,
    label: 'Story 6',
    title: 'Ready title',
    slotHolder: '',
    holdSlot: '',
    chunks: [],
    since: 100,
  })
})

test('compose: the hold\'s slot rule', () => {
  const formedBehind = compose(facts({ heldReady: readyRow, building: building(), slot: '29-x' }), IDLE, heldOwn(), 0)
  expect(formedBehind).toMatchObject({ view: 'planning', stage: 'ready', slotHolder: '29-x', holdSlot: '29-x' })

  const stays = compose(
    facts({ heldReady: readyRow, building: building(), slot: '29-x' }),
    IDLE,
    heldOwn({ stage: 'ready', stages: [], holdSlot: '29-x', slotHolder: '29-x' }),
    0,
  )
  expect(stays).toMatchObject({ view: 'planning', stage: 'ready', slotHolder: '29-x', holdSlot: '29-x' })

  const freed = compose(
    facts({ heldReady: readyRow }),
    IDLE,
    heldOwn({ stage: 'ready', stages: [], holdSlot: '29-x', slotHolder: '29-x' }),
    0,
  )
  expect(freed).toMatchObject({ stage: 'ready', slotHolder: '', holdSlot: '' })

  const otherStory = compose(
    facts({ heldReady: readyRow, building: building(), slot: '30-y' }),
    IDLE,
    heldOwn({ stage: 'ready', stages: [], holdSlot: '29-x', slotHolder: '29-x' }),
    0,
  )
  expect(otherStory?.view).toBe('building')

  const startedFromFree = compose(
    facts({ heldReady: readyRow, building: building(), slot: '30-y' }),
    IDLE,
    heldOwn({ stage: 'ready', stages: [] }),
    0,
  )
  expect(startedFromFree?.view).toBe('building')
})

test('compose: planning starting elsewhere replaces the ready row', () => {
  const snap = compose(
    facts({ heldReady: readyRow, staged: [staged('u')] }),
    IDLE,
    heldOwn({ stage: 'ready', stages: [] }),
    0,
  )

  expect(snap).toMatchObject({ view: 'planning', owned: false, path: staged('u').path })
})

test('compose: an own story that plans again wins over its ready row', () => {
  const snap = compose(
    facts({ heldReady: readyRow, own: [staged('t')] }),
    IDLE,
    heldOwn({ stage: 'ready', stages: [] }),
    0,
  )

  expect(snap).toMatchObject({ stage: 'planner', owned: true })
})

const story = (status: string, extra = ''): string => `---\nstatus: ${status}\n${extra}---\nbody\n`
const choice = (file: string, number = '', dir = '/work/p/.craft/cycles/c/stories'): Choice => ({
  path: `${dir}/${file}`,
  label: number ? `Story ${number}` : file.replace(/\.md$/, ''),
  title: '',
})
const labels = (list: Choice[]): string[] => list.map(c => c.label)

test('orderChoices puts the row\'s own story first, then by story number', () => {
  const own = choice('6-own.md', '6')
  const list = orderChoices(own, [choice('9-b.md', '9'), choice('2-a.md', '2')])
  expect(labels(list)).toEqual(['Story 6', 'Story 2', 'Story 9'])
})

test('orderChoices lists the own story once when it is also in the cycle', () => {
  const own = choice('6-own.md', '6')
  const list = orderChoices(own, [choice('2-a.md', '2'), choice('6-own.md', '6')])
  expect(labels(list)).toEqual(['Story 6', 'Story 2'])
})

test('orderChoices puts unnumbered stories last, by file name', () => {
  const list = orderChoices(null, [choice('zeta.md'), choice('10-x.md', '10'), choice('alpha.md'), choice('3-y.md', '3')])
  expect(labels(list)).toEqual(['Story 3', 'Story 10', 'alpha', 'zeta'])
})

test('orderChoices falls back to the file name\'s leading digits', () => {
  const list = orderChoices(null, [choice('12-b.md'), choice('4-a.md')])
  expect(labels(list)).toEqual(['4-a', '12-b'])
})

test('orderChoices with no own story starts at the lowest number', () => {
  const list = orderChoices(null, [choice('5-e.md', '5'), choice('1-a.md', '1')])
  expect(list[0]?.label).toBe('Story 1')
})

test('readyToStart: ready with no stage is true; planning, active, or ready with a stage is false', () => {
  expect(readyToStart(story('ready'))).toBe(true)
  expect(readyToStart(story('ready', 'planning_stage:\n'))).toBe(true)
  expect(readyToStart(story('planning'))).toBe(false)
  expect(readyToStart(story('active'))).toBe(false)
  expect(readyToStart(story('ready', 'planning_stage: triage\n'))).toBe(false)
  expect(readyToStart('')).toBe(false)
})

test('describeChoice falls back to the file name as label', () => {
  const plain = describeChoice('/work/p/.craft/backlog/idea.md', story('ready', 'title: "An idea"\n'))
  expect(plain).toEqual({ path: '/work/p/.craft/backlog/idea.md', label: 'idea', title: 'An idea' })
  const numbered = describeChoice('/work/p/x/2-a.md', story('ready', 'story_number: 2\ntitle: T\x1b[31m\n'))
  expect(numbered.label).toBe('Story 2')
  expect(numbered.title).toBe('T[31m')
})

const CYCLE = '/work/p/.craft/cycles/c/stories'

test('blockReason: a held slot wins over every other reason', () => {
  const c = choice('2-a.md', '2')
  expect(blockReason(c, '', '/other', '', '7-next')).toBe('Story 7 is building')
})

test('blockReason: a cycle story outside the active cycle or unreadable is out of the cycle', () => {
  const moved = choice('2-a.md', '2', '/work/p/.craft/cycles/d/stories')
  expect(blockReason(moved, story('ready'), '/other', CYCLE, '')).toBe('Story 2 isn\'t in the active cycle anymore')
  const gone = choice('2-a.md', '2')
  expect(blockReason(gone, '', '/other', CYCLE, '')).toBe('Story 2 isn\'t in the active cycle anymore')
  expect(blockReason(gone, story('ready'), '/other', '', '')).toBe('Story 2 isn\'t in the active cycle anymore')
})

test('blockReason: the row\'s own story is exempt from the cycle check', () => {
  const own = choice('x.md', '', '/work/p/.craft/backlog')
  expect(blockReason(own, story('ready'), own.path, '', '')).toBe('')
  expect(blockReason(own, story('ready'), own.path, CYCLE, '')).toBe('')
})

test('blockReason: not ready', () => {
  const c = choice('2-a.md', '2')
  expect(blockReason(c, story('active'), '/other', CYCLE, '')).toBe('Story 2 isn\'t ready anymore')
  expect(blockReason(c, story('ready'), '/other', CYCLE, '')).toBe('')
})

test('whoHolds still renders `Story 29` for `29-build-progress-band` and the raw name otherwise', () => {
  expect(whoHolds('29-build-progress-band')).toBe('Story 29')
  expect(whoHolds('build-it')).toBe('build-it')
})
