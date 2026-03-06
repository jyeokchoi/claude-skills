---
name: _install
description: claude-skills 설치 + 프로젝트 설정
---

# 🛠️ claude-skills 설치

이 스킬은 claude-skills를 설치하고, 프로젝트 설정을 인터랙티브하게 진행한다.

## 실행 원칙 (절대 위반 금지)

1. **모든 스텝을 중단 없이 연속 실행한다.** AskUserQuestion 응답을 받으면 결과를 변수에 저장하고 즉시 다음 스텝으로 넘어간다. 중간에 사용자에게 보고하거나 확인을 구하지 않는다.
2. **AskUserQuestion은 반드시 사용자 선택이 필요한 경우에만 사용한다.** 자동 탐지로 충분한 값은 묻지 않는다.
3. **독립적인 작업은 병렬로 실행한다.** 탐지 명령, 파일 읽기 등은 동시에 수행한다.
4. **실패 시 재시도 → 대안 → 건너뛰기 순으로 처리한다.** 사용자에게 어떻게 할지 AskUserQuestion으로 묻는다.
5. **Step 7(결과 보고) 전까지 사용자에게 텍스트 출력을 하지 않는다.** 모든 커뮤니케이션은 AskUserQuestion으로만 한다.

---

## Step 1: 🤖 oh-my-claudecode 확인

```bash
ls ~/.claude/plugins/cache/omc/oh-my-claudecode/ 2>/dev/null && echo "OMC_FOUND" || echo "OMC_NOT_FOUND"
```

- **OMC_FOUND:** `$OMC_STATUS = "installed"`. → 즉시 Step 2로.
- **OMC_NOT_FOUND:** `$OMC_STATUS = "not installed"`. AskUserQuestion으로 묻는다:

```yaml
question: "oh-my-claudecode(OMC)가 설치되어 있지 않습니다. OMC 없이도 동작하지만 멀티에이전트 기능이 제한됩니다."
header: "OMC"
options:
  - label: "건너뛰기 (Recommended)"
    description: "OMC 없이 진행. 나중에 설치 가능 (https://github.com/Yeachan-Heo/oh-my-claudecode)"
  - label: "OMC 설치"
    description: "지금 oh-my-claudecode를 설치합니다"
```

"OMC 설치" 선택 시 공식 가이드를 따른다. 설치 성공하면 `$OMC_STATUS = "installed"`. 실패 시 경고만 하고 계속 진행한다.

→ 즉시 Step 1-B 실행.

## Step 1-B: 🎭 Playwright MCP 확인

vbrowser 스킬(브라우저 E2E 테스트)을 사용하려면 Playwright MCP 서버가 필요하다.

### 1-B-1. 설치 여부 확인

`~/.claude.json`(또는 `~/.claude/settings.json`)을 읽어 `mcpServers.playwright` 설정이 있는지 확인한다:

```bash
grep -l "playwright" ~/.claude.json ~/.claude/settings.json 2>/dev/null && echo "PLAYWRIGHT_FOUND" || echo "PLAYWRIGHT_NOT_FOUND"
```

- **PLAYWRIGHT_FOUND:** `$PLAYWRIGHT_STATUS = "installed"`. → 즉시 Step 2로.
- **PLAYWRIGHT_NOT_FOUND:**

AskUserQuestion:

```yaml
question: "Playwright MCP가 설정되지 않았습니다. 브라우저 E2E 테스트(/vbrowser)에 필요합니다."
header: "Playwright"
options:
  - label: "설치 (Recommended)"
    description: "@playwright/mcp를 설치하고 Claude Code에 등록합니다"
  - label: "건너뛰기"
    description: "나중에 설치. /vbrowser 스킬 사용 불가"
```

### 1-B-2. 설치 실행 ("설치" 선택 시)

```bash
# Claude Code CLI로 MCP 서버 등록 (user scope)
claude mcp add playwright -s user -- npx @playwright/mcp@latest
```

설치 후 확인:
```bash
grep "playwright" ~/.claude.json 2>/dev/null && echo "OK" || echo "FAIL"
```

- **OK:** `$PLAYWRIGHT_STATUS = "installed"`
- **FAIL:** 수동 설정 안내 출력:

> Playwright MCP 자동 등록에 실패했습니다. `~/.claude.json`의 `mcpServers`에 수동으로 추가하세요:
> ```json
> {
>   "mcpServers": {
>     "playwright": {
>       "command": "npx",
>       "args": ["@playwright/mcp@latest"]
>     }
>   }
> }
> ```

