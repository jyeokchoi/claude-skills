# PRD: 스킬 감사 개선

> 생성일: 2026-03-06
> 기반: `.claude/worklogs/skill-audit-improvement/analysis.md`
> 스코프: C-1, C-2, C-3, I-2, I-3 (5건)
> 제외: I-1 (vwork/vauto DRY — 별도 대규모 리팩토링), I-4 (fallback 중복 — 장기 과제)

---

## 요구사항 목록

### REQ-1: vqa critic 에이전트 모델 불일치 해소 (C-1)

**문제**: `skills/workflow/vqa/SKILL.md:82`에서 critic을 `model="sonnet"`으로 호출하지만, `skills/_shared/agent-routing.md:15`는 critic의 기본 model을 `opus`로 정의한다. 의도적 다운그레이드라면 문서화가 없다.

**요구사항**: critic 호출을 `model="opus"`로 복원하거나, 의도적 다운그레이드라면 인라인 주석으로 이유를 명시한다.

**수정 대상**:
- `skills/workflow/vqa/SKILL.md` — 82행 (`Task(subagent_type="oh-my-claudecode:critic", model="sonnet", ...)`)

**수용 기준**:
1. vqa/SKILL.md:82의 critic 호출이 `model="opus"`이거나, `model="sonnet"` + 다운그레이드 사유 주석이 존재한다.
2. agent-routing.md의 critic 기본 model(`opus`)과 일치하거나, REQ-4에서 정의할 다운그레이드 컨벤션을 따른다.

---

### REQ-2: vqa/request-to-* analyst 에이전트 모델 불일치 해소 (C-2)

**문제**: 4개 스킬 파일에서 analyst를 `model="sonnet"`으로 호출하지만, `skills/_shared/agent-routing.md:23`은 analyst의 기본 model을 `opus`로 정의한다. 4개 파일 모두 동일한 패턴이므로 의도적 다운그레이드 가능성이 높으나 문서화가 없다.

**요구사항**: 각 호출을 `model="opus"`로 복원하거나, 의도적 다운그레이드라면 인라인 주석으로 이유를 명시한다.

**수정 대상** (4개 파일):
- `skills/workflow/vqa/SKILL.md` — 153행 (Agent 3: Test Verification)
- `skills/request/request-to-ux-researcher/SKILL.md` — 34행 (Phase 1)
- `skills/request/request-to-qa/SKILL.md` — 133행 (Agent 3)
- `skills/request/request-to-designer/SKILL.md` — 37행 (Phase 1)

**수용 기준**:
1. 4개 파일 모두에서 analyst 호출이 `model="opus"`이거나, `model="sonnet"` + 다운그레이드 사유 주석이 존재한다.
2. 4개 파일의 처리 방식이 일관적이다 (전부 복원 또는 전부 문서화).

---

### REQ-3: vauto 절대 규칙에 Skill() 강제 규칙 추가 (C-3)

**문제**: `skills/workflow/vwork/SKILL.md:446`에는 `/worklog-start`와 `/worklog-finish`를 반드시 `Skill()` 도구로 호출하라는 절대 규칙이 존재한다. 그러나 `skills/workflow/vauto/SKILL.md`의 절대 규칙 섹션(403~418행)에는 이 규칙이 누락되어 있다.

**요구사항**: vauto/SKILL.md의 절대 규칙 섹션에 vwork와 동일한 Skill() 강제 규칙을 추가한다.

**수정 대상**:
- `skills/workflow/vauto/SKILL.md` — 절대 규칙 섹션 (403~418행 부근)

**추가할 규칙 (vwork:446 기준)**:
```
- **`/worklog-start`와 `/worklog-finish`를 반드시 Skill 도구로 호출한다.** 워크로그 생성은 `Skill("worklog-start", ...)`로, 워크플로우 마무리는 `Skill("worklog-finish", ...)`로만 수행한다. Write/Edit/Bash로 워크로그를 수동 생성하거나, commit/push/PR/Jira/Gist/worktree 정리를 직접 수행하지 않는다.
```

**수용 기준**:
1. vauto/SKILL.md의 절대 규칙 섹션에 Skill() 강제 규칙이 존재한다.
2. 규칙 내용이 vwork/SKILL.md:446과 실질적으로 동일하다.
3. "이제 실행하라." 마커 앞에 위치한다.

---

### REQ-4: agent-routing.md에 의도적 다운그레이드 컨벤션 문서화 (I-2)

**문제**: `skills/_shared/agent-routing.md`는 에이전트별 기본 model만 정의하고, 스킬에서 기본 model과 다른 model을 사용할 때의 규칙이 없다. 이로 인해 C-1, C-2 같은 비문서화 다운그레이드가 반복 발생한다.

**기존 의도적 다운그레이드 사례** (참조):
- `pr-review`: code-reviewer를 opus 대신 sonnet (메모에 기록됨)
- `vplan`: code-reviewer를 opus 대신 sonnet (메모에 기록됨)

