# 상태 보존 규칙

`state_write` 호출 시 기존 필드 유실을 방지하는 공통 규칙.

## 규칙

모든 `state_write(mode="{mode}")` 호출에 적용된다:

1. 호출 전에 반드시 `state_read(mode="{mode}")`로 현재 상태를 읽는다.
2. 기존 필드를 모두 보존한 뒤, 변경할 필드만 덮어쓴다.
3. 누적 필드(`feedback_iterations`, `spawned_agents`, `current_item_index`, `verify_retry_count` 등) 유실 방지에 특히 주의한다.

## 예외

완료 시 최종 정리 (`state_write(mode="{mode}", data={ "active": false })`)는 상태 보존 불필요.
