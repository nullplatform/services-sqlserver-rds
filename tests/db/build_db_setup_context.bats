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
  export REGION="ap-south-1"
  export CONTEXT='{"service":{"id":"svc-1","slug":"payments"},"type":"update","entity_nrn":"organization=1:account=2"}'

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

@test "resources are named after the service slug and id" {
  run_and_dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=instance_name=payments-svc-1"* ]]
}

@test "the service name is used when the context has no slug" {
  export CONTEXT='{"service":{"id":"svc-1","name":"Payments DB"},"type":"update"}'
  run_and_dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=instance_name=payments-db-svc-1"* ]]
}

@test "the service is read from the api when the context carries neither slug nor name" {
  export CONTEXT='{"service":{"id":"svc-1"},"type":"update"}'
  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"
[ "\$1 \$2" = "service read" ] && echo '{"id":"svc-1","slug":"from-api"}'
exit 0
MOCK
  run_and_dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=instance_name=from-api-svc-1"* ]]
  grep -q "^np service read --id svc-1" "$MOCK_LOG"
}

write_db_setup_state() {
  export AWS_MOCK_STATE_FILE="$BATS_TEST_TMPDIR/db_setup.tfstate"
  cat > "$AWS_MOCK_STATE_FILE" <<'JSON'
{
  "version": 4,
  "outputs": {
    "hostname":          {"value": "sql.from-state.rds.amazonaws.com"},
    "port":              {"value": 1433},
    "master_secret_arn": {"value": "arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/master"},
    "database_name":     {"value": "app_42"},
    "db_username":       {"value": "app_42"}
  },
  "resources": [{"type": "aws_secretsmanager_secret", "name": "app"}]
}
JSON
}

run_delete_and_dump() {
  unset SERVER_HOSTNAME SERVER_PORT SERVER_MASTER_SECRET_ARN DB_NAME DB_USERNAME
  export CONTEXT='{"service":{"id":"svc-1","slug":"payments"},"type":"delete","entity_nrn":"organization=1:account=2"}'
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_db_setup_context' 2>&1; \
    echo \"DB_HOST=\$DB_HOST\"; echo \"MASTER_SECRET_ARN=\$MASTER_SECRET_ARN\"; \
    echo \"DB_NAME=\$DB_NAME\"; echo \"DB_USERNAME=\$DB_USERNAME\"; \
    echo \"SETUP_SKIPPED=\${SETUP_SKIPPED:-}\"; echo \"TOFU_VARIABLES=\$TOFU_VARIABLES\""
}

@test "a delete whose create failed before storing attributes cleans up from the tofu state" {
  write_db_setup_state
  run_delete_and_dump
  [ "$status" -eq 0 ]
  [[ "$output" != *"Skipping DB cleanup"* ]]
  [[ "$output" == *"DB_HOST=sql.from-state.rds.amazonaws.com"* ]]
  [[ "$output" == *"MASTER_SECRET_ARN=arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/master"* ]]
  [[ "$output" == *"DB_NAME=app_42"* ]]
  [[ "$output" == *"DB_USERNAME=app_42"* ]]
  [[ "$output" == *"-var=db_host=sql.from-state.rds.amazonaws.com"* ]]
  grep -q "get-object key=services/rds-sqlserver/svc-1/db_setup.tfstate" "$MOCK_LOG"
}

@test "a delete with a state that no longer holds resources skips cleanup" {
  write_db_setup_state
  jq '.resources = []' "$AWS_MOCK_STATE_FILE" > "$AWS_MOCK_STATE_FILE.tmp" && mv "$AWS_MOCK_STATE_FILE.tmp" "$AWS_MOCK_STATE_FILE"
  run_delete_and_dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping DB cleanup"* ]]
}

@test "a delete that cannot read the tofu state fails instead of reporting success" {
  export AWS_MOCK_STATE_FILE=denied
  run_delete_and_dump
  [ "$status" -ne 0 ]
  [[ "$output" == *"AccessDenied"* ]]
  [[ "$output" != *"Skipping DB cleanup"* ]]
}

@test "the region exported by build_context reaches the backend and the module" {
  run_and_dump
  [ "$status" -eq 0 ]
  [[ "$output" == *"-backend-config=region=ap-south-1"* ]]
  [[ "$output" == *"-var=region=ap-south-1"* ]]
}

@test "a missing region from build_context fails instead of defaulting" {
  unset REGION
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_db_setup_context'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"REGION is not set"* ]]
}
