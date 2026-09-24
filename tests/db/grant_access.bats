#!/usr/bin/env bats

load '../helpers/common'

setup() {
  setup_mock_bin
  make_sqlcmd_mock 0
  make_aws_mock

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export DB_HOST="db.example.rds.amazonaws.com"
  export DB_PORT="1433"
  export DB_NAME="app_42"
  export DB_USERNAME="app_42"
  export MASTER_SECRET_ARN="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/master"
}

@test "read-write asks for all three managed roles" {
  export LINK_ACCESS_LEVEL="read-write"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -eq 0 ]
  run grep -c -- "-v WantRead=1 -v WantWrite=1 -v WantDdl=1" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "read asks for the reader role and explicitly unsets the others" {
  export LINK_ACCESS_LEVEL="read"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -eq 0 ]
  run grep -c -- "-v WantRead=1 -v WantWrite=0 -v WantDdl=0" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "write asks for the writer role only" {
  export LINK_ACCESS_LEVEL="write"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -eq 0 ]
  run grep -c -- "-v WantRead=0 -v WantWrite=1 -v WantDdl=0" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "role membership is applied by set_role_members.sql" {
  export LINK_ACCESS_LEVEL="read-write"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -eq 0 ]
  run grep -c "sql/set_role_members.sql" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "grants run against the application database, never master" {
  export LINK_ACCESS_LEVEL="read-write"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "-d master" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an unset access level defaults to read-write" {
  unset LINK_ACCESS_LEVEL
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -eq 0 ]
  run grep -c -- "-v WantRead=1 -v WantWrite=1 -v WantDdl=1" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "an unknown access level aborts without touching the database" {
  export LINK_ACCESS_LEVEL="admin"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -ne 0 ]
  run grep -c "sqlcmd" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a username that is not a valid identifier aborts before connecting" {
  export LINK_ACCESS_LEVEL="read"
  export DB_USERNAME="app'; DROP LOGIN sa--"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -ne 0 ]
  run grep -c "sqlcmd" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a link that was never created is a no-op" {
  export LINK_NEVER_CREATED="true"
  export LINK_ACCESS_LEVEL="read"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -eq 0 ]
  run grep -c "sqlcmd" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a T-SQL failure fails the step" {
  make_sqlcmd_mock 1
  export LINK_ACCESS_LEVEL="read"
  run "$DB_SERVICE_PATH/scripts/aws/grant_access"
  [ "$status" -ne 0 ]
}

@test "revoke_access clears every managed role" {
  run "$DB_SERVICE_PATH/scripts/aws/revoke_access"
  [ "$status" -eq 0 ]
  run grep -c -- "-v WantRead=0 -v WantWrite=0 -v WantDdl=0" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "revoke_access is a no-op when the service has no database yet" {
  unset DB_NAME
  run "$DB_SERVICE_PATH/scripts/aws/revoke_access"
  [ "$status" -eq 0 ]
  run grep -c "sqlcmd" "$MOCK_LOG"
  [ "$output" = "0" ]
}
