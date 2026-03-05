---
name: vtest
description: Unified testing workflow. Identifies test gaps from vqa report, writes unit/integration/e2e tests, and verifies coverage. Worklog-integrated. Replaces tdd-review and integration-test.
argument-hint: 'Usage: /vtest [worklog-folder-or-worklog.md]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `test_command` | 프로젝트 설정에서 탐지 | 테스트 실행 명령 |
| `project_type` | auto-detect | frontend / backend / fullstack / cli / library |
| `test_framework` | auto-detect | vitest / jest / pytest / go test 등 |

테스트 갭을 식별하고 이를 채우는 테스트를 작성하는 통합 테스팅 워크플로우를 실행한다. 이 스킬은 유닛 테스팅 (구 tdd-review), 통합 테스팅 (구 integration-test)을 통합하고 e2e 테스트 지원을 추가한다 — 모두 워크로그와 연동된다.

## 정규 단계 테이블 (SSOT)

아래 표가 vtest의 단계 전이 단일 진실 기준이다.

| 현재 단계 | 완료 조건 | 다음 단계 | 주요 출력 |
|-----------|-----------|----------|----------|
| 대상 결정/사전 준비 | PLAN/REPORT/TEST_COMMAND/PROJECT_TYPE 확정 | Phase 1 | 테스트 컨텍스트 |
| Phase 1 (갭 식별) | Source 우선순위 기반 갭 목록 확정 | Phase 2 | 최종 갭 목록 |
| Phase 2 (전략 선택) | 범위 선택 확정 | Phase 3 또는 Phase 2B | 선택된 테스트 범위 |
| Phase 2B (브라우저 E2E) | vbrowser 실행 완료 | Phase 4 | `browser-test-report.md` |
| Phase 3 (테스트 작성) | 선택 갭 테스트 작성/검증 완료 | Phase 4 | 테스트 파일/결과 |
| Phase 4 (커버리지 보고) | 보고/워크로그 업데이트 완료 | Phase 5 | 테스트 작성 결과 요약 |
| Phase 5 (인계) | 오케스트레이션/독립 실행 분기 완료 | 종료 | 다음 단계 안내 |

Source 우선순위 계약:
1. Source 1 (`report.md`) 우선
2. Source 2 (`plan.md`) 보조
3. Source 3 (사용자 요청) 최후

상위 Source가 유효하면 하위 Source로 폴백하지 않는다.

## 대상 결정

- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다.
- `PLAN_FILE` = `{WORKLOG_DIR}/plan.md`
- `REPORT_FILE` = `{WORKLOG_DIR}/report.md`

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=auto`인 경우:
  - Phase 2 범위 선택 → 기본값: "전체 갭 해결"
  - Phase 2 브라우저 E2E → `WEB_APP=true` + E2E 갭 존재 시 "브라우저 E2E 테스트" 자동 선택
  - Phase 3 Step 3 사용자 체크포인트 → 기본값: 제안된 테스트케이스로 진행

## 사전 준비

1. worklog.md를 읽어 작업 컨텍스트 파악
2. 프로젝트 타입 감지: `_shared/resolve-project-type.md`를 로드하고 해당 절차를 따른다. 오케스트레이션 컨텍스트에서 설정된 `PROJECT_TYPE` 변수가 있으면 그대로 사용한다.
3. 테스트 프레임워크 감지: 프로젝트 설정 또는 auto-detect (vitest / jest / pytest / go test 등)
4. 테스트 명령 결정: `_shared/resolve-test-command.md`를 로드하고 해당 로직을 따라 `TEST_COMMAND`를 설정한다.
5. 웹 앱 여부 감지:
   - `project_type`이 `frontend` 또는 `fullstack`이면 → `WEB_APP=true`
   - package.json에 `react`, `vue`, `svelte`, `next`, `nuxt`, `vite` 등이 있으면 → `WEB_APP=true`
   - 그 외 → `WEB_APP=false`
6. 기존 테스트 패턴 탐색:
   - `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go` 등을 Glob으로 탐색
   - 기존 테스트 파일 1-2개를 읽어 컨벤션 파악 (이름 규칙, import, 패턴)

## Phase 1: 갭 식별

### Source 1: VQA Report (primary)

`{WORKLOG_DIR}/report.md`가 존재하는 경우:

1. Test Verification 섹션 (Agent 3 출력) 읽기
2. 다음을 추출한다:
   - Coverage Map: `MISSING` 테스트가 있는 동작
   - Missing Tests 목록
   - Test Quality Issues (약한 단언, implementation-detail 테스트)
3. 각 갭을 분류한다:

| 갭 | 타입 | 우선순위 | 근거 |
|-----|------|----------|-----------|
| {테스트 없는 동작} | unit / integration / e2e | HIGH / MEDIUM / LOW | {해당 타입인 이유} |

### Source 2: Plan (secondary)

보고서는 없지만 `plan.md`가 있는 경우:

1. 동작 명세와 체크리스트 항목 추출
2. 변경 파일 근처의 관련 테스트 파일 탐색 (테스트 패턴을 Glob으로 탐색)
3. 테스트가 없는 동작 식별

### Source 3: 사용자 요청 (tertiary)

보고서도 플랜도 없는 경우:

```
AskUserQuestion:
  question: "테스트 대상을 지정해주세요."
  header: "Target"
  options:
    - label: "파일/모듈 지정"
      description: "특정 파일이나 모듈의 테스트를 작성합니다"
    - label: "변경 기반"
      description: "현재 브랜치에서 변경된 파일의 테스트를 작성합니다"
