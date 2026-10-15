#!/usr/bin/env bash

load_metrics_helpers() {
  SCRIPTS_DIR="$SERVER_SERVICE_PATH/scripts/aws"
  setup_mock_bin
  export MOCK_CW_EXIT="${MOCK_CW_EXIT:-0}"
  export MOCK_CW_RESPONSE='{"Label":"x","Datapoints":[]}'
  unset AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN NOTIFICATION_ACTION

  cat > "$MOCK_BIN/aws" <<'MOCK'
#!/bin/bash
echo "aws $*" >> "$MOCK_LOG"
case "$*" in
  "cloudwatch get-metric-statistics"*)
    echo "cloudwatch credentials: ${AWS_ACCESS_KEY_ID:-agent}" >> "$MOCK_LOG"
    if [ "$MOCK_CW_EXIT" != "0" ]; then
      echo "An error occurred (AccessDenied) when calling the GetMetricStatistics operation" >&2
      exit "$MOCK_CW_EXIT"
    fi
    echo "$MOCK_CW_RESPONSE" ;;
  *)
    echo "unexpected aws call: $*" >&2
    exit 1 ;;
esac
MOCK

  cat > "$MOCK_BIN/np" <<'MOCK'
#!/bin/bash
echo "np $*" >> "$MOCK_LOG"
echo "{}"
MOCK
  chmod +x "$MOCK_BIN"/aws "$MOCK_BIN"/np
}

metric_context() {
  jq -n --argjson arguments "$1" '{arguments: $arguments}'
}

server_service() {
  jq -n '{
    id: "0f3a6b1e-9c2d-4e8f-a1b2-c3d4e5f60718",
    attributes: {
      hostname: "np-sql-0f3a6.abc.us-west-2.rds.amazonaws.com",
      port: 1433,
      db_instance_identifier: "np-sql-0f3a6",
      master_secret_arn: "arn:aws:secretsmanager:us-west-2:222222222222:secret:np-sql-0f3a6-master-AbCdEf"
    }
  }'
}

run_script() {
  local script="$1"
  run bash -c "bash '$SCRIPTS_DIR/$script' >'$BATS_TEST_TMPDIR/stdout' 2>'$BATS_TEST_TMPDIR/stderr'"
  captured_stdout=$(cat "$BATS_TEST_TMPDIR/stdout")
  captured_stderr=$(cat "$BATS_TEST_TMPDIR/stderr")
}

assert_equal() {
  if [ "$1" != "$2" ]; then
    echo "expected: $2"
    echo "actual:   $1"
    return 1
  fi
}

assert_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "expected to contain: $2"
    echo "actual: $1"
    return 1
  fi
}

assert_not_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "expected not to contain: $2"
    echo "actual: $1"
    return 1
  fi
}
