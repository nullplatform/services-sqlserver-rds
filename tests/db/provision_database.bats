#!/usr/bin/env bats

load '../helpers/common'

MIGRATOR_SECRET="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/db/app_42/migrator"

make_tofu_outputs_mock() {
  local app_password="$1"
  cat > "$MOCK_BIN/tofu" <<MOCK
#!/usr/bin/env bash
echo "tofu \$*" >> "$MOCK_LOG"
if [ "\$1 \$2" = "output -raw" ]; then
  case "\$3" in
    db_password)         echo "$app_password" ;;
    migrator_secret_arn) echo "$MIGRATOR_SECRET" ;;
    *) echo "tofu: output \$3 not found" >&2; exit 1 ;;
  esac
fi
exit 0
MOCK
  chmod +x "$MOCK_BIN/tofu"
}

make_secrets_mock() {
  local migrator_username="$1" migrator_password="$2"
  cat > "$MOCK_BIN/aws" <<MOCK
#!/usr/bin/env bash
echo "aws \$*" >> "$MOCK_LOG"
[ "\$1 \$2" = "secretsmanager get-secret-value" ] || { echo "aws mock: unexpected \$*" >&2; exit 1; }
case "\$4" in
  "$MIGRATOR_SECRET") echo '{"username":"$migrator_username","password":"$migrator_password","host":"db","port":"1433","dbname":"app_42"}' ;;
  "\$MASTER_SECRET_ARN") echo '{"username":"npmaster","password":"s3cr3t"}' ;;
  *) echo "aws mock: no secret \$4" >&2; exit 254 ;;
esac
MOCK
  chmod +x "$MOCK_BIN/aws"
}

setup() {
  setup_mock_bin
  make_sqlcmd_mock 0
  make_secrets_mock "migrator_user_app_42" "MiGr4t0rPassw0rdMiGr4t0rPassw0rd"
  make_tofu_outputs_mock "aB3dEfGhIjKlMnOpQrStUvWxYz012345"

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$OUTPUT_DIR"
  export DB_HOST="db.example.rds.amazonaws.com"
  export DB_PORT="1433"
  export DB_NAME="app_42"
  export DB_USERNAME="app_42"
  export MIGRATOR_USERNAME="migrator_user_app_42"
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

@test "the migrations login is created against master with the password from its secret" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d master .*create_database_and_login.sql -v DbName=app_42 -v DbUser=migrator_user_app_42 -v DbPassword=MiGr4t0rPassw0rdMiGr4t0rPassw0rd" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "the migrations user is db_owner of the application database only" {
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42 .*create_user.sql -v DbUser=migrator_user_app_42$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "-d app_42 .*add_db_owner.sql -v DbUser=migrator_user_app_42$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "add_db_owner.sql -v DbUser=app_42$" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an empty tofu password aborts instead of setting a blank login" {
  make_tofu_outputs_mock ""
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an empty migrations password aborts before any connection" {
  make_secrets_mock "migrator_user_app_42" ""
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  [[ "$output" == *"generated password is empty"* ]] || false
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a migrations secret for another user aborts before any connection" {
  make_secrets_mock "migrator_user_other" "MiGr4t0rPassw0rdMiGr4t0rPassw0rd"
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is for user 'migrator_user_other', expected 'migrator_user_app_42'"* ]] || false
  run grep -c "^sqlcmd " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an unreadable migrations secret aborts before any connection" {
  export MIGRATOR_SECRET="arn:aws:secretsmanager:us-east-1:1:secret:missing"
  make_tofu_outputs_mock "aB3dEfGhIjKlMnOpQrStUvWxYz012345"
  export MIGRATOR_SECRET="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/db/app_42/migrator"
  run "$DB_SERVICE_PATH/scripts/aws/provision_database"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read the migrations credentials from arn:aws:secretsmanager:us-east-1:1:secret:missing"* ]] || false
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

@test "cleanup also removes the migrations user and its login, derived from the database name" {
  unset MIGRATOR_USERNAME
  run "$DB_SERVICE_PATH/scripts/aws/drop_database_user"
  [ "$status" -eq 0 ]
  run grep -c -- "-d app_42 .*drop_user.sql -v DbUser=migrator_user_app_42$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "-d master .*drop_login.sql -v DbUser=migrator_user_app_42$" "$MOCK_LOG"
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
