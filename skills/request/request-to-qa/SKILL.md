---
name: request-to-qa
description: 워크로그 기반으로 QA 엔지니어에게 수동 테스트 플로우 보고서를 생성하고 Jira에 첨부한다
argument-hint: 'Usage: /request-to-qa [worklog-folder-or-worklog.md]'
---

## 경로 규칙

> **`_shared/X`** → `{Base directory}/../_shared/X` (`{Base directory}`는 시스템이 주입하는 "Base directory for this skill" 값)
> **`X` 스킬** → 스킬 시스템이 제공하는 경로. `Glob("**/X/SKILL.md")`로 탐색 가능.

워크로그의 변경 내용을 분석하여 QA 엔지니어가 수동 테스트를 수행할 수 있도록 테스트 플로우와 영향 범위를 정리한 보고서를 생성한다. vqa/vtest/vanalyze 스타일의 분석을 활용한다.

## 대상 결정

- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다.
- worklog.md에서 `jira` 필드를 추출한다 (Jira 첨부용).

## Phase 0: 컨텍스트 수집

1. worklog.md 읽기 → Goal, Completion criteria, Decisions
2. `resolve-base-branch` 스킬의 절차를 따라 `BASE_REF`를 설정한다.
3. 변경 파일 수집:
   ```bash
   git diff {BASE_REF}...HEAD --name-only
   git diff {BASE_REF}...HEAD --stat
   ```
4. 기존 분석 결과 로드 (있으면):
   - `{WORKLOG_DIR}/report.md` (vqa 보고서)
   - `{WORKLOG_DIR}/analysis.md` (vanalyze 보고서)
5. 테스트 현황 파악:
   - `_shared/resolve-test-command.md`를 로드하고 `TEST_COMMAND`를 설정한다.
   - 테스트 실행: `{TEST_COMMAND}` → 결과 캡처
   - 변경 파일 근처의 테스트 파일 경로 탐색 (Glob으로 `*.test.*`, `*.spec.*`)

## Phase 1: 병렬 분석 (3개 에이전트)

3개 에이전트를 **병렬로** 실행한다.

### Agent 1: 기능 테스트 시나리오 (sonnet)

```
Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     prompt="
Read-only 분석 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

수동 QA 테스트 시나리오를 작성한다.

## Your Task

worklog의 Goal과 Completion criteria를 기반으로, QA 엔지니어가 수동으로 수행할 테스트 시나리오를 작성한다.

각 시나리오에 포함할 내용:
1. **시나리오 ID**: TC-{NNN}
2. **시나리오명**: 한 줄 요약
3. **우선순위**: P0 (필수) / P1 (권장) / P2 (선택)
4. **전제 조건**: 필요한 상태, 데이터, 설정
5. **테스트 단계**: 번호 매긴 구체적 조작 순서
6. **기대 결과**: 각 단계 또는 최종 기대 동작
7. **관련 파일**: 해당 기능의 소스 파일

P0 기준: 새로 추가된 핵심 기능, 기존 기능에 영향을 주는 변경
P1 기준: 엣지 케이스, 설정 조합, 다양한 입력
P2 기준: UI 미세 조정, 비핵심 경로

## Worklog Context
{worklog content}

## Code Changes
{diff + changed file paths}

## Output Format
### P0 시나리오

#### TC-001: {시나리오명}
- **전제 조건**: {조건}
- **단계**:
  1. {step}
  2. {step}
- **기대 결과**: {expected}
- **관련 파일**: {files}

### P1 시나리오
...

### P2 시나리오
...
")
```

### Agent 2: 영향 범위 분석 (opus)

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="
Read-only 분석 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

변경의 영향 범위를 분석하여 회귀 테스트가 필요한 영역을 식별한다.

## Your Task

1. **직접 변경 영역**: diff에서 직접 수정된 기능
2. **간접 영향 영역 (blast radius)**: 변경된 모듈을 import/사용하는 다른 모듈 추적
3. **회귀 테스트 필요 영역**: 기존 기능 중 깨질 수 있는 부분
4. **리스크 평가**: 데이터 손실, 내보내기 깨짐, 프리뷰 오류 등 심각한 리스크

각 영역에 대해 리스크 수준(HIGH/MED/LOW)과 간단한 확인 방법을 기술한다.

## Code Changes
{diff + changed file paths}

## Worklog Context
{worklog content}

## Output Format
### 직접 변경 영역
- {영역}: {변경 내용} — 리스크: {HIGH/MED/LOW}

