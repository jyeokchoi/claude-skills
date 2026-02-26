# Jira 이슈 생성 (공통 절차)

## 입력

- `task_brief` (선택): 이슈 설명에 사용할 컨텍스트
- `suggested_summary` (선택): 제안할 이슈 제목

## 절차

### 1. Atlassian 인증

- `getAccessibleAtlassianResources` → `cloudId` 및 `cloudUrl` (e.g., `https://{org}.atlassian.net`) 획득
- `atlassianUserInfo` → `account_id` 획득
- 401 에러 시: "`/mcp` 명령으로 재인증 필요" 안내 후 중단

### 2. 이슈 타입 선택 (AskUserQuestion)

| 타입           | 설명                       |
| -------------- | -------------------------- |
| Bug            | 버그 수정                  |
| Task           | 일반 개발 작업             |
| 개선           | 기능 개선                  |
| 개발 내부 작업 | 내부 리팩토링/기술 부채    |

### 3. Summary 결정

- `suggested_summary`가 있으면 제안, 사용자 확인/수정
- 없으면 사용자 입력 요청

### 4. Description 작성

이슈 타입별 Jira 템플릿 사용 (프로젝트 루트 `.claude/skills/_templates/jira/` 우선, fallback: `~/.claude/skills/_templates/jira/`):

- Bug → `bug.md`
- Task/개선/개발 내부 작업 → `task.md` 또는 `feature.md`
- `task_brief`가 있으면 템플릿에 반영

### 5. projectKey 결정

프로젝트 루트 `rules/workflow.md`가 존재하면:
- `jira_pattern` 설정에서 프로젝트 키 prefix 추출 (e.g., `VREW-\d+` → `VREW`)

`rules/workflow.md`가 없거나 `jira_pattern`이 설정되지 않은 경우:
- 사용자에게 Jira 프로젝트 키 입력 요청 (e.g., `PROJ`)

### 6. 이슈 생성

```
createJiraIssue:
  cloudId: {cloud_id}
  projectKey: {project_key}
  issueTypeName: {selected_type}
  summary: {summary}
  description: {description}
  assignee_account_id: {account_id}
```

### 7. 반환값

- `issue_key`: e.g., {PROJECT_KEY}-12345
- `issue_url`: 다음 우선순위로 결정
  1. 프로젝트 루트 `rules/workflow.md`의 `jira_base_url` 설정이 있으면 `{jira_base_url}{issue_key}` 사용
  2. 없으면 Step 1의 `getAccessibleAtlassianResources`에서 획득한 `cloudUrl`로 `{cloudUrl}/browse/{issue_key}` 구성
