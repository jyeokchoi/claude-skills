---
name: vwork
description: Unified workflow orchestrator. Single entry point for analyze → PRD → plan → implement → verify → test → finish pipeline, driven by worklog phase.
argument-hint: 'Usage: /vwork [--auto] [worklog-path | task-name | ISSUE-KEY] [brief]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용.

워크로그 phase를 기반으로 전체 작업 라이프사이클을 관리하는 통합 오케스트레이터.

## 입력

- 원본 인자: $ARGUMENTS

인자 해석:
- `--auto` 플래그: 자동 모드 활성화 (ralph loop이 모든 phase를 구동)
- 첫 번째 비플래그 토큰: 워크로그 경로, 작업명, 또는 Jira 이슈 키
- 나머지 텍스트: 작업 설명 (task brief)

## Phase 상태 머신

워크로그의 `phase` 필드가 워크플로우를 구동한다:

```
[기존 수정] → ANALYZE → PRD → PLAN → IMPL ←──┐
                                        ↓     │
[신규 기능] ──────────→ PRD → PLAN → IMPL   VERIFY ─┤──→ DONE
                                        ↓     │
                                       TEST ──┘
```

진입점은 작업 유형에 따라 달라진다:
- **기존 코드 수정** (modification): ANALYZE부터 시작 — 기존 코드 이해와 영향도 분석이 필요
- **신규 기능** (new-feature): PRD부터 시작 — 분석할 기존 코드가 없으므로 요구사항 정의부터

피드백 루프:
- VERIFY → IMPL (비테스트 이슈) → VERIFY (수정 후 재검증)
- VERIFY → TEST (테스트 갭) → VERIFY (테스트 작성 후 재검증)

phase 전이는 피드백 루프를 제외하면 **전진 전용**이다.

## 절차

### 1. 워크로그 결정 또는 생성

**인자가 워크로그 경로(폴더 또는 .md 파일)인 경우:**
- 기존 워크로그를 로드하고 `phase` 필드를 읽는다
- phase가 비어있거나 미설정이면: 작업 유형 감지 (아래 참조) → 초기 phase 설정
- 재개 검증 수행 (아래 참조)
- Step 2 (모드 선택)로 진행

**인자가 작업명 또는 Jira 이슈 키인 경우 (기존 워크로그 없음):**
- `/worklog-start` 로직을 호출하여 새 워크로그 생성
- 작업 유형 감지 (아래 참조) → 초기 phase 설정
- Step 2로 진행

**인자 없음:**
- 활성 워크로그 검색 (`.claude/worklogs/.active` 또는 find)
- 발견 시: 워크로그 로드, phase 읽기, 재개 검증 수행, Step 2로 진행
- 미발견 시: 사용자에게 작업명 또는 이슈 키를 요청, `/worklog-start`로 새 워크로그 생성

**작업 유형 감지 (신규 vs 기존 수정):**

워크로그의 Goal, Completion criteria, task brief에서 작업 유형을 자동 감지한다:

| 유형 | 감지 신호 | 초기 phase |
|------|-----------|------------|
| **신규 기능** (new-feature) | "새 기능", "new feature", "신규", "새로 만들", "create", "build from scratch", "greenfield" | `PRD` |
| **기존 수정** (modification) | "수정", "변경", "fix", "refactor", "modify", "개선", "migrate", "버그", "regression", 또는 특정 파일/모듈 경로 언급 | `ANALYZE` |

- frontmatter에 `type: new-feature` 또는 `type: modification`이 명시되어 있으면 감지를 건너뛰고 해당 값을 사용한다.
- 키워드로 명확히 판별된 경우에도, 판단 결과와 근거를 워크로그 Decisions에 기록한다.
- 감지 불가 시:
  - **auto 모드**: 에이전트가 Goal, Completion criteria, task brief, 관련 코드베이스 상태(기존 파일 존재 여부 등)를 종합하여 최선의 판단을 내린다. **판단 결과와 근거를 반드시 워크로그 Dashboard의 Decisions 섹션에 기록한다:**
    ```
    - [CURRENT] Task type: {new-feature|modification} — 근거: {판단 근거 1~2문장}
    ```
  - **step 모드**: 사용자에게 질문:
    ```
    AskUserQuestion:
      question: "이 작업은 신규 기능인가요, 기존 코드 수정인가요?"
      header: "Task Type"
      options:
        - label: "신규 기능"
          description: "새로 만드는 기능입니다. 요구사항 정의(PRD)부터 시작합니다."
        - label: "기존 코드 수정"
          description: "기존 코드를 변경합니다. 코드 분석(ANALYZE)부터 시작합니다."
    ```

**재개 검증 (기존 워크로그만 해당):**

방금 생성된 워크로그(빈 Dashboard)면 건너뛴다. 기존 워크로그를 재개할 때:

