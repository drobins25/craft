# Rules for a story with a user interface

`hooks/scripts/story-rules.sh` prints the part below to the builder when a story's frontmatter says `type: ui`, names a mockup, or has a Visual Direction binding table. The part is printed without its heading.

## builder

Where your chunk builds something a person looks at or operates, these four things are rarely written in a plan and a user notices them at once. Handle them in your chunk's files, as you do the cases under "Build it for real inputs"; a gap outside your chunk goes under Observations.

- **Every state renders.** While something loads, after it fails and when there is nothing to show, the screen says which of these it is. A failure says what went wrong and, where trying again can help, offers it.
- **Every action answers.** Anything that takes time shows that it is working, and a second click while it runs does not send it twice.
- **Everything works from the keyboard.** Each control can be reached, operated and seen to have focus without a mouse.
- **A control that cannot be used says why.** When something is disabled, the screen names what is missing.

Values a mockup or a token settles stay as they are; these add markup and states around them.
