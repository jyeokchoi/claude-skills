---
name: sync-omc
description: OMC 릴리스 변경사항을 추적하고, 기존 스킬에 필요한 업데이트를 분석하여 기록한다.
argument-hint: "Usage: /sync-omc [--apply]"
allowed-tools: Read, Edit, Write, Bash(gh:*), Bash(grep:*), Bash(ls:*), Bash(cat:*), Bash(curl:*), Glob, Grep, Agent, AskUserQuestion
---

# OMC 동기화

oh-my-claudecode(OMC)의 릴리스 변경사항을 가져와서 기존 모든 스킬에 대해 필요한 변경사항을 분석하고 기록한다.

## 경로 규칙

> **`_shared/X`** -> `{Base directory}/../_shared/X` (`{Base directory}`는 시스템이 주입하는 "Base directory for this skill" 값)
> **`_install`** -> `{Base directory}/../_install/SKILL.md`

## 트리거

- "omc 업데이트됐어", "omc 동기화", "스킬 호환성 점검"
- `/sync-omc`

## 입력

- `--apply` (선택): 분석 결과를 바탕으로 스킬 수정까지 진행. 미제공 시 분석 보고서만 생성.

## 절차

### Step 1: 버전 확인

#### 1-1. 현재 베이스 버전 읽기

`_install/SKILL.md`의 frontmatter에서 `omc-base-version` 값을 읽는다.

```bash
grep 'omc-base-version' "{_install/SKILL.md 경로}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
```

-> `$BASE_VERSION` (e.g., `4.6.0`)

실패 시: `$BASE_VERSION = "unknown"` -> AskUserQuestion으로 버전 직접 입력 요청.

#### 1-2. 현재 설치된 OMC 버전 확인

```bash
ls ~/.claude/plugins/cache/omc/oh-my-claudecode/ 2>/dev/null | sort -V | tail -1
```

-> `$CURRENT_VERSION` (e.g., `4.7.6`)

실패 시: GitHub API로 최신 릴리스 확인:
```bash
gh api repos/Yeachan-Heo/oh-my-claudecode/releases/latest --jq '.tag_name' 2>/dev/null | sed 's/^v//'
```

#### 1-3. 버전 비교

- `$BASE_VERSION == $CURRENT_VERSION` -> "이미 최신 상태입니다." 출력 후 종료.
- `$BASE_VERSION < $CURRENT_VERSION` -> Step 2로 진행.
- `$BASE_VERSION == "unknown"` -> Step 2로 진행 (전체 릴리스 분석).

### Step 2: 릴리스 변경사항 수집

#### 2-1. CHANGELOG 로컬 우선 탐색

설치된 OMC의 CHANGELOG를 먼저 확인한다:

```bash
CHANGELOG_PATH="$HOME/.claude/plugins/cache/omc/oh-my-claudecode/$CURRENT_VERSION/CHANGELOG.md"
[ -f "$CHANGELOG_PATH" ] && echo "LOCAL" || echo "REMOTE"
```

- **LOCAL**: `Read`로 CHANGELOG.md 전체를 읽는다.
- **REMOTE**: GitHub API로 릴리스 노트를 수집한다.

#### 2-2. GitHub API로 릴리스 노트 수집 (REMOTE인 경우)

`$BASE_VERSION` 이후의 모든 릴리스 노트를 가져온다:

```bash
gh api repos/Yeachan-Heo/oh-my-claudecode/releases --paginate --jq \
  '.[] | select(.tag_name > "v'"$BASE_VERSION"'") | "## \(.tag_name)\n\(.body)\n---"'
```

#### 2-3. 변경사항 정리

수집한 릴리스 노트에서 스킬에 영향을 줄 수 있는 변경사항을 추출한다. 다음 카테고리로 분류:

| 카테고리 | 설명 | 예시 |
|----------|------|------|
| `breaking` | 기존 API/동작 변경 | tool 이름 변경, 파라미터 변경 |
| `deprecation` | 사용 중단 예정 | skill/tool 이름 deprecated |
| `new-feature` | 새 기능 추가 | 새 agent type, 새 tool |
| `behavior-change` | 동작 방식 변경 | team lifecycle 변경, hook 동작 변경 |
| `bugfix-relevant` | 스킬 동작에 영향 주는 버그 수정 | state 관리 변경 |

-> `$CHANGES` (분류된 변경사항 목록)

### Step 3: 스킬 영향도 분석

#### 3-1. 전체 스킬 목록 수집

```bash
find "{skills 루트}" -name "SKILL.md" -not -path "*/_install/*" -not -path "*/_templates/*"
```

#### 3-2. 병렬 분석

역할 `analyst`로 에이전트 팀을 구성한다 (_shared/agent-routing.md 참조). 최대 3개 에이전트를 병렬로 실행하여 스킬을 분석한다.

각 에이전트에게 전달할 프롬프트:

