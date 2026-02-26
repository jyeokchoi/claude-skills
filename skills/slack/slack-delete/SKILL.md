---
name: slack-delete
description: Slack 메시지 삭제용 curl 명령어를 생성한다. 메시지 링크 또는 채널+타임스탬프를 받아 복붙 가능한 커맨드를 출력.
argument-hint: 'Usage: /slack-delete <slack-message-url-or-channel+ts>'
---

## 목적

Slack MCP에 `chat.delete` API가 없으므로, 사용자가 직접 셸에 복붙할 수 있는 curl 삭제 명령어를 생성한다.

## Inputs

- `$ARGUMENTS`: Slack 메시지 URL 또는 "채널ID 타임스탬프" 형태

### URL 파싱 규칙

Slack 메시지 URL 형식: `https://{workspace}.slack.com/archives/{channelId}/p{timestamp}`

- `channelId`: URL path의 `/archives/` 다음 세그먼트 (예: `C06RAC95CAJ`)
- `timestamp`: `p` 접두사 제거 후, 뒤에서 6자리 앞에 `.` 삽입 (예: `p1771942796064479` -> `1771942796.064479`)

## Workflow

1. `$ARGUMENTS`에서 채널 ID와 타임스탬프를 파싱한다
2. Slack MCP `conversations_replies`로 해당 메시지가 존재하는지 확인한다
3. 스레드인 경우 (replies가 여러 개), 스레드 전체를 삭제할지 부모 메시지만 삭제할지 사용자에게 확인한다
4. 아래 형식으로 curl 명령어를 출력한다

## 출력 형식

```
아래 명령어를 셸에 복붙하세요:
```

```bash
curl -s -X POST https://slack.com/api/chat.delete \
  -H "Authorization: Bearer $SLACK_MCP_XOXB_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"channel":"{channelId}","ts":"{timestamp}"}'
```

### 스레드 전체 삭제 시

각 reply의 ts를 역순으로 나열하여 여러 curl 명령어를 `&&`로 연결한다 (자식 메시지 먼저, 부모 메시지 마지막).

## 주의사항

- 토큰 값을 하드코딩하지 않는다. 항상 `$SLACK_MCP_XOXB_TOKEN` 환경변수를 참조한다.
- 봇이 보낸 메시지만 삭제 가능하다. 다른 사용자의 메시지는 `chat.delete` 권한이 없을 수 있음을 안내한다.
