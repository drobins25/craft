import type { EngineInterface } from 'claude-code'

import type { PlanStage, ProgressChunk, ProgressSnapshot } from '../types'

const MAX_CHUNKS = 99

// What a story file says about the build it is part of.
export type BuildingFacts = {
  path: string
  label: string
  title: string
  storyStatus: string
  chunks: ProgressChunk[]
  error: string
}

export type StagedStory = { path: string; label: string; title: string; stage: PlanStage }

// One scanned story file: the stamp it was read at, and the staged story it held.
export type ScanEntry = { stamp: string; story: StagedStory | null }

// Everything one pass reads from disk. `compose` turns it, with the session's
// flags, into the snapshot the band draws.
export type DiskFacts = {
  root: string
  own: StagedStory[]
  building: BuildingFacts | null
  staged: StagedStory[]
  heldComplete: BuildingFacts | null
  heldReady: { path: string; label: string; title: string } | null
  // The cycle's raw current-story value; '' when no story holds the slot.
  slot: string
  motion: boolean
}

// What the session knows that no file says: a model turn is running, how many
// question cards are open, a chunk validator or the claims audit is running.
export type SessionFlags = { working: boolean; waiting: number; validating: boolean }

function trimSlashes(path: string): string {
  return path.replace(/\/+$/, '')
}

// The leading `---` block of a story or registry file; empty when there is none.
export function frontmatter(text: string): string {
  return text.match(/^---\r?\n([\s\S]*?)\r?\n---/)?.[1] ?? ''
}

// Drawn text never carries a control character, so a crafted title or state
// value cannot reach the terminal as an escape sequence.
function clean(value: string): string {
  return value.replace(/[\u0000-\u001f\u007f]/g, '')
}

