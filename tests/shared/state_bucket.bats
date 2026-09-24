#!/usr/bin/env bats

load '../helpers/common'

BUCKET="acme-tofu-state"
SERVICE_ID="11111111-2222-3333-4444-555555555555"

setup() {
  setup_mock_bin

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export CONTEXT="{\"service\":{\"id\":\"${SERVICE_ID}\"}}"
  export RDS_SQL_SERVER_S3_STATE_BUCKET="$BUCKET"

  printf '%s\n' "$BUCKET" > "$BATS_TEST_TMPDIR/existing_buckets"
  export EXISTING_BUCKETS="$BATS_TEST_TMPDIR/existing_buckets"

  cat > "$MOCK_BIN/aws" <<MOCK
#!/usr/bin/env bash
echo "aws \$*" >> "$MOCK_LOG"
bucket=""
prev=""
for a in "\$@"; do
  if [ "\$prev" = "--bucket" ]; then bucket="\$a"; fi
  prev="\$a"
done
case "\$1 \$2" in
  "s3api head-bucket")
    grep -qxF "\$bucket" "\$EXISTING_BUCKETS" || exit 255
    ;;
  "s3api list-object-versions")
    echo 'null'
    ;;
esac
exit 0
MOCK
  chmod +x "$MOCK_BIN/aws"

  cat > "$MOCK_BIN/np" <<'MOCK'
#!/usr/bin/env bash
echo '{"attributes":{}}'
MOCK
  chmod +x "$MOCK_BIN/np"
}

@test "an unset bucket variable fails before touching AWS" {
  unset RDS_SQL_SERVER_S3_STATE_BUCKET
  run "$DB_SERVICE_PATH/scripts/aws/build_context"
  [ "$status" -ne 0 ]
  [[ "$output" == *"RDS_SQL_SERVER_S3_STATE_BUCKET is not set"* ]]
  run grep -c "^aws " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an empty bucket variable is rejected too" {
  export RDS_SQL_SERVER_S3_STATE_BUCKET=""
  run "$DB_SERVICE_PATH/scripts/aws/build_context"
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not set"* ]]
}

@test "a bucket that does not exist fails instead of being created" {
  export RDS_SQL_SERVER_S3_STATE_BUCKET="not-there"
  run "$DB_SERVICE_PATH/scripts/aws/build_context"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist or is not reachable"* ]]
  run grep -c "create-bucket" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "the service never creates a bucket on the happy path either" {
  run "$DB_SERVICE_PATH/scripts/aws/build_context"
  [ "$status" -eq 0 ]
  run grep -cE "create-bucket|put-bucket-versioning" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "state is namespaced per service instance under the shared bucket" {
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_context' >/dev/null 2>&1; \
    echo \"B=\$TFSTATE_BUCKET\"; echo \"P=\$TFSTATE_KEY_PREFIX\""
  [ "$status" -eq 0 ]
  [[ "$output" == *"B=${BUCKET}"* ]]
  [[ "$output" == *"P=services/rds-sqlserver/${SERVICE_ID}/"* ]]
}

@test "cleanup refuses to run with an empty prefix" {
  export TFSTATE_BUCKET="$BUCKET"
  export TFSTATE_KEY_PREFIX=""
  run "$DB_SERVICE_PATH/scripts/aws/delete_tfstate_objects"
  [ "$status" -ne 0 ]
  [[ "$output" == *"would delete every service's state"* ]]
  run grep -c "delete-objects" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "cleanup scopes its listing to this instance's prefix" {
  export TFSTATE_BUCKET="$BUCKET"
  export TFSTATE_KEY_PREFIX="services/rds-sqlserver/${SERVICE_ID}/"
  run "$DB_SERVICE_PATH/scripts/aws/delete_tfstate_objects"
  [ "$status" -eq 0 ]
  run grep -c -- "--prefix services/rds-sqlserver/${SERVICE_ID}/" "$MOCK_LOG"
  [ "$output" = "2" ]
}

@test "cleanup never deletes the bucket itself" {
  export TFSTATE_BUCKET="$BUCKET"
  export TFSTATE_KEY_PREFIX="services/rds-sqlserver/${SERVICE_ID}/"
  run "$DB_SERVICE_PATH/scripts/aws/delete_tfstate_objects"
  [ "$status" -eq 0 ]
  run grep -c "delete-bucket" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "both packages resolve the state bucket identically" {
  for svc in rds-sqlserver-db rds-sqlserver-server; do
    run grep -c 'RDS_SQL_SERVER_S3_STATE_BUCKET' "$REPO_ROOT/${svc}/scripts/aws/build_context"
    [ "$output" = "3" ]
    run grep -c 'TFSTATE_KEY_PREFIX="services/rds-sqlserver/${SERVICE_ID}/"' "$REPO_ROOT/${svc}/scripts/aws/build_context"
    [ "$output" = "1" ]
  done
}

@test "no package still names a bucket after the service id" {
  run grep -rn 'TFSTATE_BUCKET="np-service' "$REPO_ROOT/rds-sqlserver-db/scripts" "$REPO_ROOT/rds-sqlserver-server/scripts"
  [ "$status" -ne 0 ]
}

@test "np-service survives only as the local scratch directory" {
  run grep -rhn 'np-service' "$REPO_ROOT/rds-sqlserver-db/scripts" "$REPO_ROOT/rds-sqlserver-server/scripts"
  [ "$status" -eq 0 ]
  while IFS= read -r line; do
    [[ "$line" == *"/tmp/np-service-"* ]] || [[ "$line" == *"np-tofu-bin"* ]]
  done <<< "$output"
}

@test "the prefix groups every instance of this service type together" {
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_context' >/dev/null 2>&1; echo \"\$TFSTATE_KEY_PREFIX\""
  [ "$status" -eq 0 ]
  [[ "$output" == "services/rds-sqlserver/"* ]]
  [[ "$output" == *"/${SERVICE_ID}/" ]]
}

@test "the IAM modules grant the named bucket and no wildcard" {
  for svc in rds-sqlserver-db rds-sqlserver-server; do
    run grep -c 'var.state_bucket_name' "$REPO_ROOT/${svc}/specs/requirements/aws/locals.tf"
    [ "$output" = "2" ]
    run grep -c 'np-service' "$REPO_ROOT/${svc}/specs/requirements/aws/main.tf"
    [ "$output" = "0" ]
  done
}
