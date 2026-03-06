# 스킬 감사 분석 보고서

> 생성일: 2026-03-06
> 분석 대상: `skills/**/SKILL.md`, `skills/_shared/*.md`, `skills/_templates/**`
> 분석 에이전트: analyzer (debugger)

---

## 요약

| 카테고리 | 건수 |
|---|---|
| 모순 (Contradictions) | 3건 |
| 비효율 (Inefficiencies) | 4건 |
| Deprecated/존재하지 않는 의존성 | 0건 |

---

## 1. 모순 (Contradictions)

### C-1. critic 에이전트 모델 불일치

**심각도**: HIGH
**위치**: `skills/_shared/agent-routing.md` ↔ `skills/workflow/vqa/SKILL.md:82`

`_shared/agent-routing.md`는 `critic` 에이전트의 기본 model을 **opus**로 정의한다.
그러나 `vqa/SKILL.md:82`는 `Task(subagent_type="oh-my-claudecode:critic", model="sonnet", ...)`으로 호출한다.

```
# agent-routing.md
critic | oh-my-claudecode:critic | opus | ...

# vqa/SKILL.md:82
Task(subagent_type="oh-my-claudecode:critic", model="sonnet", ...)
```

agent-routing.md에는 의도적 다운그레이드 허용 여부나 기준이 없다.
코드 리뷰어나 품질 전략가 등 일부 스킬은 의도적 다운그레이드를 메모에 기록하지만, critic은 기록 없음.

**영향**: vqa 실행 시 critic이 설계 의도보다 낮은 품질로 동작할 수 있다.

---

### C-2. analyst 에이전트 모델 불일치 (4개 파일)

**심각도**: MEDIUM
**위치**: `skills/_shared/agent-routing.md` ↔ 아래 4개 파일

`_shared/agent-routing.md`는 `analyst` 에이전트의 기본 model을 **opus**로 정의한다.
그러나 4개 스킬 파일에서 `model="sonnet"`으로 호출한다:

| 파일 | 위치 |
|---|---|
| `skills/workflow/vqa/SKILL.md` | :153 |
| `skills/request/request-to-ux-researcher/SKILL.md` | :34 |
| `skills/request/request-to-qa/SKILL.md` | :133 |
| `skills/request/request-to-designer/SKILL.md` | :37 |

```
# agent-routing.md
analyst | oh-my-claudecode:analyst | opus | ...

# 실사용 (4개 파일 공통)
Task(subagent_type="oh-my-claudecode:analyst", model="sonnet", ...)
```

**영향**: analyst 호출이 표준 기본값(opus)으로 의도한 분석 깊이에 미치지 못할 수 있다.
4개 파일 전체에 걸쳐 동일하게 sonnet을 사용하는 점을 보면 의도적 패턴일 가능성도 있으나 문서화 없음.

---

### C-3. vauto의 worklog-start/finish Skill() 강제 규칙 누락

**심각도**: HIGH
**위치**: `skills/workflow/vwork/SKILL.md` ↔ `skills/workflow/vauto/SKILL.md`

`vwork/SKILL.md`의 "절대 규칙" 섹션:
```
worklog-start와 worklog-finish는 반드시 Skill() 도구로 호출한다.
직접 절차를 인라인으로 실행하는 것을 금지한다.
```

`vauto/SKILL.md`에는 이 규칙이 **없다**.
vauto도 동일한 워크플로우 파이프라인을 실행하며 worklog-start/finish를 참조하지만, Skill() 강제 규칙 없이 단순 참조만 한다.

**영향**: vauto 실행 시 오케스트레이터가 worklog-start/finish 절차를 인라인으로 직접 실행할 위험이 있다. 이는 worklog 구조 오염, .active 파일 미생성, 상태 불일치를 일으킬 수 있다.

---

## 2. 비효율 (Inefficiencies)

### I-1. vwork ↔ vauto 대규모 중복 (DRY 위반)

**심각도**: HIGH
**위치**: `skills/workflow/vwork/SKILL.md`, `skills/workflow/vauto/SKILL.md`

두 파일 사이에 90% 이상 동일한 내용이 중복된다:

| 중복 내용 | 비고 |
|---|---|
| Phase 상태 머신 (ANALYZE→PRD→PLAN→IMPL→VERIFY→TEST→DONE) | 완전 동일 |
| Phase별 팀원 매핑 테이블 | 완전 동일 |
| Per-phase CLI 라우팅 규칙 | 완전 동일 |
| 복잡도 판단 기준 (simple/standard/complex) | 완전 동일 |
| 상태 보존 규칙 | 완전 동일 |
| Notepad 라이프사이클 | 완전 동일 |
| Step 0~7 절차 구조 | 거의 동일 |
| 절대 규칙 (vwork에만 Skill() 강제 포함) | 부분 중복 |

