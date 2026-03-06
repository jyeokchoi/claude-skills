---
name: request-to-ux-researcher
description: 워크로그 기반으로 UX writer에게 신규 문자열 검토 요청 보고서를 생성하고 Jira에 첨부한다
argument-hint: 'Usage: /request-to-ux-researcher [worklog-folder-or-worklog.md]'
---

## 경로 규칙

> **`_shared/X`** → `{Base directory}/../_shared/X` (`{Base directory}`는 시스템이 주입하는 "Base directory for this skill" 값)
> **`X` 스킬** → 스킬 시스템이 제공하는 경로. `Glob("**/X/SKILL.md")`로 탐색 가능.

워크로그의 변경 내용을 분석하여 새로 추가된 i18n 문자열이 앱 내 어디에서 어떤 맥락으로 사용되는지 정리한 보고서를 생성한다. vbrowser로 실제 앱에서 문자열이 표시되는 화면의 스크린샷을 캡처하고, Jira에 첨부할 수 있는 형태로 출력한다.

## 대상 결정

- `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다.
- worklog.md에서 `jira` 필드를 추출한다 (Jira 첨부용).

## Phase 0: 컨텍스트 수집

1. worklog.md 읽기 → Goal, Completion criteria
2. `resolve-base-branch` 스킬의 절차를 따라 `BASE_REF`를 설정한다.
3. diff에서 새로 추가된 번역 키 추출:
   ```bash
   git diff {BASE_REF}...HEAD -- '*.ts' '*.tsx' | grep "^+" | grep -oE "t\(['\"][^'\"]+['\"]\)" | sort -u
   ```
4. 추가로 Grep으로 `useTranslation`, `t('`, `t("` 패턴을 변경 파일에서 검색하여 누락된 키를 보완한다.
5. 각 키가 사용된 컴포넌트 파일과 라인을 Grep으로 식별한다.
6. 신규 키가 0개이면 사용자에게 보고하고 중단.

## Phase 1: 문자열 맥락 분석 (에이전트 위임)

```
Task(subagent_type="oh-my-claudecode:analyst", model="opus",
     prompt="
Read-only 분석 에이전트. Read, Glob, Grep으로 코드를 직접 탐색할 수 있다. Write, Edit, Bash는 사용하지 않는다.

새로 추가된 번역 키의 맥락을 분석한다.

## Your Task

각 번역 키에 대해 다음을 분석:

1. **UI 유형 분류**: 버튼 라벨 / 툴팁 / 메뉴 항목 / 드롭다운 옵션 / 설명 텍스트 / 에러 메시지 / 대화상자 / 토스트 / 기타
2. **사용 위치**: 어떤 컴포넌트에서, 앱 내 어떤 화면에서 보이는지
3. **사용자 컨텍스트**: 사용자가 어떤 상황/흐름에서 이 문자열을 보게 되는지
4. **주변 문자열**: 같은 영역에서 사용되는 기존 번역 키/텍스트 (톤 참고용)
5. **조건부 표시 여부**: 항상 보이는지, 특정 조건에서만 보이는지 (호버, 클릭, 설정 변경 등)
6. **스크린샷 캡처 가이드**: 이 문자열을 화면에 표시하려면 앱에서 어떤 조작이 필요한지

## Translation Keys
{키 목록 + 사용된 파일:라인}

## Worklog Context
{worklog content}

## Output Format
### 문자열 분석

#### 1. `{key}`
- **현재 텍스트**: {코드에서 추출한 기본값 또는 키}
- **UI 유형**: {분류}
- **사용 위치**: {컴포넌트} → {화면 내 위치}
- **사용자 컨텍스트**: {상황 설명}
- **주변 문자열**: {기존 텍스트 예시}
- **조건부 표시**: {항상/조건 설명}
- **캡처 가이드**: 사진{N} — {앱 내 경로/조작} — {무엇을 캡처}
")
```

## Phase 2: 스크린샷 수집 (vbrowser)

Phase 1의 "캡처 가이드"를 따라 vbrowser로 앱 스크린샷을 캡처한다.

1. 스크린샷 저장 디렉토리 생성:
   ```bash
   SCREENSHOT_DIR="{WORKLOG_DIR}/attachments/ux-writer"
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

`{WORKLOG_DIR}/attachments/ux-writer-report.md`에 작성:

```markdown
# UX Writing 검토 요청: {task-name}

**Date:** {timestamp}
**Jira:** {jira_url}
**총 신규 문자열**: {N}개

## 문자열 목록

### 1. `{translation_key}`
- **현재 텍스트**: "{default_text}"
- **UI 유형**: {버튼 라벨 / 툴팁 / 메뉴 항목 / ...}
- **사용 위치**: {컴포넌트 → 화면 내 위치 설명}
- **사용자 컨텍스트**: {어떤 상황에서 보게 되는지}
- **스크린샷**: 사진{N}
- **코드 위치**: {file:line}
- **주변 문자열**: {같은 영역의 기존 문자열 예시}

### 2. `{translation_key}`
...

## UX Writer 액션 아이템
- [ ] {N}개 문자열 검토 및 Lokalise 등록
- [ ] 톤/보이스 일관성 확인
- [ ] 다국어 번역 길이 고려 (UI 레이아웃 영향)
```

## Phase 4: 배포

1. 스크린샷 zip 압축:
   ```bash
   cd "{WORKLOG_DIR}/attachments"
   zip -j ux-writer-screenshots.zip ux-writer/*.png
   ```

2. 보고서 Gist 업로드:
   ```bash
   GIST_URL=$(gh gist create --filename ux-writer-report.md "{WORKLOG_DIR}/attachments/ux-writer-report.md" 2>/dev/null)
   ```

3. Jira 코멘트 추가 (`addCommentToJiraIssue`):
   ```
   UX Writing 검토 요청 보고서: {GIST_URL}
   ```

4. `_shared/update-worklog.md`를 통해 워크로그 업데이트:
   - `timeline_entry`: "UX Writing 검토 요청 보고서 생성 — 신규 문자열 {N}개, 사진 {M}장"

5. 사용자에게 안내:
   ```
   보고서: {GIST_URL}
   스크린샷 zip: {WORKLOG_DIR}/attachments/ux-writer-screenshots.zip
   → Jira에 zip 파일을 수동으로 첨부해주세요: {jira_url}
   ```

## 절대 규칙

- **분석 에이전트는 read-only.** Write/Edit/Bash를 사용하지 않는다.
- **스크린샷 파일명은 사진1.png, 사진2.png, ... 형식을 따른다.**
- **보고서 내 스크린샷 참조는 "사진{N}" 텍스트로 한다.**
- **Phase 2에서 자체 판단으로 전체 SKIP 금지.** vbrowser 연결 실패 시 반드시 AskUserQuestion으로 사용자에게 확인한다.
- **vbrowser는 반드시 `Skill("vbrowser")`로 명시적 호출한다.** 내부 절차를 임의로 따르거나 생략하지 않는다.
- **개별 캡처 실패 시 SKIP 처리.** 2-3회 연속 실패하면 해당 항목을 건너뛴다.
- **번역 키 추출은 diff 기반.** 기존에 있던 키를 포함하지 않는다.
- **무거운 작업은 위임한다** — `_shared/delegation-policy.md` 참조

이제 실행하라.
