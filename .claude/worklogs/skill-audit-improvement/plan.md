# 구현 체크리스트: 스킬 감사 개선

> 기반: `prd.md` (REQ-1~5), `analysis.md` (C-1, C-2, C-3, I-2, I-3)
> 확정 결정: REQ-1/REQ-2는 sonnet 유지 + 다운그레이드 주석 추가

---

## Phase 1: 컨벤션 정의 (REQ-4)

- [x] **IMPL-1**: `skills/_shared/agent-routing.md` — 60행과 62행 사이에 "모델 오버라이드 규칙" 서브섹션 추가

  **삽입 위치**: `Claude Task() 호출 예시` 코드 블록 닫힘(60행 ` ``` `) 뒤, `### omc-teams 호출 예시`(62행) 앞

  **추가할 텍스트**:
  ```markdown

  ### 의도적 모델 오버라이드 규칙

  기본 model과 다른 model을 사용하는 경우, Task() 호출 코드 바로 위에 사유 주석을 명시한다:

  ```
  # 의도적 다운그레이드: {사유}
  Task(subagent_type="oh-my-claudecode:critic", model="sonnet", ...)
  ```

  - 다운그레이드(opus→sonnet, sonnet→haiku): 비용/속도 최적화, read-only 검증 등 경량 작업
  - 업그레이드(sonnet→opus, haiku→sonnet): 복잡도 증가, 깊은 분석 필요
  - 기존 문서화된 사례: `pr-review`(code-reviewer sonnet), `vplan`(code-reviewer sonnet)

  ```

  **검증**: agent-routing.md에 "의도적 모델 오버라이드 규칙" 섹션이 존재하고, 주석 형식 예시가 포함되어 있다.

---

## Phase 2: 모델 불일치 해소 (REQ-1 + REQ-2)

- [x] **IMPL-2**: `skills/workflow/vqa/SKILL.md:82` — critic 호출에 다운그레이드 사유 주석 추가

  **현재** (82행):
  ```
  Task(subagent_type="oh-my-claudecode:critic", model="sonnet",
  ```

  **변경 후** (81행 뒤에 주석 삽입, 82행 유지):
  ```
  # 의도적 다운그레이드: read-only 의도 검증 — 워크로그 대비 구현 일치 확인으로 sonnet 충분
  Task(subagent_type="oh-my-claudecode:critic", model="sonnet",
  ```

  **검증**: 82행 바로 위에 `# 의도적 다운그레이드:` 주석이 존재한다.

- [x] **IMPL-3**: `skills/workflow/vqa/SKILL.md:153` — analyst 호출에 다운그레이드 사유 주석 추가

  **현재** (153행):
  ```
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **변경 후** (152행 뒤에 주석 삽입, 153행 유지):
  ```
  # 의도적 다운그레이드: read-only 테스트 커버리지 분석 — 패턴 매칭 중심으로 sonnet 충분
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **검증**: 153행 바로 위에 `# 의도적 다운그레이드:` 주석이 존재한다.

- [x] **IMPL-4**: `skills/request/request-to-designer/SKILL.md:37` — analyst 호출에 다운그레이드 사유 주석 추가

  **현재** (37행):
  ```
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **변경 후** (36행 뒤에 주석 삽입, 37행 유지):
  ```
  # 의도적 다운그레이드: read-only UI 변경 분류 — 파일 매칭/분류 중심으로 sonnet 충분
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **검증**: 37행 바로 위에 `# 의도적 다운그레이드:` 주석이 존재한다.

- [x] **IMPL-5**: `skills/request/request-to-qa/SKILL.md:133` — analyst 호출에 다운그레이드 사유 주석 추가

  **현재** (133행):
  ```
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **변경 후** (132행 뒤에 주석 삽입, 133행 유지):
  ```
  # 의도적 다운그레이드: read-only 테스트 커버리지 갭 분석 — 파일 매칭 중심으로 sonnet 충분
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **검증**: 133행 바로 위에 `# 의도적 다운그레이드:` 주석이 존재한다.

- [x] **IMPL-6**: `skills/request/request-to-ux-researcher/SKILL.md:34` — analyst 호출에 다운그레이드 사유 주석 추가

  **현재** (34행):
  ```
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **변경 후** (33행 뒤에 주석 삽입, 34행 유지):
  ```
  # 의도적 다운그레이드: read-only 번역 키 맥락 분석 — 파일 매칭/분류 중심으로 sonnet 충분
  Task(subagent_type="oh-my-claudecode:analyst", model="sonnet",
  ```

  **검증**: 34행 바로 위에 `# 의도적 다운그레이드:` 주석이 존재한다.

---

## Phase 3: 독립 수정 (REQ-3 + REQ-5)

- [x] **IMPL-7**: `skills/workflow/vauto/SKILL.md` — 절대 규칙 섹션(417행)과 "이제 실행하라."(419행) 사이에 Skill() 강제 규칙 추가

  **삽입 위치**: 417행 뒤, 419행 "이제 실행하라." 앞

  **추가할 텍스트**:
  ```markdown
  - **`/worklog-start`와 `/worklog-finish`를 반드시 Skill 도구로 호출한다.** 워크로그 생성은 `Skill("worklog-start", ...)`로, 워크플로우 마무리는 `Skill("worklog-finish", ...)`로만 수행한다. Write/Edit/Bash로 워크로그를 수동 생성하거나, commit/push/PR/Jira/Gist/worktree 정리를 직접 수행하지 않는다.
  ```

  **검증**: vauto/SKILL.md의 "## 절대 규칙" 섹션에 `/worklog-start`와 `/worklog-finish`를 Skill 도구로 호출하라는 규칙이 존재하고, vwork/SKILL.md:446과 내용이 동일하다.

- [x] **IMPL-8**: `skills/worklog/worklog-compact/SKILL.md:43-50` — Step 1의 조건부 참조를 무조건 참조로 변경

  **현재** (43-50행):
  ```markdown
  - `_shared/resolve-worklog-target.md`가 존재하는 경우:
    > **Shared**: `_shared/resolve-worklog-target.md` 절차를 따른다. (`required_files`: 없음)
  - 없는 경우 폴백:
    - $ARGUMENTS가 경로이면 해당 경로 사용
    - 없으면 활성 워크로그 자동 탐색:
      ```bash
      find .claude/worklogs -name "worklog.md" -type f 2>/dev/null | head -5
      ```
  ```

  **변경 후** (43-50행을 아래 1행으로 교체):
  ```markdown
  - `_shared/resolve-worklog-target.md`를 로드하고 해당 절차를 따른다 (`required_files`: 없음).
  ```

  **참고**: workflow 스킬들(vqa:46, vplan:46, vimpl:113, vanalyze:44, vtest:47)이 사용하는 무조건 참조 패턴과 동일. worklog-amend/SKILL.md:42-43도 같은 조건부 패턴이지만 본 태스크 스코프 외.

  **검증**: worklog-compact/SKILL.md의 Step 1에서 "존재하는 경우" 조건부 분기와 폴백 로직이 제거되고, 무조건 참조 1행만 존재한다.

---

## 검증 체크리스트

- [x] **VERIFY-1**: agent-routing.md에 "의도적 모델 오버라이드 규칙" 섹션 존재 확인
- [x] **VERIFY-2**: vqa/SKILL.md에 critic(82행), analyst(153행) 다운그레이드 주석 존재 확인
- [x] **VERIFY-3**: request-to-designer(37행), request-to-qa(133행), request-to-ux-researcher(34행) 다운그레이드 주석 존재 확인
- [x] **VERIFY-4**: vauto/SKILL.md 절대 규칙에 Skill() 강제 규칙 존재 및 vwork/SKILL.md:446과 내용 일치 확인
- [x] **VERIFY-5**: worklog-compact/SKILL.md Step 1이 무조건 참조 패턴으로 변경 확인
