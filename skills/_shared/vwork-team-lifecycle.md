# vwork 팀 Lifecycle 관리
<!-- 경로 규칙: `_shared/X` = 같은 디렉토리의 X | `_templates/X` = 형제 `_templates/` 디렉토리의 X -->

vwork의 에이전트 팀 생성, JIT 스폰, Eager Cleanup, Phase 전이 시 팀원 관리 절차.

## 정규 매핑 참조

SKILL.md의 "정규 Phase-팀원 매핑" 테이블이 단일 진실 기준이다. `_shared/agent-routing.md`에 전체 에이전트 라우팅 테이블이 정의되어 있다.

참고: 브라우저 E2E 테스트(`/vbrowser`)는 팀원이 아닌, `qa`나 `tester`가 필요 시 내부 서브에이전트로 스폰하여 처리한다.

## Just-in-Time 스폰 정책

현재 phase에 필요한 팀원만 스폰한다. 이미 `spawned_agents`에 있고 팀 config에 활성 상태이면 재스폰하지 않는다.

| Phase | 스폰 대상 | 비고 |
|-------|----------|------|
| ANALYZE | `analyzer` | task_type=new-feature면 스폰하지 않음 |
| PRD | `planner` | |
| PLAN | `planner` | PRD에서 이미 스폰했으면 재사용 |
| IMPL | `implementer` | CLI 워커 라우팅 적용 가능 (아래 참조) |
| VERIFY | `qa` | |
| TEST | `tester` | CLI 워커 라우팅 적용 가능 (아래 참조) |

**IMPL/TEST phase CLI 워커 스폰:**

`_shared/cli-runtime-check.md`와 `_shared/agent-routing.md`의 "스킬별 CLI 라우팅 매핑"을 참조하여 CLI 워커가 선택된 경우:
- Claude Task() 대신 `omc-teams MCP 도구`로 CLI 워커 스폰 (아래 CLI 워커 스폰 템플릿 참조)
- `spawned_agents`에 순수 이름만 기록 (예: `"implementer"`, `"tester"`)
- 별도 `cli_workers` 맵에 메타데이터를 기록: `{"implementer": {"cli_type": "codex", "team_name": "..."}, "tester": {"cli_type": "gemini", "team_name": "..."}}`
- `state_write(mode="vwork")` 시 `spawned_agents`와 `cli_workers` 모두 갱신

**base name 매칭 규칙:**
- `spawned_agents`에서 역할을 식별할 때는 항목 자체가 역할명이다 (접미사 없음).
- `cli_workers` 맵에서 해당 역할명이 키로 존재하면 CLI 워커 팀원으로 판단한다.
- 예: `spawned_agents = ["implementer"]`, `cli_workers = {"implementer": {"cli_type": "codex", "team_name": "wl-impl"}}` → `implementer`는 CLI 워커

피드백 루프 대비 스폰:
- VERIFY phase에서 `implementer`가 팀에 없으면 추가 스폰 (VERIFY→IMPL 대비).
- TEST phase에서 `implementer`가 팀에 없으면 추가 스폰 (TEST→VERIFY→IMPL 대비).

## Eager Cleanup 정책

phase 전이 시 이후 phase에서 필요 없는 팀원을 `shutdown_request`로 정리한다.

| Phase 전이 | 정리 대상 | 근거 |
|-----------|----------|------|
| ANALYZE → PRD | `analyzer` | ANALYZE 이후 불필요 |
| PLAN → IMPL | `planner` | PLAN 이후 불필요 |
| VERIFY → DONE | `spawned_agents` 전원 | 모든 작업 완료 |

정리하지 **않는** 경우:
- PRD → PLAN: `planner` 유지 (PLAN에서도 필요)
- IMPL → VERIFY: `implementer` 유지 (피드백 루프 대비)
- VERIFY → IMPL: `qa` 유지 (재검증 필요)
- VERIFY → TEST: `qa` 유지, `tester` 스폰
- TEST → VERIFY: `tester` 유지, `qa` 이미 활성

정리 절차 — 팀원 유형별 분기:

`cli_workers[{팀원명}]`이 존재하는지로 유형을 식별한다.

**Claude 에이전트 팀원** (`cli_workers`에 없는 경우):
```
SendMessage(type="shutdown_request", recipient="{팀원}", content="Phase 완료 — 정리")
```
응답 수신 후 `spawned_agents`에서 제거.

**CLI 워커 팀원** (`cli_workers[{팀원명}]`이 존재하는 경우):
```
mcp__team__omc_run_team_cleanup(job_id="{cli_workers[{팀원명}].job_id}")
```
호출 성공 후 `spawned_agents`에서 제거, `cli_workers`에서 해당 키 제거.

참고: cleanup은 내부적으로 비동기 정리를 수행할 수 있으나, 호출이 성공하면 리소스 해제가 진행 중인 상태로 간주한다.

정리 완료 후 상태 보존 규칙에 따라 `state_write(mode="vwork")`로 `spawned_agents`와 `cli_workers` 모두 갱신.

## 스폰 템플릿

### Claude 에이전트 스폰 (기본)

SKILL.md 정규 매핑 테이블의 subagent_type과 model을 사용하여 스폰한다:
```
Task(subagent_type="{subagent_type}", model="{model}",
     team_name="vwork-{WORKLOG_SLUG}", name="{담당 팀원}",
     prompt="당신은 vwork 팀의 {담당 팀원}입니다. 팀 리드(vwork)의 지시를 기다리세요.")
```

### CLI 워커 스폰 (IMPL/TEST phase, CLI 라우팅 적용 시)

`_shared/cli-runtime-check.md` 섹션 6의 호출 패턴을 사용한다:
```
mcp__team__omc_run_team_start(count=1, provider="{codex|gemini}", task="{작업 제목}: {task description — TDD/Testing Philosophy 포함}")
# → {"teamName": "...", ...}

# 완료 대기
mcp__team__omc_run_team_status(team_name="{teamName}")
```

스폰 후:
- `spawned_agents`에 순수 이름 추가 (예: `"implementer"`)
- `cli_workers` 맵에 메타데이터 기록 (예: `{"implementer": {"cli_type": "codex", "team_name": "{teamName}"}}`)
- `state_write(mode="vwork")`로 양쪽 모두 갱신

## Phase 전이 시 Lifecycle 실행

phase 전이가 확정된 후 아래를 순차 실행한다:

1. **Cleanup**: Eager Cleanup 정책에 따라 불필요한 팀원에게 `shutdown_request` 전송. 응답 수신 후 `spawned_agents`에서 제거.
2. **Spawn**: JIT 스폰 정책에 따라 다음 phase 필요 팀원을 스폰. `spawned_agents`에 append.
3. **State 갱신**: 상태 보존 규칙에 따라 `state_write(mode="vwork")`로 `spawned_agents`와 `current_phase`를 갱신.

전이별 실행 요약:

| 전이 | Cleanup | Spawn |
|------|---------|-------|
| ANALYZE → PRD | `analyzer` 정리 | `planner` 스폰 |
| PRD → PLAN | (없음) | (planner 재사용) |
| PLAN → IMPL | `planner` 정리 | `implementer` 스폰 |
| IMPL → VERIFY | (implementer 유지) | `qa` 스폰 |
| VERIFY → IMPL | (없음) | (implementer 이미 활성) |
| VERIFY → TEST | (없음) | `tester` 스폰 |
| TEST → VERIFY | (없음) | (qa, tester 이미 활성) |
| VERIFY → DONE | (DONE에서 전원 정리) | (없음) |
