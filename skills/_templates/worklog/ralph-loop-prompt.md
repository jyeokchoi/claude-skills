You are operating in a persistent Ralph loop. Your source of truth is the task worklog.

## Worklog

- Path: {{WORKLOG_PATH}}
- Main file: {{WORKLOG_PATH}}/worklog.md

## Non-negotiable rules

1. At the start of EACH iteration:
   - Read the worklog.md Dashboard and the latest Timeline entry.
2. Do ONE meaningful batch of work per iteration (small, verifiable).
3. Before attempting to stop:
   - Update worklog.md inline:
     - Overwrite ONLY the Dashboard block between:
       <!-- WORKLOG:DASHBOARD:START --> and <!-- WORKLOG:DASHBOARD:END -->
     - Append ONE new Timeline entry immediately after:
       <!-- WORKLOG:TIMELINE:INSERT:HERE -->
     - Do NOT edit older timeline entries.
4. DONE is allowed only if:
   - Completion criteria are satisfied AND
   - Latest Timeline entry contains evidence (commands/files/tests) AND
   - Frontmatter phase is set to DONE AND
   - You output EXACTLY the completion promise string from `rules/project-params.md` project settings (key: `completion_promise`).

## Worklog structure

**Outside Dashboard (stable — do NOT overwrite):**
- Goal (1–2 lines)
- Completion criteria (bullets)
- Remember (permanent context)
- Links (accumulative)

**Inside Dashboard (always-current — overwrite between markers):**
- Next actions: 3–7 checkbox items
- Blockers/Risks
- Decisions (short)

## Timeline entry format (newest first)

### <YYYY-MM-DD HH:MM> (Ralph iter <n>)

**Summary**

- **Work done**

- **Evidence**
  - Commands:
  - Files:
  - Tests:

**Problems / Notes**

- **Next**

-

## Output discipline

- If not done: do NOT print the completion promise.
- If done: print ONLY the completion promise (from `rules/project-params.md`) on its own line.
