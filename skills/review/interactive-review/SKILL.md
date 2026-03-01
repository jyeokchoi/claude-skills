---
name: interactive-review
description: 파일별 인터랙티브 코드 리뷰. explain-code로 리뷰 순서를 결정한 뒤 state 파일로 진행 상황을 추적한다. 중단 후 재개 가능.
argument-hint: 'Usage: /interactive-review [--reset] [base-branch]'
---

# 인터랙티브 코드 리뷰

## 개요

`explain-code`로 리뷰 순서를 결정하고, state 파일로 진행 상황을 추적하며 파일 하나씩 인터랙티브하게 리뷰한다. 중단 후 재개하면 마지막으로 리뷰한 파일 다음부터 이어서 진행한다.

## 입력

- 원본 인자: $ARGUMENTS
- `--reset`: 기존 state 파일을 삭제하고 처음부터 재시작
- `base-branch`: diff 기준 브랜치 (생략 시 `rules/project-params.md` → 자동 탐지)

## State 파일

state 파일 경로: `.claude/interactive-review/state.md`

state 파일 형식:
```markdown
# Interactive Review State

Created: {YYYY-MM-DD}
Branch: {current-branch}
Base: {base-branch}
Files: {total}/{checked}

## 리뷰 체크리스트

- [x] src/auth/login.ts — 인증 진입점, 가장 먼저
- [ ] src/auth/session.ts — login.ts에 의존
- [ ] src/api/user.ts — session에 의존
```

## 절차

### 1. State 확인

**`--reset` 플래그가 있는 경우:**
- 기존 state 파일 삭제
- Step 2 (신규 시작)로 진행

**State 파일이 존재하는 경우 (재개):**
- state 파일을 읽어 체크리스트 파싱
- 체크되지 않은 첫 번째 파일 확인
- 상태 요약 출력:
  ```
  인터랙티브 리뷰 재개
  브랜치: {branch} ← {base}
  진행: {checked}/{total} 파일 완료
  다음 파일: {next-file}
  ```
- Step 4 (파일 리뷰)로 직접 점프

**State 파일이 없는 경우:**
- Step 2로 진행

### 2. 리뷰 범위 결정 (신규 시작)

base-branch 결정 순서:
1. 인자에 `base-branch`가 있으면 사용
2. `rules/project-params.md`에 `base_branch`가 있으면 사용
3. `gh repo view --json defaultBranchRef`로 자동 탐지
4. 실패 시 사용자에게 질문

```bash
git diff --stat {base-branch}..HEAD
```

변경된 파일이 없으면 "변경된 파일이 없습니다." 출력 후 종료.

### 3. explain-code 실행 및 State 생성

`/explain-code`를 실행하여 리뷰 순서를 얻는다.

`explain-code`의 "추천 리뷰 순서" 출력을 파싱하여 state 파일을 생성한다:
```
Write(".claude/interactive-review/state.md", ...)
```

state 파일에 포함할 정보:
- 생성 날짜, 현재 브랜치, base 브랜치
- 체크리스트: `- [ ] {파일경로} — {리뷰 순서 이유}`

state 파일 생성 후 Step 4로 진행.

### 4. 파일 리뷰

체크되지 않은 다음 파일(`{next-file}`)을 오케스트레이터가 직접 읽어 내용을 수집한 뒤, `code-reviewer` subagent에게 위임한다. 오케스트레이터는 결과만 수신한다.

**오케스트레이터가 파일 내용 수집:**
```
file_content = Read("{next-file}")
```

**subagent에게 위임:**

