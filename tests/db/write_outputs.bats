#!/usr/bin/env bats

load '../helpers/common'

APP_PASSWORD="sup3rs3cr3tapppassword0123456789"

setup() {
  setup_mock_bin

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$OUTPUT_DIR"
  export CONTEXT='{"service":{"id":"svc-1"},"link":{"id":"lnk-1"}}'

  cat > "$MOCK_BIN/tofu" <<MOCK
#!/usr/bin/env bash
echo "tofu \$*" >> "$MOCK_LOG"
cat <<'JSON'
{
  "hostname":          {"value": "sql.example.rds.amazonaws.com"},
  "port":              {"value": 1433},
  "db_username":       {"value": "app_42"},
  "db_password":       {"value": "$APP_PASSWORD"},
  "database_name":     {"value": "app_42"},
  "master_secret_arn": {"value": "arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/master"},
  "app_secret_arn":    {"value": "arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/svc-1/app"}
}
JSON
MOCK
  chmod +x "$MOCK_BIN/tofu"

  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"

prev=""
for arg in "\$@"; do
  if [ "\$prev" = "--body" ]; then
    if [ -f "\$arg" ]; then
      cat "\$arg" >> "$BATS_TEST_TMPDIR/body.json"
    else
      echo "np: --body is not a readable file: \$arg" >&2
      exit 1
    fi
  fi
  prev="\$arg"
done

if [ "\$1 \$2" = "service read" ]; then
  cat <<'JSON'
{"attributes":{"hostname":"sql.example.rds.amazonaws.com","port":1433,"username":"app_42","password":"$APP_PASSWORD","database_name":"app_42","master_secret_arn":"arn:master","app_secret_arn":"arn:app"}}
JSON
fi
exit 0
MOCK
  chmod +x "$MOCK_BIN/np"
}

@test "service attributes are patched from a body file, not inline JSON" {
  run "$DB_SERVICE_PATH/scripts/aws/write_service_outputs"
  [ "$status" -eq 0 ]
  run grep -c -- "--body /" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "the application password never reaches the service patch argv" {
  run "$DB_SERVICE_PATH/scripts/aws/write_service_outputs"
  [ "$status" -eq 0 ]
  run grep -c "$APP_PASSWORD" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "the password does reach the API, in the body file" {
  run "$DB_SERVICE_PATH/scripts/aws/write_service_outputs"
  [ "$status" -eq 0 ]
  run grep -c "$APP_PASSWORD" "$BATS_TEST_TMPDIR/body.json"
  [ "$output" = "1" ]
}

@test "the body file is a well formed patch payload" {
  run "$DB_SERVICE_PATH/scripts/aws/write_service_outputs"
  [ "$status" -eq 0 ]
  run jq -r '.attributes.database_name' "$BATS_TEST_TMPDIR/body.json"
  [ "$output" = "app_42" ]
}

@test "the temporary body file is removed when the script exits" {
  run "$DB_SERVICE_PATH/scripts/aws/write_service_outputs"
  [ "$status" -eq 0 ]
  BODY_PATH=$(grep -o -- "--body [^ ]*" "$MOCK_LOG" | head -1 | cut -d' ' -f2)
  [ -n "$BODY_PATH" ]
  [ ! -f "$BODY_PATH" ]
}

@test "the application password never reaches the link patch argv" {
  run "$DB_SERVICE_PATH/scripts/aws/write_link_outputs"
  [ "$status" -eq 0 ]
  run grep -c "$APP_PASSWORD" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "the link body carries a ready to use jdbc url" {
  run "$DB_SERVICE_PATH/scripts/aws/write_link_outputs"
  [ "$status" -eq 0 ]
  run jq -r '.attributes.jdbc_url' "$BATS_TEST_TMPDIR/body.json"
  [ "$output" = "jdbc:sqlserver://sql.example.rds.amazonaws.com:1433;databaseName=app_42;encrypt=true;trustServerCertificate=true" ]
}