```

### Phase 1-B: 병렬 갭 심층 분석

활성 Source(1, 2, 또는 3)에서 기본 갭 목록을 추출한 뒤, 2개 에이전트를 **병렬로** 실행하여 갭을 심층 분석한다. 에이전트는 Bash를 사용하지 않으며 — 모든 컨텍스트를 프롬프트에 포함한다.

**Agent 1 — 커버리지 분석 (test-engineer):**

`_shared/orchestration-context.md`의 **CLI 가용성 결정** 절차에 따라 `CODEX_AVAILABLE`, `GEMINI_AVAILABLE`, `CLI_TYPE`을 사용한다.

**CLI_TYPE=codex 또는 (`CLI_TYPE` 미지정 + `CODEX_AVAILABLE=true`)인 경우:**
```
ToolSearch(query="+omc_run_team_start")
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{WORKLOG_SLUG}-test-gap",
  "agentTypes": ["codex"],
  "tasks": [{"subject": "커버리지 갭 분석", "description": "
IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided.

Analyze the test coverage gaps for this implementation.

## Your Task
Identify which behaviors are untested or poorly tested, and recommend test types.

## Source Files
{source file contents for changed files}

## Existing Tests
{existing test file contents}

## Known Gaps (from VQA/Plan)
{raw gap list}

## Testing Rules (MUST follow)
1. Test ONLY externally observable behavior (function input/output, UI state, user-visible results)
2. Do NOT test implementation details (internal refs, private variables, internal call counts)
3. Use mocks/stubs ONLY for external dependencies (APIs, timers, browser APIs) — never mock internal functions of the module under test
4. Do NOT modify implementation to make tests pass by exploiting knowledge of internals — fix the external behavior instead

## Output Format
### Prioritized Gap List
| Gap | Type (unit/integration/e2e) | Priority | Rationale |
|-----|---------------------------|----------|-----------|

### Additional Gaps Found
- {gap not in the known list}: {why it matters}
"}],
  "cwd": "{cwd}"
})
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({"job_id": "{jobId}"})
```

**CLI_TYPE=gemini 또는 (`CLI_TYPE` 미지정 + `GEMINI_AVAILABLE=true` + `CODEX_AVAILABLE=false`)인 경우:**
```
ToolSearch(query="+omc_run_team_start")
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{WORKLOG_SLUG}-test-gap",
  "agentTypes": ["gemini"],
  "tasks": [{"subject": "커버리지 갭 분석", "description": "위 codex 경로와 동일한 프롬프트"}],
  "cwd": "{cwd}"
})
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({"job_id": "{jobId}"})
```

**그 외 (claude fallback):**
```
Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     prompt="
IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided.

Analyze the test coverage gaps for this implementation.

## Your Task
Identify which behaviors are untested or poorly tested, and recommend test types.

## Source Files
{source file contents for changed files}

## Existing Tests
{existing test file contents}

## Known Gaps (from VQA/Plan)
{raw gap list}

## Output Format
### Prioritized Gap List
| Gap | Type (unit/integration/e2e) | Priority | Rationale |
|-----|---------------------------|----------|-----------|

### Additional Gaps Found
- {gap not in the known list}: {why it matters}
")
```

**Agent 2 — 엣지 케이스/오류 경로 분석 (quality-reviewer):**
```
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="
IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided.

Identify edge cases and error paths that need test coverage.

## Your Task
Find scenarios where the implementation could behave unexpectedly.

## Source Files
{source file contents for changed files}

## Existing Tests
{existing test file contents}

