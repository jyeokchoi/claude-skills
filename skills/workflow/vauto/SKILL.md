---
name: vauto
description: Unified workflow orchestrator. Auto-mode entry point for analyze → PRD → plan → implement → verify → test → finish pipeline.
argument-hint: 'Usage: /vauto [worklog-path | task-name | ISSUE-KEY] [brief]'
# 자동 전이 전용 오케스트레이터.
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.local.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용.

워크로그 phase를 기반으로 전체 작업 라이프사이클을 관리하는 통합 오케스트레이터의 auto 전용 진입점.

## 입력

- 원본 인자: $ARGUMENTS

인자 해석:
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

## 정규 전이 테이블 (SSOT)

아래 테이블이 `vauto`의 정상 전이 단일 진실 기준이다.

| 현재 phase | 기본 다음 phase | 전이 근거 |
|------------|-----------------|----------|
| ANALYZE | PRD | 분석 결과 확정 |
| PRD | PLAN | 요구사항/스토리 확정 |
| PLAN | IMPL | 구현 체크리스트 확정 |
| IMPL | VERIFY | 구현 완료 후 검증 진입 |
| TEST | VERIFY | 테스트 작성/수정 후 재검증 |

예외 전이는 VERIFY의 verdict route에서만 허용한다:
- `all_pass` → DONE
- `code_issues` / `code_issues_and_test_gaps` → IMPL
- `test_gaps` → TEST

## 정규 Phase-팀원 매핑 (단일 참조 테이블)

이 테이블이 모든 phase-팀원 관계의 단일 진실 기준이다. Step 0, 3-B, 4-S, 4, 5에서 이 테이블을 참조한다. `_shared/agent-routing.md`에 전체 에이전트 라우팅 테이블이 정의되어 있으며, 아래는 vauto 전용 역할명-Phase 매핑이다.

| Phase | 담당 팀원 | 스킬 | subagent_type | model | 비고 |
|-------|----------|------|---------------|-------|------|
| ANALYZE | `analyzer` | /vanalyze | oh-my-claudecode:debugger | sonnet | CLI: codex (디버깅, 복잡한 로직 분석) |
| PRD | `planner` | /vplan (Stage 1) | oh-my-claudecode:planner | opus | |
| PLAN | `planner` | /vplan (Stages 2-4) | oh-my-claudecode:planner | opus | CLI: codex (아주 복잡한 플래닝) |
| IMPL | `implementer` | /vimpl | oh-my-claudecode:executor | sonnet | CLI: codex (복잡한 로직, backend) / gemini (frontend, 단순+넓은 범위) |
| VERIFY | `qa` | /vqa | oh-my-claudecode:verifier | sonnet | |
| TEST | `tester` | /vtest | oh-my-claudecode:test-engineer | sonnet | CLI: codex (backend) / gemini (frontend 테스트) |

## Per-phase CLI 라우팅 규칙

Phase별로 `codex_available`, `gemini_available`, `project_type`을 기반으로 cli_type을 결정한다. Step 3에서 CLI 가용성만 확인하고, Step 4에서 phase별 규칙을 적용한다.

| Phase | 조건 | cli_type | model (fallback) | 근거 |
|-------|------|----------|-----------------|------|
| ANALYZE | codex_available | codex | — | 디버깅, 복잡한 로직 분석 |
| ANALYZE | 복잡 + !codex_available | claude | opus | 복잡한 분석 fallback |
| ANALYZE | 단순 + !codex_available | claude | sonnet | 단순한 분석 fallback |
| PLAN | 복잡한 플래닝/구체화 + codex_available | codex | — | 복잡한 추론, 플랜 구체화 |
| PLAN | 간단한 플래닝 | claude | opus | 오케스트레이션, 일반 플래닝 |
| IMPL | backend + codex_available | codex | — | 복잡한 로직 작성 |
| IMPL | frontend + gemini_available | gemini | — | 프론트엔드 코드, 단순+넓은 범위 |
| IMPL | 복잡한 로직 + !codex_available | claude | opus | 복잡한 로직 fallback |
| IMPL | 단순한 로직 | claude | sonnet | 단순한 로직 |
| VERIFY | 복잡 | claude | opus | 복잡한 검증 (codex 크로스 검증은 vqa 내부 Agent 5가 처리) |
| VERIFY | 단순 | claude | sonnet | 단순 검증 (codex 크로스 검증은 vqa 내부 Agent 5가 처리) |
| TEST | backend + codex_available | codex | — | backend 테스트 |
| TEST | frontend + gemini_available | gemini | — | 프론트엔드 테스트 |
| TEST | 기타 | claude | sonnet | 기타 테스트 |

