---
name: worklog-start
description: Create a new task worklog with optional Jira integration
argument-hint: 'Usage: /worklog-start [--no-jira] [--no-branch] [--slack <thread-url-or-channel>] [task-name | ISSUE-KEY] [brief]'
allowed-tools: Bash(cat:*), Bash(test:*), Bash(ls:*), Bash(date:*), Bash(grep:*), Bash(git:*), Bash(mkdir:*), Bash(cp:*), Bash(find:*), Bash(python:*), Read, Edit, Write, AskUserQuestion, Task
---

구조화된 멀티세션 작업을 위한 task worklog를 생성하고 초기화한다.

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

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

## 입력값

- Raw arguments: $ARGUMENTS

해석:

- `--no-jira` 플래그 (선택): Jira 이슈 생성/조회 건너뛰기
- `--no-branch` 플래그 (선택): git 브랜치 생성 건너뛰기 (현재 브랜치 사용)
- `--slack <value>` 플래그 (선택): 컨텍스트를 수집할 Slack 스레드 URL 또는 채널
- 첫 번째 비플래그 토큰 = task-name 또는 기존 Jira 이슈 키 (예: PROJ-12345)
- 나머지 텍스트 (있을 경우) = task brief (설명 및 초기화에 사용)

## 단계

### 1. 인자 파싱

- `--no-jira` 플래그 존재 여부 확인 → `skip_jira = true` 설정
- `--no-branch` 플래그 존재 여부 확인 → `skip_branch = true` 설정
- `--slack <value>` 플래그 존재 여부 확인 → `slack_arg = <value>` 설정
- 첫 번째 비플래그 토큰이 프로젝트 설정의 `jira_pattern` (기본 `[A-Z]+-\d+`)과 일치하는지 확인 → 기존 Jira 이슈 키
- task_name_raw = 첫 번째 비플래그 토큰 (비어있을 수 있음)
- task_brief = 나머지 텍스트 (비어있을 수 있음)

### 2. Slack 컨텍스트 수집 (조건부)

프로젝트 설정에서 `slack_integration`이 `true`이거나 `--slack` 플래그가 제공된 경우에만 실행.

**A. Slack 소스 결정:**
- `--slack <value>`가 제공된 경우, 해당 값을 스레드 URL 또는 채널로 사용
- `slack_integration=true`이지만 `--slack` 플래그 없음: 사용자에게 선택적으로 Slack 스레드 URL/채널 요청

**B. Slack 컨텍스트 조회:**
- 값이 스레드 URL인 경우: Slack MCP 도구로 스레드 메시지 조회
- 값이 채널명인 경우: 해당 채널의 최근 메시지 조회

**C. 관련 컨텍스트 추출:**
- 논의 내용을 배경, 요구사항, 결정사항, 미결 질문으로 요약

**D. task_brief에 주입:**
- 추출된 Slack 컨텍스트를 기존 task_brief 앞에 추가

### 3. Jira 이슈 처리 (선택)

**첫 번째 토큰이 기존 Jira 이슈 키인 경우:**

a. Jira MCP 도구(사용 가능한 경우)로 이슈 상세 조회:
   - `getJiraIssue` → 요약, 설명, 이슈 유형, 댓글
b. task_name = `{issue_key}-{summary_short}`의 kebab-case
c. 이슈 설명 + 댓글 → task_brief
d. jira_url: 프로젝트 설정에 `jira_base_url`이 설정된 경우 사용 (예: `https://company.atlassian.net/browse/{key}`), 없으면 이슈 키로 구성

**`skip_jira`가 false이고 기존 이슈 키가 없는 경우:**

a. 사용자에게 Jira 이슈 생성 여부 확인:
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
b. 생성하는 경우: Jira MCP 도구로 task_brief를 설명으로 하는 이슈 생성
c. task_name = `{issue_key}-{summary_short}`의 kebab-case
d. jira_url: 프로젝트 설정에 `jira_base_url`이 설정된 경우 사용, 없으면 이슈 키로 구성

**`skip_jira`가 true이거나 Jira를 건너뛴 경우:**

- task_name_raw이 비어있으면 사용자에게 task name 입력 요청
- jira 필드는 비어있게 된다

### 4. task name 정규화

- 소문자로 변환, 공백/언더스코어를 `-`로 교체, `[a-z0-9-]` 외 문자 제거

