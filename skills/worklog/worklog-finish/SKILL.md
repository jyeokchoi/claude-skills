---
name: worklog-finish
description: Finish a worklog task, optionally update a Jira issue, and optionally create a PR
argument-hint: "Usage: /worklog-finish [--path <worklog-path>] [--pr] [--no-pr] [--no-jira]"
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*), Bash(git merge-base:*), Bash(git push:*), Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git remote:*), Bash(git blame:*), Bash(git worktree:*), Bash(find:*), Bash(grep:*), Bash(ls:*), Bash(rm -rf .claude*), Bash(rm -f .claude*), Bash(cd:*), Bash(yarn:*), Bash(gh:*), Read, Write, Edit, AskUserQuestion, Task, mcp__plugin_atlassian_atlassian__*, mcp__github__*
---

worklog 작업을 완료하고, 연결된 Jira 이슈를 선택적으로 업데이트하며, PR을 선택적으로 생성한다.

## 핵심 설계 원칙

- **Worklog 파일은 절대 git에 커밋하지 않는다.** Gist에 업로드하고, Jira에 첨부(가능한 경우)한 뒤 삭제한다.
- **Jira API 마크다운**: `\n` 문자열 리터럴 사용 금지 (escape되어 포맷 깨짐). 실제 줄바꿈 또는 한 줄로 작성.

## 입력값

- `--path <worklog-path>` (선택): worklog 폴더의 직접 경로
- `--pr` (선택): 완료 후 PR 생성 (확인 건너뜀)
- `--no-pr` (선택): PR 생성 건너뜀
- `--no-jira` (선택): jira 필드가 있어도 Jira 업데이트 건너뜀
- 경로 미제공 시 현재 브랜치와 일치하는 worklog 탐색

## 단계

### 0. 메인 저장소 경로 탐지 (worktree 정리를 위해)

```bash
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
```

### 1. worklog 찾기

- `--path` 제공된 경우: 직접 사용
- 아닌 경우: 현재 브랜치 조회 → frontmatter의 `branch` 필드가 일치하는 `.claude/worklogs/` 검색

### 2. worklog 읽기 및 정보 추출

- frontmatter 파싱: `jira` (→ 이슈 키), `branch`, `worktree_path` (Step 8에서 사용하므로 변수에 보존)
- Goal, Completion criteria (Dashboard 상단), Dashboard Decisions 읽기

### 3. 변경 정보 수집

**base branch 결정:**

`_shared/resolve-base-branch.md`가 존재하는 경우:
> **Shared**: `_shared/resolve-base-branch.md` 절차를 따른다.

없는 경우: 프로젝트 설정 파일(`rules/project-params.md`)의 `base_branch` → 자동 탐지 → 사용자 질문

변경 파일 수집:
```bash
git fetch $REMOTE
git diff --name-only $(git merge-base HEAD $BASE_REF)..HEAD
```

변경 파일을 사용자에게 보여주고 다음 항목 요청:
- **수정 범위**: 변경된 내용 요약
- **기존 기능 영향 범위**: 영향받을 수 있는 기존 기능

### 4. Jira 이슈 업데이트 (jira 필드가 있고 --no-jira가 아닌 경우)

a. Jira MCP 연결 확인 (`ToolSearch`로 atlassian 도구 검색). 사용 불가 시 이 단계를 건너뛰고 사용자에게 알림.

b. `getAccessibleAtlassianResources` → cloudId 획득

c. `getJiraIssue` → 현재 설명 조회

d. 프로젝트에 `.claude/skills/_templates/jira/finish-update.md`가 있으면 로드하고 `{{changes}}`와 `{{impact}}`를 채움. 없으면 인라인으로 간단한 업데이트 내용 작성.

e. `editJiraIssue`: 기존 설명 앞에 업데이트 내용 추가

### 5. worklog를 Gist에 보관하고 정리

a. `_shared/update-worklog.md`로 worklog 업데이트:
   - `phase_update`: `DONE`
   - `timeline_entry`: 완료 요약 + 변경 파일

