// The two lines hooks/scripts/planning-stage.sh prints on success. The bash test runs the
// real script and compares its output to these literals, and the band's parser test reads
// the same literals, so the line format and the regex that reads it cannot drift apart.
export const SET_LINE = 'Planning stage set to planner: /work/p/.craft/cycles/c/stories/t.md'
export const CLEARED_LINE = 'Planning stage cleared: /work/p/.craft/cycles/c/stories/t.md'
