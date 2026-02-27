---
name: vplan
description: 'Structured planning pipeline: PRD (requirements/user stories/acceptance criteria) → behavior/interface spec → architecture/technical spec → implementation checklist, with consensus review'
argument-hint: 'Usage: /vplan [worklog-folder-or-worklog.md]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `base_branch` | auto-detect | diff 기준 브랜치 |
| `shared_types_dir` | (없음) | 공유 타입 디렉토리 |
| `jira_pattern` | `[A-Z]+-\d+` | Jira 티켓 패턴 |
| `project_type` | auto-detect | frontend / backend / fullstack / cli / library |

단계별로 진행하며 병렬 서브에이전트로 플랜을 검토하여 합의에 이르고, 워크로그 폴더에 PRD와 플랜 파일을 출력하는 구조화된 플래닝 파이프라인을 실행한다.

## 대상 결정

- `_shared/resolve-worklog-target.md`가 존재하면 로드하여 해당 로직을 따른다.
- 폴백 (공유 리졸버를 사용할 수 없는 경우):
  - $ARGUMENTS가 제공된 경우:
    - 폴더인 경우: "{arg}/worklog.md"를 대상으로 설정
    - 파일인 경우: 해당 파일을 대상으로 설정하고, dirname에서 폴더 추출
  - 그 외:
    - ".claude/worklogs/.active"를 읽어 활성 워크로그 폴더를 가져옴
- 대상이 없으면 중단하고 오류를 출력한다.
- `WORKLOG_DIR` = 워크로그 폴더 경로로 설정
- `PRD_FILE` = `{WORKLOG_DIR}/prd.md`로 설정
- `PLAN_FILE` = `{WORKLOG_DIR}/plan.md`로 설정

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`인 경우: 동작 분기 표에 따라 사용자 인터랙션 동작을 조정한다.
- `ORCHESTRATED=true`이고 `current_phase=PRD`인 경우: Stage 1 (PRD)만 실행 후 종료.
- `ORCHESTRATED=true`이고 `current_phase=PLAN`인 경우: Stage 1 건너뛰고 Stages 2-4 실행.

## 사전 준비

1. worklog.md Dashboard를 읽어 작업 목표와 완료 기준 파악.
2. `{WORKLOG_DIR}/analysis.md`가 존재하는지 확인 (`/vanalyze` 출력):
   - 존재하는 경우: 읽어서 추가 컨텍스트로 활용. 출력: "분석 파일을 발견했습니다. 플래닝에 반영합니다."
3. 기준 브랜치 결정: `_shared/resolve-base-branch.md`를 로드하고 해당 로직을 따라 `BASE_REF`를 설정한다.
4. 프로젝트 타입 감지:
   - `rules/project-params.md`에서 `project_type` 확인
   - 설정되지 않은 경우: package.json (frontend/fullstack), pyproject.toml (backend), go.mod (backend), Cargo.toml (backend/cli/library) 등에서 자동 감지
   - 불명확한 경우: 사용자에게 질문

## 자동 라우팅 (PRD vs 플랜)

**`ORCHESTRATED=true`인 경우:** 아티팩트 기반 자동 라우팅을 완전히 건너뛴다. orchestration 상태의 `current_phase`만 사용한다:
- `current_phase=PRD` → Stage 1만 (위 Orchestration context에 정의됨)
- `current_phase=PLAN` → Stages 2-4만 (위 Orchestration context에 정의됨)

**독립 실행 (`ORCHESTRATED=false`)인 경우:** 기존 아티팩트를 기반으로 실행할 단계를 결정한다:

- **`PRD_FILE`이 없는 경우**: Stage 1 (PRD) 실행 후, Stages 2-4로 계속할지 질문한다.
- **`PRD_FILE`은 있지만 `PLAN_FILE`이 없는 경우**: Stage 1 건너뛰고 Stages 2-4 실행.
- **둘 다 있는 경우**: 사용자에게 질문:
    ```
    AskUserQuestion:
      question: "PRD와 플랜이 이미 존재합니다. 어떻게 진행할까요?"
      header: "Existing Artifacts"
      options:
        - label: "PRD 수정"
          description: "기존 PRD를 수정합니다"
        - label: "플랜 수정"
          description: "기존 플랜을 수정합니다"
        - label: "전체 재작성"
          description: "PRD와 플랜을 모두 새로 작성합니다"
    ```

## 파이프라인 단계

각 단계를 순차적으로 실행한다. 각 단계는 반드시:
- 불명확하거나 모호한 영역을 파악하여 AskUserQuestion으로 사용자에게 질문
- 사용자가 놓칠 수 있는 사항 식별 (엣지 케이스, 의존성, 제약 조건)
- 사용자가 이해를 확인한 후에만 다음 단계로 진행

---

### Stage 1: PRD — Product Requirements Document (요구사항 정의)

구현의 계약 역할을 하는 포괄적인 요구사항 문서.

#### 1A. 요구사항 수집

워크로그/분석으로 이미 답이 나온 질문은 건너뛴다. 갭을 채우기 위해 사용자에게 세부 질문을 한다.

**필수 (명확하지 않으면 반드시 질문):**
1. 어떤 문제를 해결하는가? (사용자 불편, 비즈니스 영향)
2. 누가 영향을 받는가? (대상 사용자/청중)
3. 제안된 솔루션이나 기능은 무엇인가?
4. 성공 지표는 무엇인가? (잘 작동하는지 확인 방법)
5. 어떤 제약이 있는가? (기술적, 일정, 호환성)

**기술 컨텍스트 (워크로그/분석에 없으면 질문):**
6. 기존 코드베이스 수정인가, 신규 개발인가?
7. 통합 요구사항이 있는가? (외부 API, 내부 시스템)
8. 성능/규모 요구사항이 있는가? (사용자 수, 데이터 볼륨, 지연 시간 목표)

**범위 (항상 질문):**
9. 명시적으로 범위 밖인 것은 무엇인가?
10. 알려진 위험이나 열린 질문이 있는가?

스마트 기본값 사용: 워크로그와 분석이 충분한 컨텍스트를 제공하면, 이해한 내용을 요약하고 각 질문을 다시 묻는 대신 사용자에게 확인 요청.

#### 1B. PRD 작성

다음 구조로 `PRD_FILE`에 PRD를 작성한다:

```markdown
# PRD: {task-name}

