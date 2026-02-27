# Git Worktree 생성 (공통 절차)

## 입력

- `task_name`: 워크트리 디렉토리명에 사용할 식별자
- `branch_name`: 생성/추적할 브랜치명
- `base_ref`: 분기 기준 (e.g., `develop`, `upstream/develop`, `origin/{branch}`)
- `create_branch`: `true`(새 브랜치) 또는 `false`(기존 브랜치 추적)
- `dependency_install` (선택): 의존성 설치 커맨드. 제공되면 Step 3의 기본 로직 대신 이 커맨드를 실행

## 절차

### 1. 경로 결정

```bash
repo_root=$(git rev-parse --show-toplevel)
worktree_path="${repo_root}/../worktrees/{task_name}"
```

### 2-A. 새 브랜치 생성 (create_branch=true)

```bash
git worktree add -b {branch_name} {worktree_path} {base_ref}
```

### 2-B. 기존 원격 브랜치 추적 (create_branch=false)

```bash
git fetch origin {branch_name}
git worktree add {worktree_path} {branch_name}
```

로컬 브랜치가 없으면:

```bash
git worktree add {worktree_path} origin/{branch_name}
cd {worktree_path} && git checkout -B {branch_name} origin/{branch_name}
```

### 3. 의존성 설치

**`dependency_install`이 제공된 경우:** 해당 커맨드를 `{worktree_path}`를 치환하여 실행.

**제공되지 않은 경우:** `rules/project-params.md`에서 `dependency_install` 설정을 읽는다.

**설정도 없는 경우:** 프로젝트에 맞는 패키지 매니저를 자동 탐지:

```bash
# 1. rules/project-params.md의 dependency_install 사용 (있으면)
# 2. 없으면 worktree 루트에서 lock file 기반 자동 탐지:
#    yarn.lock → yarn install
#    package-lock.json → npm install
#    없으면 하위 디렉토리 탐색 후 사용자에게 질문:
#    "의존성 설치 명령을 알려주세요 (예: cd react && yarn install)"
#    → project_memory_add_note("dependency_install: {user_answer}")
```

- 시간이 오래 걸리므로 `run_in_background: true` 또는 subshell 실행 권장

### 4. 반환값

- `worktree_path` (절대 경로)