1. 상태 요약 출력:
   ```
   워크로그 상태 요약
   Goal: {goal}
   Jira: {jira_url}
   Branch: {branch}
   완료 기준: {completed}/{total}
   Phase: {phase}
   결정사항: {decisions}
   최근 작업: {last timeline entry summary}
   ```

2. 이전 결정 검증 (Decisions 섹션이 비어있지 않은 경우):
   ```
   AskUserQuestion:
     question: "이전 세션의 결정사항이 여전히 유효한가요?"
     header: "Decisions"
     options:
       - label: "예, 유효함"
         description: "기존 결정대로 이어서 진행"
       - label: "아니오, 수정 필요"
         description: "일부 결정이 바뀌었거나 재검토 필요"
   ```
   - "수정 필요" 선택 시: 자유 입력으로 변경사항 수집, 기존 결정에 `[INVALIDATED {date}]` 표시, 새 결정에 `[CURRENT]` 추가

3. `_shared/update-worklog.md`로 워크로그 업데이트:
   - `timeline_entry`: "세션 재개 — Phase: {phase}, 재개 지점: {first pending action}"

### 2. 모드 선택

**`--auto` 플래그가 있는 경우:**
- mode = auto 설정
- 출력: "자동 모드 활성화. 완료까지 자동으로 진행합니다."
- ralph loop 활성화:
  1. `rules/project-params.md`에서 `completion_promise` 사용 (기본값: `**WORKLOG_TASK_COMPLETE**`)
  2. `state_write(mode="ralph")`로 ralph 상태 생성:
     ```json
     {
       "active": true,
       "iteration": 1,
       "max_iterations": 100,
       "completion_promise": "{COMPLETION_PROMISE}",
       "worklog_path": "{WORKLOG_DIR}",
       "linked_ultrawork": true
     }
     ```
  3. `state_write(mode="ultrawork")`로 ultrawork 상태 생성:
     ```json
     {
       "active": true,
       "linked_to_ralph": true
     }
     ```
- Step 3으로 진행

**`--auto` 플래그가 없는 경우:**

```
AskUserQuestion:
  question: "워크플로우 모드를 선택하세요."
  header: "Mode"
  options:
    - label: "자동 모드 (Auto)"
      description: "Ralph loop으로 모든 페이즈를 자동 진행합니다. 각 단계에서 중요 결정만 물어봅니다."
    - label: "단계별 모드 (Step-by-step)"
      description: "각 페이즈 완료 후 다음 단계 진행 여부를 확인합니다."
```

- "자동 모드": mode = auto, ralph loop 활성화 (--auto 경로와 동일)
- "단계별 모드": mode = step

### 3. 오케스트레이션 컨텍스트

서브 스킬이 오케스트레이션 상태를 인식할 수 있도록 컨텍스트를 기록한다:

- `_shared/orchestration-context.md`를 로드하고 **vwork — 쓰기** 프로토콜을 따른다.
- `state_write(mode="vwork", data={ "active": true, "mode": "{auto|step}", "current_phase": "{phase}", "worklog_dir": "{WORKLOG_DIR}", "feedback_iterations": 0 })`
- **상태 보존 규칙**: `state_write` 호출 전에 반드시 `state_read(mode="vwork")`로 현재 상태를 읽고, `feedback_iterations` 등 누적 필드를 보존한다. feedback loop 진입 시 `feedback_iterations`를 증가시킨다. 최대 5회 초과 시 사용자에게 보고.
- 각 서브 스킬 호출 전에 `current_phase`를 해당 phase로 업데이트한다.

### 4. Phase 실행

워크로그의 `phase` 필드를 읽고 해당 phase 스킬을 실행한다.

#### ANALYZE phase

- `/vanalyze {WORKLOG_DIR}` 호출
- 완료 시: `phase: 'PRD'`로 업데이트
- step 모드인 경우:
  ```
  AskUserQuestion:
    question: "분석이 완료되었습니다. PRD(요구사항 정의)로 진행할까요?"
    header: "Phase: ANALYZE → PRD"
    options:
      - label: "진행"
        description: "요구사항 정의를 시작합니다"
      - label: "분석 재실행"
        description: "추가 분석이 필요합니다"
      - label: "PRD 건너뛰기 → 바로 플래닝"
        description: "이미 요구사항이 명확합니다"
  ```
  - "진행": PRD로 계속
  - "분석 재실행": ANALYZE에 머무름
  - "PRD 건너뛰기": `phase: 'PLAN'`으로 업데이트

#### PRD phase

- `/vplan {WORKLOG_DIR}` 호출 — orchestration state `current_phase=PRD`에 따라 vplan이 Stage 1 (PRD)만 실행
- 완료 시: `phase: 'PLAN'`으로 업데이트
- step 모드인 경우: "구현 플래닝으로 진행할까요?" 질문

#### PLAN phase

