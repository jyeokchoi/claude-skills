---
name: request-to-designer
description: 워크로그 기반으로 디자이너에게 UI 검토 요청 보고서를 생성하고 Jira에 첨부한다
argument-hint: 'Usage: /request-to-designer [worklog-folder-or-worklog.md]'
---

## 경로 규칙

> **`_shared/X`** → `{Base directory}/../_shared/X` (`{Base directory}`는 시스템이 주입하는 "Base directory for this skill" 값)
> **`X` 스킬** → 스킬 시스템이 제공하는 경로. `Glob("**/X/SKILL.md")`로 탐색 가능.

워크로그의 변경 내용을 분석하여 디자이너가 검토해야 할 UI 변경사항을 정리한 보고서를 생성한다. vbrowser로 실제 앱 스크린샷을 캡처하고, Jira에 첨부할 수 있는 형태로 출력한다.

## 대상 결정

- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다.
- worklog.md에서 `jira` 필드를 추출한다 (Jira 첨부용).

## Phase 0: 컨텍스트 수집

1. worklog.md 읽기 → Goal, Completion criteria, Decisions
2. `resolve-base-branch` 스킬의 절차를 따라 `BASE_REF`를 설정한다.
3. 변경 파일 수집:
   ```bash
   git diff {BASE_REF}...HEAD --name-only
   ```
4. UI 관련 파일 필터링:
   - `*.tsx` (컴포넌트)
   - `*.scss` / `*.css` (스타일)
   - `*.svg` / `*.png` (아이콘/에셋)
   - `constants/icon*.ts`, `constants/featureIcon*.ts` (아이콘 상수)
5. 필터링된 파일이 0개이면 사용자에게 보고하고 중단.

## Phase 1: UI 변경 분석 (에이전트 위임)

```
Task(subagent_type="oh-my-claudecode:analyst", model="opus",
     prompt="
Read-only 분석 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

변경된 UI 파일을 분석하여 디자이너 검토 항목을 분류한다.

## Your Task

다음 카테고리로 변경사항을 분류:

1. **새로 추가된 UI 컴포넌트**: 파일 경로, 역할, 앱 내 위치
2. **기존 UI 수정**: 무엇이 어떻게 바뀌었는지 (before/after 설명)
3. **새 아이콘/에셋**: 파일 경로, 용도, 임시 여부 판별 (파일명에 tmp/placeholder/ic_ 등, 또는 worklog에 '임시' 언급)
4. **레이아웃/스타일 변경**: scss diff 기반 변경 설명
5. **디자이너 검토 필요 항목**: 색상, 크기, 간격, 아이콘 교체, 인터랙션 등

각 항목에 대해 앱 내에서 해당 UI를 확인할 수 있는 경로/방법도 기술한다 (스크린샷 캡처 가이드용).

## Worklog Context
{worklog content}

## Changed UI Files
{UI 관련 변경 파일 목록 + diff}

## Output Format
### 새로 추가된 UI
- **{컴포넌트명}**: {파일:라인} — {역할} — 앱 내 위치: {어디서 보이는지}

### 기존 UI 수정
- **{컴포넌트명}**: {파일:라인} — {변경 내용} — 앱 내 위치: {어디서 보이는지}

### 아이콘/에셋
| 파일 | 용도 | 임시 여부 | 비고 |

### 스타일 변경
- {파일}: {변경 설명}

### 디자이너 검토 포인트
- {구체적 검토 항목}: {이유}

### 스크린샷 캡처 가이드
- 사진{N}: {앱 내 경로/조작} — {무엇을 캡처해야 하는지}
")
```

## Phase 2: 스크린샷 수집 (vbrowser)

Phase 1의 "스크린샷 캡처 가이드"를 따라 vbrowser로 앱 스크린샷을 캡처한다.

1. 스크린샷 저장 디렉토리 생성:
   ```bash
   SCREENSHOT_DIR="{WORKLOG_DIR}/attachments/designer"
   mkdir -p "$SCREENSHOT_DIR"
   ```

