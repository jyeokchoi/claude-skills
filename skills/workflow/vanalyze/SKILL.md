---
name: vanalyze
description: Deep code understanding and impact analysis for existing code modifications. Outputs analysis document for vplan input.
argument-hint: 'Usage: /vanalyze [worklog-folder-or-worklog.md] [file-or-module-path]'
---

## 경로 규칙

> **`_shared/X`** → `{Base directory}/../_shared/X` (`{Base directory}`는 시스템이 주입하는 "Base directory for this skill" 값)
> **`X` 스킬** → 스킬 시스템이 제공하는 경로. `Glob("**/X/SKILL.md")`로 탐색 가능.

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.local.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 |
| `timestamp_suffix` | (없음) | 타임스탬프 뒤 문자열 (예: KST) |

기존 코드를 깊이 이해하고 계획된 수정사항의 영향을 평가하는 코드 분석 워크플로우를 실행한다. 출력 결과는 `/vplan`의 입력 컨텍스트로 사용된다.

## 정규 단계 테이블 (SSOT)

아래 표가 vanalyze의 단계 전이 단일 진실 기준이다.

| 현재 단계 | 완료 조건 | 다음 단계 | 주요 출력 |
|-----------|-----------|----------|----------|
| 사전 준비 | 입력/컨텍스트/TEST_COMMAND 확정 | Phase 0 또는 Phase 1 | 준비 컨텍스트 |
| Phase 0 (버그 재현) | 버그 재현 결과 확정 | Phase 1 또는 종료 | 재현 테스트, 재현 결과 |
| Phase 1 (범위 식별) | 분석 범위 확정 | Phase 2 | `SCOPE_FILES`, `SCOPE_DESCRIPTION` |
| Phase 2 (심층 이해) | deep analysis 완료 | Phase 3 | `ARCHITECTURE_RESULT`, `BEHAVIOR_RESULT`, `TEST_COVERAGE_RESULT` |
| Phase 3 (영향도) | impact 분석/교차검증 완료 | Phase 4 | `IMPACT_RESULT` |
| Phase 4 (종합) | `analysis.md` 작성 완료 | Phase 5 | `ANALYSIS_FILE` |
| Phase 5 (검토/인계) | 사용자 검토 + 워크로그 업데이트 완료 | 종료 | 분석 요약, 다음 단계 안내 |

전이 예외:
- 버그 리포트가 아니면 Phase 0을 건너뛰고 Phase 1로 시작한다.
- 버그 리포트인데 재현 결과가 모두 PASS이면 사용자 결정(재검토/이미 수정됨/재현 없이 분석)에 따른다.
- 버그 리포트 판별 불가 + `ORCHESTRATION_MODE=auto`이면 질문 없이 Phase 0을 건너뛰고 Phase 1로 시작한다.

## 대상 결정

- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다.
- `ANALYSIS_FILE` = `{WORKLOG_DIR}/analysis.md`
- 나머지 인수 = 분석할 파일 경로, 모듈명, 또는 기능 설명

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`인 경우: 동작 분기 표에 따라 사용자 인터랙션 동작을 조정한다.

## 사전 준비

1. worklog.md를 읽어 작업 컨텍스트 파악 (목표, 변경할 내용과 이유)
2. CLI 가용성 확인: `_shared/orchestration-context.md`의 **CLI 가용성 결정** 절차에 따라 `CODEX_AVAILABLE`을 설정한다 (vanalyze는 codex만 사용, gemini 불필요).
3. 테스트 명령 결정: `_shared/resolve-test-command.md`를 로드하고 해당 로직을 따라 `TEST_COMMAND`를 설정한다.
4. `ANALYSIS_FILE`이 이미 존재하는 경우:
   - `ORCHESTRATION_MODE=auto`인 경우: 기존 분석을 덮어쓴다 (질문 생략).
   - 그 외: "기존 분석이 있습니다. 새로 작성할까요, 기존 분석에 추가할까요?"를 질문한다.

## Phase 0: Bug Reproduction (버그 리포트 시 필수)

이 Phase는 버그 리포트 워크로그에서만 실행한다. 버그 여부 판별:
1. 워크로그 frontmatter에 `type: bug`이 있으면 → 실행
2. `type` 필드가 없으면: Goal 섹션에서 "버그", "bug", "fix", "regression", "오류", "에러" 키워드 탐지 → 키워드 발견 시 실행
3. 판별 불가 시:
   - `ORCHESTRATION_MODE=auto`면 Phase 0을 건너뛰고 Phase 1로 진행한다.
   - 그 외에는 사용자에게 질문: "이 워크로그는 버그 리포트인가요?"

버그 리포트로 판별된 경우, 분석 전에 반드시 재현 테스트를 작성하여 버그를 확인한다.
버그 리포트가 아닌 경우, Phase 0을 건너뛰고 Phase 1로 진행한다.

### Step 1: 버그 리포트 파싱

워크로그의 goal/completion criteria에서 버그 증상을 추출한다:
- 각 버그별 **기대 동작** vs **실제 동작** 정리
- 재현에 필요한 **전제 조건** (상태, 입력, 시나리오) 식별

### Step 2: 재현 테스트 작성

각 버그에 대해 **외부 동작 관점의 failing test**를 작성한다.

#### 2-1. 버그 타입 분류

버그 증상에서 재현 방식을 결정한다:

| 신호 키워드 | 버그 타입 | 재현 방식 |
|------------|----------|----------|
| "UI", "화면", "클릭", "렌더링", "표시", "팝업", "버튼", "페이지", "입력 필드", "scroll", "drag" 등 | UI/브라우저 | 2-2 + 2-3 |
| "API", "로직", "계산", "반환값", "상태", "데이터", "파싱" 등 | 로직/유닛 | 2-2만 |
| 판별 불가 | — | 2-2만 (기본) |

#### 2-2. 코드 재현 테스트 (항상 시도)

메인 에이전트가 기존 테스트 패턴을 수집한 후, test-engineer에게 위임한다:

1. **메인 에이전트 수집** (위임 전): Glob/Grep으로 관련 테스트 파일과 패턴을 파악한다 (가벼운 탐색이므로 직접 수행).

2. **test-engineer 위임**:

```
Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     prompt="
Write reproduction tests for the following bugs.

