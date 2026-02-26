---
name: worklog-compact
description: Worklog의 Timeline을 코드 최종 상태 기반 요약 문서로 대체한다
argument-hint: 'Usage: /worklog-compact [worklog-path] [--dry-run]'
---

# Worklog Compact

기존 Timeline(세션별 작업 기록)을 삭제하고, 현재 코드 상태를 base branch와 비교하여 **최종 결과 문서**로 대체한다.

## Project settings

이 스킬은 다음 프로젝트 설정을 참조한다 (`rules/workflow.md` 또는 `rules/project-params.md`):

| 설정 | 용도 |
|------|------|
| `base_branch` | diff 기준 브랜치 (e.g., `upstream/develop`) |
| `fork_workflow` | remote 결정 (`true` → upstream, `false` → origin) |

설정이 없으면: `gh repo view --json defaultBranchRef`로 자동 탐지 → 실패 시 사용자에게 질문 → `project_memory_add_note("base_branch: {answer}")`

## 목적

- 다음 세션에서 코드를 빠르게 이해하기 위한 컨텍스트
- PR 설명이나 Jira에 첨부할 최종 변경 요약

## 핵심 원칙

- **코드가 진실의 원천**: Timeline의 과거 기록이 아닌 git diff(base branch 대비)가 정보의 원천
- **중간 과정 불필요**: 작업 도중의 시행착오, 롤백, 디버깅 기록은 모두 삭제
- **Dashboard 보존**: Goal, Completion criteria, Next actions, Decisions, Remember, Links 등 Dashboard는 그대로 유지

## 실행 단계

### Step 1: 워크로그 탐색

- $ARGUMENTS가 경로이면 해당 경로 사용
- 없으면 활성 워크로그 자동 탐색:
  ```bash
  find .claude/worklogs -name "worklog.md" -type f 2>/dev/null | head -5
  ```

### Step 2: 현재 상태 수집

**a. Base branch 결정:**
- `rules/workflow.md`에서 `base_branch` 설정을 읽는다 (e.g., `BASE_REF="upstream/develop"`)
- `fork_workflow` 설정도 확인: `true`면 remote=`upstream`, `false`면 remote=`origin`
- 설정이 없으면 자동 탐지:
```bash
# 1. gh repo view --json defaultBranchRef로 기본 브랜치 탐지
# 2. fork 여부: git remote -v 로 upstream 존재 확인
# 3. 탐지 실패 시 사용자에게 질문 → project_memory_add_note("base_branch: {answer}")
```

**b. 변경 파일 목록:**
```bash
MERGE_BASE=$(git merge-base HEAD $BASE_REF)
git diff $MERGE_BASE...HEAD --name-only
git diff $MERGE_BASE...HEAD --stat
```

**c. 변경 내용 상세:**
```bash
git diff $MERGE_BASE...HEAD
```

**d. 현재 워크로그 읽기:**
- Dashboard 전체 (보존 대상)
- Timeline 전체 (삭제 대상이지만, Design Decisions 추출을 위해 먼저 읽음)
- Frontmatter (보존)

### Step 3: 코드 분석

변경된 파일들을 읽고 다음을 파악한다:

1. **변경 파일 구조**: 어떤 디렉토리/모듈이 영향받았는지
2. **아키텍처/설계 결정**: 기존 Timeline의 Decisions + 코드 구조에서 추론
3. **주요 로직 변경**: base branch 대비 새로 추가/수정/삭제된 핵심 로직
   - before(base): 기존 코드의 동작
   - after(branch): 변경 후 동작
   - 중간 과정의 변경이 아닌 base ↔ 현재 코드 비교만 기술

### Step 4: 최종 결과 문서 생성

Timeline 영역(`<!-- WORKLOG:TIMELINE:START -->` ~ `<!-- WORKLOG:TIMELINE:END -->`)을 다음 구조로 대체:

```markdown
<!-- WORKLOG:TIMELINE:START -->
<!-- WORKLOG:TIMELINE:INSERT:HERE -->

## Compact Summary (generated: {YYYY-MM-DD HH:MM})

### Overview
- {한 줄 요약: 이 브랜치가 하는 일}

### Architecture / Design Decisions
- {왜 이 구조를 선택했는지}
- {주요 설계 결정과 근거}

### Changes (vs {BASE_REF})

**변경 파일 구조:**
{tree 형식 또는 디렉토리별 그룹핑}

**주요 로직 변경:**

#### {변경 영역 1}
- **Before (base):** {기존 동작 설명}
- **After (branch):** {변경 후 동작 설명}
- **변경 이유:** {근거}

#### {변경 영역 2}
...

### Remaining Work
{Dashboard의 Next actions 중 미완료 항목이 있으면 여기에 요약. 모두 완료면 이 섹션 생략}

<!-- WORKLOG:TIMELINE:END -->
```

### Step 5: 워크로그 업데이트

- `--dry-run`이면 생성된 문서를 출력만 하고 종료
- 아니면 worklog.md의 Timeline 영역을 새 내용으로 교체
- Dashboard, Frontmatter는 변경하지 않음

### Step 6: 결과 출력

```
Worklog compacted:
  - Path: {worklog_path}
  - Base: {BASE_REF} ({merge_base_short})
  - Changed files: {count}
  - Timeline entries removed: {old_entry_count}
  - New: Compact Summary
```

## 주의사항

- `<!-- WORKLOG:TIMELINE:INSERT:HERE -->` 마커는 반드시 유지 (compact 이후에도 Timeline 추가 가능)
- Dashboard 구조 (`<!-- WORKLOG:DASHBOARD:START/END -->`) 유지
- Frontmatter 절대 수정 금지
- Remember 섹션은 절대 삭제/축약하지 않는다 (사용자가 명시적으로 삭제 요청한 경우에만 제거)
- Decisions의 설계 근거는 Architecture 섹션에 반영한 뒤에도 Dashboard에서 삭제하지 않는다

## 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `--dry-run` | 실제 수정 없이 미리보기만 | false |

Proceed now.
