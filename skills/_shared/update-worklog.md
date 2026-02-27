# 워크로그 업데이트 (공통 절차)

모든 스킬이 워크로그를 업데이트할 때 반드시 이 절차를 따른다.

## 입력

- `worklog_path`: 워크로그 파일 경로 (`{WORKLOG_DIR}/worklog.md`)
- `dashboard_updates`: Dashboard 블록에 쓸 내용 (Next actions, Blockers/Risks, Decisions)
- `timeline_entry`: 추가할 Timeline 엔트리 (없으면 생략 가능)
- `stable_updates`: Dashboard 밖 섹션 업데이트 (Goal, Completion criteria, Remember, Links — 선택적)
- `phase_update`: phase frontmatter 변경 (선택적 — vwork와 worklog-finish만 사용)

## 워크로그 구조 규칙

```
---
frontmatter (phase, jira, branch, ...)
---

# Task: <name>

## Goal                          ← 안정 섹션 (덮어쓰기 금지)
## Completion criteria           ← 안정 섹션 (덮어쓰기 금지)

<!-- WORKLOG:DASHBOARD:START -->
## Dashboard (always-current)    ← 덮어쓰기 가능
### Next actions
### Blockers / Risks
### Decisions
<!-- WORKLOG:DASHBOARD:END -->

## Remember                      ← 안정 섹션 (절대 삭제/축약 금지)
## Links                         ← 안정 섹션 (누적만 가능, 삭제 금지)

<!-- WORKLOG:TIMELINE:START -->
<!-- WORKLOG:TIMELINE:INSERT:HERE -->
### {최신 엔트리} ← 항상 상세 버전 (현재 작업 중인 세션)
### {이전 엔트리} · [전문](timeline-details/...) ← 압축 버전
### {더 이전 엔트리} · [전문](timeline-details/...)
<!-- WORKLOG:TIMELINE:END -->
```

### 타임라인 엔트리 형식

**상세 버전 (INSERT:HERE 바로 다음 — 가장 최근 엔트리):**
```markdown
### {TIMESTAMP} ({context})

**Summary**

- **Work done**
  - {시도한 것, 탐색 경로, 중간 시도 포함 — 상세히}

- **Evidence**
  - Commands: {실행한 git/bash 명령}
  - Files: {변경/생성된 파일 목록}
  - Tests: {테스트 결과}

- **Problems / Notes**
  - {막힌 지점, 실패한 접근법, 우회 방법}

- **Next**
  - {다음 단계}
```

**압축 버전 (이전 엔트리 — 새 업데이트 시 자동 압축됨):**
```markdown
### {TIMESTAMP} ({context}) · [전문](timeline-details/{TIMESTAMP_FILE}.md)

- **결정**: {핵심 결정사항}
- **구현**: {구현/변경한 것}
- **결과**: {테스트 결과, 성과}
```

## 보호 규칙 (Non-negotiable)

1. **Dashboard 마커 안만 덮어쓰기.** `<!-- WORKLOG:DASHBOARD:START -->` ~ `<!-- WORKLOG:DASHBOARD:END -->` 사이만 교체.
2. **안정 섹션 보존.** Goal, Completion criteria, Remember, Links는 명시적 `stable_updates` 입력이 있을 때만 수정. 그 외에는 절대 건드리지 않음.
3. **Remember 절대 삭제 금지.** 사용자가 명시적으로 요청한 경우에만 제거.
4. **Timeline 엔트리 규칙:**
   - 새 엔트리는 `<!-- WORKLOG:TIMELINE:INSERT:HERE -->` 바로 다음에 삽입.
   - 직전 엔트리(INSERT:HERE 바로 다음)는 새 업데이트 시 압축 가능 (Step 2.5).
   - 압축된 엔트리(`· [전문]` 링크 포함)는 수정/삭제 금지.
5. **Frontmatter phase는 vwork와 worklog-finish만 변경.** 다른 스킬은 `phase_update`를 사용하지 않음.

## 절차

### 1. Git context 수집

업데이트 전 현재 상태를 수집한다:

```bash
TIMESTAMP=$(TZ=${timezone:-UTC} date "+%Y-%m-%d %H:%M")  # timezone은 rules/project-params.md 참조, 미설정 시 UTC
BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_STATUS=$(git status -sb)
GIT_DIFF_STAT=$(git diff --stat)
RECENT_COMMITS=$(git log -5 --oneline --no-decorate)
```

이 정보는 Timeline 엔트리의 Evidence에 포함한다.

### 2. Dashboard 블록 생성

`dashboard_updates` 입력으로 새 Dashboard 블록을 구성한다:

```markdown
<!-- WORKLOG:DASHBOARD:START -->

## Dashboard (always-current)

### Next actions

{next_actions — 3~7개 checkbox 항목}

### Blockers / Risks

{blockers}

### Decisions

{decisions}

<!-- WORKLOG:DASHBOARD:END -->
```

### 2.5. 직전 타임라인 엔트리 압축

`timeline_entry` 입력이 있고 타임라인에 기존 엔트리가 있는 경우에만 실행한다.

**탐지:**

