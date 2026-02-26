---
name: worklog-start
description: Create a new task worklog with optional Jira integration and bootstrap it with analysis + planning
argument-hint: 'Usage: /worklog-start [--no-jira] [--no-branch] [--slack <thread-url-or-channel>] [task-name | ISSUE-KEY] [brief]'
allowed-tools: Bash(cat:*), Bash(test:*), Bash(ls:*), Bash(date:*), Bash(grep:*), Bash(git:*), Bash(mkdir:*), Bash(cp:*), Bash(find:*), Bash(python:*), Read, Edit, Write, AskUserQuestion, Task
---

You are creating and bootstrapping a task worklog for structured multi-session work.

## Project settings

이 스킬은 `rules/workflow.md`의 프로젝트별 설정을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `worktree_policy` | `optional` | `always`=항상 생성, `optional`=사용자에게 물음, `never`=생성 안함 |
| `fork_workflow` | `false` | true면 origin=fork, upstream=org |
| `develop_sync` | `git fetch origin` | worktree 전 develop 동기화 |
| `dependency_install` | (없음) | worktree 후 의존성 설치 명령 |
| `branch_pattern` | `feature/{task_name}` | 브랜치 이름 패턴 |
| `jira_pattern` | `[A-Z]+-\d+` | Jira 이슈 키 패턴 |
| `jira_base_url` | (없음) | Jira URL prefix |
| `timezone` / `timestamp_suffix` | local / (없음) | 타임스탬프 |
| `slack_integration` | `false` | Slack 컨텍스트 수집 |
| `base_branch` | (자동 탐지) | base branch 명시 지정 |
| `completion_promise_default` | `**WORKLOG_TASK_COMPLETE**` | 완료 약속 문자열 |

## Inputs

- Raw arguments: $ARGUMENTS

Interpretation:

- `--no-jira` flag (optional): Skip Jira issue creation/lookup
- `--no-branch` flag (optional): Skip git branch creation (use current branch)
- `--slack <value>` flag (optional): Slack thread URL or channel to collect context from
- First non-flag token = task-name OR existing Jira issue key (e.g., PROJ-12345)
- Remaining text (if any) = task brief (used for description and bootstrap)

## Steps

### 1. Parse arguments

- Check if `--no-jira` flag is present → set `skip_jira = true`
- Check if `--no-branch` flag is present → set `skip_branch = true`
- Check if `--slack <value>` flag is present → set `slack_arg = <value>`
- Check if first non-flag token matches `jira_pattern` from project settings (default `[A-Z]+-\d+`) → existing Jira issue key
- task_name_raw = first non-flag token (can be empty)
- task_brief = remaining text (can be empty)

### 2. Check for uncommitted changes (MANDATORY)

```bash
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "ERROR: Uncommitted changes detected. Please commit or stash them first."
  exit 1
fi
```

### 2.5. Slack context collection (conditional)

**Only when** `slack_integration` is `true` in project settings OR `--slack` flag was provided.

**A. Determine Slack source:**
- If `--slack <value>` was provided, use that value as thread URL or channel
- If `slack_integration=true` but no `--slack` flag: ask user for optional Slack thread URL/channel

**B. Fetch Slack context:**
- If value is a thread URL: fetch the thread messages using Slack MCP tools
- If value is a channel name: fetch recent messages from that channel

**C. Extract relevant context:**
- Summarize the discussion into: background, requirements, decisions, open questions

**D. Inject into task_brief:**
- Prepend extracted Slack context to any existing task_brief

### 3. Jira issue handling (optional)

**If first token is an existing Jira issue key:**

a. Fetch issue details via Jira MCP tools (if available):
   - `getJiraIssue` → summary, description, issue type, comments
b. task_name = kebab-case of `{issue_key}-{summary_short}`
c. issue description + comments → task_brief
d. jira_url: Use `jira_base_url` from project settings if configured (e.g., `https://company.atlassian.net/browse/{key}`), else compose from issue key

**If `skip_jira` is false and no existing issue key:**

a. Ask the user whether to create a Jira issue:
   ```
   AskUserQuestion:
     question: "Jira 이슈를 생성할까요?"
     header: "Jira"
     options:
       - label: "예, 생성"
         description: "새 Jira 이슈를 생성합니다"
       - label: "아니오, 건너뛰기"
         description: "Jira 없이 진행합니다"
   ```
b. If creating: use Jira MCP tools to create issue with task_brief as description
c. task_name = kebab-case of `{issue_key}-{summary_short}`
d. jira_url: Use `jira_base_url` from project settings if configured, else compose from issue key

**If `skip_jira` is true or Jira skipped:**

- task_name_raw이 비어있으면 사용자에게 task name 입력 요청
- jira field will be empty

### 4. Normalize task name

- Lowercase, replace spaces/underscores with `-`, remove characters not in `[a-z0-9-]`

### 5. Compute metadata

