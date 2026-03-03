# CLI 런타임 확인

스킬이 외부 CLI 워커(codex/gemini)를 사용하기 전에 반드시 수행하는 표준 확인 절차.
`_shared/agent-routing.md`의 "스킬별 CLI 라우팅 매핑" 테이블과 함께 사용한다.

## 섹션 1: CLI 설치 확인 절차

**실행 주체:** 오케스트레이터 직접 (에이전트 위임 아님)

**세션 내 1회 캐싱:** 이미 확인한 결과가 있으면 재실행하지 않는다.

```bash
# codex 확인
which codex 2>/dev/null && echo "CODEX_AVAILABLE=true" || echo "CODEX_AVAILABLE=false"

# gemini 확인
which gemini 2>/dev/null && echo "GEMINI_AVAILABLE=true" || echo "GEMINI_AVAILABLE=false"
```

**결과 변수:**
- `CODEX_AVAILABLE` = `true` / `false`
- `GEMINI_AVAILABLE` = `true` / `false`

**엣지 케이스:**
- CLI 바이너리는 있지만 실행 권한 없음 (`which` 성공, 실행 실패) → `false`로 처리 후 fallback
- 세션 중간에 CLI 설치/삭제 → 세션 시작 시 캐시한 값을 계속 사용 (재확인 안 함)

## 섹션 2: project_type × task_type → CLI 매핑 테이블

`project_type`은 `rules/project-params.md` 또는 자동 감지 값을 사용한다.

| project_type | task_type | 선택 CLI | 조건 |
|---|---|---|---|
| `backend` | 구현, 테스트 분석, 코드 리뷰 | codex | `CODEX_AVAILABLE=true` |
| `frontend` | 구현, UI/UX, 테스트 | gemini | `GEMINI_AVAILABLE=true` |
| `fullstack` | 구현 | 파일 경로 기반 분류 (아래 참조) | CLI 가용 시 |
| `fullstack` | 테스트 분석, 코드 리뷰 | codex | `CODEX_AVAILABLE=true` |
| `cli` | 모든 task_type | claude Task() | CLI 미사용 |
| `library` | 모든 task_type | claude Task() | CLI 미사용 |

**fullstack 파일 경로 분류 규칙:**

경로에 포함된 세그먼트로 분류한다:
- `components/`, `pages/`, `styles/`, `ui/`, `views/`, `layouts/` → **gemini**
- `api/`, `services/`, `db/`, `models/`, `routes/`, `middleware/`, `server/` → **codex**
- 양쪽 모두 포함(혼합) 또는 분류 불가 → **claude fallback**

## 섹션 3: 타임아웃 정책

- **기본 타임아웃:** 5분 (프로젝트별 `rules/project-params.md`의 `cli_timeout_minutes`로 조정 가능)
- **타임아웃 발생 시:** 부분 결과 폐기 → claude Task() fallback으로 전환 (재시도 없음)
- **타임아웃 감지:** `omc_run_team_wait` 반환값에서 `status=timeout` 또는 응답 없음으로 판단

## 섹션 4: Fallback 절차

**조건:**
1. CLI 미설치 (`CODEX_AVAILABLE=false` / `GEMINI_AVAILABLE=false`)
2. `project_type`이 cli/library
3. CLI 타임아웃 (5분 초과)
4. CLI 응답이 요구 형식에 맞지 않고 재실행 불가
5. fullstack 혼합 경로 (파일 경로 분류 불가)

**Fallback 절차:**
1. 로그 메시지 패턴 (워크로그 타임라인에 기록):
   ```
   [CLI fallback] 이유: {reason} → claude Task({역할}, {model})으로 전환
   ```
2. 기존 `Task(subagent_type="oh-my-claudecode:{역할}", model="{model}", ...)` 호출로 대체
3. **Silent fallback**: 사용자에게 별도 알림 없이 투명하게 전환 (워크로그 기록만 수행)

## 섹션 5: CLI 워커 task description 템플릿

CLI 워커에 전달하는 task description에는 반드시 아래 섹션을 포함한다.

### TDD 구조화 출력 형식 (vimpl용)

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

### Testing Philosophy 주입 텍스트 (vtest/vimpl용)

```
## Testing Rules (MUST follow)
1. Test ONLY externally observable behavior (function input/output, UI state, user-visible results)
2. Do NOT test implementation details (internal refs, private variables, internal call counts)
3. Use mocks/stubs ONLY for external dependencies (APIs, timers, browser APIs) — never mock internal functions of the module under test
```

### vplan 합의 검토 출력 형식 (codex code-reviewer용)

```
## Required Output Format

### Findings
| # | Severity | Finding | Suggestion |
|---|----------|---------|------------|

### Verdict
APPROVE or REVISE

(REVISE인 경우 CRITICAL/HIGH severity 항목만 근거로 사용)
```

**파싱 실패 처리:** CLI 응답이 위 형식에 맞지 않으면 → 해당 호출에 한해 claude Task() fallback으로 재실행 (라운드 카운트 소진 않음).

## 섹션 6: omc-teams MCP 도구 호출 패턴

```
# 1. ToolSearch로 deferred tool 로드
ToolSearch(query="+omc_run_team_start")

# 2. CLI 워커 시작
mcp__plugin_oh-my-claudecode_team__omc_run_team_start({
  "teamName": "{context-slug}",
  "agentTypes": ["codex"],  // 또는 ["gemini"]
  "tasks": [{"subject": "...", "description": "{prompt — TDD/Testing Philosophy 포함}"}],
  "cwd": "{cwd}"
})
# → returns { "jobId": "..." }

# 3. 완료 대기 (타임아웃: cli_timeout_minutes, 기본 5분)
mcp__plugin_oh-my-claudecode_team__omc_run_team_wait({
  "job_id": "{jobId}"
})
# → returns result (status: completed/failed/timeout)

# 4. 정리 (phase 전이 시)
mcp__plugin_oh-my-claudecode_team__omc_run_team_cleanup({
  "teamName": "{context-slug}"
})

# 5. 상태 확인 (compaction 복구 시)
mcp__plugin_oh-my-claudecode_team__omc_run_team_status({
  "teamName": "{context-slug}"
})
# → returns: running / completed / failed / not_found
```

**spawned_agents 기록:** CLI 워커 스폰 시 `spawned_agents`에 `{name}:cli:{codex|gemini}` 형식으로 기록한다.
예: `["implementer:cli:codex", "tester:cli:gemini"]`
