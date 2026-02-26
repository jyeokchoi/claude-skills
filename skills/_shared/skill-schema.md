# 스킬 파일 스키마

스킬 정의, 네이밍, 구조에 관한 규칙.

## 파일 시스템 구조

```
.claude/skills/
├── _shared/
│   ├── agent-routing.md          (에이전트 역할 → subagent_type 매핑)
│   ├── skill-schema.md            (이 파일)
│   └── ... (기타 공통 절차)
├── worklog-start/
│   └── SKILL.md                   (스킬 정의)
├── exhaustive-review/
│   └── SKILL.md
└── ...
```

**핵심 규칙:**

- 각 스킬은 `{스킬명}/SKILL.md` 경로에 위치
- 파일명은 항상 `SKILL.md` (대문자)
- `_shared/` 폴더: 공통 절차, 라우팅, 스키마 정의 (스킬이 아님)

## Frontmatter 필드

SKILL.md 파일의 맨 앞에 `---` 사이에 YAML 메타데이터를 정의한다.

### 필수 필드

| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `name` | string | 스킬 이름 (디렉터리명과 일치) | `worklog-start` |
| `description` | string | 한 줄 설명 (사용자 도움말용) | `Create a new task worklog` |

### 권장 필드

| 필드 | 타입 | 설명 | 예시 |
|------|------|------|------|
| `argument-hint` | string | 사용법 안내 (인자를 받는 스킬은 필수) | `Usage: /worklog-start [task-name]` |
| `allowed-tools` | comma-separated | 허용할 도구 목록 (기본: 전체) | `Bash(git:*), Read, Write, Task` |
| `triggers` | comma-separated | 자동 감지용 키워드 (skill 메커니즘에서 사용) | `worklog, start, new task` |

### 선택 필드

| 필드 | 타입 | 설명 |
|------|------|------|
| `category` | string | 스킬 카테고리 (예: workflow, utility, review) |
| `requires-worktree` | boolean | 워크트리 필수 여부 |
| `team-capable` | boolean | Team 모드 호환성 |

### Frontmatter 예시

```yaml
---
name: worklog-start
description: Create a new task worklog and bootstrap it using analyze + plan agents
argument-hint: 'Usage: /worklog-start [task-name] [brief]'
allowed-tools: Bash(mkdir:*), Bash(cp:*), Bash(git:*), Read, Write, Edit, Task
triggers: worklog, start, create task, bootstrap
---
```

## 네이밍 규칙

스킬 이름에 따라 범위와 용도가 결정된다.

### 1. 프로젝트 전용 스킬: `{project}:` 접두사

특정 프로젝트의 워크플로우에 깊게 통합된 스킬.

**예시:**
- `myproject:deploy` — 특정 프로젝트 배포 자동화
- `myproject:release-notes` — 특정 프로젝트 릴리스 노트 생성

**특징:**
- 워크로그와 강하게 연결됨
- 프로젝트 전용 도구 (Jira, Slack 등) 통합
- 대부분 인자를 받음

### 2. 범용 스킬: 접두사 없음

모든 프로젝트에서 사용 가능한 스킬.

**예시:**
- `autopilot` — 자동 실행
- `exhaustive-review` — 코드리뷰
- `tdd-review` — TDD 리뷰

**특징:**
- 프로젝트 독립적
- 프로젝트 전용 스킬에서도 사용 가능

## 본문 구조 (권장)

SKILL.md 본문은 다음 구조를 따른다.

### 1. 목적/설명

스킬의 고수준 목적을 설명. 사용자가 "언제 이 스킬을 써야 하는가?"를 이해하도록.

```markdown
## 목적

이 스킬은 신규 작업을 시작할 때 다음을 자동으로 처리한다:
1. git 워크트리 생성 (격리된 작업 공간)
2. 워크로그 초기화 및 부트스트랩
```

### 2. 전제조건 (있을 경우)

스킬 실행 전 만족해야 할 조건.

```markdown
## 전제조건

- git 저장소가 clean 상태 (커밋되지 않은 변경사항 없음)
```

### 3. 입력 (Inputs)

`$ARGUMENTS`를 어떻게 파싱하는지 설명.

```markdown
## 입력

- `$ARGUMENTS`: 스킬에 전달된 원본 인자

## 인자 파싱 규칙

- 첫 번째 토큰: task-name
- 나머지 텍스트: task brief (선택사항)
```

### 4. 단계별 절차 (Steps)

스킬이 실행하는 각 단계를 상세히 설명.

```markdown
## 단계

### 1. 인자 파싱

- task_name, task_brief 추출

### 2. 커밋되지 않은 변경사항 확인

중단 조건: git diff 상태 확인

### 3. git 워크트리 생성

`create-worktree` 공통 절차 참조
(_shared/create-worktree.md)

### 4. 에이전트 부트스트랩

역할 `planner`로 위임 (_shared/agent-routing.md 참조):
  prompt: "..."
```

### 5. 공통 절차 참조

스킬이 공통 절차를 사용할 때, 절차 파일의 이름과 링크를 명시.

```markdown
**참조:** _shared/create-worktree.md
```

### 6. 출력 (Output)

스킬이 반환하거나 출력하는 값들.

```markdown
## 출력

- `WORKLOG_DIR`: 생성된 워크로그 폴더 경로
```

### 7. 에러 처리 (Error Handling)

예상 가능한 에러 상황과 처리 방법.

```markdown
## 에러 처리

| 상황 | 처리 |
|------|------|
| git이 clean하지 않음 | 중단, 사용자에게 커밋 요청 |
| 워크트리 생성 실패 | 중단, 기존 워크트리 충돌 확인 |
```

### 8. 예시 (Examples)

스킬 사용 예시.

```markdown
## 예시

/worklog-start "새 기능 구현" "사용자 피드백을 바탕으로..."
```

## 에이전트 역할 참조 규칙

스킬에서 에이전트를 호출할 때는 **역할명만 명시**한다.

### 올바른 예

```markdown
역할 `architect`로 위임 (_shared/agent-routing.md 참조):
  model: opus
  prompt: "..."
```

### 잘못된 예 (피할 것)

```markdown
Task(subagent_type="oh-my-claudecode:architect", model="opus", prompt="...")
```

이유: 구현 세부사항(`subagent_type`)은 `_shared/agent-routing.md`에서 조회하도록 중앙화.

## 공통 절차 파일 목록

`_shared/` 폴더에 있는 공통 절차들:

| 파일 | 설명 |
|------|------|
| `agent-routing.md` | 에이전트 역할 → subagent_type 매핑 |
| `create-worktree.md` | git 워크트리 생성 |
| `print-worktree-summary.md` | 워크트리 정보 출력 |
| `create-pr.md` | Pull Request 생성 |
| `code-review-gate.md` | 코드리뷰 gating |
| `lint-format.md` | 린트 및 포맷 |
| `exclude-local-only-commits.md` | [LOCAL-ONLY] 커밋 제외 |
| `cleanup-worktree.md` | 워크트리 정리 |
| `resolve-worklog-target.md` | 워크로그 타겟 결정 |
| `skill-schema.md` | 이 파일 (스킬 스키마) |

## 스킬 간 호출 규칙

한 스킬이 다른 스킬을 호출할 때:

1. **명시:** SKILL.md 본문에서 호출 대상을 명시
   ```markdown
   다음으로 진행:
   /vanalyze (_shared/agent-routing.md 참조)
   ```
2. **추적성:** 의존 관계가 명확하도록 문서화