## Known Gaps (from VQA/Plan)
{raw gap list}

## Output Format
### Edge Cases Missing Tests
- {scenario}: {expected behavior} — {risk if untested}

### Error Path Gaps
- {error condition}: {how it should be handled} — {risk if untested}
")
```

두 에이전트 결과를 병합하여 최종 갭 목록을 확정한다. 중복은 제거하고 우선순위는 높은 쪽을 취한다.

## Phase 2: 테스트 전략

테스트 갭을 사용자에게 제시한다:

```
## 테스트 갭 분석 결과

### 유닛 테스트 (Unit)
- [ ] {function/module}: {missing test description}
...

### 통합 테스트 (Integration)
- [ ] {flow/module}: {missing test description}
...

### E2E 테스트 (End-to-End)
- [ ] {user scenario}: {missing test description}
...

총 {N}개 테스트 갭 발견.
```

```
AskUserQuestion:
  question: "테스트 작성 범위를 선택하세요."
  header: "Scope"
  options:
    - label: "전체 갭 해결"
      description: "모든 누락 테스트를 작성합니다"
    - label: "유닛 테스트만"
      description: "유닛 테스트 갭만 해결합니다"
    - label: "통합 테스트만"
      description: "통합 테스트 갭만 해결합니다"
    - label: "선택 작성"
      description: "특정 갭을 선택하여 작성합니다"
    # WEB_APP=true이고 E2E 갭이 존재하는 경우에만 추가:
    - label: "브라우저 E2E 테스트 (Playwright MCP)"
      description: "PRD 유저 시나리오를 브라우저에서 직접 실행합니다 (/vbrowser)"
```

"브라우저 E2E 테스트" 선택 시 → Phase 2B로 이동.
그 외 선택 시 → Phase 3으로 이동.

`ORCHESTRATED=true` + `auto` + `WEB_APP=true` + E2E 갭만 존재 (코드 레벨 갭 없음): "브라우저 E2E 테스트" 자동 선택.
`ORCHESTRATED=true` + `auto` + `WEB_APP=true` + E2E 갭과 코드 레벨 갭 모두 존재: "전체 갭 해결" 자동 선택 후 Phase 3 → Phase 2B 순서로 실행.

## Phase 2B: 브라우저 E2E 실행

"브라우저 E2E 테스트 (Playwright MCP)"가 선택된 경우에만 실행한다.

`/vbrowser {WORKLOG_DIR}` 스킬을 호출한다. vbrowser가 다음을 처리한다:
- 앱 URL 감지 (dev server → 워크로그 메타데이터 → 사용자 질문)
- PRD 유저 시나리오 + E2E 갭 목록에서 테스트 케이스 수집
- Playwright MCP로 브라우저 직접 실행 및 스크린샷 캡처
- `{WORKLOG_DIR}/browser-test-report.md` 보고서 생성
- 워크로그 업데이트

vbrowser 완료 후 → Phase 4로 이동 (커버리지 보고서에 브라우저 테스트 결과 포함).

## Phase 3: 테스트 작성 (갭별)

선택된 각 갭에 대해 다음을 실행한다:

### Step 1: 대상 분석

테스트가 필요한 소스 코드를 읽는다. 다음을 식별한다:
- 의존성과 mock 전략
- 프로젝트의 기존 테스트 패턴 (사전 준비에서 파악한 것)
- 테스트 파일 위치 컨벤션

### Step 2: 테스트케이스 설계

각 갭에 대해 구체적인 테스트케이스를 제안한다:

**유닛 테스트:**
- Happy path (정상 입력 → 기대 출력)
- 엣지 케이스 (빈 값, null, 경계값, 0, 음수)
- 오류 경로 (유효하지 않은 입력, 예외)

**통합 테스트 (프로젝트 타입 고려):**

| 프로젝트 타입 | 접근 방식 |
|---|---|
| Frontend (React) | `renderHook` / `render` + `waitFor` for async flows, component interactions |
| Frontend (Vue/Svelte) | Component testing library equivalents |
| Backend (Node/Express) | Supertest for API endpoints, middleware chain testing |
| Backend (Python/FastAPI) | TestClient for API endpoints, dependency injection testing |
| Backend (Go) | httptest for handlers, service layer integration |
| CLI | Process spawn + stdout/stderr assertions |
| Library | Public API integration tests, cross-module interactions |

**E2E 테스트 (프로젝트 타입 고려):**

| 프로젝트 타입 | 접근 방식 |
|---|---|
| Web app | Playwright / Cypress (browser-based user flows) |
| API | API contract tests with real server |
| CLI | Full command execution with real filesystem/network |

### Step 3: 사용자 체크포인트

설계된 테스트케이스를 사용자에게 제시한다:

```
## 제안 테스트케이스: {target}

