---
name: worklog-amend
description: Use when a worklog exists but is missing required fields (jira, branch, frontmatter) or when you need to move an existing worklog to a new worktree
argument-hint: 'Usage: /worklog-amend [worklog-path]'
allowed-tools: Bash(mkdir:*), Bash(cp:*), Bash(mv:*), Bash(rm:*), Bash(date:*), Bash(git rev-parse:*), Bash(git config:*), Bash(git worktree:*), Bash(git branch:*), Bash(git checkout:*), Bash(git fetch:*), Bash(test:*), Bash(ls:*), Bash(cd:*), Bash(pwd:*), Read, Write, Edit, AskUserQuestion, mcp__plugin_atlassian_atlassian__*
---

기존 worklog의 누락된 필드를 채우고, 선택적으로 새 worktree로 이전한다.

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `worktree_policy` | `optional` | worktree 생성 정책 (`always` / `optional` / `never`) |
| `branch_pattern` | `feature/{task_name}` | 브랜치 이름 패턴 |
| `jira_pattern` | `[A-Z]+-\d+` | Jira 이슈 키 패턴 |
| `jira_base_url` | (없음) | Jira 이슈 URL 접두사 |
| `base_branch` | auto-detect | worktree base 브랜치 |

## 입력값

- Raw arguments: $ARGUMENTS
- 인자가 없으면 `.claude/worklogs/`에서 활성 worklog 자동 탐색

## 변경 불가 규칙

- 새 worklog를 생성하지 않는다 — 기존 worklog만 수정한다
- worklog.md 업데이트는 `_shared/update-worklog.md`를 통해 수행한다 (복사본 생성 금지)
- 수정 시 기존 내용을 모두 보존한다

## 단계

### 1. worklog 탐색

- `_shared/resolve-worklog-target.md`가 존재하는 경우:
  > **Shared**: `_shared/resolve-worklog-target.md` 절차를 따른다. (`required_files`: 없음)
- 없는 경우 폴백:
  - $ARGUMENTS에 경로가 있으면 직접 사용
  - 인자 없음: `.claude/worklogs/*/worklog.md`에서 가장 최근이거나 DONE이 아닌 worklog 탐색 (`phase` 필드 확인)
  - 여러 개 발견 시 사용자에게 선택 요청

### 2. worklog 읽기 및 누락 필드 확인

worklog.md를 읽고 누락된 필수 frontmatter 필드를 식별한다:

| 필드               | 필수 여부 | 누락 시 기본값                      |
| ------------------ | --------- | ----------------------------------- |
| `jira`             | 예        | (사용자에게 묻기)                   |
| `branch`           | 예        | task name + jira key으로 도출       |
| `created`          | 예        | 폴더명에서 추출 또는 오늘 날짜      |
| `owner`            | 예        | `git config user.name`              |
| `phase`            | 예        | `ANALYZE`                           |

worklog 내용도 확인: Goal, Completion criteria (Dashboard 상단), Dashboard Next actions/Decisions.

### 3. 누락 필드 채우기

**jira (비어있고 사용자가 추가하려는 경우):**

AskUserQuestion: "Jira 이슈를 생성하시겠습니까?" (예/아니오)

"예"인 경우:

- `_shared/create-jira-issue.md`가 존재하는 경우:
  > **Shared**: `_shared/create-jira-issue.md` 절차를 따른다.
- 없는 경우: 사용자에게 Jira 이슈 제목과 설명을 요청하고 `mcp__plugin_atlassian_atlassian__` 도구로 직접 생성.

**branch (비어있는 경우):**
- 프로젝트 설정의 `branch_pattern` 사용 (기본: `feature/{task_name}`)
- jira key가 있는 경우: `feature/{JIRA_KEY}.{task_name_short}` (또는 `branch_pattern` 설정에 따름)
- 사용자에게 확인 또는 수정 요청

**created/owner/phase:**
- 위 표의 기본값으로 채움 (phase 직접 기입은 초기 필드 생성이므로 update-worklog.md Rule 5 예외)

### 4. worklog 내용 보완 (내용이 부족한 경우)

Goal 또는 Completion criteria (Dashboard 상단)가 비어있거나 Dashboard Next actions가 비어있는 경우:
- 사용자에게 초기 내용을 채울지 확인
- 예인 경우: Goal과 초기 Next actions를 요청하여 채움
- `_shared/update-worklog.md`로 worklog 업데이트:
  - `timeline_entry`: 수정 요약

### 5. worktree 이전 여부 확인

`worktree_policy` = `never`인 경우: 이 단계를 완전히 건너뜀.

`worktree_policy` = `always`인 경우: 확인 없이 직접 Step 6으로 진행.

`worktree_policy` = `optional` (기본값)인 경우:
AskUserQuestion: "워크로그 수정이 완료되었습니다. 새 워크트리를 생성하고 워크로그를 이동하시겠습니까?" (예/아니오)

### 6. worktree 생성 및 이전 (해당하는 경우)

`base_branch` 결정:
- `_shared/resolve-base-branch.md`가 존재하는 경우:
  > **Shared**: `_shared/resolve-base-branch.md` 절차를 따른다.
- 없는 경우: 프로젝트 설정의 `base_branch` → 자동 탐지 → 사용자 질문

`_shared/create-worktree.md`가 존재하는 경우:
> **Shared**: `_shared/create-worktree.md` 절차를 따른다.
> - `task_name` = 브랜치 이름 단축형 (`branch_pattern`에 따라 접두사 제거), `branch_name` = worklog frontmatter의 branch, `base_ref` = `{base_branch}`, `create_branch` = `true`

없는 경우 (인라인 worktree 생성):
```bash
# worktree 경로 결정: 저장소 루트와 형제 디렉토리
repo_root=$(git rev-parse --show-toplevel)
worktree_base=$(dirname "$repo_root")/worktrees
worktree_path="$worktree_base/{task_name}"
git worktree add -b {branch_name} "$worktree_path" {base_branch}
```

worklog를 새 worktree로 이동:
```bash
mkdir -p {worktree_path}/.claude/worklogs/
mv {current_worklog_folder} {worktree_path}/.claude/worklogs/
```

`.active` 포인터를 새 위치로 업데이트:
```bash
# 기존 .active가 이동된 워크로그를 가리키면 새 경로로 갱신
OLD_ACTIVE=".claude/worklogs/.active"
if [[ -f "$OLD_ACTIVE" ]] && [[ "$(cat "$OLD_ACTIVE")" == *"{worklog_folder_name}"* ]]; then
  rm -f "$OLD_ACTIVE"
fi
# 새 위치에 .active 설정
echo "{worktree_path}/.claude/worklogs/{worklog_folder_name}" > "{worktree_path}/.claude/worklogs/.active"
```

frontmatter 업데이트: `worktree_path: {worktree_path}` 추가

### 7. 요약 출력

```
Worklog amended:
  - Amended fields: [수정된 필드 목록]
  - Path: {worklog_path}
  - Jira: {jira_url or "없음"}
  - Branch: {branch_name}
```

worktree가 생성된 경우:

- `_shared/print-worktree-summary.md`가 존재하는 경우:
  > **Shared**: `_shared/print-worktree-summary.md` 절차를 따른다.
- 없으면 인라인 출력:
  ```
  Worktree created:
    - Path: {worktree_path}
    - Branch: {branch_name}
    - Base: {base_branch}

  Next: cd {worktree_path}
  ```

이제 실행하라.
