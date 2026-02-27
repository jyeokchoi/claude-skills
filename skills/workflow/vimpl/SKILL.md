---
name: vimpl
description: Incremental or auto implementation with TDD, code-simplifier, parallel verification, and ralph loop persistence
argument-hint: 'Usage: /vimpl [worklog-folder-or-worklog.md]'
---

## 프로젝트 설정

이 스킬은 프로젝트 설정 파일(`rules/project-params.md`)을 참조한다 (auto-loaded). 설정이 없으면 기본값 사용:

| 설정 | 기본값 | 용도 |
|------|--------|------|
| `test_command` | 프로젝트 설정에서 탐지 | 테스트 실행 명령 |
| `completion_promise` | `**WORKLOG_TASK_COMPLETE**` | ralph loop 완료 감지용 (OMC 내부) |

TDD, 코드 단순화, 병렬 검증, ralph loop 지속성을 사용하여 플랜 체크리스트를 항목별로 실행하는 구현 워크플로우를 실행한다.

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
- `PLAN_FILE` = `{WORKLOG_DIR}/plan.md`로 설정
- `PLAN_FILE`이 없으면 중단: "플랜 파일이 없습니다. `/vplan` 으로 먼저 플랜을 작성하세요."
- 테스트 명령 결정: `_shared/resolve-test-command.md`를 로드하고 해당 로직을 따라 `TEST_COMMAND`를 설정한다.

## 오케스트레이션 컨텍스트

- `_shared/orchestration-context.md`를 로드하고 **서브 스킬 — 읽기** 프로토콜을 따른다.
- `ORCHESTRATED=true`인 경우: 아래 모드 선택과 Ralph loop 활성화의 동작이 변경된다.

## 모드 선택 (세션 유지)

**`ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=auto`인 경우:**
- 자동으로 Auto 모드 선택. 질문 생략.

**`ORCHESTRATED=true`이고 `ORCHESTRATION_MODE=step`인 경우:**
- 자동으로 Incremental 모드 선택. 질문 생략.

**그 외 (독립 실행):**

세션 시작 시 한 번만 질문한다. `<remember priority>vimpl mode: {choice}</remember>`로 전체 세션 동안 선택을 기억한다.

```
AskUserQuestion:
  question: "구현 모드를 선택해주세요."
  header: "Mode"
  options:
    - label: "점진 모드 (Incremental)"
      description: "각 구현 단위마다 유저가 직접 변경사항을 검토하고 승인합니다."
    - label: "자동 모드 (Auto)"
      description: "서브에이전트의 exhaustive-review 컨센서스로 자동 승인합니다."
```

이전 모드 선택이 메모리에 있으면 확인: "이전에 {mode} 모드를 선택하셨습니다. 계속할까요?"

## Ralph loop 활성화

**`ORCHESTRATED=true`인 경우:** 이 섹션 전체를 건너뛴다. vwork가 ralph loop을 관리하므로 vimpl이 별도로 활성화하지 않는다.

**그 외 (독립 실행):**

모드 선택 후 작업이 중단되지 않도록 ralph loop을 활성화한다:

1. `state_read(mode="ralph")`로 ralph 상태가 이미 존재하는지 확인. `active=true`이면 활성화 건너뜀 (이미 다른 컨텍스트에서 활성화됨).
2. `rules/project-params.md`에서 `completion_promise` 사용 (기본값: `**WORKLOG_TASK_COMPLETE**`).
3. `state_write(mode="ralph")`로 ralph 상태 생성:
   ```json
   {
     "active": true,
     "iteration": 1,
     "max_iterations": 100,
     "completion_promise": "<PROMISE>",
     "worklog_path": "<WORKLOG_DIR>",
     "linked_ultrawork": true
   }
   ```
4. `state_write(mode="ultrawork")`로 ultrawork 상태 생성:
   ```json
   {
     "active": true,
     "linked_to_ralph": true
   }
   ```

## 구현 루프 (체크리스트 항목별)

플랜 파일을 읽는다. 첫 번째 미완료 항목(`- [ ]`)을 찾는다. 각 항목에 대해 다음을 실행한다:

### Step 1: 단위 이해

체크리스트 항목의 의도, 파일, 테스트 기준을 읽는다. 관련 소스 파일을 읽어 현재 상태를 파악한다.

### Step 2: TDD — 테스트 먼저 작성 (Red 단계)

구현 코드를 작성하기 전에:

1. **UX/동작 수준 테스트**: 사용자 관점에서 기대 동작을 기술하는 통합 또는 컴포넌트 테스트를 작성한다. 이 테스트는 초기에 FAIL해야 한다.
2. **유닛 테스트**: 구현할 특정 로직에 대한 유닛 테스트를 작성한다. 이 테스트도 초기에 FAIL해야 한다.
3. 테스트를 실행하여 실패 확인 (Red): `{TEST_COMMAND} {test-file}`
4. 테스트를 먼저 작성할 수 없는 경우 (예: 테스트 인프라 미비), 워크로그에 기록하고 구현을 진행하되 즉시 테스트를 추가한다.

### Step 3: 구현 (Green 단계)

모든 테스트를 통과하는 데 필요한 최소한의 코드를 작성한다:

1. 체크리스트 항목에 기술된 변경사항을 구현한다
2. 테스트를 실행하여 통과 확인 (Green): `{TEST_COMMAND} {test-file}`
3. 테스트가 실패하면 Green이 될 때까지 반복한다.

