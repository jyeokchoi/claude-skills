# Base Branch 결정 (공통 절차)

## 입력

- `project_settings`: `rules/project-params.md`에서 로드된 프로젝트 설정 (auto-loaded)

## 절차

### 1. 프로젝트 설정 확인

- `base_branch`가 설정되어 있으면 그 값을 `BASE_REF`로 사용
- `fork_workflow` 설정도 확인: `true`면 remote=`upstream`, `false`면 remote=`origin`

### 2. 자동 탐지 (설정이 없는 경우)

```bash
# 1. gh repo view --json defaultBranchRef 로 기본 브랜치 탐지
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null)

# 2. fork 여부: git remote -v 로 upstream 존재 확인
if git remote -v | grep -q upstream; then
  REMOTE="upstream"
else
  REMOTE="origin"
fi

BASE_REF="$REMOTE/$DEFAULT_BRANCH"
```

### 3. Fallback (탐지 실패 시)

- 사용자에게 질문: "기준 브랜치를 지정해주세요 (예: origin/main, upstream/develop)"
- 응답을 `project_memory_add_note("base_branch: {answer}")`로 저장

## 반환값

- `BASE_REF`: 전체 remote/branch 경로 (예: `origin/main`, `upstream/develop`)
- `REMOTE`: remote 이름 (예: `origin`, `upstream`)
