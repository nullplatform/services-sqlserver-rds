#!/usr/bin/env bats

load '../helpers/common'

make_tofu_outputs_mock() {
  local app_password="$1" migrator_password="$2"
  cat > "$MOCK_BIN/tofu" <<MOCK
#!/usr/bin/env bash
echo "tofu \$*" >> "$MOCK_LOG"
if [ "\$1 \$2" = "output -raw" ]; then
  case "\$3" in
    db_password)       echo "$app_password" ;;
    migrator_password) echo "$migrator_password" ;;
    *) echo "tofu: output \$3 not found" >&2; exit 1 ;;
  esac
fi
exit 0
MOCK
  chmod +x "$MOCK_BIN/tofu"
}

setup() {
  setup_mock_bin
  make_sqlcmd_mock 0
  make_aws_mock
  make_tofu_outputs_mock "aB3dEfGhIjKlMnOpQrStUvWxYz012345" "MiGr4t0rPassw0rdMiGr4t0rPassw0rd"

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$OUTPUT_DIR"
  export DB_HOST="db.example.rds.amazonaws.com"
  export DB_PORT="1433"
  export DB_NAME="app_42"
  export DB_USERNAME="app_42"
  export MIGRATOR_USERNAME="app_42_mig"
  export MASTER_SECRET_ARN="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/master"
}

@test "the database and login are created against master" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d master .*create_database_and_login.sql .*-v DbUser=app_42 " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "the database user is created against the application database" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42 .*create_user.sql -v DbUser=app_42$" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "each user gets a login, a database user, and the migrator its db_owner membership" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "5" ]
}

@test "the generated password reaches the login script" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-v DbUser=app_42 -v DbPassword=aB3dEfGhIjKlMnOpQrStUvWxYz012345" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "the migrations login is created against master with its own password" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d master .*create_database_and_login.sql -v DbName=app_42 -v DbUser=app_42_mig -v DbPassword=MiGr4t0rPassw0rdMiGr4t0rPassw0rd" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "the migrations user is db_owner of the application database only" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42 .*create_user.sql -v DbUser=app_42_mig$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "-d app_42 .*add_db_owner.sql -v DbUser=app_42_mig$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "add_db_owner.sql -v DbUser=app_42$" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an empty tofu password aborts instead of setting a blank login" {
  make_tofu_outputs_mock "" "MiGr4t0rPassw0rdMiGr4t0rPassw0rd"
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an empty migrations password aborts before any connection" {
  make_tofu_outputs_mock "aB3dEfGhIjKlMnOpQrStUvWxYz012345" ""
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  [[ "$output" == *"migrator_password output is empty"* ]] || false
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a missing migrations username aborts before any connection" {
  unset MIGRATOR_USERNAME
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  [[ "$output" == *"migrations username is empty"* ]] || false
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
  run grep -c -- "-d app_42 .*drop_user.sql -v DbUser=app_42$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "-d master .*drop_login.sql -v DbUser=app_42$" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "cleanup also removes the migrations user and its login, derived from the app user" {
  unset MIGRATOR_USERNAME
  run "$DB_SERVICE_PATH/scripts/aws/drop_database_user"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42 .*drop_user.sql -v DbUser=app_42_mig$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "-d master .*drop_login.sql -v DbUser=app_42_mig$" "$MOCK_LOG"
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
