---
name: integration-test
description: React Hook 통합 테스트 작성 워크플로우. renderHook 기반으로 비동기 흐름, 취소, 에러 처리, 상태 전이를 검증한다.
---

<Purpose>
React Hook 내부의 비동기 흐름을 테스트하는 통합 테스트 작성 워크플로우.
단위 테스트로 커버할 수 없는 **여러 모듈이 협력하는 흐름**(비동기 초기화, 취소, 에러 전파, 상태 전이)을 검증한다.
</Purpose>

<Use_When>
- React Hook 내부의 useEffect 비동기 흐름을 테스트할 때
- 단위 테스트로 순수 함수는 커버했지만, 조립된 흐름이 미검증일 때
- 취소(cleanup), 경쟁 조건, 에러 전파 등 비동기 시나리오를 검증할 때
- "통합 테스트", "hook 테스트", "renderHook", "비동기 흐름 테스트"
</Use_When>

<Do_Not_Use_When>
- 순수 함수 단위 테스트만 필요할 때 → tdd-review 또는 직접 작성
- 컴포넌트 렌더링 테스트 (DOM 검증)가 필요할 때 → @testing-library/react의 render 사용
- E2E 테스트가 필요할 때 → Playwright/Cypress 등
</Do_Not_Use_When>

<Core_Concepts>

## 단위 테스트 vs 통합 테스트

```
단위 테스트: 함수 하나의 입력 → 출력 검증
  detectChange(state, slices, version) → { kind: 'initialize' }

통합 테스트: 여러 모듈이 함께 작동하는 흐름 검증
  useCustomHook 호출
    → detectChange로 변경 감지
    → DataManager 대기
    → controller.initialize() 호출
    → 상태를 initialized로 전환
    → playingRef에 따라 play/pause 호출
```

## 통합 테스트가 필요한 신호

| 코드 특성 | 단위 테스트로 충분? | 통합 테스트 필요? |
|-----------|-------------------|-----------------|
| 순수 함수 (입력 → 출력) | ✅ | ❌ |
| 이벤트 발행/구독 | ✅ | ❌ |
| Hook 내 useEffect 비동기 흐름 | ❌ | ✅ |
| cleanup/취소 로직 | ❌ | ✅ |
| 상태 전이 (initialized: false → true) | ❌ | ✅ |
| 여러 비동기 작업의 직렬화 | ❌ | ✅ |
| 에러 발생 시 콜백 전파 | ❌ | ✅ |

## 핵심 도구

### renderHook
React Hook을 가짜 컴포넌트 안에서 실행하는 도구.
Hook은 컴포넌트 밖에서 호출할 수 없으므로, renderHook이 대신 감싸준다.

```typescript
import { renderHook, waitFor } from '@testing-library/react';

const { result, rerender, unmount } = renderHook(
  (props) => useMyHook(props),
  { initialProps: { value: 1 } }
);

// result.current → hook의 현재 반환값
// rerender({ value: 2 }) → props 변경 시뮬레이션
// unmount() → 컴포넌트 언마운트 (cleanup 트리거)
```

### waitFor
비동기 작업이 완료될 때까지 assertion을 반복 시도한다.

```typescript
await waitFor(() => {
  expect(result.current.initialized).toBe(true);
});
```

### act
React 상태 업데이트를 동기적으로 처리한다.
renderHook과 waitFor 내부에서 자동으로 act를 감싸주므로, 명시적 사용은 드물다.

</Core_Concepts>

<Project_Settings>

이 스킬은 다음 프로젝트 설정을 참조한다 (`rules/workflow.md` 또는 `rules/project-params.md`):

| 설정 | 용도 |
|------|------|
| `test_command` | 테스트 실행 명령 (e.g., `yarn test --run`) |

설정이 없으면: package.json에서 자동 탐지 → 실패 시 사용자에게 질문 → `project_memory_add_note("test_command: {answer}")`