## Bug Symptoms
{Step 1에서 추출한 각 버그별 기대 동작 vs 실제 동작}

## Preconditions
{Step 1에서 식별한 전제 조건: 상태, 입력, 시나리오}

## Existing Test Patterns
{메인 에이전트가 수집한 관련 테스트 파일 내용}

## Test Command
{TEST_COMMAND}

## Rules
1. Match existing test file style and patterns exactly
2. Test ONLY externally observable behavior (UI state changes, event occurrences, output values)
3. Do NOT test implementation details (private refs, internal function call counts)
4. Include bug number/description in test names (e.g., 'Bug #1: 역방향 selection 재생 시 range가 비정상')
5. Tests MUST FAIL with current code (reproduction = Red)
6. Do NOT mock internal functions of the module under test — mock only external dependencies (APIs, timers, browser APIs)

## Output
- Test file path(s) created
- Test names and what each verifies
")
```

**UI 버그 병렬 실행**: 버그 타입이 UI/브라우저(2-2 + 2-3)인 경우, test-engineer 위임(2-2)과 vbrowser 호출(2-3)을 **동시에** 실행한다.

#### 2-3. 브라우저 재현 (UI/브라우저 버그인 경우 추가 실행)

Step 1에서 추출한 버그 시나리오를 `{WORKLOG_DIR}/browser-scenarios.md`에 기록한다 (Dashboard에 기록하지 않는다 — Dashboard는 worklog 업데이트 시 덮어쓰여짐. vbrowser는 이 파일을 Source 0(최우선)으로 로드하므로 파일이 존재하면 Source 1, 2, 3을 모두 건너뜀):

```markdown
# Browser Scenarios (Bug Reproduction)
- Scenario: {기대 동작 vs 실제 동작}
- Preconditions: {초기 상태, 입력값, URL}
```

그 후 `/vbrowser {WORKLOG_DIR}`을 `ORCHESTRATED=true`로 호출한다. vbrowser 호출 시 `{WORKLOG_DIR}/browser-scenarios.md`가 존재하면 이를 최우선 재현 시나리오로 사용한다.

vbrowser 실행 중 코드 재현 테스트(2-2) 작성을 병행해도 된다.

### Step 3: Red 확인 (재현 성공)

코드 테스트와 브라우저 재현 결과를 통합하여 확인한다.

#### 코드 테스트 (항상)

작성한 테스트를 실행하여 **반드시 FAIL** 하는지 확인한다:

```bash
# Pre-flight에서 결정된 TEST_COMMAND 사용
{TEST_COMMAND} {test-file}
```

- **모든 재현 테스트가 FAIL**: 재현 성공.
- **일부 PASS**: 해당 버그는 이미 수정되었거나 재현 조건이 부정확. 테스트를 수정하거나, 유저에게 재현 조건을 확인.
- **테스트 자체가 에러**: 테스트 코드 수정 후 재시도.

#### 브라우저 재현 결과 (UI/브라우저 버그인 경우)

vbrowser 실행 결과에서 버그 증상과 일치하는 FAIL 시나리오가 있는지 확인한다:

- **FAIL 시나리오 존재**: 브라우저 재현 성공. 스크린샷이 분석 근거로 활용됨.
- **모두 PASS**: 브라우저에서 재현 불가. 환경 문제(데이터, 로그인 상태 등)일 수 있음 → 유저 확인.

**두 재현 모두 PASS인 경우:** 버그가 이미 수정되었거나 재현 조건이 부정확할 가능성이 높다. 사용자에게 보고:

```
AskUserQuestion:
  question: "코드 테스트와 브라우저 재현이 모두 PASS입니다. 어떻게 진행할까요?"
  header: "All PASS"
  options:
    - label: "재현 조건 재검토"
      description: "버그 재현 조건을 수정하거나 다른 시나리오 시도"
    - label: "이미 수정됨으로 처리"
      description: "버그가 이미 수정된 것으로 보고 분석을 종료합니다"
    - label: "재현 없이 분석 진행"
      description: "재현 없이 코드 분석만 진행합니다"
