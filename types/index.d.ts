export type ProgressChunk = { n: number; state: 'done' | 'building' | 'waiting' }

export type ProgressSnapshot = {
  path: string
  label: string
  title: string
  storyStatus: string
  chunks: ProgressChunk[]
  error: string
}

declare module 'claude-code' {
  interface PluginState {
    craft: { progress: Shaped<ProgressSnapshot | null>; progressHidden: boolean }
  }
}