`$PLAYWRIGHT_STATUS = "manual"`로 설정하고 계속 진행.

### 1-B-3. 브라우저 설치

Playwright MCP가 등록되면 브라우저 바이너리도 필요하다:

```bash
npx playwright install chromium 2>/dev/null
```

실패 시 경고만 출력하고 계속 진행한다 (첫 실행 시 자동 설치됨).

→ 즉시 Step 2 실행.

## Step 2: 📁 스킬 설치 위치 선택

AskUserQuestion:

```yaml
question: "스킬을 어디에 설치할까요?"
header: "스킬 위치"
options:
  - label: "유저 레벨 (Recommended)"
    description: "~/.claude/skills/ — 모든 프로젝트에서 사용 가능"
  - label: "프로젝트 레벨"
    description: "{현재 디렉토리}/.claude/skills/"
```

- "유저 레벨" → `$SKILLS_DIR = ~/.claude/skills/`
- "프로젝트 레벨" → `$SKILLS_DIR = {cwd}/.claude/skills/`
- "Other" → 사용자 입력값을 `$SKILLS_DIR`로 사용

→ 즉시 Step 3 실행.

## Step 3: 📦 스킬 설치

### 3-1. 설치 실행

git이 사용 가능하면 git clone, 아니면 curl로 tarball을 받는다. **install.sh를 직접 실행하지 않고** 아래 절차를 인라인으로 수행한다:

```bash
# 1. 임시 디렉토리에 다운로드
TEMP_DIR=$(mktemp -d)

# git 사용 가능하면 clone, 아니면 curl
git clone --depth 1 https://github.com/jyeokchoi/claude-skills.git "$TEMP_DIR/claude-skills" 2>/dev/null || \
  (curl -sL https://github.com/jyeokchoi/claude-skills/archive/refs/heads/main.tar.gz | tar xz -C "$TEMP_DIR" && mv "$TEMP_DIR/claude-skills-main" "$TEMP_DIR/claude-skills")

# 2. $SKILLS_DIR 생성
mkdir -p "$SKILLS_DIR"

# 3. _shared, _templates 복사
cp -r "$TEMP_DIR/claude-skills/skills/_shared" "$SKILLS_DIR/"
cp -r "$TEMP_DIR/claude-skills/skills/_templates" "$SKILLS_DIR/"

# 4. 카테고리 하위의 스킬들을 플랫하게 복사 (기존 스킬은 백업)
# 겹치는 스킬만 백업한다
for category_dir in "$TEMP_DIR/claude-skills/skills"/*/; do
  category=$(basename "$category_dir")
  [[ "$category" == _* ]] && continue
  for skill_dir in "$category_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name=$(basename "$skill_dir")
    [ -d "$SKILLS_DIR/$skill_name" ] && mkdir -p "$SKILLS_DIR.backup.$(date +%Y%m%d)" && cp -r "$SKILLS_DIR/$skill_name" "$SKILLS_DIR.backup.$(date +%Y%m%d)/"
    cp -r "$skill_dir" "$SKILLS_DIR/$skill_name"
  done
done

# 5. 정리
rm -rf "$TEMP_DIR"
```

### 3-2. 훅 등록

`$SKILLS_DIR/_shared/hooks/` 디렉토리에 훅 스크립트가 있으면 `~/.claude/settings.json`에 자동 등록한다.

```bash
# settings.json 경로
SETTINGS="$HOME/.claude/settings.json"

# settings.json이 없으면 기본 구조 생성
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
```

Read 도구로 `$SETTINGS`를 읽고, `hooks` 객체에 아래 항목이 **없는 경우에만** 추가한다 (이미 있으면 건너뛴다):

| 훅 이벤트 | 스크립트 | timeout | matcher |
|-----------|---------|---------|---------|
| `PreCompact` | `node "$SKILLS_DIR/_shared/hooks/pre-compact-worklog.mjs"` | 10 | (없음) |
| `SessionStart` | `node "$SKILLS_DIR/_shared/hooks/post-compact-inject.mjs"` | 5 | `compact` |

등록 형식 (JSON):
```json
{
  "PreCompact": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "node \"$SKILLS_DIR/_shared/hooks/pre-compact-worklog.mjs\"",
          "timeout": 10
        }
      ]
    }
  ],
  "SessionStart": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "node \"$SKILLS_DIR/_shared/hooks/post-compact-inject.mjs\"",
          "timeout": 5
        }
      ],
      "matcher": "compact"
    }
  ]
}
```

