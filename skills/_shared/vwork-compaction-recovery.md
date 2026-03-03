# vwork Compaction Recovery (상태 재수화)

vwork의 Step 0에서 사용하는 컨텍스트 컴팩션 후 ralph 재진입 감지 및 복구 절차.

## 자동 복구 소스

컴팩션 후 두 가지 자동 복구 소스가 존재한다:
1. `<notepad-context>` — priority notepad. `vwork활성` 텍스트가 보이면 ralph 재진입으로 간주.
2. `<worklog-context>` — PreCompact/SessionStart 훅이 주입한 워크로그 Dashboard, Goal, phase 정보. 이 정보가 보이면 활성 워크로그가 있으므로 작업을 이어야 한다.

두 소스 중 하나라도 보이면 아래 복구 절차를 반드시 따른다.

## 복구 절차

`state_read(mode="vwork")`를 실행한다:

### `active=true`이고 `current_phase`가 설정된 경우 (ralph 재진입)

**변수 복구:**
- `WORKLOG_DIR` = `state.worklog_dir`
- `WORKLOG_SLUG` = `state.worklog_slug`
- `project_type` = `state.project_type`
- `task_type` = `state.task_type`
- `mode` = `state.mode`
- `team_name` = `state.team_name`
- `feedback_iterations` = `state.feedback_iterations`
- `spawned_agents` = `state.spawned_agents`

**행동 규칙 복구 (compaction 후 규칙 유실 방지):**
- `Glob(pattern="**/workflow/vwork/SKILL.md")`로 스킬 파일 경로를 찾는다.
- `Read`로 두 구간을 읽어 행동 규칙을 컨텍스트에 복원한다:
  1. **`## 절대 규칙`** 섹션 — 위임 금지, 워크로그 업데이트 등 핵심 행동 규칙
  2. **`#### {current_phase} phase`** 섹션 — 현재 phase의 구체적 실행 지침
- **복원 후 행동 원칙**: 오케스트레이터는 SendMessage로 팀원에게 작업을 위임하는 것만 수행한다.

**phase 일치 검증 (state와 워크로그 동기화):**
- 워크로그 파일의 `phase` 필드를 읽는다.
- 워크로그 `phase`와 state의 `current_phase`가 다른 경우: **워크로그 값을 진실 기준으로 사용**.
  - 이유: 컴팩션 직전에 워크로그 업데이트는 완료됐지만 state_write가 완료되지 않았을 수 있다.
  - `current_phase`를 워크로그 값으로 갱신: `state_write(mode="vwork")`로 `current_phase` 동기화 (상태 보존 규칙 준수).
- 일치하거나 워크로그 읽기 실패 시: state 값을 그대로 사용.

**팀 생존 여부 확인 (좀비 팀 감지 포함):**

1. `~/.claude/teams/{team_name}/config.json`이 **없으면**: 팀 종료됨 → **Step 3-B (팀 재생성)로 점프**
2. `config.json`이 **존재하면**:
   - config.json의 `members` 배열에서 현재 phase의 필수 팀원 확인 (SKILL.md 정규 매핑 테이블 참조. VERIFY는 `qa` + `implementer` 피드백 루프 대비)
   - 필수 팀원이 없으면: **TeamDelete → Step 3-B로 점프**
   - 필수 팀원이 있으면: `spawned_agents`에서 팀원 유형을 식별하여 분기:

   **팀원 유형 식별:** `spawned_agents` 항목에서 `:cli:` 접미사 여부로 구분한다.
   - `{name}:cli:codex` 또는 `{name}:cli:gemini` 형식 → **CLI 워커 팀원**
   - 그 외 → **Claude 에이전트 팀원**

   **Claude 에이전트 팀원:** 기존 ping 방식으로 생존 확인:
     ```
     SendMessage(type="message", recipient="{필수팀원}", content="health check — 응답하세요", summary="ping")
     ```
   - **15초 이내 응답**: 활성 → 활성 팀원으로 유지
   - **15초 이내 응답 없음**: 좀비 → **TeamDelete → Step 3-B로 점프**

   **CLI 워커 팀원:** `omc_run_team_status`로 상태 확인:
     ```
     ToolSearch(query="+omc_run_team_status")
     mcp__plugin_oh-my-claudecode_team__omc_run_team_status({"teamName": "{team_name}"})
     ```
   - 결과 `running`: CLI 워커 활성 → **Step 4 (Phase 실행)로 직접 점프**
   - 결과 `completed` / `failed` / `not_found`: CLI 워커 비활성 → claude Task() fallback으로 전환 (재스폰 않음), `spawned_agents`에서 해당 항목(`:cli:` 접미사) 제거 후 `state_write`로 갱신

   **전원 확인 완료 후 (모든 팀원이 활성 상태):**
   - **Step 4 (Phase 실행)로 직접 점프**

### `active=false` 또는 state 없는 경우 (신규 실행)

Step 1부터 정상 진행한다.