**요구사항**: agent-routing.md에 "의도적 모델 오버라이드 규칙" 섹션을 추가한다.

**수정 대상**:
- `skills/_shared/agent-routing.md` — 새로운 섹션 추가 (기존 "스킬에서의 사용법" 섹션 뒤)

**추가할 내용 (핵심)**:
- 기본 model과 다른 model을 사용하는 경우, 호출 코드 근처에 인라인 주석으로 다운그레이드/업그레이드 사유를 명시해야 한다.
- 주석 형식 예시: `# 의도적 다운그레이드: {사유}` 또는 `<!-- downgrade: {사유} -->`

**수용 기준**:
1. agent-routing.md에 모델 오버라이드 규칙 섹션이 존재한다.
2. "기본 model과 다른 model 사용 시 사유 명시" 규칙이 명확히 기술되어 있다.
3. 주석 형식 예시가 포함되어 있다.

---

### REQ-5: worklog-compact의 resolve-worklog-target 조건부 참조 제거 (I-3)

**문제**: `skills/worklog/worklog-compact/SKILL.md:43-44`에서 `_shared/resolve-worklog-target.md`를 "존재하는 경우에만" 조건부로 로드한다. 다른 worklog 스킬(worklog-start, worklog-finish, worklog-amend)은 모두 무조건 참조한다. resolve-worklog-target.md는 현재 독립 스킬로 격상되어 항상 존재하므로 조건부 분기가 불필요하다.

**수정 대상**:
- `skills/worklog/worklog-compact/SKILL.md` — Step 1 워크로그 탐색 (43~50행)

**현재 코드** (43-50행):
```markdown
- `_shared/resolve-worklog-target.md`가 존재하는 경우:
  > **Shared**: `_shared/resolve-worklog-target.md` 절차를 따른다. (`required_files`: 없음)
- 없는 경우 폴백:
  - $ARGUMENTS가 경로이면 해당 경로 사용
  - 없으면 활성 워크로그 자동 탐색:
```

**변경 후**:
```markdown
- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다 (`required_files`: 없음).
```

조건부 분기와 폴백 로직을 제거하고, 다른 worklog 스킬과 동일한 무조건 참조 패턴으로 통일한다.

**수용 기준**:
1. worklog-compact/SKILL.md의 Step 1에서 resolve-worklog-target.md를 무조건 참조한다.
2. "존재하는 경우" 조건부 분기와 폴백 로직이 제거되었다.
3. 다른 worklog 스킬(worklog-start 등)의 참조 패턴과 일관적이다.

---

## 영향 파일 목록 (전체)

| REQ | 파일 경로 | 수정 유형 |
|-----|----------|----------|
| REQ-1 | `skills/workflow/vqa/SKILL.md` | model 변경 또는 주석 추가 |
| REQ-2 | `skills/workflow/vqa/SKILL.md` | model 변경 또는 주석 추가 |
| REQ-2 | `skills/request/request-to-ux-researcher/SKILL.md` | model 변경 또는 주석 추가 |
| REQ-2 | `skills/request/request-to-qa/SKILL.md` | model 변경 또는 주석 추가 |
| REQ-2 | `skills/request/request-to-designer/SKILL.md` | model 변경 또는 주석 추가 |
| REQ-3 | `skills/workflow/vauto/SKILL.md` | 절대 규칙 항목 추가 |
| REQ-4 | `skills/_shared/agent-routing.md` | 새 섹션 추가 |
| REQ-5 | `skills/worklog/worklog-compact/SKILL.md` | Step 1 로직 단순화 |

**총 수정 파일**: 7개 (vqa/SKILL.md는 REQ-1, REQ-2 공통)

---

## 의존성 및 실행 순서

- **REQ-4를 먼저 실행**: 다운그레이드 컨벤션이 정의되어야 REQ-1, REQ-2에서 "문서화" 경로를 선택할 수 있다.
- **REQ-1, REQ-2**: REQ-4 완료 후 실행. 둘은 독립적이므로 병렬 가능 (단 vqa/SKILL.md 동시 수정 주의).
- **REQ-3, REQ-5**: 독립적. 다른 REQ와 병렬 가능.

권장 순서: `REQ-4 → (REQ-1 + REQ-2) → REQ-3 + REQ-5` (또는 REQ-3, REQ-5는 아무 때나)

---

## 미결정 사항

REQ-1, REQ-2에서 "opus 복원" vs "sonnet 유지 + 문서화" 결정이 필요하다. 이는 executor가 구현 시 사용자에게 확인받아야 한다.

- **복원 근거**: agent-routing.md 기본값 준수, critic/analyst는 깊은 분석이 필요한 역할
- **유지 근거**: 4개 파일에서 동일 패턴 사용 → 비용/속도 최적화 의도 가능성. vqa의 critic은 read-only 검증용이므로 sonnet으로 충분할 수 있음