```

두 재현 중 **하나라도 Red**이면 Step 4로 진행한다.

### Step 4: 유저 확인

**`ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=auto`인 경우:**
- 모든 재현 테스트가 FAIL이면 → 자동으로 "분석 진행" (Phase 1로 이동)
- 일부 PASS이면 → 재현 조건 재검토가 필요하므로 사용자에게 보고 후 판단을 요청한다 (핵심 결정)

**그 외:**

재현 결과를 유저에게 보고하고 다음 단계 진행 여부를 확인한다:

```
AskUserQuestion:
  question: "버그 재현 테스트 결과입니다. 다음 단계로 진행할까요?"
  header: "Reproduction"
  options:
    - label: "분석 진행"
      description: "재현이 확인되었으므로 코드 분석을 시작합니다"
    - label: "재현 수정"
      description: "재현 테스트를 수정하거나 추가 버그를 재현합니다"
    - label: "중단"
      description: "분석을 중단합니다"
```

- **"분석 진행"**: Phase 1로 이동
- **"재현 수정"**: 유저 피드백 반영 → Step 2로 복귀
- **"중단"**: 워크로그 업데이트 후 종료

### 절대 규칙

- **버그 리포트의 경우, 재현 테스트 없이 분석을 시작하지 않는다.** Phase 0 판별 결과가 버그 리포트이면, 재현이 완료되어야 Phase 1 진입 가능. 버그 리포트가 아닌 경우 Phase 0은 건너뛴다.
- **테스트는 외부 동작만 검증한다.** implementation detail 테스트 금지.
- **기존 테스트가 깨지지 않아야 한다.** 재현 테스트 추가 시 기존 테스트 regression 확인.
- **UI/브라우저 버그는 vbrowser로 추가 재현한다.** 코드 테스트만으로 재현이 불충분한 UI 버그는 반드시 vbrowser를 병행한다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

## Phase 1: 분석 범위 식별

워크로그 목표와 명시적 경로를 기반으로 분석 대상을 결정한다:

1. 명시적 파일/모듈 경로가 주어진 경우: 해당 경로에서 시작
2. 변경 의도만 있는 경우 (워크로그 기반): `explore` 에이전트 + Glob/Grep으로 관련 코드 영역 파악
3. 사용자에게 분석 범위 확인 요청:
   ```
   AskUserQuestion:
     question: "분석 범위가 맞나요?"
     header: "Scope"
     options:
       - label: "맞음"
         description: "이 범위로 분석을 진행합니다"
       - label: "범위 조정"
         description: "파일이나 모듈을 추가/제거합니다"
   ```

## Phase 2: 코드 심층 이해

`_shared/deep-code-analysis.md`를 로드하고 해당 절차를 따른다.

입력:
- `SCOPE_FILES` = Phase 1에서 확정된 분석 대상 파일 목록
- `SCOPE_DESCRIPTION` = Phase 1에서 확정된 분석 범위 설명
- `WORKLOG_CONTEXT` = 워크로그 목표 및 변경 의도
- `CODEX_AVAILABLE` = 사전 준비에서 설정한 값
- `CLI_TYPE` = 사전 준비에서 설정한 값

결과를 `ARCHITECTURE_RESULT`, `BEHAVIOR_RESULT`, `TEST_COVERAGE_RESULT`로 수신하여 Phase 3과 Phase 4에서 사용한다.

## Phase 3: 영향도 분석

워크로그의 변경 의도를 기반으로 영향 범위를 분석한다.

### Agent 4: Impact assessment (영향도 분석)

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="
Assess the impact of the planned change on the existing codebase.

## Planned Change
{worklog goal and change description}

## Current Architecture
{ARCHITECTURE_RESULT}

## Current Behaviors
{BEHAVIOR_RESULT}

## Analyze
- Direct changes needed (files that MUST change)
- Indirect effects (callers, consumers, type dependents that MAY need changes)
- Risk areas (what could break silently)
- Type system impact (shared types, API contracts — check shared_types_dir from project settings if available)
- Serialization/migration concerns (does saved data format change?)
- Performance implications
- Backward compatibility concerns

## Output Format
### Direct Changes Required
- {file}: {what needs to change} — {confidence: HIGH/MEDIUM/LOW}

### Indirect Effects (Blast Radius)
- {file/module}: {why it might be affected} — {risk: HIGH/MEDIUM/LOW}

### Risk Assessment
- [SEVERITY] {risk}: {description} — {mitigation}

### Constraints
- {things that must NOT change or break}

### Recommended Change Order
- {suggested sequence for making changes safely}

IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

### Codex 교차 검증 (CODEX_AVAILABLE=true인 경우)

`CODEX_AVAILABLE=true`인 경우, Agent 4(Claude architect)와 codex CLI 워커를 **병렬로** 실행하여 교차 검증한다.

**codex CLI 워커 실행** (`_shared/cli-runtime-check.md` 섹션 6 참조):

```
Skill("oh-my-claudecode:ask-codex", "영향도 분석: {Agent 4와 동일한 프롬프트}")
# 결과 텍스트, .omc/artifacts/ask/ 에 자동 저장
```

Agent 4 (Claude architect)와 codex CLI 워커를 **동시에** 호출한다.

**결과 병합 규칙:**

| 조건 | 처리 | 신뢰도 |
|------|------|--------|
| 양쪽 모두 동일한 항목 식별 | 해당 항목 채택 | HIGH |
| 한쪽만 식별한 항목 | 해당 항목 채택 + `[단독 식별]` 표시 | MEDIUM (검토 필요) |
| 양쪽 평가가 충돌 (예: risk HIGH vs LOW) | 양쪽 근거 모두 기록 + `[평가 분기]` 표시 | — (사용자 판단 필요) |

병합 결과를 `IMPACT_RESULT`로 저장한다.

**`CODEX_AVAILABLE=false`인 경우:** Agent 4 (Claude architect, opus) 단독으로 실행한다. 기존 동작과 동일.

**codex 타임아웃/실패 시:** `_shared/cli-runtime-check.md` 섹션 4 fallback 절차를 따른다. codex 결과를 폐기하고 Agent 4 결과만 사용한다 (silent fallback).

## Phase 4: 종합

모든 에이전트 출력을 `ANALYSIS_FILE`로 합산한다:

```markdown
# Analysis: {task-name}

