import type { ElementTable, RenderElement } from 'claude-code'

import type { Choice, Chooser, PlanStage, ProgressSnapshot } from '../types'

import { STAGES, whoHolds } from './take'

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
const HINT = ' · enter to choose a story (ctrl+x tab to focus)'

// Line two: the balls and words that never shrink, and the grey hint that may
// be cut short on a narrow terminal.
type LineTwo = { whole: RenderElement[]; hint: string }

const stepName = (stage: PlanStage): string => stage.replace(/-/g, ' ')

// The state word after the label: where the build stands. The planning views
// and the ready row draw their own state slot.
function stateOf(snap: ProgressSnapshot): { text: string; color: string } {
  if (snap.view !== 'building') return { text: stepName(snap.stage as PlanStage), color: PLAN_BASE }
  if (snap.storyStatus === 'complete') return { text: 'complete', color: 'success' }
  return { text: snap.validating ? 'validating' : 'building', color: BUILD_BASE }
}

// One ball per chunk: a green ring while it builds, a filled green ball once built.
const BALL = { done: '●', building: '○', waiting: '○' } as const
const BALL_COLOR = { done: 'success', building: 'success', waiting: 'inactive' } as const

// Line two of the building view.
function chunkRow(els: ElementTable, snap: ProgressSnapshot): LineTwo {
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
  return {
    whole: [
      ...snap.chunks.map(c => <Text key={String(c.n)} color={BALL_COLOR[c.state]}>{BALL[c.state]}</Text>),
      <Text key="detail">{` ${detail}`}</Text>,
    ],
    hint: '',
  }
}

// Line two of a planning view: one ball per step, the current step a green ring,
// the same ball language as the building view's current chunk.
function stepRow(els: ElementTable, snap: ProgressSnapshot): LineTwo {
  const { Text } = els
  const k = STAGES.indexOf(snap.stage as PlanStage) + 1
  const after = STAGES[k]
  return {
    whole: [
      ...STAGES.map((stage, i) => (
        <Text key={stage} color={i + 1 <= k ? 'success' : 'inactive'}>{i + 1 < k ? '●' : '○'}</Text>
      )),
      <Text key="step">{` step ${k} of ${STAGES.length} · ${snap.minutes}m`}</Text>,
    ],
    hint: ` · next: ${after ? stepName(after) : READY}`,
  }
}

// Line two of the view over several stories: one ring per story.
function groupRow(els: ElementTable, snap: ProgressSnapshot): LineTwo {
  const { Text } = els
  return {
    whole: [
      ...snap.stages.map((_, i) => <Text key={String(i)} color="success">○</Text>),
      <Text key="minutes">{` ${snap.minutes}m`}</Text>,
    ],
    hint: '',
  }
}

// Line two of the held ready row: every step done, and how to start the build
// when nothing is running.
function readyRow(els: ElementTable, snap: ProgressSnapshot): LineTwo {
  const { Text } = els
  return {
    whole: [
      ...STAGES.map(stage => <Text key={stage} color="success">●</Text>),
      <Text key="done">{` all ${STAGES.length} steps done`}</Text>,
    ],
    hint: snap.slotHolder === '' ? HINT : '',
  }
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

function lineTwo(els: ElementTable, snap: ProgressSnapshot): LineTwo {
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
  const two = lineTwo(els, snap)

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
      <Box paddingLeft={2}>
        <Box gap={1} flexShrink={0}>{two.whole}</Box>
        {two.hint ? <Text color="inactive" wrap="truncate-end">{two.hint}</Text> : null}
      </Box>
    </Box>
  )
}

// What the chooser's buttons do; the caller owns the state they change.
export type ChooserActions = {
  pick: (index: number) => void
  page: (start: number) => void
  earlier: () => void
  cancel: () => void
  back: () => void
  start: () => void
}

const CANCEL_WIDTH = 'x: cancel'.length
const BACK_WIDTH = '‹ back'.length
// The gap between two items on the chooser's second line.
const GAP = 3

