# 에이전트 라우팅

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

## 외부 CLI 워커 (omc-teams 호출)

Codex/Gemini CLI가 설치된 환경에서 선호하는 런타임. CLI가 없는 경우 Claude fallback을 사용한다.

| 역할 | CLI | 선호 대상 작업 | Claude fallback |
|------|-----|---------------|----------------|
| codex | codex | 상세 디버깅, 정밀 검증, 테스트 분석 | debugger / verifier / test-engineer (opus) |
| gemini | gemini | 프론트엔드 코드, UI/UX 설계 | executor / designer (opus) |

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

### omc-teams 호출 예시

```python
mcp__team__omc_run_team_start({
  "teamName": "{context-slug}",
  "agentTypes": ["codex"],  # 또는 "gemini"
  "tasks": [{"subject": "...", "description": "{prompt}"}],
  "cwd": "{cwd}"
})
# → mcp__team__omc_run_team_wait({"job_id": "{jobId}"})
```

## OMC 상태/스킬 매핑

| 참조 | 실제 호출 | 용도 |
|------|----------|------|
| `ralph 루프 종료` | `/oh-my-claudecode:cancel` | ralph/ultrawork 모드 종료 |
| `ralph 상태 기록` | `state_write(mode="ralph")` | ralph 루프 상태 파일 생성 |
| `ultrawork 상태 기록` | `state_write(mode="ultrawork")` | ultrawork 상태 파일 생성 |

상태 파일 경로:
- `.omc/state/ralph-state.json`
- `.omc/state/ultrawork-state.json`
