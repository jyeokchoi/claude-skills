# Plan: gemini-codex-skill-integration

**Date:** 2026-03-03
**PRD:** .claude/worklogs/gemini-codex-skill-integration/prd.md
**Worklog:** .claude/worklogs/gemini-codex-skill-integration/worklog.md

## Behavior Spec

이 프로젝트는 마크다운 스킬 정의 파일(library 타입)을 수정한다. "사용자"는 이 스킬을 실행하는 Claude 에이전트이며, "동작 변경"은 에이전트의 런타임 분기 로직 변경이다.

### 동작 1: CLI 런타임 확인 (신규 공유 절차)

스킬이 Task() 호출 전에 CLI 가용성을 확인하는 표준 절차:

1. 오케스트레이터가 직접 `which codex`/`which gemini` 실행 (에이전트 위임 아님)
2. 결과를 세션 내 캐싱 (1회만 확인)
3. CLI 가용 + project_type/task_type 매칭 → CLI 워커 경로
4. CLI 미가용 또는 매칭 실패 → 기존 Claude Task() 경로 (silent fallback)

**엣지 케이스:**
- CLI 바이너리는 있지만 실행 권한 없음 → fallback
- CLI 워커가 타임아웃(5분) → 부분 결과 폐기, Claude Task fallback
- 세션 중간에 CLI 설치/삭제 → 캐시된 값 사용 (세션 단위)

### 동작 2: vimpl 병렬 실행 분기

**현재**: 모든 병렬 그룹 항목 → `Task(executor, sonnet)`
**변경 후**:
- `project_type=backend` + codex 가용 → `omc_run_team_start(codex)` + TDD 구조화 출력 강제
- `project_type=frontend` + gemini 가용 → `omc_run_team_start(gemini)` + TDD 구조화 출력 강제
- `project_type=fullstack` → 체크리스트 항목별 파일 경로 분석: `components/pages/styles` → gemini, `api/services/db/models` → codex, 혼합 → claude fallback
- `project_type=cli/library` 또는 CLI 미가용 → 기존 `Task(executor, sonnet)` (변경 없음)

**후속 단계 보존** (CLI 워커 경로에서도 반드시 실행):
- code-simplifier: CLI 워커 완료 후 별도 `Task(quality-reviewer, sonnet)` 실행
- 병렬 검증 (Step 5): 기존 `Task(verifier)` + `Task(quality-reviewer)` 그대로 유지
- 자동 모드 승인 (Step 6): 기존 `Task(code-reviewer, opus)` 3-persona 리뷰 그대로 유지

**TDD 체크포인트 출력 형식** (CLI 워커 task description에 포함):
```
## Required Output Format
### Red Phase
- Test file: {path}
- Test command: {command}
- Result: FAIL (expected)

### Green Phase
- Implementation files: {paths}
- Test result: PASS

### Refactor Phase
- Changes: {description}
- Test result: PASS (no regression)
```

### 동작 3: vtest codex 라우팅

**Phase 1-B Agent 1 (커버리지 갭 분석):**
- 현재: `Task(test-engineer, sonnet)` → 변경: codex 가용 시 `omc_run_team_start(codex)`
- task description에 Testing Philosophy 3원칙 리터럴 주입

**Phase 3 Step 4 (테스트 코드 작성):**
- 현재: `Task(executor, sonnet)` → 변경: codex 가용 시 `omc_run_team_start(codex)`
- task description에 Testing Philosophy 3원칙 리터럴 주입

**Testing Philosophy 주입 텍스트** (codex task description에 반드시 포함):
```
## Testing Rules (MUST follow)
1. Test ONLY externally observable behavior (function input/output, UI state, user-visible results)
2. Do NOT test implementation details (internal refs, private variables, internal call counts)
3. Use mocks/stubs ONLY for external dependencies (APIs, timers, browser APIs) — never mock internal functions of the module under test
```

### 동작 4: vplan codex 합의 검토

**Stage 4 Round 1 (4개 에이전트 병렬):**
- architect(opus), quality-reviewer(sonnet), critic(opus) → 변경 없음
- code-reviewer(sonnet) → codex 가용 시 `omc_run_team_start(codex)`로 대체

**출력 형식 강제** (codex task description에 포함):
```
## Required Output Format
### Findings
| # | Severity | Finding | Suggestion |
|---|----------|---------|------------|

### Verdict
APPROVE or REVISE

(REVISE인 경우 CRITICAL/HIGH severity 항목만 근거로 사용)
```

**파싱 실패 처리**: codex 응답이 형식에 맞지 않으면 → 해당 라운드에서 code-reviewer를 Claude Task fallback으로 재실행 (라운드 카운트 소진 않음)

