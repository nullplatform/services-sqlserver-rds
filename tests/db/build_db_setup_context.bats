#!/usr/bin/env bats

load '../helpers/common'

setup() {
  setup_mock_bin
  make_aws_mock

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/work"
  export TFSTATE_BUCKET="acme-tofu-state"
  export TFSTATE_KEY_PREFIX="services/rds-sqlserver/svc-1/"
  export CONTEXT='{"service":{"id":"svc-1"},"type":"update","entity_nrn":"organization=1:account=2"}'

  export SERVER_HOSTNAME="sql.example.rds.amazonaws.com"
  export SERVER_PORT="1433"
  export SERVER_MASTER_SECRET_ARN="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/master"
  export DB_NAME="app_42"
  export DB_USERNAME="app_42"

  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"
exit 0
MOCK
  chmod +x "$MOCK_BIN/np"
}

run_and_dump() {
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_db_setup_context' >/dev/null 2>&1; \
    echo \"DB_HOST=\$DB_HOST\"; echo \"DB_PORT=\$DB_PORT\"; \
    echo \"MASTER_SECRET_ARN=\$MASTER_SECRET_ARN\"; \
    echo \"TOFU_MODULE_DIR=\$TOFU_MODULE_DIR\"; echo \"TOFU_VARIABLES=\$TOFU_VARIABLES\"; \
    echo \"TOFU_INIT_VARIABLES=\$TOFU_INIT_VARIABLES\""
}

@test "stored service attributes resolve the connection without a lookup" {
  run_and_dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"DB_HOST=sql.example.rds.amazonaws.com"* ]]
  [[ "$output" == *"DB_PORT=1433"* ]]
  [[ "$output" == *"MASTER_SECRET_ARN=arn:aws:secretsmanager"* ]]
}

@test "a service that already knows its server never calls np service list" {
  run "$DB_SERVICE_PATH/scripts/aws/build_db_setup_context"
  [ "$status" -eq 0 ]
  run grep -c "service list" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "the tofu module and variables point at db_setup" {
  run_and_dump
  [[ "$output" == *"TOFU_MODULE_DIR=$DB_SERVICE_PATH/db_setup"* ]]
  [[ "$output" == *"-var=db_name=app_42"* ]]
  [[ "$output" == *"-var=db_username=app_42"* ]]
}

@test "the backend key is namespaced under this instance's prefix" {
  run_and_dump
  [[ "$output" == *"-backend-config=bucket=acme-tofu-state"* ]]
  [[ "$output" == *"-backend-config=key=services/rds-sqlserver/svc-1/db_setup.tfstate"* ]]
}

@test "a stored database name that is not a valid identifier aborts" {
  export DB_NAME="app-42"
  run "$DB_SERVICE_PATH/scripts/aws/build_db_setup_context"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a valid SQL Server identifier"* ]]
}

@test "the default port is the SQL Server one, not the PostgreSQL one" {
  unset SERVER_PORT
  run_and_dump
  [[ "$output" == *"DB_PORT=1433"* ]]
}

@test "a delete on a service that was never created skips cleanup instead of failing" {
  unset SERVER_HOSTNAME
  export CONTEXT='{"service":{"id":"svc-1"},"type":"delete","entity_nrn":"organization=1:account=2"}'
  run "$DB_SERVICE_PATH/scripts/aws/build_db_setup_context"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping DB cleanup"* ]]
  run grep -c "service list" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a create on a service with no discoverable server fails instead of guessing" {
  unset SERVER_HOSTNAME
  export CONTEXT='{"service":{"id":"svc-1"},"type":"create","entity_nrn":"organization=1:account=2"}'
  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"
echo '{"results":[]}'
MOCK
  chmod +x "$MOCK_BIN/np"
  run "$DB_SERVICE_PATH/scripts/aws/build_db_setup_context"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No active RDS SQL Server instance found"* ]]
}
