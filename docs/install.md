# claude-skills 설치 가이드

이 문서는 LLM 에이전트가 사용자를 도와 claude-skills를 설치할 때 따르는 가이드이다.

## Step 1: oh-my-claudecode 확인

claude-skills는 [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode) (OMC)의 에이전트(executor, architect, explorer 등)를 활용한다. OMC 없이도 기본 동작은 가능하지만, 멀티에이전트 기능이 제한된다.

확인:

```bash
ls ~/.claude/plugins/cache/omc/oh-my-claudecode/ 2>/dev/null && echo "OMC installed" || echo "OMC not found"
```

- **OMC가 없는 경우:** 사용자에게 OMC 설치 여부를 물어본다. 설치를 원하면 [oh-my-claudecode 공식 레포](https://github.com/Yeachan-Heo/oh-my-claudecode)의 설치 가이드를 따른다.
- **OMC가 이미 있는 경우:** 다음 단계로 넘어간다.

## Step 2: 스킬 설치

install.sh를 실행한다. 겹치는 스킬이 있으면 자동으로 백업한다.

```bash
curl -sL https://raw.githubusercontent.com/jyeokchoi/claude-skills/main/install.sh | bash
```

설치 완료 후 확인:

```bash
ls ~/.claude/skills/vplan/SKILL.md && echo "OK" || echo "FAIL"
```

## Step 3: 프로젝트 설정

`_install` 스킬이 설치 직후 자동으로 프로젝트 파라미터 위치 선택 + 인터랙티브 설정까지 진행한다.
재설정이 필요하면 `_install` 스킬을 다시 다운로드해서 실행하면 된다.

## Step 4: 결과 보고

사용자에게 설치 결과를 알려준다:

1. 설치된 스킬 수: `ls -d ~/.claude/skills/*/SKILL.md 2>/dev/null | wc -l`
2. OMC 상태: 설치됨/미설치
3. 프로젝트 설정: 생성됨/건너뜀

추천 시작점:
- `/worklog-start` — 새 작업 시작 (Jira 연동, worktree 생성, 분석/플래닝)
- `/vplan` — 구조화된 플래닝
- `/vimpl` — TDD 기반 구현
- `/exhaustive-review` — 3인 페르소나 토론 리뷰

## Step 5: 에이전트의 조언

결과 보고 후, README의 "나만의 하네스와 워크플로우 만들기" 섹션을 사용자에게 보여준다:

https://github.com/jyeokchoi/claude-skills#나만의-하네스와-워크플로우-만들기
