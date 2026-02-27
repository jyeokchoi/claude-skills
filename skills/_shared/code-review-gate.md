# 코드 리뷰 게이트 (공통 절차)

## 입력

- `diff_target` (기본값: `rules/project-params.md`의 `base_branch`, 없으면 auto-detect): diff 비교 대상 ref
- `changed_files`: 변경된 파일 목록

## 절차

### 1. 코드 리뷰 실행

`code-reviewer` 역할로 위임 (_shared/agent-routing.md 참조):
- `diff_target` 대비 diff 전달
- 변경된 파일 목록 및 전문 전달

### 2. 결과 판단

- Severity HIGH 이상 항목이 **없으면** → 통과, 계속 진행

- Severity HIGH 이상 항목이 **있으면**:
  1. 사용자에게 리뷰 결과 표시
  2. 수정 여부 확인 (AskUserQuestion)

### 3. 수정 루프

수정이 필요한 경우:
1. `executor` 역할에 위임하여 수정 (_shared/agent-routing.md 참조)
2. 수정 완료 후 Step 1로 돌아가 재리뷰
3. 같은 이슈가 2회 연속 지적되면 사용자에게 판단 위임

## 반환값

- `review_passed`: boolean (리뷰 통과 여부)