```
다음 OMC 변경사항과 스킬 파일들을 비교 분석하라.

## OMC 변경사항 (v{BASE_VERSION} -> v{CURRENT_VERSION})
{$CHANGES}

## 분석 대상 스킬
{할당된 스킬 파일 목록과 내용}

## 분석 기준

각 스킬에 대해 다음을 확인:

1. **breaking**: 스킬이 사용하는 OMC tool/API/agent가 변경되었는가?
   - tool 이름 변경 (e.g., `state_write` -> `omc_state_write`)
   - 파라미터 추가/삭제/변경
   - agent type 이름 변경
2. **deprecation**: 스킬이 deprecated된 기능을 사용하는가?
3. **new-feature**: 스킬이 활용할 수 있는 새 기능이 있는가?
   - 새 agent type 활용 가능
   - 새 tool로 기존 로직 단순화 가능
4. **behavior-change**: OMC 동작 변경으로 스킬의 가정이 깨지는가?
   - team lifecycle 변경
   - hook 실행 순서 변경
   - state 파일 경로/구조 변경

## 출력 형식

각 스킬별로:
- 스킬명
- 영향 여부: 있음/없음
- 영향 카테고리: breaking/deprecation/new-feature/behavior-change
- 구체적 위치: SKILL.md 내 해당 섹션/라인
- 필요한 변경: 구체적 수정 내용
- 우선순위: critical/high/medium/low
```

#### 3-3. 분석 결과 병합

에이전트 결과를 병합하여 단일 보고서로 정리한다.

### Step 4: 보고서 생성

`_install/omc-sync-report.md` 파일에 분석 결과를 기록한다:

```markdown
# OMC Sync Report

- **분석 일시**: {timestamp}
- **베이스 버전**: v{BASE_VERSION}
- **현재 버전**: v{CURRENT_VERSION}
- **분석 대상**: {스킬 수}개 스킬

## 요약

| 우선순위 | 스킬 수 |
|----------|---------|
| Critical | {N} |
| High     | {N} |
| Medium   | {N} |
| Low      | {N} |
| 영향 없음 | {N} |

## 주요 OMC 변경사항

### Breaking Changes
{목록}

### Deprecations
{목록}

### New Features
{목록}

### Behavior Changes
{목록}

## 스킬별 영향 분석

### [Critical] {스킬명}
- **영향 카테고리**: {카테고리}
- **위치**: {SKILL.md 내 위치}
- **현재**: {현재 코드/설정}
- **변경 필요**: {구체적 수정 내용}

### [High] {스킬명}
...

(영향 없는 스킬은 목록만 나열)

## 변경 없음
- {스킬명1}, {스킬명2}, ...
```

사용자에게 보고서 요약을 출력한다:

```
OMC 동기화 분석 완료 (v{BASE_VERSION} -> v{CURRENT_VERSION})

  Critical: {N}개
  High:     {N}개
  Medium:   {N}개
  Low:      {N}개
  영향 없음: {N}개

  보고서: {보고서 경로}
```

### Step 5: 적용 (--apply 플래그가 있는 경우)

`--apply` 플래그가 없으면 여기서 종료.

#### 5-1. 적용 범위 확인

AskUserQuestion:

```yaml
question: "어떤 범위까지 자동 적용할까요?"
header: "적용 범위"
options:
  - label: "Critical + High만"
    description: "필수 변경만 적용"
  - label: "Critical + High + Medium"
    description: "권장 변경까지 적용"
  - label: "전체"
    description: "Low 포함 모든 변경 적용"
  - label: "하나씩 확인"
    description: "각 변경을 개별적으로 승인/거부"
```

#### 5-2. 스킬 수정 실행

선택된 범위의 변경사항을 적용한다:

1. 각 스킬의 `SKILL.md`를 `Edit`으로 수정
2. 수정된 파일 목록을 사용자에게 보고
3. "하나씩 확인" 선택 시: 각 변경마다 AskUserQuestion으로 승인/거부

#### 5-3. 베이스 버전 갱신

모든 적용이 완료되면 `_install/SKILL.md`의 `omc-base-version`을 `$CURRENT_VERSION`으로 업데이트:

```
Edit: _install/SKILL.md
  old: omc-base-version: "{BASE_VERSION}"
  new: omc-base-version: "{CURRENT_VERSION}"
```

#### 5-4. 보고서 업데이트

`omc-sync-report.md`에 적용 결과를 추가:

```markdown
## 적용 결과

- **적용 일시**: {timestamp}
- **적용 범위**: {선택된 범위}
- **적용 완료**: {N}개
- **건너뜀**: {N}개
- **베이스 버전 갱신**: v{BASE_VERSION} -> v{CURRENT_VERSION}
```

### Step 6: 완료 보고

```
OMC 동기화 완료!

  v{BASE_VERSION} -> v{CURRENT_VERSION}
  수정된 스킬: {N}개
  보고서: {보고서 경로}

  다음 단계:
  - 변경된 스킬을 검토하려면: git diff
  - 설치 디렉토리에 반영하려면: 각 스킬 디렉토리를 ~/.claude/skills/에 복사
```

## 절대 규칙

1. **보고서 없이 스킬을 수정하지 않는다.** Step 4(보고서 생성) 완료 후에만 수정 가능.
2. **`--apply` 없이 자동 수정하지 않는다.** 기본 동작은 분석 + 보고서 생성만.
3. **`_install/SKILL.md`는 `omc-base-version` 필드만 수정한다.** 다른 필드는 건드리지 않는다.
4. **영향 없는 스킬은 수정하지 않는다.** 분석 결과 영향이 확인된 스킬만 수정 대상.
5. **CHANGELOG 로컬 우선.** 네트워크 호출을 최소화한다.
6. **보고서는 항상 `_install/omc-sync-report.md`에 기록한다.** 이전 보고서가 있으면 덮어쓴다.