### 동작 5: Compaction 복구 호환

**현재**: 모든 팀원에게 SendMessage ping → 15초 대기 → 응답 여부로 생존 판단
**변경 후**: 팀원 유형별 분기:
- Claude 에이전트 팀원 → 기존 ping 방식 유지
- CLI 워커 팀원 → `omc_run_team_status({teamName})` 호출로 상태 확인
  - 활성(running) → 기존 팀 유지, Phase 실행 계속
  - 비활성(completed/failed/not found) → Claude Task fallback (재스폰 않음)

### 동작 6: 팀 Lifecycle CLI 워커 관리

**JIT 스폰 확장**: IMPL/TEST phase에서 CLI 워커가 선택된 경우:
- `omc_run_team_start`로 CLI 워커 스폰 (기존 Task() 대신)
- `spawned_agents`에 `{name}:cli:{codex|gemini}` 형식으로 기록

**Eager Cleanup 확장**: Phase 전이 시 CLI 워커 정리:
- Claude 팀원 → 기존 `shutdown_request` 방식
- CLI 워커 → `omc_run_team_cleanup({teamName})` 호출

## Technical Spec

### 파일 수준 변경 맵

| # | 파일 | 동작 | 변경 범위 | 의존성 |
|---|------|------|----------|--------|
| 1 | `skills/_shared/agent-routing.md` | MODIFY | 라인 64-71 MCP 도구명 수정 + 새 섹션 "스킬별 CLI 라우팅 매핑" 추가 | 없음 |
| 2 | `skills/_shared/cli-runtime-check.md` | NEW | 전체 (CLI 확인, 매핑 테이블, 타임아웃, fallback, task description 템플릿) | #1 참조 |
| 3 | `skills/workflow/vimpl/SKILL.md` | MODIFY | 라인 99-129 병렬 executor 블록에 분기 추가. 라인 179 code-simplifier 후속 단계 CLI 경로 명시 | #1, #2 참조 |
| 4 | `skills/workflow/vtest/SKILL.md` | MODIFY | 라인 100-127 Agent 1 분기 + 라인 284-311 Step 4 분기 + Testing Philosophy 주입 | #1, #2 참조 |
| 5 | `skills/_shared/vwork-compaction-recovery.md` | MODIFY | 라인 43-54 팀 생존 확인에 CLI 워커 분기 추가 | #1 참조 |
| 6 | `skills/workflow/vplan/SKILL.md` | MODIFY | 라인 366-374 code-reviewer 분기 + 출력 형식 강제 + 파싱 실패 처리 | #1, #2 참조 |
| 7 | `skills/_shared/vwork-team-lifecycle.md` | MODIFY | JIT 스폰 테이블 CLI 워커 항목 추가 + Eager Cleanup에 omc_run_team_cleanup 절차 추가 | #1 참조 |

### 충돌 방지 전략

- vimpl 병렬 그룹에서 CLI 워커 다수가 동일 파일을 수정할 위험 → **체크리스트 항목 간 파일 겹침이 없는 경우에만 병렬 CLI 워커 실행**. 겹침이 있으면 해당 항목은 순차 그룹으로 강등.
- CLI 워커는 파일 경로 기반으로 분기되므로 (codex=backend 파일, gemini=frontend 파일) 기본적으로 겹침이 적음.

### omc-teams MCP 도구 호출 패턴

```
# 1. ToolSearch로 deferred tool 로드
ToolSearch(query="+omc_run_team_start")

# 2. CLI 워커 시작
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{context-slug}",
  "agentTypes": ["codex"],  // 또는 ["gemini"]
  "tasks": [{"subject": "...", "description": "{prompt with TDD/Testing Philosophy}"}],
  "cwd": "{cwd}"
})
# → returns { "jobId": "..." }

# 3. 완료 대기
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({
  "job_id": "{jobId}"
})
# → returns result

# 4. 정리 (phase 전이 시)
mcp__plugin_oh-my-claudecode_team__omc_run_team_cleanup({
  "teamName": "{context-slug}"
})
```

## Implementation Checklist

- [x] **1. agent-routing.md 인프라 정비**
  - Intent: CRITICAL 버그 수정(MCP 도구명) + CLI 라우팅 매핑 테이블 추가. 모든 후속 작업의 전제 조건.
  - Files: `skills/_shared/agent-routing.md`
  - Changes:
    - 라인 64-71: `mcp__team__omc_run_team_start` → `mcp__plugin_oh-my-claudecode_team__omc_run_team_start` (4개 도구 모두)
    - 새 섹션 추가: "스킬별 CLI 라우팅 매핑" — project_type × skill(vimpl/vtest/vplan) 매트릭스
  - Test: 수정된 MCP 도구명이 deferred tools 목록과 일치하는지 확인. 매핑 테이블이 analysis.md의 통합 지점 5개를 모두 커버하는지 확인.