두 파일의 유일한 차이:
- **vwork**: 사용자 승인 단계 포함 (human-in-the-loop), 절대규칙에 Skill() 강제 명시
- **vauto**: 자동 전이 (승인 없음), Skill() 강제 규칙 없음

**영향**: Phase 상태 머신 등 핵심 로직 수정 시 두 파일을 모두 수정해야 하며, 한 파일만 수정하면 동작 불일치가 발생한다.

**권장 방향**: 공통 절차를 `_shared/vwork-core.md`로 추출하고, vwork/vauto는 차이점(승인 여부, Skill() 강제)만 정의한다.

---

### I-2. 모델 다운그레이드 패턴 미문서화

**심각도**: MEDIUM
**위치**: `skills/_shared/agent-routing.md`

agent-routing.md는 기본 model만 정의하고, 의도적 다운그레이드의 허용 조건/기준이 없다.
현재 의도적 다운그레이드 사례:
- `pr-review`: code-reviewer를 opus 대신 sonnet (메모에 기록됨)
- `vplan`: code-reviewer를 opus 대신 sonnet (메모에 기록됨)
- `vqa`: critic을 opus 대신 sonnet (문서화 없음 — C-1)
- `vqa`, `request-to-*` 3개: analyst를 opus 대신 sonnet (문서화 없음 — C-2)

**영향**: 스킬 작성자가 다운그레이드 시 문서화해야 한다는 컨벤션을 알 수 없어 C-1, C-2 같은 비문서화 케이스가 반복 발생한다.

**권장 방향**: agent-routing.md에 "의도적 다운그레이드 규칙: 기본 model과 다른 model 사용 시 스킬 내 주석 또는 메모에 이유를 명시한다" 추가.

---

### I-3. worklog-compact의 resolve-worklog-target 조건부 참조

**심각도**: LOW
**위치**: `skills/worklog/worklog-compact/SKILL.md`

worklog-start, worklog-finish, worklog-amend 등 다른 worklog 스킬들은 `_shared/resolve-worklog-target.md`를 **무조건** 참조한다.
그러나 worklog-compact는 "resolve-worklog-target.md가 존재하는 경우에만" 조건부로 로드한다.

**영향**: compact가 실행될 때 resolve-worklog-target.md 없이 워크로그 탐색을 다르게 처리할 수 있어 동작 불일치 위험이 있다. 해당 파일이 항상 존재하는 한 실질적 영향은 없지만, 일관성을 해친다.

---

### I-4. worklog-finish/worklog-start 내 fallback 절차 중복

**심각도**: LOW
**위치**: `skills/worklog/worklog-finish/SKILL.md`, `skills/worklog/worklog-start/SKILL.md`

두 스킬 모두 resolve-base-branch/create-worktree/create-pr 스킬을 호출할 때 fallback 절차(스킬 없을 시 직접 실행)를 각각 인라인으로 기술한다.
이 fallback 로직이 중복되어 있어 스킬 참조 방식이 변경되면 두 파일 모두 수정해야 한다.

---

## 3. Deprecated/존재하지 않는 의존성

**결론: 발견 없음 (Clean)**

git status에서 `D`(삭제됨)로 표시된 8개 `_shared` 파일:
- `_shared/cleanup-worktree.md`
- `_shared/code-review-gate.md`
- `_shared/create-jira-issue.md`
- `_shared/create-pr.md`
- `_shared/create-worktree.md`
- `_shared/lint-format.md`
- `_shared/print-worktree-summary.md`
- `_shared/resolve-base-branch.md`

이 파일들을 참조하는 스킬이 **0건**임을 Grep으로 확인.
`skill-schema.md`에도 "모두 독립 스킬로 격상됨"이 명시되어 있음.
`_shared/vwork-session-routing.md`는 vwork/vauto에서 정상 참조되며 파일도 존재함.

---

## 우선순위 요약

| ID | 심각도 | 카테고리 | 제목 | 권장 조치 |
|---|---|---|---|---|
| C-1 | HIGH | 모순 | critic 모델 불일치 | vqa에 의도적 다운그레이드 주석 추가 또는 opus로 복원 |
| C-3 | HIGH | 모순 | vauto Skill() 강제 규칙 누락 | vauto 절대규칙에 Skill() 강제 추가 |
| I-1 | HIGH | 비효율 | vwork/vauto 대규모 중복 | _shared/vwork-core.md 추출 검토 |
| C-2 | MEDIUM | 모순 | analyst 모델 불일치 (4건) | 의도 확인 후 문서화 또는 opus 복원 |
| I-2 | MEDIUM | 비효율 | 다운그레이드 패턴 미문서화 | agent-routing.md에 컨벤션 추가 |
| I-3 | LOW | 비효율 | worklog-compact 조건부 참조 | 조건부 제거하여 다른 스킬과 일관성 맞춤 |
| I-4 | LOW | 비효율 | fallback 절차 중복 | 장기적 _shared 통합 검토 |
