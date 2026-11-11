import type { ElementTable, RenderElement } from 'claude-code'

import type { PlanStage, ProgressSnapshot } from '../types'

import { STAGES } from './take'

// The sheen: a two-letter highlight sweeps the view word left to right over
// frames 0 to 8, then the word rests for three frames; 5 frames a second.
export const FRAME_MS = 200
export const FRAMES = 12

// Theme keys only, never a color value. The building view takes the implementer's
// label green with the theme's success green for the sweep; the planning view
// takes the planning agent's blue pair.
export const BUILD_BASE = 'green_FOR_SUBAGENTS_ONLY'
export const BUILD_SWEEP = 'success'
export const PLAN_BASE = 'claudeBlue_FOR_SYSTEM_SPINNER'
export const PLAN_SWEEP = 'claudeBlueShimmer_FOR_SYSTEM_SPINNER'

const LOOKS = {
  building: { word: 'Building', base: BUILD_BASE, sweep: BUILD_SWEEP },
  planning: { word: 'Planning', base: PLAN_BASE, sweep: PLAN_SWEEP },
  'planning-many': { word: 'Planning', base: PLAN_BASE, sweep: PLAN_SWEEP },
} as const

// Whether the view word is moving: it follows the story, not the turn, so a
// story building in background agents keeps sweeping. Moving means no card is
// up, the view is the build or a planning view of a story this session is
// planning, and the state is not a finished one. The frame timer writes only
// while this holds.
export function moves(snap: ProgressSnapshot): boolean {
  if (snap.error || !snap.motion || snap.waitingOnUser) return false
  if (snap.view === 'building') return snap.storyStatus !== 'complete'
  return snap.owned && snap.stage !== 'ready'
}

const READY = 'ready to implement'
const HINT = ' · enter to implement (ctrl+x tab to focus)'

const stepName = (stage: PlanStage): string => stage.replace(/-/g, ' ')

// The state word after the label: where the build stands. The planning views
// and the ready row draw their own state slot.
function stateOf(snap: ProgressSnapshot): { text: string; color: string } {
  if (snap.view !== 'building') return { text: stepName(snap.stage as PlanStage), color: PLAN_BASE }
  if (snap.storyStatus === 'complete') return { text: 'complete', color: 'success' }
  return { text: snap.validating ? 'validating' : 'building', color: BUILD_BASE }
}

// The story a gated ready row waits behind: the slot's leading digits as
// `Story <n>`, else the slot's own name.
function whoHolds(slotHolder: string): string {
  const number = slotHolder.match(/^\d+/)?.[0]
  return number ? `Story ${number}` : slotHolder
}

// One ball per chunk: a green ring while it builds, a filled green ball once built.
const BALL = { done: '●', building: '○', waiting: '○' } as const
const BALL_COLOR = { done: 'success', building: 'success', waiting: 'inactive' } as const

// Line two of the building view.
function chunkRow(els: ElementTable, snap: ProgressSnapshot): RenderElement[] {
  const { Text } = els
  const total = snap.chunks.length
  const doneCount = snap.chunks.filter(c => c.state === 'done').length
  const current = snap.chunks.find(c => c.state === 'building')
  const detail =
    snap.storyStatus === 'complete'
      ? `all ${total} chunks done`
      : current
        ? `chunk ${current.n} of ${total}`
        : `${doneCount} of ${total} chunks done`
  return [
    ...snap.chunks.map(c => <Text key={String(c.n)} color={BALL_COLOR[c.state]}>{BALL[c.state]}</Text>),
    <Text key="detail">{` ${detail}`}</Text>,
  ]
}