b. Gist에 업로드:
```bash
GIST_URL=$(gh gist create --filename worklog.md {worklog_path}/worklog.md 2>/dev/null)
```
- 기본값은 **secret** gist (비공개). 프로젝트 설정 `gist_visibility`가 `public`이면 `--public` 추가.
- **업로드 실패 시**: 오류 메시지를 출력하고 사용자에게 확인. 삭제하지 않음.

c. 진행 전 gist URL 검증:
```bash
if [[ "$GIST_URL" != https://* ]]; then
  echo "Gist 업로드 실패. 워크로그를 삭제하지 않습니다."
  # 사용자에게 알리고 Step 6으로 건너뛴다
fi
```

d. Jira 사용 가능하고 gist 성공 시: `addCommentToJiraIssue`에 gist URL 추가 (한 줄로 작성):
```
Worklog 파일: {GIST_URL}
```

e. 로컬 worklog 폴더 삭제 (gist 검증은 Step 5c에서 완료):
```bash
rm -rf {worklog_path}
```

f. `.active` 포인터 초기화 (삭제된 worklog를 가리키는 경우):
```bash
ACTIVE_FILE=".claude/worklogs/.active"
if [[ -f "$ACTIVE_FILE" ]] && [[ "$(cat "$ACTIVE_FILE")" == *"{worklog_folder_name}"* ]]; then
  rm -f "$ACTIVE_FILE"
fi
```

### 6. PR 생성 처리

- `--no-pr`: Step 7로 건너뜀
- 플래그 없음: 사용자에게 "PR을 생성하시겠습니까?" 확인
- 아니오: Step 7로 건너뜀

**a. [LOCAL-ONLY] 커밋 제외 (MANDATORY - push 전에 반드시 실행):**

프로젝트에 `_shared/exclude-local-only-commits.md`가 있는 경우:
> **Shared**: `_shared/exclude-local-only-commits.md` 절차를 따른다.

없는 경우:
```bash
# [LOCAL-ONLY] 커밋이 있으면 경고 후 사용자 확인
git log --grep='\[LOCAL-ONLY\]' --oneline
```
[LOCAL-ONLY] 커밋이 발견되면 사용자에게 알리고 처리 방법을 확인한다.

**b. PR 생성:**

프로젝트에 `_shared/create-pr.md`가 있는 경우:
> **Shared**: `_shared/create-pr.md` 절차를 따른다.
> - `branch_name`: {branch_name}
> - `jira_key`: {jira_key} (frontmatter에서 추출, 없으면 생략)
> - `changes_summary`: Step 3에서 수집한 수정 범위
> - `impact_summary`: Step 3에서 수집한 영향 범위
> - `base_branch`: Step 3에서 결정한 BASE_REF의 브랜치명
> - `changed_files`: Step 3에서 수집한 변경 파일 목록

없는 경우: `gh pr create` 명령을 직접 실행한다:
```bash
gh pr create \
  --title "{pr_title}" \
  --body "$(cat <<'EOF'
## Summary
{changes_summary}

## Impact
{impact_summary}

## Changed files
{changed_files}
EOF
)" \
  --base {base_branch}
```

### 7. 최종 요약 출력

| 항목           | 값                                     |
| -------------- | -------------------------------------- |
| Jira issue     | {jira_url or "없음"}                   |
| Gist (worklog) | {gist_url}                             |
| PR             | {pr_url or "미생성"}                   |
| Branch         | {branch_name}                          |
| Changed files  | {count}                                |
| Phase          | DONE                                   |

### 8. worktree 정리 처리 (해당하는 경우)

- worklog의 frontmatter에 `worktree_path`가 있었는지 확인 (삭제 전)
- worktree가 존재하고 메인 저장소와 다른 경우: 사용자에게 "Worktree를 정리하시겠습니까?" 확인

**예:**

프로젝트에 `_shared/cleanup-worktree.md`가 있는 경우:
> **Shared**: `_shared/cleanup-worktree.md` 절차를 따른다.
> - `main_repo_path`: {MAIN_REPO}
> - `worktree_path`: {worktree_path}

없는 경우:
```bash
cd {MAIN_REPO}
git worktree remove {worktree_path} --force
```

**아니오:** "Worktree preserved at {worktree_path}"

이제 실행하라.