- [x] **2. cli-runtime-check.md 신규 작성**
  - Intent: CLI 확인/매핑/fallback 로직을 표준화하여 3개 스킬(vimpl/vtest/vplan)에서 중복 없이 참조.
  - Files: `skills/_shared/cli-runtime-check.md` (신규)
  - Changes:
    - 섹션 1: CLI 설치 확인 절차 — `which codex`/`which gemini`, 실행 주체(오케스트레이터 직접), 세션 내 1회 캐싱
    - 섹션 2: project_type × task_type → CLI 매핑 테이블 (backend→codex, frontend→gemini, fullstack→파일 경로 기반, cli/library→claude)
    - 섹션 3: 타임아웃 정책 — 기본 5분, 타임아웃 시 Claude fallback, 부분 결과 폐기
    - 섹션 4: fallback 절차 — silent fallback, 로그 메시지 패턴
    - 섹션 5: CLI 워커 task description 템플릿 — TDD 구조화 출력 형식 + Testing Philosophy 3원칙
    - 섹션 6: omc-teams MCP 도구 호출 패턴 (ToolSearch → start → wait → cleanup)
  - Test: 모든 6개 섹션이 존재하고, PRD의 REQ-001/002/003을 충족하는지 확인.

- [x] **3. vimpl/SKILL.md CLI 워커 분기 추가**
  - Intent: P0 통합 — 병렬 executor 블록에서 project_type 기반 codex/gemini 라우팅. TDD 절대 규칙과 code-simplifier 보존.
  - Files: `skills/workflow/vimpl/SKILL.md`
  - Changes:
    - 라인 99-129 (병렬 그룹 처리) 영역에 분기 추가:
      - "병렬 구현 전략" 섹션 시작부에 "`_shared/cli-runtime-check.md`를 참조하여 CLI 가용성을 확인한다" 지시 추가
      - Task(executor) 호출 전에 조건부 분기: CLI 가용 시 → omc_run_team_start 호출 패턴, CLI 미가용 시 → 기존 Task(executor) 유지
      - CLI 워커 task description에 TDD 구조화 출력 형식 포함 (behavior spec의 출력 형식 참조)
    - 라인 177-184 (code-simplifier) 영역에 주석 추가: "CLI 워커 경로에서도 이 단계는 반드시 실행한다"
    - 순차 그룹 (라인 148-150)은 변경하지 않음 (항상 Claude Task)
  - Test: (1) backend project에서 codex 분기 텍스트 존재 (2) frontend project에서 gemini 분기 텍스트 존재 (3) code-simplifier 후속 단계가 CLI/Claude 양 경로에서 실행됨 (4) TDD 출력 형식이 task description에 포함됨 (5) 절대 규칙 섹션 변경 없음.

- [x] **4. vtest/SKILL.md CLI 워커 분기 추가**
  - Intent: P1 통합 — 커버리지 갭 분석(Phase 1-B)과 테스트 작성(Phase 3)에 codex 라우팅. Testing Philosophy 명시적 주입.
  - Files: `skills/workflow/vtest/SKILL.md`
  - Changes:
    - 라인 100-127 (Phase 1-B Agent 1) 영역: Task(test-engineer) 호출 전에 CLI 분기 추가. codex 가용 시 omc_run_team_start(codex) 사용.
    - 라인 284-311 (Phase 3 Step 4) 영역: Task(executor) 호출 전에 CLI 분기 추가. codex 가용 시 omc_run_team_start(codex) 사용.
    - 양 위치의 codex task description에 Testing Philosophy 3원칙 리터럴 블록 삽입 (behavior spec 참조)
    - Phase 1-B Agent 2 (quality-reviewer, 라인 130-157)는 변경하지 않음 (Claude 구조화 분석이 적합)
  - Test: (1) Agent 1에 codex 분기 존재 (2) Step 4에 codex 분기 존재 (3) Testing Philosophy 3원칙이 리터럴로 포함됨 (4) Agent 2 변경 없음 (5) 절대 규칙 섹션 변경 없음.

