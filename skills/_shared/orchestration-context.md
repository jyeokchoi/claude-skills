# 오케스트레이션 컨텍스트 (공통 절차)

vwork가 서브 스킬을 호출할 때, 서브 스킬이 오케스트레이션 상태를 인식할 수 있도록 컨텍스트를 제공한다.

## 프로토콜

### vwork (오케스트레이터) — 쓰기

vwork는 Phase execution(Step 4) 진입 전에 오케스트레이션 상태를 기록한다:

```
state_write(mode="vwork", data={
  "active": true,
  "mode": "auto" | "step",
  "current_phase": "ANALYZE" | "PRD" | "PLAN" | "IMPL" | "VERIFY" | "TEST" | "DONE",
  "worklog_dir": "{WORKLOG_DIR}",
  "worklog_slug": "{WORKLOG_SLUG}",
  "project_type": "{project_type}",
  "task_type": "new-feature" | "modification",
  "feedback_iterations": {number},
  "spawned_agents": ["{agent_name}", ...],
  "cli_workers": {
    "{role}": {
      "cli_type": "codex" | "gemini",
      "team_name": "{cli team name}",
      "job_id": "{omc job id}"
    }
  },
  "team_name": "{team_name}",
  "codex_available": true | false,
  "gemini_available": true | false
})
```

> **서브 스킬 쓰기 금지**: 서브 스킬(vanalyze, vplan, vimpl, vqa, vtest, vbrowser, worklog-finish)은 `state_write(mode="vwork")`를 호출해서는 안 된다. vwork state는 vwork 오케스트레이터만 갱신한다. 서브 스킬이 state를 write할 경우 재수화에 필요한 필드(`spawned_agents`, `worklog_slug` 등)가 유실될 수 있다.

vwork 종료 시 (DONE phase 완료 또는 취소):

```
state_write(mode="vwork", data={ "active": false })
```

### 서브 스킬 — 읽기

모든 서브 스킬(vanalyze, vplan, vimpl, vqa, vtest, vbrowser, worklog-finish)은 시작 시 오케스트레이션 컨텍스트를 확인한다:

```
vwork_state = state_read(mode="vwork")
ORCHESTRATED = vwork_state가 존재하고 vwork_state.active == true
ORCHESTRATION_MODE = ORCHESTRATED ? vwork_state.mode : null
CODEX_AVAILABLE = ORCHESTRATED ? (vwork_state.codex_available ?? false) : false
GEMINI_AVAILABLE = ORCHESTRATED ? (vwork_state.gemini_available ?? false) : false
PROJECT_TYPE = ORCHESTRATED ? (vwork_state.project_type ?? null) : null
```

> **`CLI_TYPE` 수신 경로**: vwork는 per-phase CLI 라우팅 테이블에 따라 phase별 `cli_type`을 결정한다 (ANALYZE/PLAN/IMPL/TEST/VERIFY). `ORCHESTRATED=true`인 경우 `CLI_TYPE`은 vwork가 서브 스킬을 호출하는 **SendMessage content**에 포함되어 전달된다 (state에 기록되지 않음). 서브 스킬은 수신한 메시지에서 `cli_type` 값을 추출하여 사용한다.

**CLI 가용성 결정 (서브 스킬 공통):**

위 프로토콜에서 설정된 변수를 기반으로 CLI 가용성을 결정한다. 서브 스킬은 개별적으로 CLI 확인을 반복하지 않는다:

- `ORCHESTRATED=true`인 경우: 위에서 추출한 `CODEX_AVAILABLE`, `GEMINI_AVAILABLE`, `PROJECT_TYPE`과 SendMessage에서 수신한 `CLI_TYPE`을 그대로 사용한다.
- `ORCHESTRATED=false`인 경우: `_shared/cli-runtime-check.md` 섹션 1을 참조하여 `CODEX_AVAILABLE`, `GEMINI_AVAILABLE`을 직접 확인한다. `CLI_TYPE`은 `_shared/cli-runtime-check.md` 섹션 2와 `_shared/resolve-project-type.md`를 참조하여 결정한다.

## 서브 스킬 동작 분기

