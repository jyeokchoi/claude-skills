# Project Parameters (프로젝트별 설정)

이 파일은 모든 워크플로우 스킬이 참조하는 프로젝트별 설정이다.
프로젝트 루트의 `.claude/rules/` 아래에 `workflow.md` 또는 `project-params.md`로 배치한다.
스킬은 이 파일이 있으면 설정값을 사용하고, 없으면 기본값(자동 탐지 → 사용자 질문 → project_memory 기억)으로 동작한다.

---

## Git

| 설정 | 기본값 | 비고 | 참조 스킬 |
|------|--------|------|-----------|
| `base_branch` | (자동 탐지: `gh repo view --json defaultBranchRef`) | PR base, diff 기준. remote-qualified 가능 (e.g., `upstream/develop`) | vplan, explain-code, exhaustive-review, exclude-local-only-commits, create-pr, worklog-compact, worklog-finish, worklog-start, worklog-amend, offload-to-branch, prd-taskmaster, web-task |
| `fork_workflow` | `false` | `true` = origin은 fork, upstream은 org repo | offload-to-branch, exclude-local-only-commits, worklog-finish, worklog-start, worklog-compact, explain-code |
| `branch_pattern` | `feature/{task_name}` | jira 연동 시 `feature/{jira_key}.{task_name_short}` 등 | worklog-start, worklog-amend, offload-to-branch |
| `develop_sync` | `git fetch origin` | worktree 생성 전 develop 동기화 명령 | worklog-start |

## Worktree

| 설정 | 기본값 | 비고 | 참조 스킬 |
|------|--------|------|-----------|
| `worktree_policy` | `optional` | `always` / `optional` / `never` | worklog-start, worklog-amend |
| `dependency_install` | (자동 탐지: lock file 기반) | worktree 생성 후 의존성 설치 명령. `{worktree_path}` 치환 가능 | create-worktree, worklog-start |

## Jira

| 설정 | 기본값 | 비고 | 참조 스킬 |
|------|--------|------|-----------|
| `jira_pattern` | (없음 = Jira 비활성) | Jira 이슈 키 정규식 (e.g., `PROJ-\d+`) | vplan, worklog-start, offload-to-branch, worklog-amend |
| `jira_base_url` | (없음) | Jira 이슈 URL prefix (e.g., `https://company.atlassian.net/browse/`) | worklog-start, create-jira-issue, worklog-amend |

## Test

| 설정 | 기본값 | 비고 | 참조 스킬 |
|------|--------|------|-----------|
| `test_command` | (자동 탐지: package.json scripts) | 테스트 실행 명령 (e.g., `yarn test --run`) | vimpl, vanalyze, tdd-review, integration-test, prd-taskmaster, web-task |

## Lint / Format

| 설정 | 기본값 | 비고 | 참조 스킬 |
|------|--------|------|-----------|
| `lint_command` | (자동 탐지: package.json의 lint script + 패키지 매니저) | 린트 명령 (e.g., `yarn eslint --fix`) | lint-format |
| `format_command` | (자동 탐지: package.json의 prettier script + 패키지 매니저) | 포맷 명령 (e.g., `yarn prettier --write`) | lint-format |

## Locale

| 설정 | 기본값 | 비고 | 참조 스킬 |
|------|--------|------|-----------|
| `timezone` | (시스템 시간대) | 타임스탬프 시간대 (e.g., `Asia/Seoul`, `America/New_York`) | worklog-start, worklog-update, web-task, vanalyze |
| `timestamp_suffix` | (없음) | 타임스탬프 뒤에 붙는 문자열 (e.g., `KST`) | worklog-update, vanalyze |

## Project Context

| 설정 | 기본값 | 비고 | 참조 스킬 |
|------|--------|------|-----------|
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 (e.g., `typings/`). 코드 분석 시 참조 | vplan, vanalyze |
| `completion_promise_default` | `**WORKLOG_TASK_COMPLETE**` | worklog frontmatter의 기본 완료 약속 문자열 | worklog-start, vimpl, web-task |
| `slack_integration` | `false` | `true`면 worklog-start에서 Slack 컨텍스트 수집 | worklog-start |

## Skill Routing (선택)

워크플로우 스킬 간 참조 시 사용할 이름:
- 기본: `/vplan`, `/vimpl`, `/vqa`, `/vanalyze`, `/worklog-start`, `/worklog-ralph`, `/worklog-finish` 등
- 프로젝트별 prefix 필요 시 여기에 매핑 기록
