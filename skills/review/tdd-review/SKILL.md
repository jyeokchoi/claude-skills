---
name: tdd-review
description: Interactive TDD workflow with exhaustive code review. Reviews code first, discusses test cases with user, refactors if untestable, then writes tests collaboratively.
---

<Purpose>
코드리뷰 기반 TDD 워크플로우. 대상 코드를 먼저 리뷰하고, 유저와 테스트 전략을 논의한 후, 필요시 리팩토링을 거쳐 유닛 테스트를 작성한다.
핵심 원칙: **유저와 인터랙티브하게 진행**. 자율적으로 모든 것을 결정하지 않는다.
</Purpose>

<Use_When>
- 기존 코드에 유닛 테스트를 추가하려 할 때
- 코드리뷰와 테스트 작성을 함께 진행하려 할 때
- 테스트하기 어려운 코드를 리팩토링하며 테스트를 작성하려 할 때
- "tdd review", "코드리뷰 + 테스트", "테스트 작성"
</Use_When>

<Do_Not_Use_When>
- 새 기능을 TDD로 처음부터 구현할 때 → `/oh-my-claudecode:tdd` 사용
- 빠른 단일 패스 코드리뷰만 필요할 때 → `/oh-my-claudecode:code-review` 사용
- 자율 모드로 대량 테스트를 작성할 때 → `/oh-my-claudecode:ralph` 사용
</Do_Not_Use_When>

<Core_Principles>
1. **인터랙티브 우선**: 모든 주요 결정은 유저와 논의 후 진행
2. **코드리뷰 선행**: 테스트 전에 설계 문제를 발견하여 리팩토링 방향을 잡음
3. **테스트 가능성 분석**: 단순히 테스트케이스를 나열하지 않고, 의존성 구조와 테스트 난이도를 분류
4. **최소 변경 리팩토링**: 테스트를 위한 변경은 export 추가, 순수 함수 추출 등 최소한으로. 아키텍처 변경은 유저와 별도 논의
5. **검증 게이트**: 테스트 통과 + 타입 체크 통과 후 다음 단계로
</Core_Principles>

<Project_Settings>

이 스킬은 다음 프로젝트 설정을 참조한다 (`rules/workflow.md` 또는 `rules/project-params.md`):

| 설정 | 용도 |
|------|------|
| `test_command` | 테스트 실행 명령 (e.g., `yarn test --run`) |

설정이 없으면: package.json에서 자동 탐지 → 실패 시 사용자에게 질문 → `project_memory_add_note("test_command: {answer}")`

</Project_Settings>

<Steps>

### Step 1: 대상 파일 읽기 + Exhaustive Code Review

1. 유저가 지정한 파일(또는 계층/모듈)의 소스코드를 읽는다
2. `/exhaustive-review` 스킬을 호출하여 코드리뷰를 수행한다
   - 리뷰 대상: 지정된 파일들의 전체 코드 (diff가 아닌 현재 상태)
   - 리뷰 포커스: 테스트 가능성, 의존성 구조, 순수 함수 추출 가능성
3. 리뷰 결과를 유저에게 제시한다

**유저 체크포인트:** 리뷰 결과에 대한 피드백 수렴

### Step 2: 테스트 대상 로직 산정 + 테스트케이스 논의

리뷰 결과를 바탕으로 테스트 대상을 분류한다:

```
| 대상 | 종류 | 테스트 가능성 | 필요 변경 |
|------|------|-------------|----------|
| fn_A | 순수 함수 | ✅ 즉시 가능 | 없음 |
| fn_B | 미export 순수 함수 | ⚠️ export 필요 | export 추가 |
| hook_C | React Hook | ❌ 직접 불가 | 로직 추출 필요 |
| class_D | 외부 의존 클래스 | ⚠️ mock 필요 | mock 전략 필요 |
```

각 테스트 대상에 대해 구체적 테스트케이스를 제안한다:
- 정상 경로 (happy path)
- 엣지 케이스 (빈 입력, 경계값 등)
- 에러 경로 (예외 상황)

**유저 체크포인트:** 테스트케이스 목록을 리뷰하고, 추가/제거/수정 요청을 받는다.

### Step 3: 테스트 가능성 판단

Step 2의 분류 결과를 기준으로 판단한다:

- **즉시 테스트 가능** → Step 5로 이동
- **소규모 변경 필요** (export 추가, 타입 export 등) → 변경 사항을 유저에게 설명하고 승인 후 적용, 그 다음 Step 5
- **리팩토링 필요** (순수 함수 추출, 의존성 역전 등) → Step 4로 이동

**유저 체크포인트:** 테스트 가능성 판단 결과에 대한 동의 확인

### Step 4: 리팩토링 (테스트 불가 시)