// How many stories fit on the page that begins at `start`, and how many are
// left for "+M more ›". The first story always shows, so a page is never empty.
export function pageOf(choices: Choice[], start: number, bodyColumns: number): { shown: number; more: number } {
  const room = bodyColumns - 2 - CANCEL_WIDTH - GAP - (start > 0 ? BACK_WIDTH + GAP : 0)
  let shown = 0
  let used = 0
  for (const choice of choices.slice(start)) {
    const width = `○ ${choice.label}`.length + GAP
    // The "+M more ›" button is sized for the count it would show after this entry.
    const rest = choices.length - start - shown - 1
    const moreAfter = rest > 0 ? `+${rest} more ›`.length + GAP : 0
    if (shown > 0 && used + width + moreAfter > room) break
    shown += 1
    used += width
  }
  return { shown, more: choices.length - start - shown }
}

function chooserList(els: ElementTable, chooser: Chooser, bodyColumns: number, act: ChooserActions): RenderElement {
  const { Box, Button, Text } = els
  const { choices, start } = chooser
  const { shown, more } = pageOf(choices, start, bodyColumns)
  const ownFirst = choices[0]?.path === chooser.own
  return (
    <Box flexDirection="column" marginTop={1}>
      <Box>
        <Box flexShrink={0}>
          <Text color={PLAN_BASE} bold>{'✶ '}</Text>
          {chooser.reason ? <Text bold>{chooser.reason}</Text> : <Text color={BUILD_BASE} bold>Implement</Text>}
          {chooser.reason ? null : <Text bold>{' which story?'}</Text>}
        </Box>
        <Text color="subtle" wrap="truncate-end">{` · ${choices.length} ready`}</Text>
      </Box>
      <Box paddingLeft={2} gap={GAP}>
        {start > 0 ? (
          <Button key="earlier" label="back" plain dimColor onPress={act.earlier}>
            <Text color="inactive">{'‹ back'}</Text>
          </Button>
        ) : null}
        {choices.slice(start, start + shown).map((choice, j) => {
          const i = start + j
          const scope = `choose-${i}`
          // A ring outside the button fills in while the button is pointed at.
          return (
            <Box key={`choice-${i}`}>
              <Box width={2}>
                <Text color="success">{'○'}</Text>
                <Box position="absolute" left={0} top={0} display="none" hover={{ scope, display: 'flex' }}>
                  <Text color="success" bold>{'●'}</Text>
                </Box>
              </Box>
              <Button key={`story-${i}`} label={choice.label} plain hover={{ scope }} onPress={() => act.pick(i)}>
                <Text color="success" bold={i === 0 && ownFirst}>{choice.label}</Text>
              </Button>
            </Box>
          )
        })}
        {more > 0 ? (
          <Button key="more" label={`+${more} more`} plain onPress={() => act.page(start + shown)}>
            <Text color="inactive">{`+${more} more ›`}</Text>
          </Button>
        ) : null}
        <Button key="cancel" label="cancel" plain hotkey="x" dimColor onPress={act.cancel} />
      </Box>
    </Box>
  )
}

function chooserConfirm(els: ElementTable, choice: Choice, act: ChooserActions): RenderElement {
  const { Box, Button, Text } = els
  return (
    <Box flexDirection="column" marginTop={1}>
      <Box>
        <Box flexShrink={0}>
          <Text color={PLAN_BASE} bold>{'✶ '}</Text>
          <Text color={BUILD_BASE} bold>Start</Text>
          <Text bold>{` ${choice.label}`}</Text>
        </Box>
        {choice.title ? <Text wrap="truncate-end">{` · ${choice.title}`}</Text> : null}
        <Box flexShrink={0}>
          <Text bold>?</Text>
        </Box>
      </Box>
      <Box paddingLeft={2} gap={GAP}>
        <Button key="start" label="start" plain onPress={act.start}>
          <Text color="success" bold>start</Text>
        </Button>
        <Button key="back" label="back" plain dimColor hotkey="n" onPress={act.back} />
      </Box>
    </Box>
  )
}

// The band turned into the story chooser: which story to implement, then the
// confirmation of the one picked. Draws whatever the chooser holds and reads nothing.
export function drawChooser(els: ElementTable, chooser: Chooser, bodyColumns: number, act: ChooserActions): RenderElement {
  const picked = chooser.mode === 'confirm' ? chooser.choices[chooser.picked] : undefined
  return picked ? chooserConfirm(els, picked, act) : chooserList(els, chooser, bodyColumns, act)
}
