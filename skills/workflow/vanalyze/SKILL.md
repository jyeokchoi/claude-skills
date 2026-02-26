---
name: vanalyze
description: Deep code understanding and impact analysis for existing code modifications. Outputs analysis document for vplan input.
argument-hint: 'Usage: /vanalyze [worklog-folder-or-worklog.md] [file-or-module-path]'
---

## Project settings

이 스킬은 `rules/workflow.md`의 프로젝트별 설정을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 |
| `timestamp_suffix` | (없음) | 타임스탬프 뒤 문자열 (예: KST) |

You are running a deep code analysis workflow to understand existing code and assess the impact of planned modifications. The output serves as input context for `/vplan`.

## Target resolution

- Try loading `_shared/resolve-worklog-target.md` if it exists and follow its logic.
- Fallback (if shared resolver not available):
  - If $ARGUMENTS contains a worklog path (folder or .md file):
    - Resolve worklog as usual → set `WORKLOG_DIR`
  - Else:
    - Read ".claude/worklogs/.active" to get the active worklog folder
- If no worklog target exists, stop and print an error.
- Set `ANALYSIS_FILE` = `{WORKLOG_DIR}/analysis.md`
- Any remaining arguments = file paths, module names, or feature descriptions to analyze

## Pre-flight

1. Read worklog.md to understand the task context (goal, what needs to change and why)
2. If `ANALYSIS_FILE` already exists, ask:
   - "기존 분석이 있습니다. 새로 작성할까요, 기존 분석에 추가할까요?"

## Phase 0: Bug Reproduction (필수)

버그 리포트가 포함된 워크로그인 경우, 분석 전에 반드시 재현 테스트를 작성하여 버그를 확인한다.

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
# rules/workflow.md의 test_command 사용, 없으면 프로젝트 package.json에서 탐지
# 탐지 불가 시 사용자에게 질문 → project_memory_add_note("test_command: {answer}")
{test_command} {test-file} --reporter=verbose
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

### Non-negotiable rules

- **재현 테스트 없이 분석을 시작하지 않는다.** 재현이 완료되어야 Phase 1 진입 가능.
- **테스트는 외부 동작만 검증한다.** implementation detail 테스트 금지.
- **기존 테스트가 깨지지 않아야 한다.** 재현 테스트 추가 시 기존 테스트 regression 확인.

## Phase 1: Scope identification

Determine WHAT to analyze based on worklog goal + any explicit paths:

1. If explicit file/module paths given: start from those
2. If only a change intent (from worklog): use `explore` agent + Glob/Grep to identify the relevant code area
3. Ask the user to confirm the analysis scope:
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

## Phase 2: Deep code understanding

For each module/file in scope, perform parallel analysis:

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

## Phase 3: Impact analysis

Based on the change intent from the worklog, analyze blast radius:

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

## Phase 4: Synthesis

Combine all agent outputs into `ANALYSIS_FILE`:

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

## Phase 5: User review

1. Present the analysis summary to the user
2. Write the full analysis to `ANALYSIS_FILE`
3. Update worklog Dashboard:
   - Add analysis file link to Links section
   - Update next actions to reflect analysis findings
4. Add Timeline entry documenting the analysis session

## Output

Print:
- Analysis file path
- Key findings summary (3-5 bullet points)
- Identified risks count by severity
- Suggestion: "분석이 완료되었습니다. `/vplan {WORKLOG_DIR}` 로 변경 계획을 수립하세요."

Proceed now.