**복잡도 판단 기준:**
- **ANALYZE**: 영향 범위 3개 모듈 이상, 또는 cross-cutting concern, 또는 레거시 코드 분석 → 복잡
- **PLAN**: REQ ≥ 10개, 또는 영향 파일 ≥ 15개, 또는 cross-cutting ≥ 3, 또는 스펙 구체화 단계 → 복잡
- **IMPL**: 알고리즘/자료구조 설계, 상태 머신, 동시성/비동기 제어, 성능 최적화, 복잡한 비즈니스 규칙 → 복잡. plan.md 체크리스트 항목의 설명에서 판단한다.
- **VERIFY**: 변경 파일 ≥ 10개, 또는 아키텍처 변경 포함, 또는 보안 관련 변경 → 복잡

## 상태 보존 규칙

`_shared/state-preservation-rule.md`를 로드하고 해당 규칙을 따른다. auto 경로 규칙:

- `team_name`, `current_phase`, `feedback_iterations`, `spawned_agents` 등 누적 필드 유실 방지.
- VERIFY→IMPL 또는 VERIFY→TEST 전이 시 `feedback_iterations`를 1 증가시킨다 (IMPL→VERIFY, TEST→VERIFY에서는 증가하지 않음).
- `code_issues_and_test_gaps` route 처리 시 VERIFY→IMPL(+1) 후 재검증에서 test_gaps가 남아 VERIFY→TEST(+1)가 추가될 수 있으며, 이는 의도된 동작이다 (최대 2회 소비).
- 최대 5회 초과 시 사용자에게 보고.

## spawned_agents 관리 규칙

`spawned_agents`는 현재 활성 팀원 이름 목록이다 (순수 이름만, 접미사 없음):
- 스폰 시 append, 정리(shutdown_request 응답 수신 또는 omc_run_team_cleanup 완료) 시 제거.
- 스폰 또는 정리 발생 시 즉시 상태 보존 규칙에 따라 `state_write`로 갱신한다.
- Step 0 재수화 시 팀원 생존 여부 확인과 DONE phase 정리 대상 결정에 사용된다.

`cli_workers`는 CLI 워커 팀원의 메타데이터 맵이다:
- 형식: `{"implementer": {"cli_type": "codex", "team_name": "...", "job_id": "..."}, "tester": {"cli_type": "gemini", "team_name": "...", "job_id": "..."}}`
- CLI 워커 스폰 시 추가, 정리 완료 시 해당 키 제거.
- `spawned_agents`와 함께 `state_write(mode="vwork")`로 항상 동시 갱신.
- `cli_workers[{팀원명}]`이 존재하면 해당 팀원은 CLI 워커로 판단한다.

## Notepad 라이프사이클

| 시점 | 갱신 내용 | 순서 제약 |
|------|----------|----------|
| Step 3 (초기) | 전체 priority 템플릿 기록 (`team:미정`) | — |
| Step 3-B (팀 생성 후) | `team:미정` → `team:{team_name}` 교체, 전체 템플릿 재출력 | — |
| Step 5 (Phase 전이) | `phase:{OLD}` → `phase:{NEW}` 교체, 전체 템플릿 재출력 | 워크로그 업데이트 → notepad 갱신 → state_write |
| DONE phase | `<remember priority></remember>` (빈 내용) 출력으로 클리어 | — |

## 절차

### 0. 상태 재수화 (ralph 재진입 감지)

**가장 먼저 실행한다.** `_shared/vwork-compaction-recovery.md`를 로드하고 해당 절차를 따른다.

요약: `<notepad-context>`에 `vwork활성`이 보이거나 `state_read(mode="vwork")`에서 `active=true`이면 ralph 재진입으로 간주. state에서 변수 복구 → 행동 규칙 복구 (SKILL.md 재읽기) → phase 일치 검증 → 팀 생존 확인 후 Step 4로 점프 또는 Step 3-B로 팀 재생성.

`active=false` 또는 state 없는 경우: Step 1부터 정상 진행.

### 1. 워크로그 결정 또는 생성

**인자가 워크로그 경로인 경우:**
- 기존 워크로그를 로드하고 `phase` 필드를 읽는다
- phase가 비어있으면: 작업 유형 감지 → 초기 phase 설정
- 재개 검증 수행
- Step 2로 진행

