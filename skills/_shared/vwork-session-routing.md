# vwork 세션 라우팅 (사용자 자유 요청 처리)

ralph loop 중 사용자가 phase 실행이 아닌 자유 요청을 보낸 경우의 라우팅 절차. **오케스트레이터는 라우터 역할만 수행하며 어떤 요청도 직접 처리하지 않는다.**

## 1. 요청 해석 및 워크플로우 매핑

사용자의 모든 요청은 현재 phase 상태 머신의 맥락에서 해석한다. 요청을 직접 처리하지 않고, 항상 팀원에게 위임한다. 먼저 요청이 어떤 phase에 해당하는 작업인지 판별한다:

| 요청 유형 | 해당 phase |
|----------|-----------|
| 코드 분석, 파일 탐색, 버그 조사, 코드베이스 질문 | ANALYZE |
| 요구사항 정의, PRD, 사용자 스토리 | PRD |
| 아키텍처 설계, 구현 플랜 | PLAN |
| 코드 구현, 수정, 리팩토링 | IMPL |
| 테스트 작성, 커버리지 보강 | TEST |
| 검증, QA, 코드 리뷰 | VERIFY |
| "계속 진행", "다음 단계" | (현재 phase 실행 — Step 4로 진행) |

## 2. 팀원 라우팅 (agent-first, phase fallback)

요청 유형에 따라 **해당 역할의 팀원**에게 우선 위임한다. 해당 팀원이 스폰되지 않은 경우에만 현재 phase 담당 팀원에게 fallback한다:

| 요청 유형 | 우선 위임 대상 | 미스폰 시 fallback |
|----------|--------------|-------------------|
| 코드 분석, 파일 탐색, 버그 조사, 코드베이스 질문 | `analyzer` | 현재 phase 담당 팀원 |
| 요구사항 정의, PRD, 사용자 스토리 | `planner` | 현재 phase 담당 팀원 |
| 아키텍처 설계, 구현 플랜 | `planner` | 현재 phase 담당 팀원 |
| 코드 구현, 수정, 리팩토링 | `implementer` | 현재 phase 담당 팀원 |
| 테스트 작성, 커버리지 보강 | `tester` | 현재 phase 담당 팀원 |
| 검증, QA, 코드 리뷰 | `qa` | 현재 phase 담당 팀원 |
| 그 외 모든 요청 | 현재 phase 담당 팀원 | — |

위임 대상은 SKILL.md의 정규 Phase-팀원 매핑 테이블을 참조한다. 우선 위임 대상이 스폰되지 않은 경우 JIT 스폰 정책에 따라 먼저 스폰하거나, 스폰 비용이 과도하면 현재 phase 담당 팀원에게 fallback한다.

## 3. 워크플로우 순서 강제

요청이 해당하는 phase와 현재 phase를 비교하여 추가 제약을 적용한다:

- **요청이 미래 phase에 해당하고, 해당 팀원이 스폰되지 않은 경우**: 직접 위임하지 **않는다**. 대신:
  1. 사용자에게 현재 phase를 먼저 완료해야 함을 안내
  2. 현재 phase 담당 팀원에게 위임하여 워크로그 Decisions에 deferred 요청으로 기록:
     ```
     SendMessage(type="message", recipient="{현재 phase 담당 팀원}",
       content="다음 요청은 미래 phase({future_phase})에 해당합니다.

       사용자 요청: {request}

       워크로그 Decisions에 아래 형식으로 기록하세요:
       [DEFERRED] {future_phase} 요청: {요약}

       기록 후 현재 phase 작업을 계속 진행하세요.",
       summary="미래 phase 요청 deferred 기록")
     ```
  3. 현재 phase 실행을 계속 진행
  - 예: ANALYZE phase에서 "이거 구현해줘" → "구현 요청을 확인했습니다. 현재 ANALYZE phase입니다. 분석을 먼저 완료한 뒤 PRD → PLAN → IMPL 순서로 진행합니다."
  - phase 건너뛰기 요청이 있어도 현재 phase 순서를 유지한다. 요청 내용은 워크로그에 기록해 해당 phase 도달 시 처리한다.

## 4. SendMessage로 위임

```
SendMessage(type="message", recipient="{현재 phase 담당 팀원}",
  content="사용자 요청: {사용자 메시지}

  현재 phase: {current_phase}
  워크로그: {WORKLOG_DIR}

  요청을 현재 phase 맥락에서 처리하고 결과를 보고하세요.",
  summary="세션 요청 위임")
```

## 5. 팀원 응답 수신 후 처리

- 응답을 사용자에게 전달한다.
- 팀원이 **phase 완료**를 보고하면 Step 5 Phase 전이 프로토콜에 따라 다음 phase로 전이한다.
- phase 전이 후에도 세션은 유지된다. ralph loop이 다음 반복을 계속한다.
