# Worktree 정리 (공통 절차)

## 입력

- `main_repo_path`: 메인 리포지토리 절대 경로
- `worktree_path`: 정리할 worktree 절대 경로

## 절차

### 1. CWD 확인

현재 작업 디렉토리가 worktree 내부인지 확인:

```bash
CURRENT_DIR=$(pwd)
```

worktree 내부라면 메인 리포로 이동 후 진행.

### 2. Worktree 제거

```bash
cd {main_repo_path} && git worktree remove {worktree_path} --force && git worktree prune
```

### 3. 실패 시 안내

CWD가 worktree 내부여서 자동 정리가 실패한 경우:

```
⚠️ 현재 세션이 worktree 내에서 실행 중이라 자동 정리가 어렵습니다.
새 터미널에서: cd {main_repo_path} && git worktree remove {worktree_path} && git worktree prune
```