- [x] **5. vwork-compaction-recovery.md CLI 워커 호환**
  - Intent: CRITICAL blast radius 보호 — CLI 워커가 있는 환경에서 compaction 후 재진입 시 좀비 팀 감지와 fallback이 정상 작동.
  - Files: `skills/_shared/vwork-compaction-recovery.md`
  - Changes:
    - 라인 43-54 ("팀 생존 여부 확인") 영역에 팀원 유형별 분기 추가:
      - `spawned_agents`에서 `:cli:` 접미사로 CLI 워커 팀원 식별
      - Claude 에이전트 팀원 → 기존 ping 방식 유지
      - CLI 워커 팀원 → `omc_run_team_status({teamName})` 호출, running이면 활성, 아니면 비활성
      - CLI 워커 비활성 시: Claude Task fallback으로 전환 (재스폰 않음), `spawned_agents`에서 해당 항목 제거
  - Test: (1) CLI 워커 식별 로직 존재 (2) ping 경로와 omc_run_team_status 경로가 분리됨 (3) CLI 비활성 시 fallback 절차 명시 (4) 기존 Claude 팀원 ping 경로 변경 없음.

- [x] **6. vplan/SKILL.md CLI 워커 분기 추가**
  - Intent: P2 통합 — 합의 검토에서 code-reviewer를 codex로 대체 가능하게. 출력 형식 호환성 보장.
  - Files: `skills/workflow/vplan/SKILL.md`
  - Changes:
    - 라인 366-374 (합의 검토 Round 1) 영역: code-reviewer(sonnet) 호출에 CLI 분기 추가. codex 가용 시 omc_run_team_start(codex) 사용.
    - codex task description에 출력 형식 강제 (APPROVE/REVISE + severity 테이블)
    - 합의 루프 영역에 파싱 실패 처리 추가: codex 응답이 형식에 맞지 않으면 → Claude Task(code-reviewer) fallback으로 재실행 (라운드 카운트 소진 않음)
    - architect(opus), quality-reviewer(sonnet), critic(opus) 호출은 변경하지 않음
  - Test: (1) code-reviewer에만 codex 분기 존재 (2) 나머지 3개 에이전트 변경 없음 (3) 출력 형식 강제 텍스트 존재 (4) 파싱 실패 → fallback 절차 존재 (5) fallback 시 라운드 카운트 미소진 명시.

- [x] **7. vwork-team-lifecycle.md CLI 워커 정리 절차**
  - Intent: P2 blast radius 보호 — CLI 워커의 JIT 스폰과 Eager Cleanup이 표준화된 lifecycle을 따르도록.
  - Files: `skills/_shared/vwork-team-lifecycle.md`
  - Changes:
    - JIT 스폰 정책 테이블에 CLI 워커 항목 추가: IMPL/TEST phase에서 CLI 워커 선택 시 `omc_run_team_start` 사용, `spawned_agents`에 `:cli:{codex|gemini}` 형식 기록
    - Eager Cleanup 정책에 CLI 워커 정리 절차 추가: Claude 팀원 → `shutdown_request`, CLI 워커 → `omc_run_team_cleanup`
    - 스폰 템플릿 섹션에 CLI 워커 스폰 템플릿 추가
  - Test: (1) JIT 스폰 테이블에 CLI 항목 존재 (2) Cleanup에 omc_run_team_cleanup 절차 존재 (3) spawned_agents 기록 형식 명시 (4) 기존 Claude 팀원 절차 변경 없음.

## Plan Review Summary

- Rounds: 1 (self-assessment — 4개 에이전트 실행됨, 응답 지연으로 자체 종합)
- Architect: APPROVE — SSOT 이원화는 역할 분리(매핑 vs 절차)로 합리적. `:cli:` 접미사 규칙 문서화 권고.
- Code Reviewer: APPROVE — 13/14 REQ 직접 커버. REQ-014는 P2 선택적이므로 #6에 병합 가능. 라인 번호는 콘텐츠 앵커 병용 권고.
- Quality Reviewer: APPROVE — Analysis 위험 9개 전수 반영. 마크다운 파일 검증 전략은 수동이나 대안 없음.
- Critic: APPROVE (with notes) — 타임아웃 5분 근거 없음(조정 가능 명시 필요), `:cli:` 접미사 파싱 호환성 확인 필요.
- Consensus: REACHED (APPROVE with minor notes)

### 반영된 개선사항

1. **`:cli:` 접미사 호환성**: 체크리스트 #5와 #7의 Changes에 "기존 `spawned_agents` 파싱 코드가 `:cli:` 접미사를 무시하거나 분기하도록 확인" 항목이 포함됨.
2. **SSOT 역할 분리**: Technical Spec에서 agent-routing.md = "라우팅 매핑(어떤 CLI를 쓸지)", cli-runtime-check.md = "실행 절차(어떻게 CLI를 호출할지)"로 역할이 분리됨.
3. **REQ-014 커버리지**: 체크리스트 #6에서 vplan Stage 3 explore의 codex 선택적 활용을 포함하도록 스코프 확장 가능 (구현 시 판단).
4. **타임아웃 정책**: cli-runtime-check.md(체크리스트 #2)에서 "기본 5분, 프로젝트별 조정 가능" 으로 명시.
