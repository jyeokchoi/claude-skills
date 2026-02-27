# 테스트 명령 결정 (공통 절차)

## 입력

- `project_settings`: `rules/project-params.md`에서 로드된 프로젝트 설정 (auto-loaded)

## 절차

### 1. 프로젝트 설정 확인

- `test_command`가 설정되어 있으면 그 값을 `TEST_COMMAND`로 사용

### 2. 자동 탐지 (설정이 없는 경우)

프로젝트 파일에서 테스트 명령을 탐지한다:

1. **package.json** (Node.js):
   - 패키지 매니저 탐지: `bun.lockb` → `bun`, `yarn.lock` → `yarn`, `pnpm-lock.yaml` → `pnpm`, 그 외 → `npm`
   - devDependencies에서 테스트 프레임워크 탐지:
     - `vitest` → `{pm} vitest run`
     - `jest` → `{pm} jest`
   - 위 탐지 실패 시: `scripts.test` 존재하면 `{pm} test`

2. **pyproject.toml** (Python):
   - `[tool.pytest]` 섹션 또는 `pytest` 의존성 → `pytest`
   - 그 외 → `python -m unittest`

3. **go.mod** (Go):
   - `go test ./...`

4. **Cargo.toml** (Rust):
   - `cargo test`

### 3. Fallback (탐지 실패 시)

- 사용자에게 질문: "테스트 실행 명령을 알려주세요 (예: yarn vitest run, pytest, go test ./...)"
- 응답을 `project_memory_add_note("test_command: {answer}")`로 저장하여 이후 세션에서 재사용

## 반환값

- `TEST_COMMAND`: 테스트 실행 명령 문자열
