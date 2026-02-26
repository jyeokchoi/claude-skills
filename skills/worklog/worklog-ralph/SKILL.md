---
name: worklog-ralph
description: Run a Ralph loop that uses a task worklog as the source of truth
argument-hint: 'Usage: /worklog-ralph <path-to-worklog-folder-or-worklog.md>'
allowed-tools: Bash(test:*), Bash(cat:*), Bash(python:*), Bash(realpath:*), Bash(ls:*), Bash(find:*), Bash(grep:*), Bash(mkdir:*), Bash(node:*)
---

You will start a Ralph loop using the specified task worklog.

## Input

- target: $ARGUMENTS

## Pre-flight Check (CRITICAL)

Before anything else, verify the OMC orchestration plugin is installed (_shared/agent-routing.md 참조):

```bash
find ~/.claude/plugins/cache -name "hooks.json" -path "*oh-my-claudecode*" 2>/dev/null | head -1
```

If NO hooks.json found:
1. Print: "❌ OMC 플러그인이 설치되지 않았습니다."
2. **STOP immediately** - do not continue.

## Steps (only proceed if pre-flight passed)

1. Resolve the target:
   - If target is a folder: use "{target}/worklog.md"
   - If target is a file: use "{target}"
2. Validate that worklog.md exists. If not, print a single error message and stop.
3. Read `completion_promise` from the worklog frontmatter if present; otherwise default to `**WORKLOG_TASK_COMPLETE**`.
4. Load ".claude/skills/_templates/worklog/ralph-loop-prompt.md" (fallback: ~/.claude/skills/_templates/worklog/) and replace:
   - `{{WORKLOG_PATH}}` → absolute path to the worklog folder
   - `{{COMPLETION_PROMISE}}` → the completion_promise value
5. Create `.omc/state/ralph-state.json` with the following structure:
   ```json
   {
     "active": true,
     "iteration": 1,
     "max_iterations": 50,
     "prompt": "<RENDERED_PROMPT>",
     "completion_promise": "<PROMISE>",
     "started_at": "<ISO_TIMESTAMP>",
     "worklog_path": "<ABSOLUTE_PATH_TO_WORKLOG>",
     "linked_ultrawork": true
   }
   ```
6. Also create `.omc/state/ultrawork-state.json` (ralph loop auto-activates ultrawork, _shared/agent-routing.md 참조):
   ```json
   {
     "active": true,
     "original_prompt": "<RENDERED_PROMPT>",
     "started_at": "<ISO_TIMESTAMP>",
     "last_checked_at": "<ISO_TIMESTAMP>",
     "reinforcement_count": 0,
     "linked_to_ralph": true
   }
   ```
7. Print success message and the rendered prompt for context.
8. The orchestration stop hook will now manage the ralph loop automatically (_shared/agent-routing.md 참조).

## Implementation (use bash + python)

Use a python script to:

- Parse YAML frontmatter (best-effort, simple regex is OK)
- Render the prompt template (replace `{{WORKLOG_PATH}}` and `{{COMPLETION_PROMISE}}`)
- Create .omc/state directory if not exists
- Write both state/ralph-state.json and state/ultrawork-state.json
- Print "✅ Ralph loop started for: <worklog_path>"
- Print "Completion promise: <promise>"

Proceed now.
