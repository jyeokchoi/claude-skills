# 린트 & 포맷 (공통 절차)

## 입력

- `changed_files`: 변경된 파일 목록 (전체 경로)
- `project_dir`: 프로젝트 디렉토리 경로 (e.g., `react/`)

## 절차

### 0. 도구 탐지

`rules/project-params.md`에 `lint_command`/`format_command`가 있으면 사용한다. 없으면 프로젝트에서 자동 탐지:

```bash
# 1. rules/project-params.md에서 lint_command / format_command 읽기 (있으면 사용)
# 2. 없으면 {project_dir}/package.json의 scripts에서 탐지:
#    - "prettier" script 있으면 → {pkg_manager} prettier --write
#    - "lint" 또는 "eslint" script 있으면 → {pkg_manager} eslint --fix
#    - pkg_manager: yarn.lock → yarn, package-lock.json → npx, pnpm-lock.yaml → pnpm
# 3. 탐지 불가 시 사용자에게 질문:
#    "린트/포맷 명령어를 알려주세요 (예: yarn prettier --write, npx eslint --fix)"
#    → project_memory_add_note("format_command: {answer}")
#    → project_memory_add_note("lint_command: {answer}")
```

### 1. 대상 파일 필터링

변경된 파일 중 린트/포맷 대상 확장자만 선별. 프로젝트의 prettier/eslint 설정에서 대상 확장자를 확인한다. 설정이 없으면 기본값:

```bash
# 기본 대상: 프로젝트 언어에 따라 결정
# JS/TS 프로젝트: .ts, .tsx, .js, .jsx, .mjs, .cjs
# Python 프로젝트: .py
# 혼합: 위 모두
echo "{changed_files}" | grep -E '\.(ts|tsx|js|jsx|mjs|cjs|py)$'
```

대상 파일이 없으면 이 절차 스킵.

### 2. Prettier (또는 포맷터) 실행

```bash
cd {project_dir} && {format_command} {filtered_files}
```

### 3. ESLint (또는 린터) 실행

```bash
cd {project_dir} && {lint_command} {filtered_files}
```

### 4. 재스테이징 및 커밋

자동 수정으로 파일이 변경된 경우:

```bash
git add {filtered_files}
git commit -m "style: format code"
```

변경 사항이 없으면 커밋 스킵.
