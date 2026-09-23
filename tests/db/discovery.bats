#!/usr/bin/env bats

load '../helpers/common'

SQLSERVER_ARN="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-sql/master"
POSTGRES_ARN="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds/np-pg/master"

filter_servers() {
  jq --argjson dims "$2" --arg prefix ":secret:nullplatform/rds-sqlserver/" \
    '[(.results // .) | .[] | . as $svc | select(
      (.attributes.hostname // "") != "" and
      ((.attributes.master_secret_arn // "") | contains($prefix)) and
      ($dims | to_entries | all(. as $kv | ($svc.dimensions[$kv.key] // null) == $kv.value))
    )]' <<< "$1"
}

@test "a PostgreSQL instance is not a candidate for a SQL Server database" {
  local payload
  payload=$(jq -n --arg arn "$POSTGRES_ARN" \
    '{results: [{id: "1", name: "pg", dimensions: {}, attributes: {hostname: "pg.rds", master_secret_arn: $arn}}]}')
  run filter_servers "$payload" '{}'
  [ "$(jq 'length' <<< "$output")" = "0" ]
}

@test "a SQL Server instance is a candidate" {
  local payload
  payload=$(jq -n --arg arn "$SQLSERVER_ARN" \
    '{results: [{id: "2", name: "sql", dimensions: {}, attributes: {hostname: "sql.rds", master_secret_arn: $arn}}]}')
  run filter_servers "$payload" '{}'
  [ "$(jq 'length' <<< "$output")" = "1" ]
  [ "$(jq -r '.[0].id' <<< "$output")" = "2" ]
}

@test "only the SQL Server instance survives when both engines share dimensions" {
  local payload
  payload=$(jq -n --arg sql "$SQLSERVER_ARN" --arg pg "$POSTGRES_ARN" \
    '{results: [
      {id: "1", name: "pg",  dimensions: {environment: "prod"}, attributes: {hostname: "pg.rds",  master_secret_arn: $pg}},
      {id: "2", name: "sql", dimensions: {environment: "prod"}, attributes: {hostname: "sql.rds", master_secret_arn: $sql}}
    ]}')
  run filter_servers "$payload" '{"environment":"prod"}'
  [ "$(jq 'length' <<< "$output")" = "1" ]
  [ "$(jq -r '.[0].id' <<< "$output")" = "2" ]
}

@test "an instance whose dimensions do not match is excluded" {
  local payload
  payload=$(jq -n --arg arn "$SQLSERVER_ARN" \
    '{results: [{id: "2", name: "sql", dimensions: {environment: "dev"}, attributes: {hostname: "sql.rds", master_secret_arn: $arn}}]}')
  run filter_servers "$payload" '{"environment":"prod"}'
  [ "$(jq 'length' <<< "$output")" = "0" ]
}

@test "an instance that has not finished creating is excluded" {
  local payload
  payload=$(jq -n --arg arn "$SQLSERVER_ARN" \
    '{results: [{id: "2", name: "sql", dimensions: {}, attributes: {hostname: "", master_secret_arn: $arn}}]}')
  run filter_servers "$payload" '{}'
  [ "$(jq 'length' <<< "$output")" = "0" ]
}

@test "two SQL Server instances are reported as ambiguous rather than picked at random" {
  local payload
  payload=$(jq -n --arg arn "$SQLSERVER_ARN" \
    '{results: [
      {id: "2", name: "a", dimensions: {}, attributes: {hostname: "a.rds", master_secret_arn: $arn}},
      {id: "3", name: "b", dimensions: {}, attributes: {hostname: "b.rds", master_secret_arn: $arn}}
    ]}')
  run filter_servers "$payload" '{}'
  [ "$(jq 'length' <<< "$output")" = "2" ]
}