**인자가 작업명 또는 Jira 이슈 키인 경우:**
- `/worklog-start`로 새 워크로그 생성
- 작업 유형 감지 → 초기 phase 설정
- Step 2로 진행

**인자 없음:**
- 활성 워크로그 검색 (`.claude/worklogs/.active` 또는 find)
- 발견 시: 로드, 재개 검증, Step 2로 진행
- 미발견 시: 사용자에게 요청, `/worklog-start`로 생성

**작업 유형 감지 (신규 vs 기존 수정):**

| 유형 | 감지 신호 | 초기 phase |
|------|-----------|------------|
| **신규 기능** (new-feature) | "새 기능", "new feature", "신규", "새로 만들", "create", "build from scratch", "greenfield" | `PRD` |
| **기존 수정** (modification) | "수정", "변경", "fix", "refactor", "modify", "개선", "migrate", "버그", "regression", 또는 특정 파일/모듈 경로 언급 | `ANALYZE` |

- frontmatter에 `type` 명시 시 그대로 사용.
- 감지 불가 시: **최선의 판단**으로 유형을 선택하고 Decisions에 기록한다: `- [CURRENT] Task type: {type} — 근거: {1~2문장}`

**재개 검증 (기존 워크로그만):**

방금 생성된 워크로그면 건너뛴다. 기존 워크로그 재개 시:
1. 상태 요약 출력 (Goal, Jira, Branch, Phase, Decisions, 최근 작업)
2. Decisions이 있으면 유효성 질문 → 수정 시 `[INVALIDATED {date}]` 표시 + 새 결정 `[CURRENT]`
3. `_shared/update-worklog.md`로 "세션 재개" 타임라인 기록

### 2. 실행 정책

vauto는 항상 세션 기반 자동 전이로 동작한다. ralph loop이 상시 활성화되어 컴팩션 복원력을 보장하고, 모든 작업은 팀원에게 위임된다.

- 출력: "자동 전이를 시작합니다. 완료까지 연속 진행합니다."

**ralph loop 활성화:**

`_shared/ralph-activation.md`를 로드하고 해당 절차를 따른다.

Step 3으로 진행

### 3. 오케스트레이션 컨텍스트

서브 스킬이 오케스트레이션 상태를 인식할 수 있도록 컨텍스트를 기록한다:

**project_type 감지 (CLI 라우팅에 사용):**
`_shared/resolve-project-type.md`를 로드하고 해당 절차를 따른다. vauto는 오케스트레이터이므로 독립 실행 경로를 사용한다.

**CLI 가용성 확인:**
`_shared/cli-runtime-check.md` 섹션 2를 참조한다:
1. `codex`/`gemini` 가용성 확인은 **병렬 실행**을 기본으로 한다.
2. `Bash(command="which codex 2>/dev/null && codex --version 2>/dev/null")` → 성공 시 `codex_available = true`, 실패/오류 시 `false`
3. `Bash(command="which gemini 2>/dev/null && gemini --version 2>/dev/null")` → 성공 시 `gemini_available = true`, 실패/오류 시 `false`

글로벌 `cli_type`은 결정하지 않는다. Phase별 CLI 라우팅 규칙(위 테이블)에 따라 Step 4에서 phase별로 결정한다.

- `_shared/orchestration-context.md`를 로드하고 **vwork — 쓰기** 프로토콜을 따른다.
- `state_write(mode="vwork", data={ "active": true, "mode": "auto", "current_phase": "{phase}", "worklog_dir": "{WORKLOG_DIR}", "worklog_slug": "{WORKLOG_SLUG}", "project_type": "{project_type}", "task_type": "{task_type}", "feedback_iterations": {기존 값 또는 0}, "spawned_agents": {기존 값 또는 []}, "cli_workers": {기존 값 또는 {}}, "codex_available": {codex_available}, "gemini_available": {gemini_available} })`
  - **`team_name`**: 이 시점에서는 미정. Step 3-B에서 팀 생성 후 상태 보존 규칙에 따라 추가.
- **재수화 대상 필드**: `worklog_slug`, `project_type`, `task_type`, `spawned_agents`는 결정 시점에서 반드시 갱신.
- 각 서브 스킬 호출 전에 `current_phase`를 해당 phase로 업데이트한다.

### 3-B. 에이전트 팀 생성

`_shared/vwork-team-lifecycle.md`를 로드하고 해당 절차를 따른다.

