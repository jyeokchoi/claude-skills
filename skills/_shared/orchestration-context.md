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
  "worklog_dir": "{WORKLOG_DIR}"
})
```

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
```

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
| vplan | Pre-flight 직후 | Auto-routing 질문, Stage 1D 유저 리뷰, consensus 후 유저 리뷰; current_phase=PRD이면 Stage 1만 실행, current_phase=PLAN이면 Stages 2-4만 실행 |
| vimpl | Mode selection 이전 | 모드 자동 선택, ralph 활성화 건너뛰기, completion promise/cancel 건너뛰기 |
| vqa | Phase 4 이전 | 유저 리뷰 옵션을 자동 분류 결과로 대체 |
| vtest | Phase 2 이전 | 스코프 자동 선택, 테스트케이스 리뷰 건너뛰기, 브라우저 E2E 자동 실행 |
| vbrowser | Phase 2 이전 | 전체/선택 확인 생략, 전체 실행 |
