import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { ProgressChunk, ProgressSnapshot } from '../types'

// The band's two session-only values: whether the user hid it, and the story
// snapshot it draws. Nothing here is written to disk.
export const progressHidden = atom({ plugin: 'craft', key: 'progressHidden' } as const, false)
export const progress = atom({ plugin: 'craft', key: 'progress' } as const, null, {
  shape: 'progress-1',
})

const REFRESH_MS = 3000

function trimSlashes(path: string): string {
  return path.replace(/\/+$/, '')
}

// The leading `---` block of a story or registry file; empty when there is none.
function frontmatter(text: string): string {
  return text.match(/^---\r?\n([\s\S]*?)\r?\n---/)?.[1] ?? ''
}

function field(block: string, key: string): string {
  const m = block.match(new RegExp(`^${key}:[ \\t]*(.*)$`, 'm'))
  return (m?.[1] ?? '').trim().replace(/^["']|["']$/g, '')
}

// Craft's state files are shell assignments, KEY="value", one per line.
function stateField(text: string, key: string): string {
  const m = text.match(new RegExp(`^${key}="?([^"\\n]*)"?\\s*$`, 'm'))
  return (m?.[1] ?? '').trim()
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
async function findRoot($: EngineInterface): Promise<string> {
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

function describeStory(path: string, text: string, currentChunk: number): ProgressSnapshot {
  const meta = frontmatter(text)
  const storyStatus = field(meta, 'status')
  const number = field(meta, 'story_number')
  const headings = (text.match(/^### Chunk \d+:/gm) ?? []).length
  const count = parseInt(field(meta, 'chunks_total'), 10) || headings
  const chunksComplete = parseInt(field(meta, 'chunks_complete'), 10) || 0
  const basename = (path.split('/').pop() ?? '').replace(/\.md$/, '')

  return {
    path,
    label: number ? `Story ${number}` : basename,
    title: field(meta, 'title'),
    storyStatus,
    chunks: chunkStates(storyStatus, count, chunksComplete, currentChunk),
    error: '',
  }
}

// When craft has cleared its current story, a story that was finished keeps its
// complete row; anything else, or a file that cannot be read, draws nothing.
async function holdFinished(
  $: EngineInterface,
  root: string,
  held: ProgressSnapshot | null,
): Promise<ProgressSnapshot | null> {
  if (!held || !held.path.startsWith(`${root}/`)) return null
  const text = await readOr($, held.path)
  if (field(frontmatter(text), 'status') !== 'complete') return null
  return describeStory(held.path, text, 0)
}

// Where the build stands, from craft's own state. Every early exit is quiet:
// only a named current story whose file cannot be read draws an error.
async function take($: EngineInterface, held: ProgressSnapshot | null): Promise<ProgressSnapshot | null> {
  const root = await findRoot($)
  if (!root) return null

  const cycleName = stateField(await readOr($, `${root}/.craft/.global-state`), 'ACTIVE_CYCLE')
  if (!cycleName) return null

  const cycle = `${root}/.craft/cycles/${cycleName}`
  const state = await readOr($, `${cycle}/.state`)
  const current = stateField(state, 'CURRENT_STORY')
  if (!current) return holdFinished($, root, held)

  const path = await findStoryFile($, `${cycle}/stories`, current)
  const text = path ? await readOr($, path) : ''
  if (!text) {
    return {
      path: '',
      label: '',
      title: '',
      storyStatus: '',
      chunks: [],
      error: `Can't read story file ${current}.md`,
    }
  }
  return describeStory(path, text, parseInt(stateField(state, 'CURRENT_CHUNK'), 10) || 0)
}

// Re-reads craft's state and stores the snapshot only when it changed, since
// every write redraws the band. Runs in a session's timer, so it never throws.
async function refresh($: EngineInterface): Promise<void> {
  try {
    const held = await read($, progress)
    const latest = await take($, held)
    if (JSON.stringify(latest) !== JSON.stringify(held)) await update($, progress, () => latest)
  } catch {
    // A failed read leaves the band as it was; the next tick tries again.
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'craft-progress',
      description: "Show or hide craft's build progress above the prompt",
    })
    // A -p run or the SDK has no surface to draw on: read nothing, start no timer.
    if (e.surface !== null) {
      await refresh($)
      $.clock.every(REFRESH_MS, () => {
        void refresh($)
      })
    }

    return next(e)
  })

  on('command.run', { command: 'craft-progress' }, async $ => {
    const hidden = await update($, progressHidden, was => !was)

    return { text: hidden ? 'Craft progress hidden.' : 'Craft progress shown.' }
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, progress)
    if (e.props.hasSurvey || !snap || (await read($, progressHidden))) return next(e)
    const { Box, Text } = $.ui.resolve(e)

    if (snap.error) {
      return <Text color="error">{snap.error}</Text>
    }

    const total = snap.chunks.length
    const doneCount = snap.chunks.filter(c => c.state === 'done').length
    const building = snap.chunks.find(c => c.state === 'building')
    const isComplete = snap.storyStatus === 'complete'
    const label = isComplete ? 'complete' : building ? 'building' : snap.storyStatus || 'ready'
    const labelColor = isComplete ? 'success' : building ? 'warning' : 'suggestion'
    // One ball per chunk: a green ring while it builds, a filled green ball once built.
    const ball = { done: '●', building: '○', waiting: '○' } as const
    const ballColor = { done: 'success', building: 'success', waiting: 'inactive' } as const
    const detail = isComplete
      ? `all ${total} chunks done`
      : building
        ? `chunk ${building.n} of ${total}`
        : `${doneCount} of ${total} chunks done`

    return (
      <Box flexDirection="column" marginTop={1}>
        <Box>
          <Box flexShrink={0}>
            <Text color="claude" bold>{`${snap.label} `}</Text>
            <Text color={labelColor} bold>{label}</Text>
          </Box>
          {snap.title ? <Text color="subtle" wrap="truncate-end">{` · ${snap.title}`}</Text> : null}
        </Box>
        <Box gap={1}>
          {snap.chunks.map(c => (
            <Text key={String(c.n)} color={ballColor[c.state]}>{ball[c.state]}</Text>
          ))}
          <Text>{` ${detail}`}</Text>
        </Box>
      </Box>
    )
  })
}
