# 프로젝트 타입 결정

스킬이 `PROJECT_TYPE`을 필요로 할 때 사용하는 공통 절차.

## 절차

### ORCHESTRATED=true인 경우

`state_read(mode="vwork").project_type` 값을 사용한다 (자체 감지 건너뜀).

### 독립 실행 (ORCHESTRATED=false)인 경우

1. `rules/project-params.local.md`에서 `project_type` 확인
2. 설정되지 않은 경우 자동 감지:
   - package.json에 `react`, `vue`, `svelte`, `next`, `nuxt`, `vite` 포함 → `frontend`
   - package.json + 서버 프레임워크(`express`, `fastify`, `koa`) + 프론트엔드 프레임워크 동시 존재 → `fullstack`
   - package.json만 있고 프론트엔드 프레임워크 없음 → `backend`
   - go.mod / pyproject.toml / Cargo.toml만 있고 UI 없음 → `backend`
   - SKILL.md / 마크다운 전용 → `library`
3. 감지 불가 시 → `library`

## 출력

- `PROJECT_TYPE` = `frontend` / `backend` / `fullstack` / `cli` / `library`