</Project_Settings>

<Steps>

### Step 1: 테스트 대상 분석

1. 대상 Hook의 소스코드를 읽는다
2. 단위 테스트로 이미 커버된 순수 함수를 확인한다
3. 통합 테스트가 필요한 흐름을 식별한다:
   - 비동기 초기화/정리 흐름
   - useEffect cleanup (취소 로직)
   - 에러 전파 경로
   - 상태 전이 시퀀스
   - props 변경에 따른 재초기화

4. 외부 의존성을 목록화한다:
   ```
   | 의존성 | 종류 | Mock 전략 |
   |--------|------|----------|
   | controller | 클래스 인스턴스 | vi.fn() 객체 |
   | DataManager | 싱글턴 | vi.mock() 모듈 mock |
   | React hooks | 프레임워크 | renderHook이 처리 |
   ```

**유저 체크포인트:** 테스트 시나리오 목록 리뷰

### Step 2: Mock 전략 설계

외부 의존성별 mock 방법을 결정한다:

**모듈 레벨 mock (vi.mock)**
- 싱글턴, static 메서드, 외부 모듈에 사용
```typescript
vi.mock('@/domain/store/dataManager', () => ({
  DataManager: {
    waitForUpdatesSettled: vi.fn().mockResolvedValue(undefined),
  },
}));
```

**인스턴스 레벨 mock (plain object)**
- 클래스 인스턴스를 주입받는 경우에 사용
- `as unknown as ClassName` 캐스트는 constructor에 넘기는 지점에만 사용
- mock 객체 자체는 plain object 타입을 유지 (프로퍼티 할당 가능하도록)
```typescript
const createMockController = () => ({
  initialize: vi.fn().mockResolvedValue(undefined),
  refresh: vi.fn().mockResolvedValue(undefined),
  play: vi.fn(),
  pause: vi.fn(),
});
```

**Ref mock**
- useRef를 통해 전달되는 값은 `{ current: value }` 객체로 mock
```typescript
const playingRef = { current: false };
const destroyedRef = { current: false };
```

### Step 3: 테스트 시나리오 작성

각 시나리오는 다음 구조를 따른다:

```typescript
it('시나리오 설명 (한국어)', async () => {
  // 1. Arrange: mock 준비 + renderHook
  const mockController = createMockController();
  const { result, rerender, unmount } = renderHook(
    (props) => useMyHook(props),
    { initialProps: { ... } }
  );

  // 2. Act: 비동기 작업 완료 대기
  await waitFor(() => {
    expect(result.current.initialized).toBe(true);
  });

  // 3. Assert: 호출 순서, 상태, 콜백 검증
  expect(mockController.initialize).toHaveBeenCalledWith(timeSlices);
});
```

**필수 시나리오 카테고리:**

1. **정상 초기화 흐름**: props 전달 → 비동기 작업 → 상태 업데이트
2. **재초기화/갱신**: props 변경 → rerender → 올바른 메서드 호출
3. **취소**: 진행 중 unmount 또는 props 변경 → 이전 작업 취소 확인
4. **에러 처리**: 비동기 작업 실패 → onError 콜백 호출
5. **경쟁 조건**: 빠른 연속 변경 → 마지막 변경만 반영

### Step 4: 테스트 작성 + 검증

1. Step 3에서 합의된 시나리오를 바탕으로 테스트 코드를 작성한다
2. 테스트를 실행한다 (`rules/workflow.md`의 `test_command` 사용, 없으면 프로젝트의 package.json에서 탐지, 그래도 없으면 사용자에게 질문 → `project_memory_add_note("test_command: {answer}")`)
3. `lsp_diagnostics`로 타입 에러를 확인한다
4. 실패하는 테스트는 원인을 분석하고 유저와 논의한다

**유저 체크포인트:** 테스트 결과 확인 + 추가 시나리오 필요 여부

</Steps>

<Patterns>

## 비동기 Hook 테스트 패턴

