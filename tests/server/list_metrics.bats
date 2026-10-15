#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/metrics'

setup() {
  load_metrics_helpers
}

@test "lists the instance metrics in the telemetry format" {
  run_script list_metrics
  [ "$status" -eq 0 ]
  assert_equal "$(echo "$captured_stdout" | jq -c '[.results[].name]')" '["CPUUtilization","DatabaseConnections","FreeStorageSpace","FreeableMemory","ReadIOPS","WriteIOPS","ReadLatency","WriteLatency"]'
  assert_equal "$captured_stderr" ""
  assert_equal "$(echo "$captured_stdout" | wc -l | tr -d ' ')" "1"
  assert_equal "$(echo "$captured_stdout" | jq '[.results[] | select(.unit and .title and (.available_filters | type == "array") and (.available_group_by | type == "array"))] | length')" "8"
}

@test "lists only metrics that fetch_metric can query" {
  run_script list_metrics
  for metric in $(echo "$captured_stdout" | jq -r '.results[].name'); do
    CONTEXT=$(metric_context "$(jq -n --arg metric "$metric" --argjson service "$(server_service)" '{metric: $metric, service: $service}')")
    export CONTEXT
    run_script fetch_metric
    [ "$status" -eq 0 ]
  done
}