### 간접 영향 영역
- {영역}: {왜 영향받는지} — 리스크: {HIGH/MED/LOW} — 확인 방법: {간단한 확인 방법}

### 회귀 테스트 필요 영역
- {영역}: {무엇을 확인해야 하는지} — 리스크: {HIGH/MED/LOW}

### 리스크 요약
| 리스크 | 심각도 | 설명 | 완화 방법 |
")
```

### Agent 3: 자동 테스트 커버리지 갭 (sonnet)

```
Task(subagent_type="oh-my-claudecode:analyst", model="opus",
     prompt="
Read-only 분석 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

자동 테스트 커버리지를 분석하여 QA 수동 확인이 필수인 영역을 식별한다.

## Your Task

1. **자동 테스트 커버 영역**: 변경된 기능 중 기존 테스트로 이미 검증되는 부분 (QA가 참고만 하면 되는 영역)
2. **수동 확인 필수 영역**: 자동 테스트로 커버되지 않아 QA가 반드시 수동으로 확인해야 하는 부분
3. **E2E 관점 시나리오**: 유닛/통합 테스트로는 검증 불가하고 실제 앱에서만 확인 가능한 시나리오

## Test Files
{변경 파일 근처의 테스트 파일 경로 + 내용 요약}

## Test Results
{테스트 실행 결과}

## VQA Report (if exists)
{기존 report.md 내용 또는 '없음'}

## Code Changes
{diff + changed file paths}

## Output Format
### 자동 테스트 커버 영역
- {기능/모듈}: {테스트 파일} — {무엇을 검증하는지}

### 수동 확인 필수 영역
- {기능/모듈}: {왜 수동 확인이 필요한지}

### E2E 확인 필요 시나리오
- {시나리오}: {왜 실제 앱에서만 확인 가능한지}
")
```

## Phase 2: 보고서 생성

3개 에이전트 결과를 합산하여 `{WORKLOG_DIR}/attachments/qa-report.md`에 작성:

```markdown
# QA 테스트 요청: {task-name}

**Date:** {timestamp}
**Jira:** {jira_url}
**Branch:** {branch_name}

## 변경 요약
{worklog Goal 기반 1-2문장}

## 수동 테스트 시나리오

### P0 (필수)

#### TC-001: {시나리오명}
- **전제 조건**: {필요한 상태/데이터}
- **단계**:
  1. {step}
  2. {step}
  3. {step}
- **기대 결과**: {expected}
- **관련 파일**: {changed files}

#### TC-002: ...

### P1 (권장)
...

### P2 (선택)
...

## 영향 범위 (회귀 테스트)

| 영역 | 리스크 | 확인 방법 | 자동 테스트 커버 |
|------|--------|----------|----------------|
| {영역} | HIGH | {간단한 확인 방법} | 수동 필요 |
| {영역} | MED | {간단한 확인 방법} | 자동 커버 |

## 자동 테스트 현황
- 전체 테스트: {N}개 통과
- 이번 변경 관련 테스트: {N}개
- 수동 확인 필수 영역: {N}개

## 리스크 요약

| 리스크 | 심각도 | 설명 | 완화 방법 |
|--------|--------|------|----------|

## QA 액션 아이템
- [ ] P0 시나리오 전체 실행
- [ ] P1 시나리오 실행
- [ ] 영향 범위 회귀 테스트 ({N}개 영역)
```

## Phase 3: 배포

1. 보고서 Gist 업로드:
   ```bash
   GIST_URL=$(gh gist create --filename qa-report.md "{WORKLOG_DIR}/attachments/qa-report.md" 2>/dev/null)
   ```

2. Jira 코멘트 추가 (`addCommentToJiraIssue`):
   ```
   QA 테스트 요청 보고서: {GIST_URL}
   ```

3. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `timeline_entry`: "QA 테스트 요청 보고서 생성 — TC {N}개 (P0: {n}, P1: {n}, P2: {n})"

4. 사용자에게 안내:
   ```
   보고서: {GIST_URL}
   → Jira 코멘트에 링크가 추가되었습니다: {jira_url}
   ```

## 절대 규칙

- **분석 에이전트는 read-only.** Write/Edit/Bash를 사용하지 않는다.
- **3개 에이전트는 반드시 병렬로 실행한다.**
- **기존 vqa/vanalyze 결과가 있으면 활용한다.** 없으면 자체 분석으로 대체.
- **테스트 시나리오는 QA 엔지니어가 수동으로 수행 가능한 수준으로 구체적이어야 한다.** "기능을 테스트한다" 같은 모호한 지시 금지.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
