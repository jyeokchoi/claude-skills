---
name: slack-share
description: Gather work progress from commits/worklogs and share to a Slack thread with user approval
argument-hint: 'Usage: /slack-share <slack-thread-url> [--since=YYYY-MM-DD] [--audience=dev|all]'
---

You are composing a work progress summary and posting it to a Slack thread.

## Input parsing

Parse $ARGUMENTS:

1. **Slack thread URL** (required): Extract `channel_id` and `thread_ts` from the URL.
   - URL format: `https://*.slack.com/archives/{channel_id}/p{timestamp}`
   - Convert timestamp: remove `p` prefix, insert `.` before last 6 digits
   - If no URL provided, stop and print: "슬랙 스레드 URL을 입력해주세요."

2. **--since** (optional): Start date for commit range. Default: last Thursday.
   - Calculate last Thursday: if today is Thu or later, use this week's Thu. Otherwise use last week's Thu.

3. **--audience** (optional): Target audience.
   - `dev`: developers only (technical details OK)
   - `all` (default): developers + designers + planners (minimize jargon, focus on user-facing impact)

## Step 1: Read the Slack thread

Use `mcp__slack__conversations_replies` to fetch the thread context. Understand what the thread is about and what kind of sharing is expected.

## Step 2: Gather work data

Run these in parallel:

1. **Commits**: `git log --since="{since_date}" --no-merges --format="----%nCommit: %h%nDate: %ad%nSubject: %s%n%b" --date=short`
2. **Worklogs**: Find and read worklogs under `.claude/worklogs/` that are IN_PROGRESS or recently updated.

## Project config (optional)

If `rules/workflow.md` exists in the project root, read it to pick up:
- `jira_pattern` — for recognizing issue keys in commit messages
- `jira_base_url` — for building issue links
- `slack_integration` — whether Slack context gathering is expected

If the file does not exist, proceed with reasonable defaults (no issue key linkification).

## Step 3: Compose the draft

### Writing rules

- **Plain text only** — no markdown syntax (no `**bold**`, `# headers`, `| tables |`)
- Use numbered lists for completed items, bullet points (`-`) for sub-items
- Structure: [completed] → [in progress] → [next TODO]

### Audience adaptation

- **audience=all** (default):
  - Describe changes in terms of user-visible behavior, not implementation details
  - Avoid: class names, function names, Redux, hook names, design patterns, file paths
  - OK: "에셋 표시 타이밍 개선", "편집 시 프리뷰 즉시 반영"

- **audience=dev**:
  - Technical details are fine
  - Include file names, architectural decisions, test counts

### Content structure

```
{thread topic} — {date range} 작업 공유 ({author name})

[완료]

1. {user-facing description} — {brief explanation}
2. ...

[진행 중] {task name}

{current status}. {what's improving}:
- {improvement 1}
- {improvement 2}
- ...

[다음 TODO]
- {priority}: {task 1}, {task 2}
- ...
```

## Step 4: User review (MANDATORY)

Print the full draft and ask: "이대로 슬랙에 올릴까요?"

Wait for user approval. If the user requests changes, revise and ask again.

**NEVER post to Slack without explicit user approval.**

## Step 5: Post to Slack

Use `mcp__slack__conversations_add_message` with:
- `channel_id`: from parsed URL
- `thread_ts`: from parsed URL
- `content_type`: `text/plain`
- `payload`: the approved draft

Print confirmation after posting.
