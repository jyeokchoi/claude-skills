# 코드 심층 분석 (공통 절차)

범위 내 코드에 대해 3가지 관점(구조, 동작, 테스트)의 병렬 분석을 수행하는 공통 절차.

## 입력

| 변수 | 필수 | 설명 |
|------|------|------|
| `SCOPE_FILES` | O | 분석 대상 파일 경로 목록 |
| `SCOPE_DESCRIPTION` | O | 분석 범위 설명 (모듈명, 기능 설명) |
| `WORKLOG_CONTEXT` | X | 워크로그 목표/변경 의도 (있으면 분석 방향 조정) |
| `CODEX_AVAILABLE` | X | codex CLI 가용 여부 (기본 false) |
| `CLI_TYPE` | X | 오케스트레이션에서 수신한 cli_type |

## CLI 라우팅

codex가 가용한 경우 분석 에이전트를 codex로 라우팅할 수 있다:

| 조건 | Agent 1 (구조 분석) | Agent 2 (동작 분석) | Agent 3 (테스트 분석) |
|------|----------------------|---------------------|------------------------|
| `cli_type=codex` | codex (omc-teams) | Claude (quality-reviewer, sonnet) | codex (omc-teams) |
| 그 외 | Claude (architect, opus) | Claude (quality-reviewer, sonnet) | Claude (test-engineer, sonnet) |

근거: codex는 정밀한 추론에 강하므로 구조 분석(Agent 1)과 테스트 분석(Agent 3)에 적합. 동작 분석(Agent 2)은 코드 품질 관점이 필요하므로 quality-reviewer를 유지한다.

### codex 라우팅 시 호출 패턴

`_shared/cli-runtime-check.md` 섹션 6을 참조한다.

Agent 1 + Agent 3을 omc-teams **1개 job(2개 task)**으로 묶어 실행한다. Agent 2는 Claude `Task()`로 동시 실행한다. 3개 모두 병렬 진행.

```
ToolSearch(query="+omc_run_team_start")
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{WORKLOG_SLUG}-deep-analysis",
  "agentTypes": ["codex"],
  "tasks": [
    {"subject": "구조 분석", "description": "{Agent 1 프롬프트}"},
    {"subject": "테스트 분석", "description": "{Agent 3 프롬프트}"}
  ],
  "cwd": "{cwd}"
})
```

Agent 2 (Claude Task)는 위 호출과 **동시에** 실행한다.

codex 결과 수신:
```
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({"job_id": "{jobId}"})
```

- `status=completed` → `taskResults[0].output` (Agent 1), `taskResults[1].output` (Agent 3)
- `status=failed` 또는 `timeout` → `_shared/cli-runtime-check.md` 섹션 4 fallback: Claude `Task()`로 재실행 (silent fallback)

정리 (분석 완료 후):
```
mcp__plugin_oh-my-claudecode_team__omc_run_team_cleanup({"teamName": "{WORKLOG_SLUG}-deep-analysis"})
```

## 실행

3개 에이전트를 **동시에** 호출한다.

### Agent 1: 구조 분석 (Architecture Mapping)

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="
Analyze the architecture of this code area.

## Scope
{SCOPE_DESCRIPTION}

## Analyze
- Module boundaries and responsibilities
- Component hierarchy and data flow
- State management patterns
- Key abstractions and interfaces
- Design patterns used
- How this area fits into the larger system

## Code
{file contents of all in-scope files}

## Change Context
{WORKLOG_CONTEXT — 있는 경우에만 포함}

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

### Agent 2: 동작 분석 (Behavior Mapping)

```
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="
Map the current behavior of this code area.

## Scope
{SCOPE_DESCRIPTION}

## Analyze
- User-visible behaviors (what the user sees/experiences)
- Internal behaviors (state transitions, side effects)
- Error handling paths
- Edge cases and boundary conditions
- Async/timing behaviors
- Undo/redo implications (if applicable)

## Code
{file contents}

## Change Context
{WORKLOG_CONTEXT — 있는 경우에만 포함}

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

### Agent 3: 테스트 분석 (Test & Coverage Mapping)

```
Task(subagent_type="oh-my-claudecode:test-engineer", model="sonnet",
     prompt="
Analyze the test coverage for this code area.

## Scope
{SCOPE_DESCRIPTION}

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

## Change Context
{WORKLOG_CONTEXT — 있는 경우에만 포함}

## Output Format
### Coverage Map
- {behavior/function} → {test file:test name} / UNTESTED

### Coverage Gaps
- {what's not tested and why it matters}

### Test Quality Notes
- {observations about test patterns}

IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

## 출력

| 키 | 출처 | 내용 |
|---|---|---|
| `ARCHITECTURE_RESULT` | Agent 1 | Architecture Overview, Key Abstractions, Data Flow, Dependencies, Dependents |
| `BEHAVIOR_RESULT` | Agent 2 | User-Facing/Internal Behaviors, Error Paths, Edge Cases |
| `TEST_COVERAGE_RESULT` | Agent 3 | Coverage Map, Coverage Gaps, Test Quality Notes |
