# [LOCAL-ONLY] 커밋 제외 (공통 절차)

PR 생성 전 [LOCAL-ONLY] 커밋을 히스토리에서 제외한다.

## 입력

- `base_branch`: PR 대상 브랜치. `rules/workflow.md`의 `base_branch` 설정을 사용한다. 없으면 자동 탐지 (`gh repo view --json defaultBranchRef`), 그래도 없으면 사용자에게 질문 → `project_memory_add_note("base_branch: {answer}")`.
- `upstream_remote`: upstream remote 이름. `rules/workflow.md`의 `fork_workflow`가 `true`면 `upstream`, 아니면 `origin`. 설정이 없으면 `git remote -v`로 탐지.

## 절차

### 1. 확인

```bash
git fetch {upstream_remote}
BASE_REF="{upstream_remote}/{base_branch}"
LOCAL_ONLY_COUNT=$(git log --oneline $(git merge-base HEAD $BASE_REF)..HEAD | grep -c '\[LOCAL-ONLY\]' || echo 0)
```

- COUNT가 0이면 이 절차 스킵

### 2. Cherry-pick으로 제외

```bash
CURRENT_HEAD=$(git rev-parse HEAD)
GOOD_COMMITS=$(git log --reverse --format=%H $(git merge-base HEAD $BASE_REF)..HEAD --grep='\[LOCAL-ONLY\]' --invert-grep)

git reset --hard $BASE_REF
for commit in $GOOD_COMMITS; do
  git cherry-pick $commit
done
```

Cherry-pick 실패 시 대안:

```bash
MERGE_BASE=$(git merge-base $CURRENT_HEAD $BASE_REF)
git checkout -b {branch_name}-clean $BASE_REF
for commit in $(git log --reverse --format=%H $MERGE_BASE..$CURRENT_HEAD --grep='\[LOCAL-ONLY\]' --invert-grep); do
  git cherry-pick $commit
done
```

### 3. 검증

```bash
REMAINING=$(git log --oneline $BASE_REF..HEAD | grep -c '\[LOCAL-ONLY\]' || echo 0)
[ "$REMAINING" -gt 0 ] && echo "❌ ERROR: Still have $REMAINING LOCAL-ONLY commits!" && exit 1
```

### 4. .claude 파일 폴백

[LOCAL-ONLY] 마커 없이 .claude 파일이 변경된 경우:

```bash
CLAUDE_FILES=$(git diff --name-only $(git merge-base HEAD $BASE_REF)..HEAD | grep -E '^\.claude' || true)
```

발견 시:

```bash
git checkout $BASE_REF -- .claude/
git add .claude/
git commit -m "chore: revert .claude changes for PR"
```
