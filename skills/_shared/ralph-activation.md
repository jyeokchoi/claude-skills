# Ralph Loop 활성화

작업 지속성을 보장하기 위한 ralph loop 활성화 공통 절차.

## 전제 조건

- **`ORCHESTRATED=true`인 경우**: 이 절차 전체를 건너뛴다. vwork가 ralph loop을 관리하므로 서브 스킬이 별도로 활성화하지 않는다.
- **`state_read(mode="ralph").active=true`인 경우**: 이미 활성화됨. 건너뛴다.

## 절차

1. `rules/project-params.local.md`에서 `completion_promise` 사용 (기본값: `**WORKLOG_TASK_COMPLETE**`)
2. `state_write(mode="ralph")`:
   ```json
   { "active": true, "iteration": 1, "max_iterations": 100, "completion_promise": "{COMPLETION_PROMISE}", "worklog_path": "{WORKLOG_DIR}", "linked_ultrawork": true }
   ```
3. `state_write(mode="ultrawork")`:
   ```json
   { "active": true, "linked_to_ralph": true }
   ```

## 복귀 규칙

이 절차는 **부속 절차**다. 3단계를 모두 완료하면 즉시 호출자의 다음 단계로 복귀한다. 결과를 사용자에게 보고하거나 일시정지하지 않는다.
