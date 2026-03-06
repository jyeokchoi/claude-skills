# 에이전트 라우팅
<!-- 경로 규칙: `_shared/X` = 같은 디렉토리의 X | `_templates/X` = 형제 `_templates/` 디렉토리의 X -->

스킬에서 에이전트를 호출할 때, 역할명만 명시하고 이 테이블에서 런타임, subagent_type, 기본 모델, 용도를 조회한다.

## Claude 에이전트 (Task() 호출)

모든 역할은 기본적으로 Claude Task()로 호출한다.

| 역할 | subagent_type | 기본 model | 용도 |
|------|--------------|-----------|------|
| architect | oh-my-claudecode:architect | opus | 아키텍처 설계, 리뷰, 영향도 평가 |
| code-reviewer | oh-my-claudecode:code-reviewer | opus | 종합 코드 리뷰 |
| quality-reviewer | oh-my-claudecode:quality-reviewer | sonnet | 품질, 유지보수성, 안티패턴 |
| critic | oh-my-claudecode:critic | opus | 계획/설계 비판적 검토 |
| verifier | oh-my-claudecode:verifier | sonnet | 완료 검증, 테스트 적절성 |
| executor | oh-my-claudecode:executor | sonnet | 구현, 리팩토링 |
| deep-executor | oh-my-claudecode:deep-executor | opus | 복잡한 자율 구현 |
| debugger | oh-my-claudecode:debugger | sonnet | 근본원인 분석, 회귀 격리 |
| test-engineer | oh-my-claudecode:test-engineer | sonnet | 테스트 전략, 커버리지 |
| explore | oh-my-claudecode:explore | haiku | 코드베이스 탐색, 심볼/파일 매핑 |
| code-simplifier | oh-my-claudecode:quality-reviewer | sonnet | 코드 단순화, 정리 (quality-reviewer alias) |
| analyst | oh-my-claudecode:analyst | opus | 요구사항 명확화, 수용 기준 |
| planner | oh-my-claudecode:planner | opus | 태스크 시퀀싱, 실행 계획 |
| security-reviewer | oh-my-claudecode:security-reviewer | sonnet | 취약성, 인증/인가 |
| build-fixer | oh-my-claudecode:build-fixer | sonnet | 빌드/툴체인/타입 오류 |
| writer | oh-my-claudecode:writer | haiku | 문서, 마이그레이션 노트 |
| designer | oh-my-claudecode:designer | sonnet | UI/UX 설계 |
| qa-tester | oh-my-claudecode:qa-tester | sonnet | 브라우저 E2E 테스트, 인터랙티브 CLI 검증 |

## 외부 CLI 워커 (omc-teams 호출)

Codex/Gemini CLI가 설치된 환경에서 선호하는 런타임. CLI가 없는 경우 Claude fallback을 사용한다.

| 역할 | CLI | 선호 대상 작업 | Claude fallback |
|------|-----|---------------|----------------|
| codex | codex | 상세 디버깅, 정밀 검증, 테스트 분석 | debugger / verifier / test-engineer (opus) |
| gemini | gemini | 프론트엔드 코드, UI/UX 설계 | designer (opus) |

### 선호 런타임 규칙

- CLI가 설치되어 있고 작업이 선호 대상에 해당하면 외부 CLI 워커를 우선 사용한다.
- CLI가 없거나 작업이 오케스트레이션과 긴밀히 연동되어야 하면 Claude 에이전트를 사용한다.

## 스킬에서의 사용법

스킬 정의에서 에이전트를 호출할 때는 **역할명만** 사용한다:

```
역할 `architect`로 위임:
  prompt: "..."
```

### Claude Task() 호출 예시

```python
Task(subagent_type="oh-my-claudecode:executor", model="sonnet", prompt="...")
Task(subagent_type="oh-my-claudecode:architect", model="opus", prompt="...")
Task(subagent_type="oh-my-claudecode:verifier", model="haiku", prompt="...")
```

### omc-teams MCP 도구 호출 예시

```python
# CLI 워커 시작
mcp__team__omc_run_team_start(count=1, provider="codex", task="{task description}")
# → {"teamName": "...", "pid": ..., "message": "..."}

# 완료 대기
mcp__team__omc_run_team_status(team_name="{teamName}")

# 정리
mcp__team__omc_run_team_cleanup(job_id="{jobId}")
```

## ask-codex / ask-gemini 스킬 (단일 쿼리, 경량)

읽기 전용 분석·검증·교차 확인에는 omc-teams MCP 도구 대신 `ask-codex` / `ask-gemini` 스킬을 사용한다. tmux 워커 lifecycle이 불필요하여 더 빠르고 가볍다.

### 선택 기준

| 작업 유형 | 사용 도구 | 이유 |
|-----------|-----------|------|
| 읽기 전용 분석/검증 (diff 리뷰, 교차 검증, 플랜 검토) | `ask-codex` / `ask-gemini` 스킬 | 코드 편집 없음, 단일 응답 |
| 코드 편집 필요 (구현, 테스트 작성, 리팩토링) | omc-teams MCP 도구 | Write/Edit 도구 사용, worker lifecycle 필요 |
| 복수 태스크를 하나의 세션에서 처리 | omc-teams MCP 도구 | 컨텍스트 공유 필요 |

### 호출 예시

```python
# 단일 쿼리 (읽기 전용)
Skill("oh-my-claudecode:ask-codex", "{분석/검증 프롬프트}")
# → 결과가 .omc/artifacts/ask/ 에 저장됨
# → stdout으로도 결과 반환

Skill("oh-my-claudecode:ask-gemini", "{분석/검증 프롬프트}")
```

### Fallback

스킬 실패 시 (exit code ≠ 0, stdout 비어있음, 파싱 실패):
- 스킬이 내부적으로 fallback을 처리한다 (silent fallback, 워크로그 기록만 수행)
- 라운드 카운트 소진 않음

## 스킬별 CLI 라우팅 매핑

> **SSOT**: 구체적인 실행 절차·호출 패턴·타임아웃·fallback은 `_shared/cli-runtime-check.md`가 단일 기준이다. 이 섹션은 개요만 기술한다.

| project_type | 선택 도구 | 비고 |
|---|---|---|
| `backend` | omc-teams MCP (codex) | `CODEX_AVAILABLE=true` 시 |
| `frontend` | omc-teams MCP (gemini) | `GEMINI_AVAILABLE=true` 시 |
| `cli` / `library` | claude fallback | 항상 |
| CLI 미가용 | claude fallback | silent fallback |

**CLI 워커 상태 관리:** `cli_workers` 맵으로 관리. `spawned_agents`는 순수 이름 목록을 유지한다.
- 형식: `cli_workers: {"implementer": {"cli_type": "codex", "team_name": "..."}, "tester": {"cli_type": "gemini", "team_name": "..."}}`
- `spawned_agents`에 접미사를 붙이지 않는다.

## OMC 상태/스킬 매핑

| 참조 | 실제 호출 | 용도 |
|------|----------|------|
| `ralph 루프 종료` | `/oh-my-claudecode:cancel` | ralph/ultrawork 모드 종료 |
| `ralph 상태 기록` | `state_write(mode="ralph")` | ralph 루프 상태 파일 생성 |
| `ultrawork 상태 기록` | `state_write(mode="ultrawork")` | ultrawork 상태 파일 생성 |

상태 파일 경로:
- `.omc/state/ralph-state.json`
- `.omc/state/ultrawork-state.json`