export function field(block: string, key: string): string {
  const m = block.match(new RegExp(`^${key}:[ \\t]*(.*)$`, 'm'))
  return clean(m?.[1] ?? '').trim().replace(/^["']|["']$/g, '')
}

// Craft's state files are shell assignments, KEY="value", one per line.
export function stateField(text: string, key: string): string {
  const m = text.match(new RegExp(`^${key}="?([^"\\n]*)"?\\s*$`, 'm'))
  return clean(m?.[1] ?? '').trim()
}

// The sheen is on unless the project's settings file says `progress_band_motion: false`;
// a missing file or key, or any other value, leaves it on.
export function motionOn(settings: string): boolean {
  return field(settings, 'progress_band_motion') !== 'false'
}

async function readOr($: EngineInterface, path: string): Promise<string> {
  try {
    return await $.fs.read(path)
  } catch {
    return ''
  }
}

async function listOr($: EngineInterface, path: string): Promise<string[]> {
  try {
    return (await $.fs.list(path)).map(entry => entry.name)
  } catch {
    return []
  }
}

export const STAGES: readonly PlanStage[] = ['content-check', 'alignment-check', 'direction', 'planner', 'plan-check', 'triage']

// A story's planning step is its `planning_stage` field when that is one of the
// six steps; nothing else on the story says where planning stands.
export function stageOf(text: string): PlanStage | null {
  const value = field(frontmatter(text), 'planning_stage')
  return STAGES.find(stage => stage === value) ?? null
}

// The paths the planning-stage script named in its output, split by what it did.
export function parseStageLines(stdout: string): { set: string[]; cleared: string[] } {
  const found = { set: [] as string[], cleared: [] as string[] }
  for (const line of stdout.split(/\r?\n/)) {
    const m = line.match(/^Planning stage (set to [a-z-]+|cleared): (\/.+)$/)
    if (!m?.[2]) continue
    if (m[1] === 'cleared') found.cleared.push(m[2])
    else found.set.push(m[2])
  }
  return found
}

// The nearest folder up from `start` holding craft's state: an initialized
// project first, then a folder with a project description.
async function nearestCraftFolder($: EngineInterface, start: string): Promise<string> {
  for (const marker of ['/.craft/.global-state', '/.craft/project.md']) {
    for (let dir = start; dir && dir !== '/'; dir = dir.slice(0, dir.lastIndexOf('/'))) {
      if (await $.fs.exists(dir + marker)) return dir
    }
  }
  return ''
}

// Where the project lives, found the way craft's own scripts find it: the
// project-root setting, else the nearest folder up from the session with craft's
// state. At a monorepo top with registered sub-projects, the pinned project,
// else the one sub-project with an active cycle, else the top itself. Craft
// also requires that top to be the repository root; a registry stands for it here.
export async function findRoot($: EngineInterface): Promise<string> {
  const fromEnv = trimSlashes((await $.env.get('CRAFT_PROJECT_ROOT')) ?? '')
  if (fromEnv && (await $.fs.exists(`${fromEnv}/.craft`))) return fromEnv

  const top = await nearestCraftFolder($, trimSlashes(await $.session.root()))
  if (!top) return ''

  const subProjects: string[] = []
  for (const name of await listOr($, `${top}/.craft/projects`)) {
    if (!name.endsWith('.md')) continue
    const relative = trimSlashes(field(frontmatter(await readOr($, `${top}/.craft/projects/${name}`)), 'path'))
    if (relative && (await $.fs.exists(`${top}/${relative}/.craft`))) subProjects.push(`${top}/${relative}`)
  }
  if (subProjects.length === 0) return top

  const pinned = trimSlashes(((await readOr($, `${top}/.craft/.pinned-project`)).split('\n')[0] ?? '').trim())
  if (pinned && (await $.fs.exists(`${pinned}/.craft`))) return pinned

  const active: string[] = []
  for (const sub of subProjects) {
    if (stateField(await readOr($, `${sub}/.craft/.global-state`), 'ACTIVE_CYCLE')) active.push(sub)
  }
  return active.length === 1 ? (active[0] ?? top) : top
}

// The story's file: named exactly by the cycle's current story, else the first
// story file whose name contains it (the way craft's own scripts find it).
async function findStoryFile($: EngineInterface, storiesDir: string, current: string): Promise<string> {
  const exact = `${storiesDir}/${current}.md`
  if (await readOr($, exact)) return exact
  const match = (await listOr($, storiesDir)).sort().find(name => name.endsWith('.md') && name.includes(current))
  return match ? `${storiesDir}/${match}` : ''
}

// Chunk n is done once its story is complete or craft has moved past it, building
// while it is the active story's current chunk, and waiting otherwise.
function chunkStates(storyStatus: string, count: number, chunksComplete: number, currentChunk: number): ProgressChunk[] {
  return Array.from({ length: count }, (_, i) => {
    const n = i + 1
    let state: ProgressChunk['state'] = 'waiting'
    if (storyStatus === 'complete' || n <= chunksComplete || (currentChunk > 0 && n < currentChunk)) state = 'done'
    else if (storyStatus === 'active' && n === currentChunk) state = 'building'
    return { n, state }
  })
}

function describeStory(path: string, text: string, currentChunk: number): BuildingFacts {
  const meta = frontmatter(text)
  const storyStatus = field(meta, 'status')
  const number = field(meta, 'story_number')
  const headings = (text.match(/^### Chunk \d+:/gm) ?? []).length
  // A story's chunk count is bounded so a bad frontmatter value cannot make
  // every refresh allocate and draw an unbounded row of balls.
  const total = Math.min(parseInt(field(meta, 'chunks_total'), 10) || headings, MAX_CHUNKS)
  const chunksComplete = parseInt(field(meta, 'chunks_complete'), 10) || 0
  const basename = (path.split('/').pop() ?? '').replace(/\.md$/, '')

  return {
    path,
    label: number ? `Story ${number}` : basename,
    title: field(meta, 'title'),
    storyStatus,
    chunks: chunkStates(storyStatus, total, chunksComplete, currentChunk),
    error: '',
  }
}

function describeStaged(path: string, text: string, stage: PlanStage): StagedStory {
  const meta = frontmatter(text)
  const number = field(meta, 'story_number')
  const basename = (path.split('/').pop() ?? '').replace(/\.md$/, '')
  return { path, label: number ? `Story ${number}` : basename, title: field(meta, 'title'), stage }
}

const fileName = (path: string): string => path.split('/').pop() ?? ''
const byFileName = (a: { path: string }, b: { path: string }): number => {
  const [x, y] = [fileName(a.path), fileName(b.path)]
  return x < y ? -1 : x > y ? 1 : 0
}

// The session's own stories that still carry a stage. A path whose file lost its
// field or cannot be read is left out; the session's own set forgets it only
// when the planning-stage script says so.
async function readOwn($: EngineInterface, paths: readonly string[]): Promise<StagedStory[]> {
  const stories: StagedStory[] = []
  for (const path of new Set(paths)) {
    const text = await readOr($, path)
    const stage = text ? stageOf(text) : null
    if (stage) stories.push(describeStaged(path, text, stage))
  }
  return stories.sort(byFileName)
}

// The story this session planned, read again after its stage left: it is a ready
// row only while the file carries no stage and reads ready.
async function readHeldReady(
  $: EngineInterface,
  held: ProgressSnapshot | null,
  own: readonly string[],
): Promise<DiskFacts['heldReady']> {
  if (!held || held.view !== 'planning' || !held.owned || !own.includes(held.path)) return null
  const text = await readOr($, held.path)
  const meta = frontmatter(text)
  if (!text || field(meta, 'planning_stage') !== '' || field(meta, 'status') !== 'ready') return null
  return { path: held.path, label: held.label, title: field(meta, 'title') }
}

// Every story in the cycle that carries a stage. A file is read again only when
// its modified time or size changed since the cache saw it.
async function scanStaged($: EngineInterface, dir: string, cache: Map<string, ScanEntry>): Promise<StagedStory[]> {
  let listing
  try {
    listing = await $.fs.list(dir)
  } catch {
    return []
  }
  const files = listing.filter(entry => entry.kind === 'file' && entry.name.endsWith('.md'))
  const staged: StagedStory[] = []
  const seen = new Set<string>()
  for (const entry of files) {
    const path = `${dir}/${entry.name}`
    const stamp = `${entry.mtimeMs}:${entry.size}`
    seen.add(path)
    let cached = cache.get(path)
    if (!cached || cached.stamp !== stamp) {
      const text = await readOr($, path)
      const stage = text ? stageOf(text) : null
      cached = { stamp, story: stage ? describeStaged(path, text, stage) : null }
      // A read that failed is tried again on the next pass.
      if (text) cache.set(path, cached)
    }
    if (cached.story) staged.push(cached.story)
  }
  for (const path of cache.keys()) if (path.startsWith(`${dir}/`) && !seen.has(path)) cache.delete(path)
  return staged.sort(byFileName)
}

// When craft has cleared its current story, a story that was finished keeps its
// complete row; anything else, or a file that cannot be read, draws nothing.
async function holdFinished(
  $: EngineInterface,
  root: string,
  held: ProgressSnapshot | null,
): Promise<BuildingFacts | null> {
  if (!held || held.view !== 'building' || !held.path.startsWith(`${root}/`)) return null
  const text = await readOr($, held.path)
  if (field(frontmatter(text), 'status') !== 'complete') return null
  return describeStory(held.path, text, 0)
}

// The cycle's raw current-story value, read fresh; '' when free or unreadable.
export async function readSlot($: EngineInterface): Promise<string> {
  const root = await findRoot($)
  if (!root) return ''
  const cycleName = stateField(await readOr($, `${root}/.craft/.global-state`), 'ACTIVE_CYCLE')
  if (!cycleName) return ''
  return stateField(await readOr($, `${root}/.craft/cycles/${cycleName}/.state`), 'CURRENT_STORY')
}

// What the project's files say, read lazily in precedence order: this session's
// own planning stories, then the cycle's current story, then every staged story,
// then the held rows. A tier is not read once a higher one is found. Own stories
// and the held ready row are read before the cycle is looked up, so a story
// planned from the backlog still draws. Only a named current story whose file
// cannot be read draws an error.
export async function take(
  $: EngineInterface,
  input: { held: ProgressSnapshot | null; own: readonly string[]; cache: Map<string, ScanEntry> },
): Promise<DiskFacts | null> {
  const root = await findRoot($)
  if (!root) return null

  const motion = motionOn(await readOr($, `${root}/.craft/settings.yaml`))
  const facts: DiskFacts = {
    root,
    own: [],
    building: null,
    staged: [],
    heldComplete: null,
    heldReady: null,
    slot: '',
    motion,
  }

  facts.own = await readOwn($, input.own.filter(path => path.startsWith(`${root}/.craft/`)))
  if (facts.own.length > 0) return facts

  facts.heldReady = await readHeldReady($, input.held, input.own)
  const cycleName = stateField(await readOr($, `${root}/.craft/.global-state`), 'ACTIVE_CYCLE')
  if (!cycleName) return facts.heldReady ? facts : null

  const cycle = `${root}/.craft/cycles/${cycleName}`
  const state = await readOr($, `${cycle}/.state`)
  facts.slot = stateField(state, 'CURRENT_STORY')

  if (facts.slot) {
    const path = await findStoryFile($, `${cycle}/stories`, facts.slot)
    const text = path ? await readOr($, path) : ''
    facts.building = text
      ? describeStory(path, text, parseInt(stateField(state, 'CURRENT_CHUNK'), 10) || 0)
      : { path: '', label: '', title: '', storyStatus: '', chunks: [], error: `Can't read story file ${facts.slot}.md` }
    return facts
  }

  facts.staged = await scanStaged($, `${cycle}/stories`, input.cache)
  if (facts.staged.length === 0) facts.heldComplete = await holdFinished($, root, input.held)
  return facts
}

// The story the clock belongs to: a planning view's story, or the group of
// several. The building view has no clock.
function clockKey(snap: ProgressSnapshot | null): string | null {
  if (!snap) return null
  if (snap.view === 'planning') return snap.path
  return snap.view === 'planning-many' ? 'many' : null
}

// The slot value the held ready row waits behind, or null once the row must go.
// A row formed while a story was running keeps waiting behind that story; a free
// slot frees it; any other story taking the slot means building began.
function readyHold(facts: DiskFacts, held: ProgressSnapshot | null): string | null {
  if (!facts.slot) return ''
  if (held?.stage !== 'ready') return facts.slot
  return held.holdSlot !== '' && held.holdSlot === facts.slot ? held.holdSlot : null
}

// The one place the view is chosen: from what the disk says and what the
// session knows. Pure, so every precedence row is tested without an engine.
export function compose(
  facts: DiskFacts | null,
  flags: SessionFlags,
  held: ProgressSnapshot | null,
  now: number,
): ProgressSnapshot | null {
  if (!facts) return null

  const common = {
    slotHolder: facts.slot,
    validating: flags.validating,
    waitingOnUser: flags.waiting > 0,
    working: flags.working,
    motion: facts.motion,
    error: '',
  }
  // The minutes since this story's planning first showed; the clock starts over
  // whenever the story shown is not the one the last snapshot showed.
  const clock = (key: string) => {
    const since = clockKey(held) === key && held ? held.since : now
    return { since, minutes: Math.floor((now - since) / 60000) }
  }
  const planning = (list: StagedStory[], owned: boolean): ProgressSnapshot => {
    const stories = [...list].sort(byFileName)
    const [only] = stories
    if (only && stories.length === 1) {
      return {
        ...common,
        view: 'planning',
        path: only.path,
        label: only.label,
        title: only.title,
        storyStatus: '',
        chunks: [],
        stage: only.stage,
        stages: [only.stage],
        owned,
        holdSlot: '',
        ...clock(only.path),
      }
    }
    return {
      ...common,
      view: 'planning-many',
      path: '',
      label: `${stories.length} stories`,
      title: '',
      storyStatus: '',
      chunks: [],
      stage: '',
      stages: stories.map(story => story.stage),
      owned,
      holdSlot: '',
      ...clock('many'),
    }
  }
  const ready = (row: NonNullable<DiskFacts['heldReady']>, holdSlot: string): ProgressSnapshot => ({
    ...common,
    view: 'planning',
    path: row.path,
    label: row.label,
    title: row.title,
    storyStatus: '',
    chunks: [],
    stage: 'ready',
    stages: [],
    owned: true,
    holdSlot,
    ...clock(row.path),
  })
  const building = (shown: BuildingFacts): ProgressSnapshot => ({
    ...common,
    view: 'building',
    ...shown,
    stage: '',
    stages: [],
    owned: false,
    holdSlot: '',
    since: 0,
    minutes: 0,
  })

  if (facts.own.length > 0) return planning(facts.own, true)

  const hold = facts.heldReady ? readyHold(facts, held) : null
  // A row that formed while a story was running stays above that story's build.
  if (facts.heldReady && facts.building && hold) return ready(facts.heldReady, hold)
  if (facts.building) return building(facts.building)
  if (facts.staged.length > 0) return planning(facts.staged, false)
  if (facts.heldReady && hold !== null) return ready(facts.heldReady, hold)
  if (facts.heldComplete) return building(facts.heldComplete)
  return null
}