| # | Type | Test | Priority |
|---|------|------|----------|
| 1 | Unit | {description} | HIGH |
| 2 | Unit | {description} | MEDIUM |
| 3 | Integration | {description} | HIGH |
...

이 테스트케이스로 진행할까요? 추가/수정/제거할 것이 있으면 말씀해주세요.
```

### Step 4: 테스트 작성

독립적인 갭들은 **병렬 에이전트**로 동시에 작성한다. 같은 파일에 쓰는 갭은 순차적으로 처리한다.

**병렬 가능 조건**: 서로 다른 테스트 파일에 작성되는 갭

`_shared/orchestration-context.md`의 **CLI 가용성 결정** 절차에 따라 `CODEX_AVAILABLE`, `GEMINI_AVAILABLE`, `CLI_TYPE`을 사용한다.

**CLI_TYPE=codex 또는 (`CLI_TYPE` 미지정 + `CODEX_AVAILABLE=true`)인 경우:**

각 갭마다 codex 워커를 실행한다:
```
ToolSearch(query="+omc_run_team_start")
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{WORKLOG_SLUG}-test-write",
  "agentTypes": ["codex"],
  "tasks": [{"subject": "테스트 작성: {gap description}", "description": "
Write tests for the following gap. Follow existing project conventions exactly.

## Gap
{gap description and type}

## Test Cases to Implement
{test cases from Step 3}

## Source File
{source file content to test}

## Existing Test File (for pattern reference)
{existing test file content — naming, imports, assertion style}

## Test File Path
{target test file path}

## Testing Rules (MUST follow)
1. Test ONLY externally observable behavior (function input/output, UI state, user-visible results)
2. Do NOT test implementation details (internal refs, private variables, internal call counts)
3. Use mocks/stubs ONLY for external dependencies (APIs, timers, browser APIs) — never mock internal functions of the module under test
4. Do NOT modify implementation to make tests pass by exploiting knowledge of internals — fix the external behavior instead

## Rules
- Mock all external dependencies
- Follow the project's existing naming and assertion patterns
- Write in the same language as existing tests
"}],
  "cwd": "{cwd}"
})
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({"job_id": "{jobId}"})
```

**CLI_TYPE=gemini 또는 (`CLI_TYPE` 미지정 + `GEMINI_AVAILABLE=true` + `CODEX_AVAILABLE=false`)인 경우:**

각 갭마다 gemini 워커를 실행한다:
```
ToolSearch(query="+omc_run_team_start")
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{WORKLOG_SLUG}-test-write",
  "agentTypes": ["gemini"],
  "tasks": [{"subject": "테스트 작성: {gap description}", "description": "위 codex 경로와 동일한 프롬프트"}],
  "cwd": "{cwd}"
})
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({"job_id": "{jobId}"})
```

**그 외 (claude fallback):**

각 갭마다 executor 에이전트를 실행한다:
```
Task(subagent_type="oh-my-claudecode:executor", model="sonnet",
     prompt="
Write tests for the following gap. Follow existing project conventions exactly.

## Gap
{gap description and type}

## Test Cases to Implement
{test cases from Step 3}

## Source File
{source file content to test}

## Existing Test File (for pattern reference)
{existing test file content — naming, imports, assertion style}

## Test File Path
{target test file path}

## Rules
- Test external behavior only — NOT implementation details
- Mock all external dependencies
- Follow the project's existing naming and assertion patterns
- Write in the same language as existing tests
")
```

동일 파일에 쓰는 갭이 2개 이상이면 하나씩 순차 실행한다 (충돌 방지).

### Step 5: 실행 및 검증

1. 작성한 테스트 실행: `{TEST_COMMAND} {test-file}`
2. 테스트가 실패하는 경우:
   - 실패 분석: 테스트 버그 vs 코드 버그
   - 테스트 버그 → 테스트 수정 후 재시도
   - 코드 버그 → 사용자에게 보고, 워크로그에 기록
3. 전체 테스트 스위트를 실행하여 regression 확인
4. 타입 오류 확인을 위해 테스트 파일에 `lsp_diagnostics` 실행

### Step 6: 반복

선택된 각 갭에 대해 Steps 1-5를 반복한다. 각 갭 완료 후:
- 진행 상황 업데이트: "{completed}/{total} 갭 해결"

## Phase 4: 커버리지 보고서

선택된 모든 갭을 처리한 후:

1. 전체 테스트 스위트 실행: `{TEST_COMMAND}`
2. 사용 가능한 경우 커버리지 실행 (예: `--coverage` 플래그)
3. 요약:

```
## 테스트 작성 결과

| Type | Written | Passing | Files |
|------|---------|---------|-------|
| Unit | {N} | {N}/{N} | {list} |
| Integration | {N} | {N}/{N} | {list} |
| E2E | {N} | {N}/{N} | {list} |
# Phase 2B가 실행된 경우에만 아래 행 포함:
| Browser E2E | {N} 시나리오 | {N}/{N} PASS | browser-test-report.md |

### 작성된 테스트 파일
- {test-file-1}: {N} tests ({descriptions})
- {test-file-2}: {N} tests ({descriptions})
# Phase 2B가 실행된 경우:
- browser-test-report.md: {N} scenarios ({PASS}개 통과, 스크린샷 {N}개)
```

4. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `dashboard_updates`: 테스트 근거 (파일 경로, 통과 수)
   - `stable_updates`: Links에 test file paths 추가
   - `timeline_entry`: 전체 테스트 결과

## Phase 5: 인계

**`ORCHESTRATED=true`인 경우:** 테스트 작성 완료 후 바로 종료. vwork가 TEST → VERIFY phase 전이를 관리한다.

**그 외 (독립 실행):**

```
AskUserQuestion:
  question: "테스트 작성이 완료되었습니다. 다음 단계를 선택하세요."
  header: "Next"
  options:
    - label: "재검증 (/vqa)"
      description: "테스트 커버리지가 충분한지 다시 검증합니다"
    - label: "추가 테스트"
      description: "다른 영역의 테스트를 추가로 작성합니다"
    # WEB_APP=true이고 Phase 2B가 아직 실행되지 않은 경우에만 추가:
    - label: "브라우저 E2E 테스트 (/vbrowser)"
      description: "PRD 유저 시나리오를 브라우저에서 직접 실행합니다"
    - label: "완료"
      description: "테스트 작성을 종료합니다"
```

- "재검증": `/vqa {WORKLOG_DIR}` 제안
- "추가 테스트": Phase 1으로 복귀
- "브라우저 E2E 테스트": `/vbrowser {WORKLOG_DIR}` 호출
- "완료": 워크로그 업데이트 후 종료

## Mock 전략 가이드 (프로젝트 타입 고려)

### 모듈 수준 mock (vi.mock / jest.mock / unittest.mock.patch)
- 싱글톤, 정적 메서드, 외부 모듈
- 데이터베이스 클라이언트, HTTP 클라이언트, 파일 시스템

### 인스턴스 수준 mock (plain object / spy)
- 생성자나 props를 통해 주입되는 클래스 인스턴스
- 가능한 plain object 사용 (타입 지정이 더 쉬움)
- 주입 지점에서만 캐스팅 (`as unknown as ClassName`)

### Ref/State mock
- React refs: `{ current: value }` 객체
- 스토어 상태: 초기 상태로 mock store 구성

### 네트워크 mock
- MSW (Mock Service Worker): integration/e2e에서 API mocking
- Nock: Node.js HTTP mocking
- httptest: Go

## 절대 규칙

- **프로젝트 타입 고려.** React 전용이 아님. 프로젝트 스택을 감지하고 적응한다.
- **기존 테스트 패턴 준수.** 기존 테스트를 먼저 읽고 해당 스타일을 따른다.
- **외부 의존성 격리.** 모든 외부 의존성은 반드시 mock 처리한다.
- **워크로그 업데이트.** 테스트 작성 전후에 `_shared/update-worklog.md`를 통해 업데이트한다.
- **Regression 확인.** 새 테스트 추가 후 기존 테스트가 모두 통과하는지 확인한다.
- **외부 동작 검증.** 구현 세부사항이 아닌 사용자가 관찰할 수 있는 동작을 테스트한다.
- **사용자 체크포인트.** 작성 전에 항상 테스트케이스를 검토용으로 제시한다. 예외: `ORCHESTRATION_MODE=auto`에서는 제안된 테스트케이스로 자동 진행하고, worklog timeline에 기록한다.
- **사용자 명시 요청 없이는 단계 생략/워크플로우 변경 금지.** vtest가 임의로 phase를 건너뛰거나 순서를 재배치하지 않는다.
- **정규 단계 테이블(SSOT)과 Source 우선순위 계약을 따른다.** 임의 폴백/분기 추가를 금지한다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