### Promise 체인 테스트
```typescript
it('이전 초기화 완료 후 다음 초기화를 실행한다', async () => {
  let resolveFirst: () => void;
  const firstInit = new Promise<void>(r => { resolveFirst = r; });
  mockController.initialize.mockReturnValueOnce(firstInit);

  const { rerender } = renderHook((props) => useMyHook(props), {
    initialProps: { items: itemsA },
  });

  // 첫 번째 초기화 진행 중에 props 변경
  rerender({ items: itemsB });

  // 첫 번째 완료
  resolveFirst!();

  await waitFor(() => {
    // 두 번째 초기화도 호출되었는지 확인
    expect(mockController.initialize).toHaveBeenCalledTimes(2);
  });
});
```

### 취소 테스트
```typescript
it('unmount 시 진행 중인 초기화를 취소한다', async () => {
  const { unmount } = renderHook((props) => useMyHook(props), {
    initialProps: { items: itemsA },
  });

  // 초기화 완료 전 unmount
  unmount();

  // 상태 업데이트가 일어나지 않음을 확인
  // (React warning 없이 테스트 통과하면 성공)
});
```

### 에러 전파 테스트
```typescript
it('초기화 실패 시 onError를 호출한다', async () => {
  const error = new Error('init failed');
  mockController.initialize.mockRejectedValue(error);
  const onError = vi.fn();

  renderHook(() => useMyHook({ onError, ... }));

  await waitFor(() => {
    expect(onError).toHaveBeenCalledWith(error);
  });
});
```

## Mock 타입 안전성 규칙

1. **plain object mock은 cast하지 않는다** — 프로퍼티 할당이 자유로움
2. **constructor 주입 시에만 `as unknown as ClassName` 사용** — 불가피한 cast를 한 곳으로 제한
3. **vi.mocked()로 모듈 mock 타이핑** — `as ReturnType<typeof vi.fn<...>>` 대신 사용
4. **branded type은 helper 함수로 생성** — 프로젝트의 타입 유틸리티 함수 활용

</Patterns>

<Tool_Usage>
- `Read`: 대상 Hook 소스코드 읽기
- `mcp__plugin_context7_context7__query-docs`: @testing-library/react API 참조 (필요 시)
- `lsp_diagnostics`: 테스트 파일 타입 체크
- `Bash (vitest)`: 테스트 실행
- `Task(executor)`: 테스트 코드 작성 위임 (대량 시)
- `AskUserQuestion`: 테스트 시나리오 확인
</Tool_Usage>

<Anti_Patterns>
- 순수 함수를 renderHook으로 테스트 (단위 테스트로 충분)
- 실제 외부 서비스에 의존하는 테스트 (모든 외부 의존성은 mock)
- setTimeout/setInterval에 의존하는 불안정한 타이밍 테스트 (waitFor 사용)
- `as unknown as` 를 mock 객체 전체에 사용 (constructor 주입 지점에만 사용)
- 통합 테스트에서 이미 단위 테스트로 커버된 순수 로직을 재검증
- 한국어가 아닌 영어로 테스트 설명 작성
</Anti_Patterns>

<Examples>
<Good>
```
유저: "useCustomHook 통합 테스트 작성해줘"

1. Hook 소스 읽기 + 외부 의존성 목록화
2. "다음 5가지 시나리오를 테스트하겠습니다: ..."
3. 유저: "취소 시나리오는 빼고 진행해"
4. 합의된 시나리오만 renderHook으로 작성
5. vitest 실행 + lsp_diagnostics 확인
6. 결과 보고
```
</Good>

<Bad>
```
유저: "useCustomHook 통합 테스트 작성해줘"

1. 순수 유틸 함수들을 다시 renderHook으로 테스트
2. 실제 DataManager를 호출하는 테스트 작성
→ 단위 테스트 중복 + 외부 의존성 미격리
```
</Bad>
</Examples>
