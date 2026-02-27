# PR 생성 (공통 절차)

## 입력

- `branch_name`: 푸시할 브랜치명
- `jira_key` (선택): Jira 이슈 키 (e.g., PROJ-12345)
- `changes_summary`: 수정 범위 요약
- `impact_summary`: 기존 기능 영향 범위
- `base_branch`: PR 대상 브랜치. `rules/project-params.md`의 `base_branch` 설정을 사용한다. 없으면 자동 탐지 (`gh repo view --json defaultBranchRef`), 그래도 없으면 사용자에게 질문 → `project_memory_add_note("base_branch: {answer}")`.
- `changed_files`: 변경된 파일 목록

## 절차

### 1. Fork 구조 감지

```bash
git remote -v
```

- `upstream`이 다른 repo를 가리킴 → fork 구조
- `origin` = fork, `upstream` = target repo
- fork가 아닌 경우 `origin`이 target repo

### 2. Push

```bash
git push -u origin {branch_name}
```

### 3. 리뷰어 탐색

변경된 파일 한정으로 검색 (repo-wide 검색 금지):

```bash
# fork 구조인 경우
git log upstream/{base_branch} --pretty=format:"%an" -30 -- {changed_files} | sort | uniq -c | sort -rn | head -5

# non-fork인 경우
git log origin/{base_branch} --pretty=format:"%an" -30 -- {changed_files} | sort | uniq -c | sort -rn | head -5
```

- 빈 결과 시 사용자에게 직접 선택 요청
- 현재 사용자 제외, git author -> GitHub username 매칭
- GitHub Copilot 리뷰어는 gh CLI로 추가 불가 → 수동 추가 안내

### 4. Label 자동감지 (선택적)

프로젝트에 label이 설정되어 있는 경우에만 적용:

```bash
gh label list 2>/dev/null
```

label이 없거나 label 적용이 불필요한 경우 이 단계 스킵.

사용자에게 추가 질문:
- release/hotfix label 필요 여부 (해당하는 경우)
- 리뷰 희망 시점

### 5. PR body 작성

- **Title (영어)**: `({jira_key}) {goal_summary_in_english}` (jira_key 없으면 jira_key 부분 생략)
- **Body (한국어)**:

```
## Summary
{Goal 한 줄 요약}
- 메인 리뷰어: {main_reviewer}
- 리뷰 희망 시점: {timing}
- 서브 리뷰어(opt.): {sub_reviewers}

## 수정 범위
{changes_summary}

## 영향 범위
{impact_summary}

## Jira
{jira_url 또는 "없음"}

## 테스트 계획
- [ ] 기존 기능 영향 없음 확인
- [ ] 새 기능 동작 확인

---
_Written by Claude Code_
```

### 6. `gh pr create`

```bash
# Fork structure:
gh pr create --repo {upstream_owner}/{upstream_repo} \
  --title "{title}" --body "{body}" --base {base_branch} \
  --head {fork_owner}:{branch_name} \
  --reviewer {reviewers} --assignee {current_user}

# Non-fork:
gh pr create --title "{title}" --body "{body}" --base {base_branch} \
  --reviewer {reviewers} --assignee {current_user}
```

label이 있는 경우 `--label {labels}` 추가.

### 7. Jira 상태 전이 (jira_key가 제공된 경우에만)

- `getTransitionsForJiraIssue` → "Waiting Review" 또는 "In Review" 찾기
- `transitionJiraIssue`
- `addCommentToJiraIssue`: `PR 생성 완료: {pr_url}`

### 8. Copilot 리뷰어 안내

```
GitHub Copilot 리뷰어는 gh CLI로 추가할 수 없습니다.
PR 페이지에서 수동으로 Copilot을 리뷰어로 추가해주세요.
```

## 반환값

- `pr_url`: 생성된 PR의 URL