1. worklog.md를 읽어 `<!-- WORKLOG:TIMELINE:INSERT:HERE -->` 직후의 첫 번째 `###` 엔트리를 찾는다.
2. 해당 엔트리에 `· [전문]` 링크가 이미 있으면 → 이미 압축된 것이므로 건너뜀.
3. 상세 버전이면 → 아래 압축 절차를 실행한다.

**압축 절차:**

1. 엔트리 헤더에서 타임스탬프 추출 (예: `2026-02-27 15:30`)
2. 타임스탬프를 파일명으로 변환: `YYYY-MM-DD-HH-MM` (예: `2026-02-27-15-30`)
3. `{WORKLOG_DIR}/timeline-details/` 디렉토리 생성 (없으면)
4. 전문을 `{WORKLOG_DIR}/timeline-details/{TIMESTAMP_FILE}.md`에 저장:
   ```markdown
   # Timeline Detail: {원본 엔트리 헤더}

   {원본 엔트리 전체 내용 그대로}
   ```
5. 워크로그의 해당 엔트리를 압축 버전으로 교체:
   ```markdown
   ### {TIMESTAMP} ({context}) · [전문](timeline-details/{TIMESTAMP_FILE}.md)

   - **결정**: {Work done + Decisions에서 핵심 결정사항 추출}
   - **구현**: {변경/생성된 파일, 주요 구현 내용}
   - **결과**: {Evidence의 테스트 결과 및 성과}
   ```
   압축 요약은 3~6줄 이내로 핵심만 남긴다.

**방법 A (python 스크립트 — 우선):** 스크립트가 존재하면 `--compact-previous` 플래그와 함께 실행.

**방법 B (Edit fallback):** Edit 도구로 직전 엔트리 구간을 압축 버전으로 직접 교체.

### 3. Timeline 엔트리 생성 (상세 버전)

`timeline_entry` 입력이 있으면 아래 형식으로 **최대한 상세하게** 구성한다:

```markdown
### {TIMESTAMP}{timestamp_suffix} ({context — e.g., "Phase: IMPL", "QA Report", "Session Resume"})

**Summary**

- **Work done**
  - {수행한 작업을 단계별로 상세히 — 시도한 접근법, 탐색 경로, 중간 과정 포함}
  - {실패한 시도도 포함 (나중에 참고가 됨)}

- **Evidence**
  - Commands: {실행한 명령어들}
  - Files: {변경/생성된 파일 목록}
  - Tests: {테스트 실행 결과 — 통과/실패 수, 커버리지 등}

**Problems / Notes**

- {막힌 지점, 예상과 다른 동작, 임시 우회 방법}

- **Next**

- {다음에 해야 할 구체적인 작업}
```

**상세 작성 기준:**
- Work done: 단순 결과가 아닌 **과정** 포함. "X를 구현함" 대신 "A 방법 시도 → 실패(이유), B 방법으로 전환 → X 구현 완료"처럼 작성.
- Evidence: 명령어 출력 중 핵심 수치/결과를 직접 인용.
- Problems: 해결하지 못한 문제와 알게 된 제약조건 명시.

### 4. 안정 섹션 업데이트 (선택적)

`stable_updates`가 제공된 경우에만:
- Goal, Completion criteria, Remember, Links 중 지정된 섹션만 업데이트
- 지정되지 않은 섹션은 건드리지 않음

### 5. Phase 업데이트 (선택적)

`phase_update`가 제공된 경우에만 frontmatter의 `phase` 필드를 변경.

### 6. 적용

**방법 A (python 스크립트 — 우선):**

```bash
# Dashboard와 Timeline을 임시 파일로 생성
# .dashboard.tmp.md: WORKLOG:DASHBOARD:START ~ END 전체
# .timeline.tmp.md: 새 Timeline 엔트리 1개

# 스크립트 경로 해결: 프로젝트 설치 → 사용자 설치 → 없으면 Method B 사용
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")
SCRIPT="$REPO_ROOT/.claude/skills/_templates/worklog/apply_worklog_update.py"
if [[ ! -f "$SCRIPT" ]]; then
  SCRIPT="$HOME/.claude/skills/_templates/worklog/apply_worklog_update.py"
fi
if [[ ! -f "$SCRIPT" ]]; then
  # Method B (Edit fallback) 사용
  echo "Python script not found, using Edit fallback"
else
  python "$SCRIPT" \
    --worklog "{worklog_path}" \
    --dashboard-file "$(dirname "{worklog_path}")/.dashboard.tmp.md" \
    --timeline-file "$(dirname "{worklog_path}")/.timeline.tmp.md" \
    --compact-previous  # Step 2.5 실행
  # 임시 파일 삭제
fi
```

**방법 B (Edit fallback — 스크립트 없을 때):**

1. Step 2.5: 직전 엔트리를 압축 버전으로 Edit 교체 (해당하는 경우)
2. Edit 도구로 `<!-- WORKLOG:DASHBOARD:START -->` ~ `<!-- WORKLOG:DASHBOARD:END -->` 구간을 새 Dashboard 블록으로 교체
3. Edit 도구로 `<!-- WORKLOG:TIMELINE:INSERT:HERE -->` 바로 다음에 새 상세 Timeline 엔트리 삽입
4. 안정 섹션/phase는 필요 시 별도 Edit

## 반환값

- 업데이트된 워크로그 파일 경로
- 현재 phase 값