**Date:** {timestamp}{timestamp_suffix if configured}
**Worklog:** {worklog path}
**Scope:** {files/modules analyzed}

## Architecture Overview
{from Agent 1 — condensed}

## Current Behavior Map
{from Agent 2 — condensed}

## Test Coverage
{from Agent 3 — condensed}

## Impact Analysis
{IMPACT_RESULT}

### Direct Changes Required
{list}

### Blast Radius
{list with risk levels}

### Risk Assessment
{prioritized risks}

### Constraints (DO NOT break)
{list}

### Recommended Change Order
{sequence}

### Cross-Verification Notes
{CODEX_AVAILABLE=true인 경우에만 포함}
- **단독 식별 항목**: {한쪽만 식별한 항목 목록 — 추가 검토 권장}
- **평가 분기**: {양쪽 평가가 충돌하는 항목 — 양쪽 근거 포함}

## Recommendations for Planning
- {key considerations for vplan to incorporate}
- {suggested approach based on analysis}
- {areas requiring user decision}
```

## Phase 5: 사용자 검토

1. `ANALYSIS_FILE`에 전체 분석 내용을 작성
2. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - Links 섹션에 분석 파일 링크 추가
   - 분석 결과를 반영하여 다음 작업 업데이트
   - `timeline_entry`: 분석 세션 요약 + 근거
3. 분석 요약을 사용자에게 제시

### 전이 트랜잭션 순서 (고정)

분석 완료 시 아래 순서를 고정한다:
1. `analysis.md` 작성/갱신
2. 워크로그 업데이트 (`_shared/update-worklog.md`)
3. 사용자에게 결과 요약 출력

## 출력

다음을 출력한다:
- 분석 파일 경로
- 주요 발견사항 요약 (3-5개 항목)
- 심각도별 식별된 위험 건수
- `ORCHESTRATED=true`인 경우: 여기서 종료. vwork가 다음 phase 전이를 관리한다.
- 그 외: "분석이 완료되었습니다. `/vplan {WORKLOG_DIR}` 로 변경 계획을 수립하세요."

## 전체 워크플로우 절대 규칙

- **사용자 명시 요청 없이는 단계 생략/워크플로우 변경 금지.** vanalyze가 임의로 단계를 건너뛰거나 순서를 재배치하지 않는다.
- **정규 단계 테이블(SSOT)을 따른다.** 예외 전이는 명시된 조건에서만 허용한다.

이제 실행하라.
