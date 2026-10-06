#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/metrics'

setup() {
  load_metrics_helpers
  export SERVICE_PATH="$SERVER_SERVICE_PATH"
  export CONTEXT
  CONTEXT=$(metric_context "$(jq -n --argjson service "$(server_service)" '{
    metric: "CPUUtilization",
    start_time: "2026-10-02T10:00:00.000Z",
    end_time: "2026-10-02T11:00:00.000Z",
    period: 300,
    service: $service
  }')")
  cat > "$MOCK_BIN/np" <<'MOCK'
#!/bin/bash
echo "np $*" >> "$MOCK_LOG"
echo "{}"
MOCK
  chmod +x "$MOCK_BIN/np"
}

run_metric() {
  export NOTIFICATION_ACTION="$1"
  run bash -c "bash '$SERVICE_PATH/entrypoint/metric' >'$BATS_TEST_TMPDIR/stdout' 2>'$BATS_TEST_TMPDIR/stderr'"
  captured_stdout=$(cat "$BATS_TEST_TMPDIR/stdout")
  captured_stderr=$(cat "$BATS_TEST_TMPDIR/stderr")
}

run_entrypoint() {
  export NP_ACTION_CONTEXT
  NP_ACTION_CONTEXT=$(jq -nc --arg action "$1" '{notification: {action: $action, slug: "x", type: "custom", arguments: {}}}')
  run bash "$SERVICE_PATH/entrypoint/entrypoint" --service-path="$SERVICE_PATH"
}

@test "answers metric:list with the metric list and touches neither np nor aws" {
  run_metric "metric:list"
  [ "$status" -eq 0 ]
  assert_equal "$(echo "$captured_stdout" | jq '.results | length')" "8"
  assert_equal "$captured_stderr" ""
  assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "answers metric:data with only the metric result and a single aws call" {
  run_metric "metric:data"
  [ "$status" -eq 0 ]
  assert_equal "$(echo "$captured_stdout" | jq -r '.metric')" "CPUUtilization"
  assert_equal "$(echo "$captured_stdout" | wc -l | tr -d ' ')" "1"
  assert_equal "$captured_stderr" ""
  assert_equal "$(grep -c '^aws ' "$MOCK_LOG")" "1"
  assert_not_contains "$(cat "$MOCK_LOG")" "np "
}

@test "answers log requests with no entries" {
  run bash "$SERVICE_PATH/entrypoint/log"
  [ "$status" -eq 0 ]
  assert_equal "$output" '{"results":[]}'
  assert_equal "$(cat "$MOCK_LOG")" ""
}

@test "routes metric notifications away from the service action runner" {
  run_entrypoint "metric:list"
  [ "$status" -eq 0 ]
  assert_equal "$(echo "$output" | jq '.results | length')" "8"
  assert_not_contains "$(cat "$MOCK_LOG")" "service-action exec"
}

@test "routes log notifications away from the service action runner" {
  run_entrypoint "log:read"
  [ "$status" -eq 0 ]
  assert_equal "$output" '{"results":[]}'
  assert_not_contains "$(cat "$MOCK_LOG")" "service-action exec"
}

@test "still hands every other notification to the service action runner" {
  run_entrypoint "service:create"
  assert_contains "$(cat "$MOCK_LOG")" "np service-action exec"
}
