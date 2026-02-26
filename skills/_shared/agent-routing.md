# 에이전트 라우팅

스킬에서 에이전트를 호출할 때, 역할명만 명시하고 이 테이블에서 실제 `subagent_type`과 기본 `model`을 조회한다.

## 라우팅 테이블

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
| code-simplifier | code-simplifier:code-simplifier | sonnet | 코드 단순화, 정리 |

## 스킬에서의 사용법

스킬 정의에서 에이전트를 호출할 때는 **역할명만** 사용한다:

```
역할 `architect`로 위임:
  model: opus (기본값과 다를 경우에만 명시)
  prompt: "..."
```

실행 시 이 테이블을 참조하여 Task() 호출로 변환:

```python
Task(subagent_type="{라우팅된 subagent_type}", model="{model}", prompt="...")
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
