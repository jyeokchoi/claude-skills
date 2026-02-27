# 워크로그 타겟 결정 (공통 절차)

## 입력

- `arguments`: 사용자가 전달한 인자 (`$ARGUMENTS`)
- `required_files`: 워크로그 디렉터리에서 필요한 추가 파일 목록 (예: `["plan.md"]`, `["analysis.md"]`)

## 절차

### 1. WORKLOG_DIR 결정

- `arguments`가 있는 경우:
  - 폴더 경로면: `WORKLOG_DIR` = 해당 경로, `WORKLOG_PATH` = `{arguments}/worklog.md`
  - `.md` 파일 경로면: `WORKLOG_PATH` = 해당 경로, `WORKLOG_DIR` = 해당 파일의 상위 디렉터리
- `arguments`가 없는 경우:
  - **우선**: `.claude/worklogs/.active` 파일이 존재하면 그 내용을 `WORKLOG_DIR`로 사용
  - **Fallback**: `.active`가 없으면 아래 명령으로 탐색:
    ```bash
    find .claude/worklogs -name "worklog.md" -path "*/worklog.md" | head -5
    ```
  - 결과가 1개면 해당 디렉터리를 `WORKLOG_DIR`로 사용
  - 결과가 2개 이상이면 목록을 출력하고 사용자에게 선택 요청
  - 결과가 없으면 오류 출력 후 중단: "활성 워크로그를 찾을 수 없습니다. 인자로 워크로그 경로를 지정하세요."

### 2. WORKLOG_PATH 존재 확인

- `WORKLOG_PATH`가 존재하지 않으면 오류 출력 후 중단: "워크로그 파일을 찾을 수 없습니다: {WORKLOG_PATH}"

### 3. required_files 존재 확인

- `required_files`의 각 파일에 대해 `{WORKLOG_DIR}/{file}` 경로 존재 확인
- 파일이 없으면 호출한 스킬의 지침에 따라 오류 처리 (중단 또는 경고 후 진행)

## 반환값

- `WORKLOG_DIR`: 워크로그 디렉터리 절대 경로
- `WORKLOG_PATH`: `{WORKLOG_DIR}/worklog.md`
- `required_files`에 명시한 각 파일의 경로: `{WORKLOG_DIR}/{file}`