- created: Use `timezone` from project settings if available (`TZ={timezone} date "+%Y-%m-%d"`), else `date "+%Y-%m-%d"`
- owner: `git config user.name`
- jira: Jira issue URL (or empty if skipped)
- branch_name: Apply `branch_pattern` from project settings (default: `feature/{task_name}`)
- completion_promise: Use `completion_promise_default` from project settings (default: `**WORKLOG_TASK_COMPLETE**`)

### 6. Create branch or worktree

**Determine `worktree_policy`** from rules/workflow.md (default: `optional`):

**If `skip_branch` is true:**
- Skip branch/worktree creation entirely, use current branch

**If `worktree_policy` = `always`:**

a. Sync develop branch using `develop_sync` from project settings if configured, else:
   ```bash
   # fork_workflow=true → git fetch upstream && git fetch origin
   # fork_workflow=false (또는 미설정) → git fetch origin
   ```
b. Determine base: use `base_branch` from project settings if configured, else:
   ```bash
   # 1. gh repo view --json defaultBranchRef로 자동 탐지
   # 2. fork_workflow에 따라 remote 결정 (upstream/origin)
   # 3. 탐지 실패 시 사용자에게 질문 → project_memory_add_note("base_branch: {answer}")
   ```
c. Create worktree:
   ```bash
   WORKTREE_DIR="../worktrees/{task_name}"
   git worktree add -b {branch_name} "$WORKTREE_DIR" ${BASE}
   ```
d. If `dependency_install` is configured in project settings, run it inside the worktree:
   ```bash
   cd "$WORKTREE_DIR" && {dependency_install}
   ```
e. Store `worktree_path = WORKTREE_DIR` for use in Step 7

**If `worktree_policy` = `optional`:**
```
AskUserQuestion:
  question: "워크트리를 생성하시겠습니까?"
  header: "Worktree"
  options:
    - label: "예, 워크트리 생성"
      description: "격리된 작업 환경을 만듭니다"
    - label: "아니오, 현재 저장소에서 작업"
      description: "브랜치만 생성합니다"
```
- "예": follow `always` path above
- "아니오": follow `never` path below

**If `worktree_policy` = `never`:**

a. Determine base: use `base_branch` from project settings if configured, else:
   ```bash
   # 1. gh repo view --json defaultBranchRef로 자동 탐지
   # 2. fork_workflow에 따라 remote 결정 (upstream/origin)
   # 3. 탐지 실패 시 사용자에게 질문 → project_memory_add_note("base_branch: {answer}")
   ```
b. Create and checkout branch:
   ```bash
   git checkout -b {branch_name} ${BASE}
   ```
c. `worktree_path` = not set (worklog goes in current repo)

### 7. Create worklog

- Detect worklog template:
  ```bash
  TEMPLATE="$(git rev-parse --show-toplevel)/.claude/skills/_templates/worklog/worklog.md"
  [ -f "$TEMPLATE" ] || TEMPLATE="$HOME/.claude/skills/_templates/worklog/worklog.md"
  ```
- Determine worklog location:
  - If worktree was created: `{worktree_path}/.claude/worklogs/{task_name}/`
  - Else: `.claude/worklogs/{task_name}/`
- Create folder at determined location
- If folder already exists: print the path and stop.
- Copy template → `{worklog_dir}/worklog.md`
- Fill frontmatter: jira, branch, created, owner, completion_promise
- If worktree_path is set, also add `worktree_path` to frontmatter
- Set `.claude/worklogs/.active` to the worklog folder path

### 8. Bootstrap content (MANDATORY)

- Analyze (understand the task, identify risks/unknowns)
- Plan (3-7 Next actions with completion criteria)
- Write results into worklog Dashboard (between WORKLOG:DASHBOARD markers) + 1 Timeline entry (after WORKLOG:TIMELINE:INSERT:HERE)

Use the worklog update mechanism:
- Create `.dashboard.tmp.md` and `.timeline.tmp.md`
- Apply via `python .claude/skills/_templates/worklog/apply_worklog_update.py` (if available)
- Otherwise apply inline via Edit tool

### 9. Print summary

```
Worklog created:
  - Task: {task_name}
  - Path: {worklog_path}
  - Branch: {branch_name} (or "current branch")
  - Worktree: {worktree_path} (or "none")
  - Jira: {jira_url} (or "none")
  - Status: PLANNING
```

### 10. Ask to continue

```
AskUserQuestion:
  question: "워크로그가 생성되었습니다. 다음 단계를 선택하세요."
  header: "Next"
  options:
    - label: "플래닝 시작 (/vplan)"
      description: "구조화된 플래닝 파이프라인을 시작합니다"
    - label: "분석 먼저 (/vanalyze)"
      description: "기존 코드를 분석한 후 플래닝합니다"
    - label: "바로 구현 (/worklog-ralph)"
      description: "Ralph loop로 즉시 구현을 시작합니다"
    - label: "나중에"
      description: "워크로그만 생성하고 종료합니다"
```

- "/vplan": Invoke `/vplan {worklog_path}`
- "/vanalyze": Invoke `/vanalyze {worklog_path}`
- "/worklog-ralph": Invoke `/worklog-ralph {worklog_path}`
- "나중에": 종료

Proceed now.