팀 생성 전에 기존 팀을 확인한다:
- `state_read(mode="vwork")`에서 `team_name`이 있고 `~/.claude/teams/{team_name}/config.json`이 존재하면: 기존 팀 재사용.
- 그 외: 새 팀 생성 → `TeamCreate(team_name="vwork-{WORKLOG_SLUG}", description="vwork 에이전트 팀 — {GOAL_SUMMARY}")`

팀 생성 후:
- 상태 보존 규칙에 따라 `state_write`에 `team_name`과 `spawned_agents` 추가.
- Notepad 라이프사이클에 따라 `team:미정` → `team:{team_name}` 갱신.

참고: 팀원들은 스킬(`/vanalyze`, `/vplan` 등)을 실행할 수 있다. 팀원이 결과를 보고할 때 `recipient="vauto"`를 사용한다.

### 3-C. phase 동기화 (worklog 기준)

Step 4 진입 직전에 워크로그 frontmatter의 `phase`를 다시 읽고, `state.current_phase`와 다르면 **워크로그 값을 진실 기준**으로 동기화한다.

- 이유: 워크로그 업데이트와 state_write의 시점 차이로 재진입 시 드리프트가 발생할 수 있다.
- 동기화는 상태 보존 규칙(`state_read` 후 부분 갱신)을 따른다.

### 4-S. 세션 라우팅 (사용자 자유 요청 처리)

ralph loop 중 사용자가 자유 요청을 보낸 경우, `_shared/vwork-session-routing.md`를 로드하고 해당 절차를 따른다.

핵심: 모든 요청을 현재 phase 맥락에서 해석하고, 정규 매핑 테이블의 현재 phase 담당 팀원에게 위임한다. 미래 phase 요청은 직접 위임하지 않고 현재 phase 완료를 안내한다.

### 4. Phase 실행

워크로그의 `phase` 필드를 읽고 정규 매핑 테이블에 따라 해당 팀원에게 위임한다.

#### 공통 위임 템플릿

```
SendMessage(type="message", recipient="{정규 매핑 테이블의 담당 팀원}",
  content="{PHASE} phase를 실행하세요.

  작업: {정규 매핑 테이블의 스킬} {WORKLOG_DIR} 를 실행하고 결과를 보고하세요.
  완료 시 결과 요약을 반환하세요.",
  summary="{PHASE} phase 위임")
```

#### 공통 결과 처리

1. 결과를 사용자에게 요약 보고
2. 사용자 인터랙션이 있으면 결정사항을 `_shared/update-worklog.md`로 기록 (Decisions에 `[CURRENT] {결정사항}`)
3. 정규 전이 테이블(또는 VERIFY verdict route)로 다음 phase를 결정
4. 다음 phase로 업데이트

#### 공통 라우팅 결정 순서

현재 phase 담당자를 실행할 때 다음 우선순위를 고정한다:
1. `spawned_agents`에 활성 팀원이 있으면 해당 팀원 재사용
2. 없고 `cli_workers[{role}]`가 있으며 해당 CLI 워커가 활성 상태면 CLI 워커 사용
3. 그 외에는 정규 Phase-팀원 매핑 테이블 기준으로 팀원을 스폰/실행

동률 시 우선순위는 `spawned_agents` > `cli_workers` > 정규 매핑이다.

#### ANALYZE phase 특수 사항

Per-phase CLI 라우팅 규칙에 따라 cli_type과 model을 결정한다:
- `codex_available=true` → `cli_type=codex`
- 복잡한 분석 + `!codex_available` → `cli_type=claude`, model=opus
- 단순한 분석 + `!codex_available` → `cli_type=claude`, model=sonnet

SendMessage content에 다음을 추가한다:
- `cli_type={cli_type}` 파라미터
- **`cli_type`이 `codex`인 경우**: `"CLI 워커(codex)를 반드시 사용하여 분석을 실행하라."`
- `cli_type=claude`이고 model이 기본과 다른 경우, 팀원 스폰 시 해당 model을 지정한다.

#### PRD phase 특수 사항

SendMessage content에 `orchestration state current_phase=PRD에 따라 Stage 1 PRD만 실행` 지시를 포함한다.

#### PLAN phase 특수 사항

SendMessage content에 `orchestration state current_phase=PLAN에 따라 Stages 2-4 + consensus review 실행` 지시를 포함한다.

Per-phase CLI 라우팅 규칙에 따라 cli_type을 결정한다:
- 복잡한 플래닝 또는 플랜 구체화 + `codex_available=true` → `cli_type=codex`
- 간단한 플래닝 → `cli_type=claude` (opus 모델)