`$SKILLS_DIR`는 실제 절대 경로로 치환한다 (e.g., `~/.claude/skills/` → `/Users/username/.claude/skills/`). 기존 `hooks` 객체의 다른 항목(e.g., `UserPromptSubmit`)은 절대 건드리지 않는다. Edit 도구로 정확히 필요한 항목만 추가한다.

### 3-3. 설치 확인

```bash
ls "$SKILLS_DIR/vplan/SKILL.md" 2>/dev/null && echo "OK" || echo "FAIL"
```

- **OK:** `$SKILL_COUNT = $(find "$SKILLS_DIR" -name "SKILL.md" | wc -l | tr -d ' ')`. → 즉시 Step 4로.
- **FAIL:** AskUserQuestion으로 묻는다:

```yaml
question: "스킬 설치에 실패했습니다. 어떻게 하시겠어요?"
header: "설치 실패"
options:
  - label: "재시도"
    description: "설치를 다시 시도합니다"
  - label: "건너뛰기"
    description: "설치 없이 프로젝트 설정만 진행합니다"
```

"재시도" → Step 3-1부터 다시. "건너뛰기" → Step 4로.

→ 즉시 Step 4 실행.

## Step 4: ⚙️ 프로젝트 파라미터 위치 선택

AskUserQuestion:

```yaml
question: "프로젝트 설정 파일(project-params.local.md)을 어디에 만들까요?"
header: "설정 위치"
options:
  - label: "프로젝트 레벨 (Recommended)"
    description: "{현재 디렉토리}/.claude/rules/project-params.local.md — 이 프로젝트 전용"
  - label: "유저 레벨"
    description: "~/.claude/rules/project-params.local.md — 모든 프로젝트의 기본값"
  - label: "건너뛰기"
    description: "설정 파일 없이 진행. 스킬이 자동 탐지로 동작합니다."
```

- "유저 레벨" → `$PARAMS_PATH = ~/.claude/rules/project-params.local.md`, `$DETECT_DIR = {cwd}`
- "프로젝트 레벨" → `$PARAMS_PATH = {cwd}/.claude/rules/project-params.local.md`, `$DETECT_DIR = {cwd}`
- "Other" → 사용자 입력 경로, `$DETECT_DIR = 해당 경로의 프로젝트 루트`
- "건너뛰기" → Step 7로 점프.

→ 즉시 Step 5 실행.

## Step 5: 🔍 자동 탐지 (병렬 실행)

**아래 명령들을 모두 병렬로 실행한다.** 각각 독립적이므로 동시에 수행해도 안전하다.

병렬 그룹 A (Bash 명령 — 동시에 실행):

```bash
# [A1] base_branch
cd "$DETECT_DIR" && gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null || echo ""

# [A2] fork_workflow + remotes
cd "$DETECT_DIR" && git remote -v 2>/dev/null

# [A3] jira_pattern
cd "$DETECT_DIR" && git log --oneline -20 2>/dev/null | grep -oE '[A-Z]+-[0-9]+' | sort -u | head -1

# [A4] timezone
date +%Z 2>/dev/null

# [A5] shared_types_dir
cd "$DETECT_DIR" && ls -d typings/ types/ shared/ 2>/dev/null | head -1

# [A6] lock file (루트 → 1-depth 하위 fallback, node_modules 제외)
cd "$DETECT_DIR" && ls yarn.lock package-lock.json pnpm-lock.yaml 2>/dev/null | head -1 || \
  find "$DETECT_DIR" -maxdepth 2 \( -name "yarn.lock" -o -name "package-lock.json" -o -name "pnpm-lock.yaml" \) -not -path "*/node_modules/*" 2>/dev/null | head -1
```

병렬 그룹 B (package.json 탐지):

1. 먼저 `$DETECT_DIR/package.json` 존재 여부를 확인한다.
   - **있으면** → Read 도구로 파싱해 `scripts.test`, `scripts.lint`, `scripts.format` 또는 `scripts.prettier` 추출.
   - **없으면 (모노레포)** → Bash로 1-depth 하위 디렉토리를 탐색한다:

```bash
find "$DETECT_DIR" -maxdepth 2 -name "package.json" -not -path "*/node_modules/*" 2>/dev/null
```