- `/vplan {WORKLOG_DIR}` 호출 — orchestration state `current_phase=PLAN`에 따라 vplan이 Stages 2-4 + consensus review 실행
- 완료 시: `phase: 'IMPL'`로 업데이트
- step 모드인 경우: "구현을 시작할까요?" 질문

#### IMPL phase

- `/vimpl {WORKLOG_DIR}` 호출
- 완료 시: `phase: 'VERIFY'`로 업데이트
- step 모드인 경우: "검증을 시작할까요?" 질문

#### VERIFY phase

- `/vqa {WORKLOG_DIR}` 호출
- `{WORKLOG_DIR}/report.md`를 읽는다. `<!-- QA:VERDICT:START -->` 블록을 파싱하여 `route:` 필드를 추출한다.
- verdict `route`에 따른 매핑:
  - **all_pass** (전체 통과): `phase: 'DONE'`으로 업데이트
  - **code_issues 또는 code_issues_and_test_gaps** (Intent/Spec/Architecture NEEDS_WORK, 테스트 갭 동반 여부 무관): `phase: 'IMPL'`로 업데이트 (vqa가 이미 FIX/TEST items를 plan.md에 추가함. code_issues_and_test_gaps인 경우 IMPL 완료 후 VERIFY에서 test_gaps만 남으면 TEST로 진행)
  - **test_gaps** (Test Verification NEEDS_WORK만 해당): `phase: 'TEST'`로 업데이트
- step 모드인 경우: 결과를 제시하고 사용자에게 질문

#### TEST phase

- `/vtest {WORKLOG_DIR}` 호출
- 완료 시: `phase: 'VERIFY'`로 업데이트 (테스트 작성 후 재검증)
- VERIFY ↔ TEST 반복 최대 5회. 5회 이후 사용자에게 보고.

#### DONE phase

- `/worklog-finish {WORKLOG_DIR}` 호출
- 오케스트레이션 컨텍스트 정리: `state_write(mode="vwork", data={ "active": false })`
- ralph loop이 활성 상태면 종료: `/oh-my-claudecode:cancel`
- 완료 요약 출력

### 5. Phase 전이 프로토콜

모든 phase 전이는 `_shared/update-worklog.md`를 따른다:
- `phase_update`: `{NEW_PHASE}`
- `dashboard_updates`: 현재 phase를 반영하는 다음 액션
- `timeline_entry`: "Phase 전이: {OLD} → {NEW}"

### 6. 피드백 루프

```
VERIFY → IMPL    (비테스트 이슈: 스펙 이탈, 아키텍처 문제)
VERIFY → TEST    (테스트 갭: 커버리지 부족, 약한 assertion)
TEST   → VERIFY  (테스트 작성 완료, 재검증 필요)
IMPL   → VERIFY  (수정 적용 완료, 재검증 필요)
```

루프당 최대 피드백 반복: 5회. 5회 이후 해결되지 않은 경우:
- **step 모드**: 남은 이슈를 사용자에게 보고. 계속 반복 / 현재 상태 수용 / 중단 중 선택.
- **auto 모드**: 에이전트가 남은 이슈를 평가하고 최선의 판단을 내린다. **판단 결과와 근거를 반드시 워크로그 Dashboard의 Decisions에 기록한다:**
  ```
  - [CURRENT] Feedback loop 종료 (5회 도달) — 근거: {미해결 이슈 요약 + 수용/중단 판단 이유}
  ```
  수용 가능한 수준이면 다음 phase로 진행하고, 치명적 이슈가 남아있으면 사용자에게 보고한다.

### 7. 에러 처리

| 상황 | 처리 |
|------|------|
| 워크로그 미발견 | 에러 출력, `/worklog-start` 안내 |
| phase 필드 비어있음 | 작업 유형 감지 → `ANALYZE` (modification) 또는 `PRD` (new-feature) |
| phase 스킬 실패 | 워크로그에 에러 기록, 사용자에게 질문 |
| ralph loop 활성 상태인데 phase가 DONE | ralph 종료, 워크로그 마무리 |

## 절대 규칙

- **워크로그가 유일한 출처.** 모든 phase는 워크로그에서 읽고 워크로그에 쓴다.
- **phase 필드를 항상 최신으로 유지.** 각 phase 전후에 반드시 업데이트.
- **auto 모드에서 phase를 건너뛰지 않는다.** 전진 전용. 단, 신규 기능은 PRD부터 시작하므로 ANALYZE를 건너뛰는 것이 아니라 시작점이 다른 것이다.
- **step 모드는 건너뛸 수 있다.** 사용자가 PRD 생략이나 phase 점프를 선택할 수 있다.
- **auto 모드는 ralph loop을 활성화한다.** 컨텍스트 윈도우 한계를 넘어 지속성을 보장.
- **step 모드는 항상 질문한다.** 사용자 확인 없이 자동 진행하지 않는다.
- **피드백 루프는 상한이 있다.** 루프당 최대 5회 반복. auto 모드에서 상한 도달 시 판단 근거를 워크로그에 기록.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
