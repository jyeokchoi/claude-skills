---
name: vanalyze
description: Deep code understanding and impact analysis for existing code modifications. Outputs analysis document for vplan input.
argument-hint: 'Usage: /vanalyze [worklog-folder-or-worklog.md] [file-or-module-path]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 |
| `timestamp_suffix` | (없음) | 타임스탬프 뒤 문자열 (예: KST) |

기존 코드를 깊이 이해하고 계획된 수정사항의 영향을 평가하는 코드 분석 워크플로우를 실행한다. 출력 결과는 `/vplan`의 입력 컨텍스트로 사용된다.

## 대상 결정

- `_shared/resolve-worklog-target.md`가 존재하면 로드하여 해당 로직을 따른다.
- 폴백 (공유 리졸버를 사용할 수 없는 경우):
  - $ARGUMENTS에 워크로그 경로(폴더 또는 .md 파일)가 포함된 경우:
    - 일반적인 방식으로 워크로그를 결정 → `WORKLOG_DIR` 설정
  - 그 외:
    - ".claude/worklogs/.active"를 읽어 활성 워크로그 폴더를 가져옴
- 워크로그 대상이 없으면 중단하고 오류를 출력한다.
- `ANALYSIS_FILE` = `{WORKLOG_DIR}/analysis.md`로 설정
- 나머지 인수 = 분석할 파일 경로, 모듈명, 또는 기능 설명

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`인 경우: 동작 분기 표에 따라 사용자 인터랙션 동작을 조정한다.

## 사전 준비

1. worklog.md를 읽어 작업 컨텍스트 파악 (목표, 변경할 내용과 이유)
2. 테스트 명령 결정: `_shared/resolve-test-command.md`를 로드하고 해당 로직을 따라 `TEST_COMMAND`를 설정한다.
3. `ANALYSIS_FILE`이 이미 존재하는 경우:
   - `ORCHESTRATION_MODE=auto`인 경우: 기존 분석을 덮어쓴다 (질문 생략).
   - 그 외: "기존 분석이 있습니다. 새로 작성할까요, 기존 분석에 추가할까요?"를 질문한다.

## Phase 0: Bug Reproduction (버그 리포트 시 필수)

이 Phase는 버그 리포트 워크로그에서만 실행한다. 버그 여부 판별:
1. 워크로그 frontmatter에 `type: bug`이 있으면 → 실행
2. `type` 필드가 없으면: Goal 섹션에서 "버그", "bug", "fix", "regression", "오류", "에러" 키워드 탐지 → 키워드 발견 시 실행
3. 판별 불가 시 → `ORCHESTRATION_MODE=auto`면 건너뛰기, 그 외에는 사용자에게 질문: "이 워크로그는 버그 리포트인가요?"

버그 리포트로 판별된 경우, 분석 전에 반드시 재현 테스트를 작성하여 버그를 확인한다.
버그 리포트가 아닌 경우, Phase 0을 건너뛰고 Phase 1로 진행한다.

### Step 1: 버그 리포트 파싱

워크로그의 goal/completion criteria에서 버그 증상을 추출한다:
- 각 버그별 **기대 동작** vs **실제 동작** 정리
- 재현에 필요한 **전제 조건** (상태, 입력, 시나리오) 식별

### Step 2: 재현 테스트 작성

각 버그에 대해 **외부 동작 관점의 failing test**를 작성한다:

1. 기존 테스트 파일과 패턴을 파악 (Glob/Grep으로 관련 테스트 탐색)
2. 기존 테스트 패턴과 동일한 스타일로 재현 테스트 작성
3. 테스트는 **사용자가 관찰할 수 있는 외부 동작**만 검증해야 한다:
   - UI 상태 변화, 이벤트 발생 여부, 출력값
   - 내부 구현 세부사항 (private ref, 내부 함수 호출 횟수 등)을 직접 검증하지 않는다
4. 테스트 이름에 버그 번호/설명을 포함한다 (예: `"Bug #1: 역방향 selection 재생 시 range가 비정상"`)

### Step 3: Red 확인 (재현 성공)

작성한 테스트를 실행하여 **반드시 FAIL** 하는지 확인한다:

```bash
# Pre-flight에서 결정된 TEST_COMMAND 사용
{TEST_COMMAND} {test-file}
```

- **모든 재현 테스트가 FAIL**: 재현 성공. Step 4로 진행.
- **일부 PASS**: 해당 버그는 이미 수정되었거나 재현 조건이 부정확. 테스트를 수정하거나, 유저에게 재현 조건을 확인.
- **테스트 자체가 에러**: 테스트 코드 수정 후 재시도.

### Step 4: 유저 확인

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

범위 내 각 모듈/파일에 대해 병렬 분석을 수행한다:

### Agent 1: Architecture mapping (구조 분석)

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="
Analyze the architecture of this code area.

## Analyze
- Module boundaries and responsibilities
- Component hierarchy and data flow
- State management patterns
- Key abstractions and interfaces
- Design patterns used
- How this area fits into the larger system

## Code
{file contents of all in-scope files}

## Output Format
### Architecture Overview
{diagram or description of module relationships}

### Key Abstractions
- {abstraction}: {purpose} — {file:line}

### Data Flow
{how data moves through the system}

### External Dependencies
- {what this code depends on}

### Dependents
- {what depends on this code}

IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

### Agent 2: Behavior mapping (동작 분석)

```
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="
Map the current behavior of this code area.