결과에서 각 `package.json`을 Read 도구로 읽어 scripts를 확인한다. 여러 개가 있으면 test/lint script가 포함된 첫 번째 것을 사용한다.

### 탐지 결과 조합

탐지 결과를 변수에 저장한다:

| 변수 | 탐지 로직 | 폴백 |
|------|-----------|------|
| `$detected_base_branch` | A1 결과. fork이면 `upstream/{branch}`, 아니면 `upstream/{branch}` | `upstream/main` |
| `$detected_fork` | A2에서 `upstream` remote 존재 여부 | `false` |
| `$detected_jira` | A3 결과에서 프로젝트 prefix 추출 (e.g., `VREW` → `VREW-\d+`) | (빈 값) |
| `$detected_test` | B에서 test script. 패키지 매니저에 맞게 조정 (e.g., `yarn test --run`) | (빈 값) |
| `$detected_lint` | B에서 lint script | (빈 값) |
| `$detected_format` | B에서 format/prettier script | (빈 값) |
| `$detected_timezone` | A4 결과를 IANA 형식으로 변환 (e.g., `KST` → `Asia/Seoul`) | `UTC` |
| `$detected_deps` | lock file 탐지 결과: `yarn.lock` → `yarn install`, `package-lock.json` → `npm install` | (빈 값) |
| `$detected_types` | A5 결과 | (빈 값) |

→ 즉시 Step 6 실행.

## Step 6: 🎛️ 인터랙티브 파라미터 설정

### 사전 질문: 자동 설정 여부

AskUserQuestion:

```yaml
questions:
  - question: "파라미터 설정을 어떻게 진행할까요?"
    header: "설정 방식"
    options:
      - label: "🚀 알아서 하기 (Recommended)"
        description: "모든 항목을 자동 탐지 값 또는 기본 Recommended 값으로 설정"
      - label: "직접 선택"
        description: "각 항목을 직접 확인하고 선택"
```

**"알아서 하기"를 선택한 경우**: 배치 1, 배치 2 질문을 모두 건너뛰고, 모든 설정 항목을 Recommended 값(탐지 실패 시 기본값)으로 적용한 뒤 자동 유도 단계로 이동한다.

**"직접 선택"을 선택한 경우**: 아래 배치 1부터 순서대로 진행한다.

### 배치 1: 핵심 설정 (4개)

AskUserQuestion:

```yaml
questions:
  - question: "PR과 diff의 기준 브랜치는?"
    header: "base_branch"
    options:
      - label: "$detected_base_branch (Recommended)"
        description: "자동 탐지됨. remote prefix 포함 가능 (e.g., upstream/develop)"
      - label: "upstream/main"
        description: "단일 리모트 프로젝트의 일반적 기본값"
  - question: "fork 기반 워크플로우인가요?"
    header: "fork"
    options:
      - label: "$detected_fork (Recommended)"
        description: "origin=내 fork, upstream=조직 repo"
      - label: "{반대값}"
        description: ""
  - question: "Jira 이슈 키 패턴은?"
    header: "Jira"
    options:
      - label: "$detected_jira (Recommended)"  # 탐지 실패면 "없음"을 Recommended로
        description: "커밋에서 탐지된 패턴 (e.g., PROJ-\\d+)"
      - label: "없음"
        description: "Jira 연동 비활성"
  - question: "worktree 사용 정책은?"
    header: "worktree"
    options:
      - label: "optional (Recommended)"
        description: "worklog-start에서 선택적으로 사용"
      - label: "always"
        description: "항상 worktree에서 작업"
      - label: "never"
        description: "worktree 사용 안 함"
```

→ 즉시 배치 2 실행.

### 배치 2: 명령어 + 부가 설정 (3~4개)

jira_pattern을 설정한 경우 jira_base_url을 포함한다. 아니면 3개만 묻는다.

AskUserQuestion:

