---
name: print-worktree-summary
description: 워크트리 설정 완료 후 요약 출력. 다른 스킬에서 인라인으로 호출한다.
allowed-tools: Bash(echo:*), Bash(pbcopy:*)
---

# 워크트리 요약 출력 (공통 절차)

## 입력

- `worktree_path`: 워크트리 절대 경로
- `worklog_path`: 워크로그 파일 경로
- `branch_name`: 브랜치명
- `jira_url`: Jira URL (없으면 "없음")

## 절차

### 1. 클립보드 복사

```bash
echo "/add-dir {worktree_path}" | pbcopy
```

### 2. 출력

```
✅ 워크트리 설정 완료

📁 Worktree: {worktree_path}
📄 Worklog: {worklog_path}
🌿 Branch: {branch_name}
🔗 Jira: {jira_url}

📋 클립보드에 복사됨: /add-dir {worktree_path}
   → Cmd+V로 붙여넣기하여 워크트리 추가

또는 새 세션으로 시작:
   exit 후: cd {worktree_path} && claude
```