```python
Task(
  subagent_type="oh-my-claudecode:code-reviewer",
  model="sonnet",
  prompt="""
다음 파일을 코드 리뷰하라.

## 파일 경로
{next-file}

## 파일 내용
{file_content}

## 리뷰 기준

아래 5가지 관점에서 검토하고, 발견 사항을 심각도(CRITICAL / HIGH / MEDIUM / LOW)와 함께 출력하라.

| 관점 | 체크 항목 |
|------|----------|
| 정확성 | 로직 오류, null/undefined 처리, 경계값, 비동기 취소·오류 경로, 레이스 컨디션 |
| 구조 | 파일 간 중복 로직(3회 이상 반복), 모듈 경계 침범, 추상화 과다·부족 |
| 일관성 | 코드베이스 컨벤션 준수, 명명 일관성, 인접 기능과의 패턴 일치 |
| 보안 | 입력 검증 누락, 인증·인가 우회, 민감 정보 노출 |
| 유지보수 | 복잡도, 가독성, 테스트 가능성, 외부에서 관찰 가능한 동작 커버 여부 |

## 출력 형식

### 발견 사항

- **[CRITICAL]** {제목}
  - 위치: {line 참조}
  - 문제: {설명}
  - 제안: {수정 방법}

- **[HIGH]** ...
- **[MEDIUM]** ...
- **[LOW]** ...

### 긍정적 패턴
- {잘 된 점}

### 종합 의견
{한두 문장 요약}

발견 사항이 없으면: "발견 사항 없음. 코드가 양호합니다."

IMPORTANT: Do NOT use Bash, Glob, or Grep. 제공된 파일 내용만으로 리뷰하라.
"""
)
```

subagent 결과를 수신하여 사용자에게 그대로 출력한다.

**State 업데이트:**

리뷰 완료 후 해당 파일을 체크 표시로 업데이트한다:
```
- [x] {파일경로} — {이유}
```

### 5. 다음 파일 진행 여부 확인

```
AskUserQuestion:
  question: "다음 파일로 진행할까요? ({checked+1}/{total}: {next-file})"
  header: "리뷰 진행"
  options:
    - label: "계속"
      description: "다음 파일을 리뷰합니다"
    - label: "이 파일 다시 보기"
      description: "현재 파일에 대해 추가로 논의합니다"
    - label: "여기서 중단"
      description: "state 파일에 저장하고 나중에 이어서 진행합니다"
```

- "계속": Step 4로 돌아가 다음 파일 리뷰
- "이 파일 다시 보기": 사용자 질문을 받아 현재 파일에 대해 추가 논의, 완료 후 다시 이 질문
- "여기서 중단": "중단됩니다. `/interactive-review`로 재개할 수 있습니다." 출력 후 종료

체크되지 않은 파일이 더 없으면 Step 6으로 진행 (질문 생략).

### 6. 리뷰 완료

모든 파일을 리뷰했을 때:

```markdown
## 인터랙티브 리뷰 완료

총 {N}개 파일 리뷰 완료.

### 심각도별 요약
- CRITICAL: {count}건
- HIGH: {count}건
- MEDIUM: {count}건
- LOW: {count}건

### 주요 발견 사항 (HIGH 이상)
{CRITICAL/HIGH 항목 목록}

### 다음 단계 제안
{이슈가 없으면: "코드 품질이 양호합니다."}
{이슈가 있으면: "HIGH 이상 이슈를 수정한 뒤 PR을 올리는 것을 권장합니다."}
```

state 파일을 삭제한다:
```bash
rm .claude/interactive-review/state.md
```

## 에러 처리

| 상황 | 처리 |
|------|------|
| 변경 파일 없음 | "변경된 파일이 없습니다." 출력 후 종료 |
| explain-code 실행 실패 | 변경 파일 목록에서 직접 체크리스트 생성 (파일명 기준 정렬) |
| 파일 읽기 실패 | "[파일 읽기 실패]" 표시 후 다음 파일로 이동, state에서 SKIP 표시 |
| state 파일 파싱 실패 | 사용자에게 알리고 `--reset`으로 재시작할 것을 권유 |

## 절대 규칙

- **state 파일이 진실 기준**: 리뷰 진행 상황은 항상 state 파일에서 읽고 쓴다.
- **파일 하나씩**: 모든 파일을 한꺼번에 리뷰하지 않는다. 사용자가 각 파일을 소화하고 질문할 수 있도록 하나씩 진행한다.
- **재개 우선**: state 파일이 있으면 항상 재개 경로로 진입한다. `--reset` 없이는 처음부터 시작하지 않는다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조