`codex_available={codex_available}`와 `cli_type={cli_type}` 파라미터를 항상 추가한다.

#### IMPL phase 특수 사항

Per-phase CLI 라우팅 규칙에 따라 cli_type과 model을 결정한다:
- `backend` + `codex_available=true` → `cli_type=codex`
- `frontend` + `gemini_available=true` → `cli_type=gemini`
- 복잡한 로직 + `!codex_available` → `cli_type=claude`, model=opus
- 단순한 로직 → `cli_type=claude`, model=sonnet

"복잡한 로직" 판단: plan.md 체크리스트 항목에 알고리즘/자료구조, 상태 머신, 동시성/비동기, 성능 최적화, 복잡한 비즈니스 규칙이 포함되는 경우.

SendMessage content에 다음을 추가한다:
- `cli_type={cli_type}` 파라미터
- **`cli_type`이 `codex` 또는 `gemini`인 경우, 병렬성 극대화 지시를 포함한다**: `"CLI 워커({cli_type})를 반드시 사용하여 독립 항목들을 최대한 병렬로 실행하라. Claude fallback으로 전환하지 말 것."`
- `cli_type=claude`이고 model이 기본(sonnet)과 다른 경우, 팀원 스폰 시 해당 model을 지정한다.

#### TEST phase 특수 사항

Per-phase CLI 라우팅 규칙에 따라 cli_type을 결정한다:
- `backend` + `codex_available=true` → `cli_type=codex` (backend 테스트)
- `frontend` + `gemini_available=true` → `cli_type=gemini` (프론트엔드 테스트)
- 기타 → `cli_type=claude`

SendMessage content에 다음을 추가한다:
- `cli_type={cli_type}` 파라미터
- **`cli_type`이 `codex` 또는 `gemini`인 경우**: `"CLI 워커({cli_type})를 반드시 사용하여 테스트를 병렬 실행하라."`

#### VERIFY phase 특수 사항

복잡도에 따라 qa model을 결정한다:
- 복잡한 검증 → qa model=opus, 단순 검증 → qa model=sonnet
- **codex 크로스 검증은 vqa 내부에서 처리한다** (Agent 5). vauto에서 별도 codex CLI 워커를 추가 스폰하지 않는다. `codex_available` 값은 vwork state를 통해 vqa에 전달되며, vqa가 Agent 5 실행 여부를 자체 판단한다.

결과 수신 후 `{WORKLOG_DIR}/report.md`를 읽고 `<!-- QA:VERDICT:START -->` 블록에서 `route:` 필드를 추출한다.

verdict 계약(엄격):
- `route`는 정확히 1개여야 한다.
- 허용 값: `all_pass`, `code_issues`, `test_gaps`, `code_issues_and_test_gaps`
- 누락/다중/미지 값이면: **phase 전이 금지** → 워크로그 에러 기록 → 사용자에게 질문 후 재검증

verdict route에 따른 매핑:
- **all_pass**: `phase: 'DONE'`
- **code_issues 또는 code_issues_and_test_gaps**: `phase: 'IMPL'` (code_issues_and_test_gaps인 경우 IMPL 완료 후 VERIFY에서 test_gaps만 남으면 TEST로 진행)
- **test_gaps**: `phase: 'TEST'`

참고: 브라우저 E2E 테스트가 필요한 경우 `qa`가 내부적으로 `/vbrowser`를 실행한다.

#### DONE phase

- `/worklog-finish {WORKLOG_DIR}` 호출
- `spawned_agents` 전원 정리 (`cli_workers` 맵 참조하여 유형별 분기):
  - `cli_workers[{팀원명}]`이 존재하면 → `mcp__plugin_oh-my-claudecode_team__omc_run_team_cleanup({"job_id": "{cli_workers[{팀원명}].job_id}"})`
  - 그 외 → `shutdown_request` 전송, 응답 수신
  - 정리 완료 시 `spawned_agents`에서 제거, `cli_workers`에서 해당 키 제거
  - 전원 정리 완료 후 `state_write(mode="vwork", data={ "spawned_agents": [], "cli_workers": {} })`
  - TeamDelete 호출
- `state_write(mode="vwork", data={ "active": false })` (상태 보존 규칙의 예외)
- ralph loop 활성이면 `/oh-my-claudecode:cancel`
- Notepad 라이프사이클에 따라 priority notepad 클리어
- 완료 요약 출력