**Date:** {timestamp}
**Status:** Draft
**Worklog:** {worklog path}

## Problem & Solution

### Problem
{2-3 sentences: pain point + who's affected + severity}

### Proposed Solution
{2-3 sentences: what we're building + why it solves the problem}

## Goals & Success Metrics

### Goal 1: {primary goal}
- Metric: {measurable metric}
- Baseline → Target: {current} → {target}
- Timeframe: {when}

## User Stories

### US-1: {story title}
**As a** {user type}, **I want to** {action}, **so that** {benefit}.

**Acceptance Criteria:**
- [ ] {specific, testable criterion 1}
- [ ] {specific, testable criterion 2}
- [ ] {specific, testable criterion 3}
- [ ] {edge case criterion}

## Functional Requirements

### Must Have (P0)
- **REQ-001**: {specific, testable requirement}
  - Acceptance: {how to verify}
- **REQ-002**: ...

### Should Have (P1)
- **REQ-NNN**: ...

### Nice to Have (P2)
- **REQ-NNN**: ...

## Non-Functional Requirements

{Specific targets, not vague. e.g., "< 200ms p95" not "fast"}

- Performance: {specific targets}
- Security: {specific requirements}
- Compatibility: {browser/platform/version requirements}
- Accessibility: {standards to meet}

## Technical Considerations

{Architecture approach, API changes, database changes, migration strategy}

## Out of Scope

- {explicitly excluded item 1}
- {explicitly excluded item 2}

## Open Questions & Risks

| # | Question/Risk | Impact | Owner | Deadline |
|---|---------------|--------|-------|----------|
| 1 | {question} | {H/M/L} | {who decides} | {when} |
```

#### 1C. PRD 검증

다음 항목들을 기준으로 PRD를 검증한다:

1. 문제 설명에 사용자 영향과 비즈니스 영향이 모두 포함되어 있는가
2. 모든 목표에 측정 가능한 지표가 있는가 (모호하지 않게)
3. 각 사용자 스토리에 3개 이상의 수락 기준이 있는가
4. 모든 기능 요구사항이 테스트 가능한가 ("빠르게"처럼 모호하지 않게)
5. 요구사항에 우선순위가 있는가 (P0/P1/P2)
6. 비기능 요구사항에 구체적인 수치 목표가 있는가
7. 범위 밖이 명시적으로 정의되어 있는가
8. 위험이 영향 수준과 함께 식별되어 있는가

검증 실패 항목이 있으면: PRD를 수정하고 재검증.

검증 결과 출력:
```
PRD 검증: {passed}/{total} 통과
{any failures with suggestions}
```

#### 1D. 사용자 검토

PRD 요약을 사용자에게 제시. 승인을 요청한다.
승인된 경우: `PRD_FILE`에 작성하고 워크로그 업데이트.

**`ORCHESTRATED=true`이고 `current_phase=PRD`인 경우:** 여기서 중단. 출력:
- PRD 파일 경로
- "PRD가 완성되었습니다. 다음 단계에서 구현 플랜을 수립합니다."

**독립 실행인 경우:** Stages 2-4로 계속할지 질문한다.

---

### Stage 2: 동작/인터페이스 명세

확인된 PRD를 기반으로 시스템 동작을 기술한다. **프로젝트 타입을 고려한다:**

#### 모든 프로젝트 타입 (항상 포함):
1. 각 사용자 대면 동작 변경 사항 기술
2. 사용자 플로우 매핑: 사용자가 X를 할 때 무슨 일이 일어나는가?
3. 사용자 인터랙션의 엣지 케이스 식별
4. 다음을 고려한다:
   - 오류 상태와 복구 경로
   - 비동기/로딩 상태
   - 깨지면 안 되는 기존 동작
5. 동작 결정이 불명확한 경우 사용자에게 질문

#### Frontend 추가 사항 (project_type = frontend 또는 fullstack인 경우):
- 컴포넌트 인터랙션 플로우
- Undo/redo 영향
- 접근성 고려사항 (키보드 탐색, 스크린 리더)
- 브레이크포인트별 반응형 동작

#### Backend 추가 사항 (project_type = backend 또는 fullstack인 경우):
- API 계약: 요청/응답 스키마, 상태 코드, 오류 형식
- 데이터 유효성 검사 규칙
- 인증/인가 플로우
- 속도 제한, 페이지네이션, 캐싱 동작

#### CLI 추가 사항 (project_type = cli인 경우):
- 명령어 인터페이스: 인수, 플래그, 서브명령어
- 입출력 형식 (JSON, 표, 일반 텍스트)
- 대화형 vs 비대화형 모드
- 종료 코드와 오류 메시지

#### Library 추가 사항 (project_type = library인 경우):
- 공개 API 표면 설계
- 오류 타입과 처리 계약
- 하위 호환성 보장
- 사용 예제

**출력:** 사용자/시스템 플로우가 포함된 동작 명세

---

### Stage 3: 아키텍처/기술 명세

확인된 동작을 기반으로 기술적 구현에 매핑한다:

1. 코드베이스를 탐색하여 현재 아키텍처 파악:
   - `explore` 에이전트 또는 직접 Glob/Grep으로 관련 파일 탐색
   - 주요 파일을 읽어 패턴과 컨벤션 파악
2. 특정 파일과 모듈에 변경 사항 매핑
3. 다음을 식별한다:
   - 수정할 파일 vs 새로 생성할 파일
   - 타입 변경 (설정된 경우 `shared_types_dir` 확인)
   - 데이터베이스/스키마 변경 (해당되는 경우)
   - 추가/수정할 테스트 파일
   - 진행 중인 작업과의 잠재적 충돌
4. 여러 유효한 접근 방식이 있는 경우 아키텍처 결정에 대해 사용자에게 질문

#### Frontend 고려사항:
- 컴포넌트 계층과 데이터 플로우
- 상태 관리 접근 방식
- 디자인 시스템 일관성

#### Backend 고려사항:
- 서비스 경계와 인터페이스
- 데이터베이스 스키마 변경과 마이그레이션 전략
- API 버전 관리 접근 방식

#### 모든 프로젝트 타입:
- 모듈 경계와 추상화
- 성능 영향
- 하위 호환성

**출력:** 파일 수준 변경 맵이 포함된 기술 명세

---

### Stage 4: 구현 체크리스트

모든 단계가 완료되면 **작고 의미 있는 변경사항의 체크리스트**로 최종 플랜을 작성한다:

각 체크리스트 항목은 반드시:
- 하나의 의도를 표현해야 한다 (예: "X에 대한 타입 정의 추가", "동작 Y 구현")
- 단일 커밋에 맞아야 한다
- 작동하는 상태여야 한다 (중간에 깨진 상태 없음)
- 다음을 포함해야 한다: 변경 내용, 어떤 파일, 무엇을 테스트할지

형식:
```markdown
# Plan: {task-name}

**Date:** {timestamp}
**PRD:** {prd path}
**Worklog:** {worklog path}

## Behavior Spec
{from Stage 2 — condensed}

## Technical Spec
{from Stage 3 — condensed}

## Implementation Checklist

- [ ] **1. {title}**
  - Intent: {what and why}
  - Files: {list of files to touch}
  - Test: {what to verify}

- [ ] **2. {title}**
  ...
```

---

## 합의 검토

플랜이 작성되면 병렬 서브에이전트로 검토한다:

### Round 1: 병렬 검토

Task 도구로 4개 에이전트를 **병렬로** 실행한다:

```
Task(subagent_type="oh-my-claudecode:architect", model="opus",
     prompt="Review this plan for architectural soundness... [PLAN_CONTENT]")
Task(subagent_type="oh-my-claudecode:code-reviewer", model="sonnet",
     prompt="Review this plan for implementation feasibility... [PLAN_CONTENT]")
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="Review this plan for quality and completeness... [PLAN_CONTENT]")
Task(subagent_type="oh-my-claudecode:critic", model="opus",
     prompt="Challenge this plan — find gaps, risks, missing steps... [PLAN_CONTENT]")
```

각 에이전트 프롬프트에는 반드시 다음이 포함되어야 한다:
- 전체 플랜 내용 (Stages 2-4) + PRD 요약
- 워크로그 목표와 완료 기준
- 관련 코드베이스 컨텍스트 (주요 파일 내용, 아키텍처)
- 지시사항: "IMPORTANT: Do NOT use the Bash tool. Analyze ONLY the context provided."
- 출력 형식: 심각도 (CRITICAL/HIGH/MEDIUM/LOW) + 평결 (APPROVE/REVISE)가 포함된 발견사항 목록

### Round 2+: 합의 루프

4개 검토 결과를 분석한다:

1. **모두 APPROVE**: 합의 도달. 사용자 검토로 진행.
2. **CRITICAL 발견사항 없이 혼합**: 피드백을 종합하고 비논쟁적 개선사항을 적용한 후 진행.
3. **CRITICAL 발견사항 또는 강한 이견**:
   a. 피드백을 반영하여 플랜 수정
   b. 병렬 검토 재실행 (Round 1으로 복귀)
   c. 최대 3 라운드
4. **3 라운드 후에도 합의 불가하고 사용자 입력이 필요한 경우**:
   - AskUserQuestion으로 쟁점을 사용자에게 제시
   - 사용자 결정 반영
   - 최종 검토 라운드 1회 실행

### 합의 보고서

합의 후 요약을 출력한다:
```
## Plan Review Summary
- Rounds: {N}
- Architect: {verdict} — {1-line}
- Code Reviewer: {verdict} — {1-line}
- Quality Reviewer: {verdict} — {1-line}
- Critic: {verdict} — {1-line}
- Consensus: {REACHED / PARTIAL (user-resolved)}
```

## 사용자 검토 및 최종화

1. 최종 플랜을 사용자에게 제시하여 검토 요청
2. 사용자가 변경을 요청하면 반영하고 필요에 따라 가벼운 검토 재실행
3. 승인되면:
   - `PLAN_FILE`에 플랜 작성
   - `_shared/update-worklog.md`를 통해 워크로그 업데이트:
     - Status: 현재 상태 반영
     - Links 섹션에 플랜 파일 링크 추가
     - `timeline_entry`: 플래닝 세션 요약

## 출력

다음을 출력한다:
- PRD 파일 경로 (생성된 경우)
- 플랜 파일 경로
- 체크리스트 항목 수
- 제안: "플랜이 완성되었습니다. `/vimpl {WORKLOG_DIR}` 로 구현을 시작하세요."

## 절대 규칙

- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