## Analyze
- User-visible behaviors (what the user sees/experiences)
- Internal behaviors (state transitions, side effects)
- Error handling paths
- Edge cases and boundary conditions
- Async/timing behaviors
- Undo/redo implications (if applicable)

## Code
{file contents}

## Output Format
### User-Facing Behaviors
- {behavior}: {how it works} — {file:line}

### Internal Behaviors
- {behavior}: {mechanism}

### Error Paths
- {error scenario}: {how it's handled}

### Edge Cases
- {case}: {current behavior}

IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

### Agent 3: Test & coverage mapping (테스트 분석)

```
Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     prompt="
Analyze the test coverage for this code area.

## Analyze
- Existing test files and what they cover
- Coverage gaps (behaviors without tests)
- Test quality (meaningful assertions vs trivial)
- Test patterns used (mocking strategy, fixtures, etc.)
- Integration vs unit test balance

## Code
{source files}

## Test Files
{test file contents}

## Output Format
### Coverage Map
- {behavior/function} → {test file:test name} / UNTESTED

### Coverage Gaps
- {what's not tested and why it matters}

### Test Quality Notes
- {observations about test patterns}

IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

## Phase 3: 영향도 분석

워크로그의 변경 의도를 기반으로 영향 범위를 분석한다:

### Agent 4: Impact assessment (영향도 분석)

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="
Assess the impact of the planned change on the existing codebase.

## Planned Change
{worklog goal and change description}

## Current Architecture
{output from Agent 1}

## Current Behaviors
{output from Agent 2}

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
{from Agent 4}

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

## Recommendations for Planning
- {key considerations for vplan to incorporate}
- {suggested approach based on analysis}
- {areas requiring user decision}
```

## Phase 5: 사용자 검토

1. 분석 요약을 사용자에게 제시
2. `ANALYSIS_FILE`에 전체 분석 내용을 작성
3. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - Links 섹션에 분석 파일 링크 추가
   - 분석 결과를 반영하여 다음 작업 업데이트
   - `timeline_entry`: 분석 세션 요약 + 근거

## 출력

다음을 출력한다:
- 분석 파일 경로
- 주요 발견사항 요약 (3-5개 항목)
- 심각도별 식별된 위험 건수
- `ORCHESTRATED=true`인 경우: 여기서 종료. vwork가 다음 phase 전이를 관리한다.
- 그 외: "분석이 완료되었습니다. `/vplan {WORKLOG_DIR}` 로 변경 계획을 수립하세요."

이제 실행하라.