### 5. 메타데이터 계산

- created: 프로젝트 설정에 `timezone`이 있으면 사용 (`TZ={timezone} date "+%Y-%m-%d"`), 없으면 `date "+%Y-%m-%d"`
- owner: `git config user.name`
- jira: Jira 이슈 URL (건너뛴 경우 비어있음)
- branch_name: 프로젝트 설정의 `branch_pattern` 적용 (기본: `feature/{task_name}`)
- base_branch:
  `_shared/resolve-base-branch.md`가 존재하는 경우:
  > **Shared**: `_shared/resolve-base-branch.md` 절차를 따른다.

  없는 경우: 프로젝트 설정의 `base_branch` → 자동 탐지 → 사용자 질문

### 6. 브랜치 또는 worktree 생성

**`skip_branch`가 true인 경우:**
- 브랜치/worktree 생성을 완전히 건너뛰고 현재 브랜치 사용

rules/project-params.md에서 **`worktree_policy` 결정** (기본: `optional`):

**`worktree_policy` = `optional`인 경우:**
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
- "예": `always` 경로로 진행
- "아니오": `never` 경로로 진행

**`worktree_policy` = `always` (또는 사용자가 "예" 선택)인 경우:**

a. 프로젝트 설정에 `develop_sync`가 설정된 경우 해당 명령으로 develop 브랜치 동기화, 없으면:
   ```bash
   # fork_workflow=true → git fetch upstream && git fetch origin
   # fork_workflow=false (또는 미설정) → git fetch origin
   ```
b. worktree 생성:
   `_shared/create-worktree.md`가 존재하는 경우:
   > **Shared**: `_shared/create-worktree.md` 절차를 따른다.
   > - `task_name` = {task_name}, `branch_name` = {branch_name}, `base_ref` = {base_branch}, `create_branch` = `true`

   없는 경우 (인라인):
   ```bash
   WORKTREE_DIR="../worktrees/{task_name}"
   git worktree add -b {branch_name} "$WORKTREE_DIR" ${base_branch}
   ```
c. 프로젝트 설정에 `dependency_install`이 설정된 경우 worktree 내에서 실행:
   ```bash
   cd "$WORKTREE_DIR" && {dependency_install}
   ```
d. Step 7에서 사용할 `worktree_path = WORKTREE_DIR` 저장

**`worktree_policy` = `never` (또는 사용자가 "아니오" 선택)인 경우:**

a. 브랜치 생성 및 체크아웃:
   ```bash
   git checkout -b {branch_name} ${base_branch}
   ```
b. `worktree_path` = 미설정 (worklog는 현재 저장소에 위치)

### 7. worklog 생성

- worklog 템플릿 탐지:
  ```bash
  TEMPLATE="$(git rev-parse --show-toplevel)/.claude/skills/_templates/worklog/worklog.md"
  [ -f "$TEMPLATE" ] || TEMPLATE="$HOME/.claude/skills/_templates/worklog/worklog.md"
  ```
- worklog 위치 결정:
  - worktree가 생성된 경우: `{worktree_path}/.claude/worklogs/{task_name}/`
  - 아닌 경우: `.claude/worklogs/{task_name}/`
- 결정된 위치에 폴더 생성
- 폴더가 이미 존재하는 경우: 경로를 출력하고 중단.
- 템플릿을 `{worklog_dir}/worklog.md`로 복사
- frontmatter 채우기: jira, branch, created, owner, phase (`ANALYZE`로 설정)
- worktree_path가 설정된 경우 frontmatter에 `worktree_path`도 추가
- `.claude/worklogs/.active`를 worklog 폴더 경로로 설정

### 8. 초기 내용 채우기

- `task_brief`가 있는 경우: Dashboard 상단의 Goal 섹션을 task brief로 설정
- 초기 Next actions 설정 (Dashboard 내부): `- [ ] /vwork 로 워크플로우 시작`

### 9. 요약 출력

```
Worklog created:
  - Task: {task_name}
  - Path: {worklog_path}
  - Branch: {branch_name} (or "current branch")
  - Worktree: {worktree_path} (or "none")
  - Jira: {jira_url} (or "none")
  - Phase: ANALYZE
```

출력: "`/vwork {worklog_path}` 로 워크플로우를 시작하세요."

이제 실행하라.