```yaml
questions:
  # jira가 설정된 경우에만 포함:
  - question: "Jira 이슈 URL prefix는? (e.g., https://company.atlassian.net/browse/)"
    header: "Jira URL"
    options:
      - label: "직접 입력"
        description: "Other를 선택해 URL을 입력하세요"
      - label: "없음"
        description: "URL 매핑 없이 키만 사용"

  - question: "테스트 실행 명령은?"
    header: "test"
    options:
      - label: "$detected_test (Recommended)"  # 탐지 실패면 "없음"을 Recommended로
        description: "package.json에서 탐지됨"
      - label: "없음"
        description: "테스트 명령 미설정"
  - question: "린트 명령은?"
    header: "lint"
    options:
      - label: "$detected_lint (Recommended)"
        description: "package.json에서 탐지됨"
      - label: "없음"
        description: "린트 명령 미설정"
  - question: "worklog-start에서 Slack 컨텍스트를 수집할까요?"
    header: "Slack"
    options:
      - label: "false (Recommended)"
        description: "Slack 연동 안 함"
      - label: "true"
        description: "worklog 시작 시 Slack 채널에서 컨텍스트 수집"
```

→ 즉시 자동 유도값 계산.

### 자동 유도 (질문 없이 결정)

사용자 응답과 탐지 결과로 나머지 값을 자동 결정한다:

| 설정 | 유도 규칙 |
|------|-----------|
| `branch_pattern` | jira 설정됨 → `feature/{jira_key}.{task_name_short}` / 아니면 → `feature/{task_name}` |
| `develop_sync` | fork=true → `git fetch origin && git fetch upstream` / false → `git fetch upstream` |
| `dependency_install` | `$detected_deps` 사용. 빈 값이면 빈 값 유지 |
| `format_command` | `$detected_format` 사용. 빈 값이면 빈 값 유지 |
| `timezone` | `$detected_timezone` |
| `timestamp_suffix` | timezone의 약어 (e.g., `Asia/Seoul` → `KST`, `America/New_York` → `EST`) |
| `shared_types_dir` | `$detected_types` 사용. 빈 값이면 빈 값 유지 |

→ 즉시 파일 생성.

### 파일 생성

`$SKILLS_DIR/_templates/project-params.local.md` 템플릿을 `$PARAMS_PATH`로 복사한다.
Edit 도구로 각 설정의 `기본값` 열을 사용자가 확인/선택한 실제 값으로 교체한다.
열 이름도 `기본값`에서 `값`으로 바꾼다.

```bash
mkdir -p "$(dirname "$PARAMS_PATH")"
cp "$SKILLS_DIR/_templates/project-params.local.md" "$PARAMS_PATH"
```

→ 즉시 Step 7 실행.

## Step 7: ✅ 결과 보고

여기서 처음으로 사용자에게 텍스트를 출력한다. 설정한 모든 값(사용자 선택 + 자동 유도)을 보여준다:

```
✅ claude-skills 설치 완료!

  📂 스킬:            {$SKILL_COUNT}개 → {$SKILLS_DIR}
  🤖 OMC:             {$OMC_STATUS}
  🎭 Playwright MCP:  {$PLAYWRIGHT_STATUS}
  ⚙️  프로젝트 설정:   {$PARAMS_PATH 또는 "건너뜀"}

  [사용자 선택]
    base_branch:         {값}
    fork_workflow:       {값}
    jira_pattern:        {값}
    worktree_policy:     {값}
    test_command:        {값}
    lint_command:        {값}
    slack_integration:   {값}

  [자동 유도]
    branch_pattern:      {값}
    develop_sync:        {값}
    dependency_install:  {값}
    timezone:            {값}
    timestamp_suffix:    {값}
    shared_types_dir:    {값}
    format_command:      {값}

🚀 추천 시작점:
  /worklog-start     — 새 작업 시작
  /vauto             — 자동 루프 실행
  /vplan             — 구조화된 플래닝
  /vimpl             — TDD 기반 구현
  /exhaustive-review — 3인 페르소나 토론 리뷰
```

→ 즉시 Step 8 실행.

## Step 8: 💬 에이전트의 조언

WebFetch로 아래 URL을 가져온 뒤, 가져온 내용을 그대로 사용자에게 텍스트로 출력한다:

https://github.com/jyeokchoi/claude-skills#claude의-조언

출력 형식:
```
> 마지막으로, 에이전트가 한마디 하고 싶답니다:

{가져온 내용}
```

→ 즉시 Step 9 실행.

## Step 9: 🧹 정리 안내

설치가 완료되었으므로 `_install` 스킬은 더 이상 필요하지 않다. 사용자에게 안내한다:

> `_install` 스킬은 설치 전용이라 더 이상 필요하지 않습니다. 원하시면 삭제하세요:
> ```
> rm -rf {$SKILLS_DIR}/_install
> ```

이제 실행하라.
