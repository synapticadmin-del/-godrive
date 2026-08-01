# review-board — the coordination branch

هذا الفرع ليس كودًا. هو لوحة مهام مشتركة بين شاتات متعددة تعمل بالتوازي على
مراجعة Synaptic Go. لا تدمجه في `main`.

This branch is not code. It is a shared task board for several chats reviewing
Synaptic Go in parallel. It is never merged into `main`.

```
board/
├── PROTOCOL.md        the rules — every chat reads this first
├── REVIEW_PLAN.md     index of T01..T26
├── TEMPLATE.md        the shape of every deliverable
├── NEW_CHAT_PROMPT.md the prompt to paste into a new chat
├── tasks/TNN.md       one detailed brief per task
└── claims/TNN.md      created by whichever chat owns TNN (this is the lock)
```

**How it works.** A chat opens, generates a `CHAT_ID`, lists `board/claims/`,
and creates the claim file for the lowest unclaimed task. Creating a file that
already exists fails at the API level, so exactly one chat wins each task even
when ten chats start in the same second. The winner reads its brief, reviews
that slice of the platform, opens a PR against `main` with its plan document,
then marks its claim `done`.

**To see progress:** list `board/claims/` — every file is a task in flight or
finished, with its PR link inside.
