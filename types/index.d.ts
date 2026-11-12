export type ProgressChunk = { n: number; state: 'done' | 'building' | 'waiting' }

export type PlanStage = 'content-check' | 'alignment-check' | 'direction' | 'planner' | 'plan-check' | 'triage'

// What the band draws, whole. The building view and both planning views share
// one shape so the stored value is tagged once; a view leaves the fields it
// does not use at their empty values.
export type ProgressSnapshot = {
  view: 'building' | 'planning' | 'planning-many'
  path: string
  label: string
  title: string
  storyStatus: string
  chunks: ProgressChunk[]
  // The planning step shown; 'ready' is the held row's terminal value and is
  // never written to a story.
  stage: PlanStage | 'ready' | ''
  stages: PlanStage[]
  // True only for a planning view built from this session's own stories.
  owned: boolean
  // The cycle's raw current-story value; '' when no story holds the slot.
  slotHolder: string
  // The slot value the held ready row waits behind.
  holdSlot: string
  validating: boolean
  waitingOnUser: boolean
  motion: boolean
  since: number
  minutes: number
  error: string
}

// One story the chooser offers; `path` is absolute, `label` is `Story <n>` or the file's name.
export type Choice = { path: string; label: string; title: string }

// The story chooser's session memory. `own` is the ready row's story path;
// `picked` and `start` index `choices`; `earlier` holds the first index of each
// page before this one; `reason` is why the last start was refused, or ''.
export type Chooser = {
  mode: '' | 'list' | 'confirm'
  own: string
  choices: Choice[]
  picked: number
  start: number
  earlier: number[]
  reason: string
}

declare module 'claude-code' {
  interface PluginState {
    craft: {
      progress: Shaped<ProgressSnapshot | null>
      ownPlanning: Shaped<string[]>
      progressHidden: boolean
      progressFrame: number
      chooser: Shaped<Chooser>
    }
  }
}
