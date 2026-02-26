---
name: web-task
description: Create a worklog and run autonomous implementation with architect/code-reviewer consensus loop, then auto-cleanup. Designed for Claude web sessions with limited MCP/plugin access.
argument-hint: 'Usage: /web-task [task-name] [brief description of the task]'
---

You are running an end-to-end autonomous task workflow designed for **Claude web sessions** where MCP and plugins are limited.

## Inputs

- Raw arguments: $ARGUMENTS
- First token = task-name (optional)
- Remaining text = task brief (optional)

## Project settings

스킬 시작 시 `rules/workflow.md`를 읽어 다음 설정을 가져온다 (없으면 기본값 사용):

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `base_branch` | (자동 탐지: `gh repo view --json defaultBranchRef`) | diff 기준 브랜치 |
| `test_command` | (package.json에서 탐지) | 테스트 실행 명령 |
| `timezone` / `timestamp_suffix` | local / (없음) | 타임스탬프 |
| `completion_promise_default` | `**WORKLOG_TASK_COMPLETE**` | worklog 완료 약속 |

## Constraints (Web Session)

- **No Jira MCP** — always `--no-jira`
- **No hooks** — ralph loop를 직접 구현 (state file 의존 없음)
- **사용 가능 도구**: Read, Write, Edit, Bash, Glob, Grep, Task, AskUserQuestion
- **사용 불가**: MCP tools, OMC state tools, Skill tool

## Workflow Overview

```
worklog 생성 (--no-jira)
    ↓
Analyze + Plan (Dashboard 작성)
    ↓
┌─→ Implementation batch
│       ↓
│   Architect review → 합의?
│       ↓ No → 수정 → ↑
│       ↓ Yes
│   Code-reviewer review → 합의?
│       ↓ No → 수정 → ↑
│       ↓ Yes
│   다음 action 남았으면 → ↑
└───────────────────────────
    ↓ (모든 action 완료)
Code-simplifier
    ↓
Lint + Format
    ↓
완료
```

## Steps

### 1. Parse arguments & create worklog

a. Parse:
- `task_name` = first token (없으면 사용자에게 질문)
- `task_brief` = remaining text (없으면 사용자에게 질문)

b. Normalize task_name: lowercase, replace spaces/underscores with `-`, remove `[^a-z0-9-]`

c. Compute metadata:
- `created`: Resolve timezone from `.claude/rules/workflow.md` (`timezone` field) if present; otherwise use system timezone. Run `date "+%Y-%m-%d"` with that timezone (e.g. `TZ='America/New_York' date "+%Y-%m-%d"`), or plain `date "+%Y-%m-%d"` if no config found.
- `owner`: `git config user.name`

d. Create worklog folder and file:
- Path: `.claude/worklogs/{task_name}/`
- Copy template: `.claude/skills/_templates/worklog/worklog.md` (fallback: `~/.claude/skills/_templates/worklog/`)
- Fill frontmatter: `jira: ""`, `branch: ""`, `created`, `owner`, `status: PLANNING`

### 2. Analyze & Plan (Bootstrap)

a. 태스크를 분석:
- task_brief 기반으로 관련 코드 탐색 (Glob, Grep, Read)
- 리스크/미지수 식별

b. Plan 작성 (3-7 Next actions with completion criteria)

c. worklog.md Dashboard 업데이트:
- Goal, Completion criteria, Next actions, Risks
- Status: `IN_PROGRESS`

d. 첫 Timeline entry 추가 (after `<!-- WORKLOG:TIMELINE:INSERT:HERE -->`)

### 3. Implementation + Consensus Loop

**각 action에 대해 아래 루프를 반복:**

#### 3a. Implementation batch

- Dashboard의 Next actions에서 미완료 항목 하나를 선택
- 구현 수행 (직접 코드 수정)
- 완료 후 worklog Timeline에 작업 내용 기록

#### 3b. Architect review

`architect` 에이전트 호출 (Read-only, `model: "opus"`):

프롬프트에 포함할 내용:
- 현재까지의 변경 diff
- 변경된 파일의 전문 (워크로그 경로 기반)
- 태스크 Goal과 Completion criteria

**합의 판단 기준:**
- Architect가 "승인" 또는 심각한 이슈 없음 → 통과
- 설계 문제 지적 시 → 수정 후 다시 3b

#### 3c. Code-reviewer review

`code-reviewer` 에이전트 호출 (`model: "sonnet"`):

프롬프트에 포함할 내용:
- 변경 diff
- 변경된 파일의 전문

**합의 판단 기준:**
- Severity HIGH 이상 이슈 없음 → 통과
- HIGH 이상 이슈 있음 → 수정 후 다시 3c
- 같은 이슈가 2회 연속 지적되면 사용자에게 판단 위임

#### 3d. 다음 action 확인

- Dashboard의 Next actions에 미완료 항목이 남아 있으면 → 3a로 복귀
- 모든 action 완료 → Step 4로 진행

**워크로그 업데이트**: 각 반복마다 Dashboard + Timeline 업데이트 필수

### 4. Code-simplifier

역할 `code-simplifier`로 위임 (_shared/agent-routing.md 참조):
- 변경된 파일 목록 전달
- 불필요한 복잡성 제거, 코드 정리

### 5. Lint & Format

> **Shared**: `.claude/skills/_shared/lint-format.md` 절차를 따른다.
> - `changed_files`: 이 태스크에서 변경된 파일 목록 (`git diff --name-only HEAD~{n}..HEAD`, n = 태스크 커밋 수)
> - `project_dir`: Auto-detect via `git rev-parse --show-toplevel` and derive the relevant sub-project directory from the changed files' paths (e.g. if files are under `react/`, use `react/`; if files span multiple sub-projects, run lint per sub-project)

### 6. Final worklog update & 완료

a. Dashboard status → `DONE`
b. 최종 Timeline entry 추가 (Evidence 포함)
c. 완료 메시지 출력

## Iteration Rules

- 각 iteration은 **반드시 의미 있는 작업**을 수행해야 함 (대기만 하는 iteration 금지)
- 사용자에게 런타임 테스트, 의사결정, 피드백을 요청하지 않음
- 의사결정이 필요하면 worklog Dashboard의 기존 컨텍스트를 기반으로 자율적으로 결정
- architect/code-reviewer 피드백이 상충할 경우 architect 의견을 우선

## Red Flags

| 생각 | 현실 |
|------|------|
| "ralph state를 만들자" | 웹 세션에서 hooks 없음. 직접 루프 구현 |
| "Jira 이슈를 만들어야지" | MCP 없음. --no-jira로 진행 |
| "사용자한테 확인받자" | 자율 모드. 스스로 결정 |
| "한번에 다 구현하자" | 작은 batch로 나눠서 review 받기 |

Proceed now.
