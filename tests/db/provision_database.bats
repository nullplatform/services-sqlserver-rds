#!/usr/bin/env bats

load '../helpers/common'

setup() {
  setup_mock_bin
  make_sqlcmd_mock 0
  make_aws_mock
  make_tofu_mock "aB3dEfGhIjKlMnOpQrStUvWxYz012345"

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$OUTPUT_DIR"
  export DB_HOST="db.example.rds.amazonaws.com"
  export DB_PORT="1433"
  export DB_NAME="app_42"
  export DB_USERNAME="app_42"
  export MASTER_SECRET_ARN="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/master"
}

@test "the database and login are created against master" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d master .*create_database_and_login.sql" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "the database user is created against the application database" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42 .*create_user.sql" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "login creation and user creation are two separate invocations" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "2" ]
}

@test "the generated password reaches the login script" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-v DbPassword=aB3dEfGhIjKlMnOpQrStUvWxYz012345" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "an empty tofu password aborts instead of setting a blank login" {
  make_tofu_mock ""
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a skipped setup provisions nothing" {
  export SETUP_SKIPPED="true"
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an injected database name aborts before any connection" {
  export DB_NAME="app_42]; DROP DATABASE [master"
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "the user is removed from the database and the login from the server" {
  run "$DB_SERVICE_PATH/scripts/aws/drop_database_user"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42 .*drop_user.sql" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "-d master .*drop_login.sql" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "cleanup never issues a statement against the application database itself" {
  run "$DB_SERVICE_PATH/scripts/aws/drop_database_user"
  [ "$status" -eq 0 ]
  run grep -c "rds_drop_database\|DROP DATABASE" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "cleanup is a no-op when the service was never created" {
  export SETUP_SKIPPED="true"
  run "$DB_SERVICE_PATH/scripts/aws/drop_database_user"
  [ "$status" -eq 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}
