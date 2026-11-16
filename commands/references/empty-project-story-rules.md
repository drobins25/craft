# Rules for a story in an empty project

`hooks/scripts/story-rules.sh` prints the part below to the planner when the project root holds nothing but `.craft` and repository housekeeping files (a README, a licence, git and editor settings) and the story names no mockup. A story built from a mockup in an empty project takes its first chunk from `mockup-story-rules.md` instead. The part is printed without its heading.

## planner

This project has nothing to build or run yet, so the first chunk stands up the framework `.craft/project.md` names: its dependencies, its config and an entry point. Its Run list is the build and the test command starting cleanly on that skeleton, so every later chunk builds on something that runs. Keep it to the skeleton; the story's features start in the next chunk.

- **The check above looks only at the project root.** If your own research finds a skeleton it could not see (a build config or entry file in a subfolder, a framework one level up in a monorepo), plan no scaffold chunk and say so as a concern, because a scaffold laid over live code overwrites it.
- **If project.md names no framework, list that as a Critical Blocker.** Which framework to use is the user's call, not yours.