리팩토링 원칙:
- **테스트를 위한 최소한의 변경만** 수행
- 아키텍처 변경은 유저와 별도 논의
- 리팩토링 전후 동작은 동일해야 함

실행 방법:
1. 리팩토링 계획을 유저에게 제시한다 (어떤 함수를 추출하고, 어디에 배치할지)
2. 유저 승인 후, `executor` 서브에이전트를 사용하여 리팩토링 수행
3. 리팩토링 후 `lsp_diagnostics`로 타입 에러 확인
4. 유저에게 결과를 보여주고, 테스트 가능 상태가 되었는지 재확인

**유저 체크포인트:** 리팩토링 결과 리뷰 + 테스트 가능성 재확인

### Step 5: 테스트 작성 + 검증

1. Step 2에서 합의된 테스트케이스를 바탕으로 테스트 코드를 작성한다
2. 테스트를 실행한다 (`rules/workflow.md`의 `test_command` 사용, 없으면 프로젝트의 package.json에서 탐지, 그래도 없으면 사용자에게 질문 → `project_memory_add_note("test_command: {answer}")`)
3. 실패하는 테스트가 있으면 원인을 분석하고 유저와 논의한다
   - 테스트가 잘못된 경우: 테스트 수정
   - 코드에 버그가 있는 경우: 유저에게 보고 후 수정 여부 결정
4. 모든 테스트 통과 후 `lsp_diagnostics`로 타입 에러 확인

**유저 체크포인트:** 테스트 결과 확인 + 추가 테스트 필요 여부

### Step 6: 다음 대상으로 반복

현재 대상의 테스트가 완료되면:
1. 완료 요약을 유저에게 제시한다 (테스트 수, 커버리지, 발견된 이슈)
2. 다음 대상 파일/계층으로 넘어갈지 유저에게 확인한다
3. 유저가 계속하면 Step 1로 돌아간다

</Steps>

<Output_Format>

각 Step 완료 시 유저에게 제시하는 형식:

**Step 1 완료 후:**
```
## 코드리뷰 완료: {파일명}
{exhaustive-review 결과 요약}

다음 단계로 넘어가서 테스트 대상을 분류할까요?
```

**Step 2 완료 후:**
```
## 테스트 대상 분류

| 대상 | 종류 | 테스트 가능성 | 비고 |
|------|------|-------------|------|
| ... | ... | ... | ... |

### 제안 테스트케이스
1. {대상}: {테스트 설명}
2. ...

이 테스트케이스로 진행할까요? 추가/수정할 것이 있으면 말씀해주세요.
```

**Step 5 완료 후:**
```
## 테스트 결과: {파일명}
- 테스트 파일: {경로}
- 테스트 수: {N}개
- 결과: 모두 통과 ✅
- 타입 체크: 에러 없음 ✅

다음 대상으로 넘어갈까요?
```

</Output_Format>

<Tool_Usage>
- `/exhaustive-review`: Step 1에서 코드리뷰 수행
- `Read`: 대상 파일 읽기
- `lsp_diagnostics`: 리팩토링/테스트 작성 후 타입 체크
- `Bash (vitest)`: 테스트 실행
- `Task(executor)`: Step 4 리팩토링 실행
- `Task(explore)`: 의존성 탐색이 필요할 때
- `AskUserQuestion`: 각 체크포인트에서 유저 의견 수렴 (단, 자연스러운 대화 흐름이면 직접 질문도 가능)
</Tool_Usage>

<Anti_Patterns>
- ❌ 유저에게 물어보지 않고 모든 테스트케이스를 자율적으로 결정
- ❌ 코드리뷰 없이 바로 테스트 작성
- ❌ 테스트를 위해 대규모 아키텍처 변경
- ❌ 한 번에 모든 계층의 테스트를 작성하려고 시도
- ❌ 테스트 실패를 유저에게 보고하지 않고 자체적으로 해결
- ❌ lsp_diagnostics 검증 없이 완료 선언
</Anti_Patterns>

<Examples>
<Good>
```
유저: "PreviewController 테스트 작성해줘"

1. PreviewController.ts를 읽고 exhaustive-review 실행
2. "리뷰 결과, 다음 3가지 로직이 테스트 가능합니다: ..."
   "이 테스트케이스로 진행할까요?"
3. 유저: "play/pause는 빼고 initialize 위주로"
4. 합의된 테스트케이스만 작성
5. 테스트 실행 + 결과 보고
```
</Good>

<Bad>
```
유저: "PreviewController 테스트 작성해줘"

1. PreviewController.ts + PlaybackSession.ts + 관련 파일 20개를 읽음
2. 모든 메서드에 대한 40개 테스트를 자율적으로 작성
3. "모든 테스트 작성 완료!" 보고
→ 유저가 원하지 않는 테스트 포함, 리뷰 기회 없음
```
</Bad>
</Examples>