### Step 4: 코드 단순화 (Refactor 단계)

1. 수정된 파일에 대해 code-simplifier 에이전트를 실행한다:
   ```
   Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
        prompt="Simplify and refactor the recently modified code for clarity and maintainability without changing behavior. Focus on: reducing complexity, improving naming, removing redundancy. Files: {list}")
   ```
2. 단순화 후 테스트를 다시 실행하여 아무것도 깨지지 않았는지 확인: `{TEST_COMMAND}`
3. 단순화 후 테스트가 실패하면 단순화 변경을 되돌리고 워크로그에 기록한다.

### Step 5: 병렬 검증

다음 두 검증을 **병렬로** 실행한다:

**검증 A — 정확성 확인:**
```
Task(subagent_type="oh-my-claudecode:verifier", model="sonnet",
     prompt="Verify this implementation is correct.
     - Checklist item: {item description}
     - Changed files: {list with diffs}
     - Test results: {test output}
     - Check: types, logic, edge cases, test coverage
     IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

**검증 B — 의도 정합성 확인:**
```
Task(subagent_type="oh-my-claudecode:quality-reviewer", model="sonnet",
     prompt="Cross-verify this implementation against the plan and worklog.
     - Plan item: {checklist item from plan.md}
     - Worklog goal: {from worklog Goal section}
     - Implementation diff: {changes made}
     - Check: Does the implementation match the intent? Missing anything?
     IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
```

어느 한 검증에서 문제가 발견되면:
- 문제를 수정한다
- 테스트를 재실행한다
- 실패한 검증만 재실행한다

### Step 6: 승인

**사용자에게 설명** (두 모드 모두):
- 어떤 파일이 왜 변경되었는가
- 전체 아키텍처에서 이 변경이 어디에 위치하는가
- 왜 이 특정 변경이 필요했는가

**점진 모드:**
- 설명을 제시하고 AskUserQuestion으로 사용자 승인 대기:
  ```
  AskUserQuestion:
    question: "구현 #{N} 검토: {title}. 승인하시겠습니까?"
    header: "Review"
    options:
      - label: "승인"
        description: "변경사항을 승인하고 다음 항목으로 진행"
      - label: "수정 필요"
        description: "피드백을 주시면 수정 후 다시 검토합니다"
      - label: "롤백"
        description: "이 변경을 되돌립니다"
  ```
- "수정 필요"인 경우: 피드백 반영 → Step 3으로 복귀
- "롤백"인 경우: `git checkout -- {files}` → 플랜에서 해당 항목을 차단됨으로 표시하고 다음으로 진행

**자동 모드:**
- 변경사항에 대해 exhaustive-review 실행:
  ```
  Task(subagent_type="oh-my-claudecode:code-reviewer", model="opus",
       prompt="Review this implementation change as three personas (Advocate, Surgeon, Challenger).
       Diff: {diff of current checklist item changes}
       Context: {relevant file contents}
       Output: APPROVE or REQUEST_CHANGES with findings.
       IMPORTANT: Do NOT use Bash. Analyze only the provided context.")
  ```
- 최종 권고가 APPROVE이면: 자동 승인
- REQUEST_CHANGES이면:
  - 제안된 수정사항 반영
  - 테스트 재실행
  - 가벼운 검증 재실행
  - 2회 반복 후에도 승인되지 않으면 사용자에게 질문으로 폴백

### Step 7: 커밋 및 완료 표시

1. 이 체크리스트 항목의 변경사항을 스테이징하고 커밋한다:
   ```bash
   git add {changed source files} {changed test files}
   git commit -m "{checklist item title}

   Implements item #{N} from plan.
   Files: {list of changed files}
   Tests: {pass/fail summary}"
   ```
2. plan.md에서 체크리스트 항목을 완료로 표시: `- [ ]` → `- [x]`
3. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `dashboard_updates`: 다음 작업, 진행 상황
   - `timeline_entry`: 완료된 작업 + 근거 (커밋 해시 포함)
4. 다음 미완료 항목으로 진행

## 완료

plan.md의 모든 체크리스트 항목이 완료되면 (`- [x]`):

1. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `timeline_entry`: 완료 근거 (모든 항목 완료, 테스트 결과, 커밋 해시)

**`ORCHESTRATED=true`인 경우:** 여기서 종료. vwork가 다음 phase(VERIFY)를 관리한다.

**그 외 (독립 실행):**

2. 완료 약속 출력: `<promise>{COMPLETION_PROMISE}</promise>`
3. ralph loop 취소: `/oh-my-claudecode:cancel`

## 절대 규칙

- **TDD를 건너뛰지 않는다.** 테스트가 구현 코드보다 먼저 작성된다.
- **code-simplifier를 건너뛰지 않는다.** Green 이후 항상 리팩토링한다.
- **승인 없이 진행하지 않는다.** 점진 모드 = 사용자. 자동 모드 = exhaustive-review 합의.
- **작업을 멈추지 않는다.** Ralph loop이 지속성을 보장한다. 각 반복은 의미 있는 작업을 해야 한다.
- **워크로그를 항상 업데이트한다.** 각 체크리스트 항목 전후에 `_shared/update-worklog.md`를 통해 업데이트한다.
- **모드를 기억한다.** Incremental vs Auto는 한 번 선택하고 유지된다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