### 5. Phase 전이 프로토콜

모든 phase 전이는 `_shared/update-worklog.md`를 따른다:
- `phase_update`: `{NEW_PHASE}`
- `dashboard_updates`: 현재 phase를 반영하는 다음 액션
- `timeline_entry`: "Phase 전이: {OLD} → {NEW}"
- Notepad 라이프사이클에 따라 priority notepad 갱신.

**팀원 Lifecycle 관리**: `_shared/vwork-team-lifecycle.md`의 Eager Cleanup/JIT 스폰 정책에 따라 Cleanup → Spawn → state_write 순서로 실행.

전이 트랜잭션 순서(고정):
1. worklog 업데이트 (`phase_update`, timeline, dashboard)
2. team lifecycle 처리 (cleanup/spawn)
3. notepad 갱신
4. `state_write(mode="vwork")`로 병합 반영

### 6. 피드백 루프

```
VERIFY → IMPL    (비테스트 이슈: 스펙 이탈, 아키텍처 문제, 소스 코드 수정 필요)
VERIFY → TEST    (테스트 갭: 커버리지 부족, 약한 assertion)
VERIFY ⟳ VERIFY  (trivial test fix: 테스트 파일만 수정, 변경 < 20줄 → qa가 VERIFY 내에서 수정+재검증)
TEST   → VERIFY  (테스트 작성 완료, 재검증 필요)
IMPL   → VERIFY  (수정 적용 완료, 재검증 필요)
```

Trivial test fix 경로:
- VERIFY verdict가 `code_issues` 또는 `code_issues_and_test_gaps`이고 수정 대상이 **테스트 파일만** + **변경 < 20줄**이면: qa에게 수정 + 재검증을 위임 (IMPL 전이 없이 VERIFY 내에서 처리). 테스트 파일: `*.test.{ts,tsx,js,jsx}`, `*.spec.{ts,tsx,js,jsx}`, `__tests__/` 디렉토리. 헬퍼/fixture/mock/config 파일은 IMPL 전이.
- 이 경우에도 `feedback_iterations` 카운터 1 증가.

피드백 전이 시 Decisions 기록 형식: `[CURRENT] Feedback #{N}: {route} — {이유 요약}`

루프당 최대 피드백 반복: 5회. 이후:
- 판단 → Decisions에 기록. 수용 가능하면 진행, 치명적이면 보고.

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
- **phase를 건너뛰지 않는다.** 전진 전용. 단, 신규 기능은 PRD부터 시작하므로 ANALYZE를 건너뛰는 것이 아니라 시작점이 다른 것이다.
- **ralph loop을 활성화한다.** 컨텍스트 윈도우 한계를 넘어 지속성을 보장.
- **피드백 루프는 상한이 있다.** 루프당 최대 5회 반복. 각 반복을 Decisions에 기록한다.
- **오케스트레이터는 실행하지 않는다.** 모든 작업은 반드시 팀원에게 `SendMessage`로 위임한다. `Read`/`Edit`/`Write`/`Bash`로 직접 코드를 읽거나 수정하는 것은 **금지**. 예외: 워크로그 읽기, state/notepad 관리, Step 0 SKILL.md 읽기.
- **오케스트레이터 직접 실행 금지 예외에 `report.md` 읽기를 포함한다.** VERIFY verdict route 파싱을 위한 `{WORKLOG_DIR}/report.md` 읽기는 허용한다.
- **팀원은 반드시 스킬을 명시적으로 사용한다.** `/vanalyze`, `/vplan`, `/vimpl`, `/vqa`, `/vtest` 호출 필수. `/vbrowser`는 `qa`나 `tester`가 내부 서브에이전트로 처리.
- **위임 정책을 준수한다** — `_shared/delegation-policy.md` 참조
- **사용자 자유 요청도 직접 처리 금지.** Step 4-S 규칙에 따라 팀원에게 위임.
- **팀 사용 강제.** `TeamCreate` → `SendMessage` 경로만 허용. `team_name` 없는 독립 `Task` 호출 금지. 예외: 팀 생성 전 Step 1~3.
- **워크플로우 순서 강제.** 모든 요청을 현재 phase 상태 머신에 맞게 해석. phase 건너뛰기 불가.
- **사용자 명시 요청 없이는 페이즈 생략/워크플로우 변경 금지.** 자동 전이 중에도 임의로 phase를 건너뛰거나 순서를 재배치하거나 대체 플로우로 전환하지 않는다.

이제 실행하라.