// Line two of a planning view: one ball per step, the current step a green ring,
// the same ball language as the building view's current chunk.
function stepRow(els: ElementTable, snap: ProgressSnapshot): RenderElement[] {
  const { Text } = els
  const k = STAGES.indexOf(snap.stage as PlanStage) + 1
  const after = STAGES[k]
  return [
    ...STAGES.map((stage, i) => (
      <Text key={stage} color={i + 1 <= k ? 'success' : 'inactive'}>{i + 1 < k ? '●' : '○'}</Text>
    )),
    <Text key="step">{` step ${k} of ${STAGES.length} · ${snap.minutes}m`}</Text>,
    <Text key="next" color="inactive">{` · next: ${after ? stepName(after) : READY}`}</Text>,
  ]
}

// Line two of the view over several stories: one ring per story.
function groupRow(els: ElementTable, snap: ProgressSnapshot): RenderElement[] {
  const { Text } = els
  return [
    ...snap.stages.map((_, i) => <Text key={String(i)} color="success">○</Text>),
    <Text key="minutes">{` ${snap.minutes}m`}</Text>,
  ]
}

// Line two of the held ready row: every step done, and how to start the build
// when nothing is running.
function readyRow(els: ElementTable, snap: ProgressSnapshot): RenderElement[] {
  const { Text } = els
  return [
    ...STAGES.map(stage => <Text key={stage} color="success">●</Text>),
    <Text key="done">{` all ${STAGES.length} steps done`}</Text>,
    ...(snap.slotHolder === '' ? [<Text key="hint" color="inactive">{HINT}</Text>] : []),
  ]
}

// The state slot of line one: a word, the control on a ready row that nothing
// blocks, or the same words as plain text while a story is running.
function stateSlot(els: ElementTable, snap: ProgressSnapshot, onPress: () => void): RenderElement | null {
  const { Button, Text } = els
  if (snap.view === 'planning-many') return null
  if (snap.stage === 'ready') {
    if (snap.slotHolder !== '') {
      return <Text color="success" bold>{`${READY} · after ${whoHolds(snap.slotHolder)}`}</Text>
    }
    return (
      <Button label={READY} plain onPress={onPress}>
        <Text color="success" bold>{READY}</Text>
      </Button>
    )
  }
  const state = stateOf(snap)
  return <Text color={state.color} bold>{state.text}</Text>
}

function lineTwo(els: ElementTable, snap: ProgressSnapshot): RenderElement[] {
  if (snap.view === 'building') return chunkRow(els, snap)
  if (snap.view === 'planning-many') return groupRow(els, snap)
  return snap.stage === 'ready' ? readyRow(els, snap) : stepRow(els, snap)
}

// `onPress` runs when the ready row's control is pressed; the caller owns what it does.
export function draw(els: ElementTable, snap: ProgressSnapshot, frame: number, onPress: () => void): RenderElement {
  const { Box, Text } = els

  if (snap.error) {
    return <Text color="error">{snap.error}</Text>
  }

  const look = LOOKS[snap.view]
  const head = moves(snap) ? frame : -1
  // The head letter is bold in the sweep color, the letter behind it plain in
  // the sweep color, every other letter in the base color.
  const word = look.word.split('').map((ch, i) => (
    <Text key={String(i)} color={i === head || i === head - 1 ? look.sweep : look.base} bold={i === head}>
      {ch}
    </Text>
  ))
  const state = stateSlot(els, snap, onPress)

  return (
    <Box flexDirection="column" marginTop={1}>
      <Box>
        <Box flexShrink={0}>
          <Text color={look.base} bold>{'✶ '}</Text>
          {word}
          <Text>{' '}</Text>
          <Text bold>{snap.label}</Text>
          {state ? <Text>{' · '}</Text> : null}
          {state}
          {snap.waitingOnUser ? <Text color="text">{' · waiting on you'}</Text> : null}
        </Box>
        {snap.title ? <Text color="subtle" wrap="truncate-end">{` · ${snap.title}`}</Text> : null}
      </Box>
      <Box gap={1} paddingLeft={2}>
        {lineTwo(els, snap)}
      </Box>
    </Box>
  )
}