2. `Skill("vbrowser")`를 명시적으로 호출하여 앱에 연결하고, 캡처 가이드의 각 항목에 대해 스크린샷을 캡처한다.
   - vbrowser 스킬 호출 시 인자로 캡처 가이드 목록과 저장 디렉토리를 전달한다.
   - 파일명은 사진{N}.png 형식을 따른다.

3. vbrowser 연결 실패 또는 앱 접근 불가 시, 자체 판단으로 SKIP하지 않고 반드시 AskUserQuestion으로 사용자에게 확인한다:
   ```
   AskUserQuestion:
     question: "vbrowser로 앱에 연결할 수 없습니다. 어떻게 진행할까요?"
     header: "스크린샷"
     options:
       - label: "앱 URL 직접 입력"
         description: "앱이 실행 중인 URL을 직접 입력하여 재시도"
       - label: "스크린샷 건너뛰기"
         description: "스크린샷 없이 보고서만 생성"
       - label: "중단"
         description: "스킬 실행을 중단하고 앱을 먼저 실행"
   ```
   - "앱 URL 직접 입력" 선택 시: 사용자가 입력한 URL로 vbrowser 재연결 시도
   - "스크린샷 건너뛰기" 선택 시: Phase 3으로 진행 (보고서에 "스크린샷 미첨부" 표기)
   - "중단" 선택 시: 스킬 실행 중단

4. 개별 캡처 실패 시: 해당 항목을 SKIP으로 기록하고 다음으로 진행.

## Phase 3: 보고서 생성

`{WORKLOG_DIR}/attachments/designer-report.md`에 작성:

```markdown
# 디자인 검토 요청: {task-name}

**Date:** {timestamp}
**Jira:** {jira_url}
**Branch:** {branch_name}

## 요약
{전체 UI 변경 한 줄 요약}

## 새로 추가된 UI

### {컴포넌트명}
- **파일**: {file:line}
- **위치**: {앱 내 어디에서 보이는지}
- **스크린샷**: 사진{N}
- **디자인 검토 포인트**: {색상/크기/레이아웃/인터랙션 등}

## 수정된 UI

### {컴포넌트명}
- **변경 내용**: {무엇이 바뀌었는지}
- **스크린샷**: 사진{N}

## 아이콘/에셋

| 파일 | 용도 | 임시 여부 | 비고 |
|------|------|----------|------|
| {svg path} | {어디서 사용} | 임시 | 정식 아이콘 필요 |

## 스타일 변경
- {파일}: {변경 설명}

## 디자이너 액션 아이템
- [ ] {구체적 요청 1}
- [ ] {구체적 요청 2}
```

## Phase 4: 배포

1. 스크린샷 zip 압축:
   ```bash
   cd "{WORKLOG_DIR}/attachments"
   zip -j designer-screenshots.zip designer/*.png
   ```

2. 보고서 Gist 업로드:
   ```bash
   GIST_URL=$(gh gist create --filename designer-report.md "{WORKLOG_DIR}/attachments/designer-report.md" 2>/dev/null)
   ```

3. Jira 코멘트 추가 (`addCommentToJiraIssue`):
   ```
   디자인 검토 요청 보고서: {GIST_URL}
   ```

4. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `timeline_entry`: "디자인 검토 요청 보고서 생성 — 사진 {N}장"

5. 사용자에게 안내:
   ```
   보고서: {GIST_URL}
   스크린샷 zip: {WORKLOG_DIR}/attachments/designer-screenshots.zip
   → Jira에 zip 파일을 수동으로 첨부해주세요: {jira_url}
   ```

## 절대 규칙

- **분석 에이전트는 read-only.** Write/Edit/Bash를 사용하지 않는다.
- **스크린샷 파일명은 사진1.png, 사진2.png, ... 형식을 따른다.**
- **보고서 내 스크린샷 참조는 "사진{N}" 텍스트로 한다.**
- **Phase 2에서 자체 판단으로 전체 SKIP 금지.** vbrowser 연결 실패 시 반드시 AskUserQuestion으로 사용자에게 확인한다.
- **vbrowser는 반드시 `Skill("vbrowser")`로 명시적 호출한다.** 내부 절차를 임의로 따르거나 생략하지 않는다.
- **개별 캡처 실패 시 SKIP 처리.** 2-3회 연속 실패하면 해당 항목을 건너뛴다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
