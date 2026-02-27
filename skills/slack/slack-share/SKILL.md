---
name: slack-share
description: Gather work progress from commits/worklogs and share to a Slack thread with user approval
argument-hint: 'Usage: /slack-share <slack-thread-url> [--since=YYYY-MM-DD] [--audience=dev|all]'
---

작업 진행 상황 요약을 작성하여 Slack 스레드에 게시하는 스킬.

## 입력 파싱

$ARGUMENTS를 파싱한다:

1. **Slack 스레드 URL** (필수): URL에서 `channel_id`와 `thread_ts`를 추출한다.
   - URL 형식: `https://*.slack.com/archives/{channel_id}/p{timestamp}`
   - 타임스탬프 변환: `p` 접두사 제거 후 뒤에서 6자리 앞에 `.` 삽입
   - URL이 없으면 중단하고 출력: "슬랙 스레드 URL을 입력해주세요."

2. **--since** (선택): 커밋 범위 시작 날짜. 기본값: 지난 목요일.
   - 지난 목요일 계산: 오늘이 목요일 이후이면 이번 주 목요일 사용. 그 외에는 지난 주 목요일 사용.

3. **--audience** (선택): 대상 독자.
   - `dev`: 개발자만 (기술적 세부사항 OK)
   - `all` (기본값): 개발자 + 디자이너 + 기획자 (전문 용어 최소화, 사용자 영향에 집중)

## 1단계: Slack 스레드 읽기

Slack MCP 스레드 읽기 도구(예: `slack_read_thread`)로 스레드 컨텍스트를 가져온다. 스레드 주제와 기대하는 공유 유형을 파악한다.

## 2단계: 작업 데이터 수집

병렬로 실행:

1. **커밋**: `git log --since="{since_date}" --no-merges --format="----%nCommit: %h%nDate: %ad%nSubject: %s%n%b" --date=short`
2. **워크로그**: `.claude/worklogs/` 아래에서 IN_PROGRESS이거나 최근 업데이트된 워크로그를 찾아 읽기.

## 프로젝트 설정 (선택)

프로젝트 설정 파일(`rules/project-params.md`)이 있으면 다음 설정을 읽는다:
- `jira_pattern` — 커밋 메시지에서 이슈 키를 인식하기 위한 패턴
- `jira_base_url` — 이슈 링크 생성을 위한 기본 URL
- `slack_integration` — Slack 컨텍스트 수집이 예상되는지 여부

파일이 없으면 합리적인 기본값으로 진행한다 (이슈 키 링크화 없음).

## 3단계: 초안 작성

### 작성 규칙

- **일반 텍스트만** — 마크다운 문법 사용 금지 (`**bold**`, `# headers`, `| tables |`)
- 완료 항목은 번호 목록, 하위 항목은 불릿 포인트(`-`) 사용
- 구조: [완료] → [진행 중] → [다음 TODO]

### 독자별 조정

- **audience=all** (기본값):
  - 구현 세부사항이 아닌 사용자가 체감하는 변화로 표현
  - 사용 금지: 클래스 이름, 함수 이름, Redux, hook 이름, 디자인 패턴, 파일 경로
  - 허용: "에셋 표시 타이밍 개선", "편집 시 프리뷰 즉시 반영"

- **audience=dev**:
  - 기술적 세부사항 허용
  - 파일 이름, 아키텍처 결정, 테스트 수 포함 가능

### 내용 구조

```
{thread topic} — {date range} 작업 공유 ({author name})

[완료]

1. {user-facing description} — {brief explanation}
2. ...

[진행 중] {task name}

{current status}. {what's improving}:
- {improvement 1}
- {improvement 2}
- ...

[다음 TODO]
- {priority}: {task 1}, {task 2}
- ...
```

## 4단계: 사용자 검토 (필수)

전체 초안을 출력하고 질문한다: "이대로 슬랙에 올릴까요?"

사용자 승인을 기다린다. 수정 요청이 있으면 수정 후 다시 확인한다.

**사용자의 명시적 승인 없이는 절대 Slack에 게시하지 않는다.**

## 5단계: Slack에 게시

Slack MCP 메시지 전송 도구(예: `slack_send_message`)로 전송한다:
- `channel_id`: 파싱된 URL에서 추출
- `thread_ts`: 파싱된 URL에서 추출
- `content_type`: `text/plain`
- `payload`: 승인된 초안

게시 후 확인 메시지를 출력한다.

이제 실행하라.