| 상황 | ORCHESTRATED + auto | ORCHESTRATED + step | standalone |
|------|---------------------|---------------------|------------|
| AskUserQuestion (비핵심) | smart default 적용, 질문 생략 | 정상 질문 | 정상 질문 |
| AskUserQuestion (핵심 결정) | 정상 질문 | 정상 질문 | 정상 질문 |
| `phase_update` | 사용 금지 (vwork가 관리) | 사용 금지 (vwork가 관리) | 허용 |
| 다른 서브 스킬 체이닝 | 금지 (vwork에 제어권 반환) | 금지 (vwork에 제어권 반환) | 허용 |
| ralph loop 활성화 | 건너뛰기 (vwork가 이미 관리) | 건너뛰기 | 정상 활성화 |
| completion promise 출력 | 건너뛰기 | 건너뛰기 | 정상 출력 |
| ralph cancel | 건너뛰기 | 건너뛰기 | 정상 실행 |
| CLI 라우팅 결정 | vwork SendMessage에서 cli_type 수신 (자체 감지 건너뜀) | vwork SendMessage에서 cli_type 수신 (자체 감지 건너뜀) | 자체 감지 (cli-runtime-check.md 참조) |

## 핵심 vs 비핵심 결정 기준

**핵심 결정** (AUTO 모드에서도 반드시 질문):
- 아키텍처 방향 선택 (2개 이상의 유효한 접근법이 존재)
- 요구사항 모호성 해소 (PRD discovery)
- 롤백 여부 (데이터 손실 가능)
- 스코프 변경 (원래 요구사항 대비 추가/제거)

**비핵심 결정** (AUTO 모드에서 smart default 적용):

| 질문 | Smart Default |
|------|---------------|
| 기존 아티팩트 덮어쓰기 여부 | 덮어쓰기 |
| 분석 스코프 확인 (vanalyze) | 자동 탐지 스코프 수용 |
| 버그 재현 진행 확인 (vanalyze) | 모든 재현 테스트 FAIL이면 진행 |
| PRD/Plan 이미 존재 시 (vplan) | 존재하는 단계는 건너뛰기 |
| 구현 모드 선택 (vimpl) | Auto 모드 |
| 테스트 범위 선택 (vtest) | 전체 갭 해결 |
| 테스트케이스 리뷰 (vtest) | 제안대로 진행 |
| 브라우저 E2E 실행 여부 (vtest) | WEB_APP=true + E2E 갭 존재 시 자동 실행 |
| vbrowser 전체/선택 실행 (vbrowser) | 전체 실행 |
| QA 결과 처리 (vqa) | 자동 분류 결과에 따라 다음 단계 자동 진행 |
| Phase 완료 후 다음 진행 (vwork step) | — (step 모드에서만 해당) |

## 각 스킬의 적용 위치

| 스킬 | 오케스트레이션 체크 위치 | 영향받는 동작 |
|------|------------------------|--------------|
| vanalyze | Pre-flight 직후 | Phase 0 유저 확인, Phase 1 스코프 확인 |
| vplan | Pre-flight 직후 | Auto-routing 질문, Stage 1D 유저 리뷰, consensus 후 유저 리뷰; current_phase=PRD이면 Stage 1만 실행, current_phase=PLAN이면 Stages 2-4만 실행, CLI 자체 확인 건너뜀 (codex_available 수신) |
| vimpl | Mode selection 이전 | 모드 자동 선택, ralph 활성화 건너뛰기, completion promise/cancel 건너뛰기, CLI 자체 감지 건너뜀 (cli_type 수신), **cli_type=codex/gemini이면 Claude fallback 금지** (파싱 실패 시 1회 예외) |
| vqa | Phase 4 이전 | 유저 리뷰 옵션을 자동 분류 결과로 대체 |
| vtest | Phase 2 이전 | 스코프 자동 선택, 테스트케이스 리뷰 건너뛰기, 브라우저 E2E 자동 실행, CLI 자체 감지 건너뜀 (cli_type 수신) |
| vbrowser | Phase 2 이전 | 전체/선택 확인 생략, 전체 실행 |
