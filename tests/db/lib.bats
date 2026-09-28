#!/usr/bin/env bats

load '../helpers/common'

setup() {
  setup_mock_bin
  source "$DB_SERVICE_PATH/scripts/aws/lib"
}

@test "access_level_flags maps read to db_datareader only" {
  run access_level_flags read
  [ "$status" -eq 0 ]
  [ "$output" = "1 0 0" ]
}

@test "access_level_flags maps write to db_datawriter only" {
  run access_level_flags write
  [ "$status" -eq 0 ]
  [ "$output" = "0 1 0" ]
}

@test "access_level_flags gives read-write the ddl role for migrations" {
  run access_level_flags read-write
  [ "$status" -eq 0 ]
  [ "$output" = "1 1 1" ]
}

@test "access_level_flags rejects an unknown level" {
  run access_level_flags superuser
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown access level"* ]]
}

@test "validate_identifier accepts a derived application database name" {
  run validate_identifier "database name" "app_123456"
  [ "$status" -eq 0 ]
}

@test "validate_identifier rejects an empty value" {
  run validate_identifier "database name" ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"is empty"* ]]
}

@test "validate_identifier rejects a name starting with a digit" {
  run validate_identifier "database name" "1app"
  [ "$status" -ne 0 ]
}

@test "validate_identifier rejects quoting and statement terminators" {
  run validate_identifier "database username" "app'; DROP LOGIN sa--"
  [ "$status" -ne 0 ]
}

@test "validate_identifier rejects a hyphenated name" {
  run validate_identifier "database name" "app-123"
  [ "$status" -ne 0 ]
}

@test "yaml_value falls back to the default for a missing key" {
  local f="$BATS_TEST_TMPDIR/values.yaml"
  printf 'region: us-east-2\n' > "$f"
  run yaml_value "aws_profile" "fallback" "$f"
  [ "$output" = "fallback" ]
}

@test "yaml_value reads a quoted value" {
  local f="$BATS_TEST_TMPDIR/values.yaml"
  printf 'aws_profile: "sso-prod"\n' > "$f"
  run yaml_value "aws_profile" "" "$f"
  [ "$output" = "sso-prod" ]
}

@test "fetch_master_credentials keeps the password out of argv" {
  make_aws_mock "npmaster" "topsecret"
  fetch_master_credentials "arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/x/master"
  [ "$MASTER_USER" = "npmaster" ]
  [ "$SQLCMDPASSWORD" = "topsecret" ]
  run grep -c "topsecret" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "validate_password accepts what random_password generates today" {
  run validate_password "aB3dEfGhIjKlMnOpQrStUvWxYz012345"
  [ "$status" -eq 0 ]
}

@test "validate_password rejects a quote that would escape the T-SQL literal" {
  run validate_password "abc'def'ghijklmnopqrstuvwxyz0123"
  [ "$status" -ne 0 ]
  [[ "$output" == *"random_password.special = false"* ]]
}

@test "validate_password rejects a password short enough to be a truncation" {
  run validate_password "short"
  [ "$status" -ne 0 ]
}

@test "validate_password rejects an empty password" {
  run validate_password ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"is empty"* ]]
}

@test "fetch_master_credentials fails loudly on an empty ARN" {
  run fetch_master_credentials ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"master secret ARN is empty"* ]]
}

@test "require_sqlcmd uses the sqlcmd already on PATH without calling mise" {
  make_sqlcmd_mock 0
  make_mise_mock 0
  run require_sqlcmd
  [ "$status" -eq 0 ]
  [ "$(calls_matching '^mise ')" -eq 0 ]
}

@test "require_sqlcmd installs the pinned go-sqlcmd with mise when sqlcmd is missing" {
  make_mise_mock 0
  PATH="$MOCK_BIN:/usr/bin:/bin"
  require_sqlcmd
  grep -q "^mise install github:microsoft/go-sqlcmd@${SQLCMD_VERSION}$" "$MOCK_LOG"
  [ "$(command -v sqlcmd)" = "$MISE_INSTALLS/github-microsoft-go-sqlcmd-${SQLCMD_VERSION}/sqlcmd" ]
}

@test "require_sqlcmd fails when mise cannot install go-sqlcmd" {
  make_mise_mock 1
  PATH="$MOCK_BIN:/usr/bin:/bin"
  run require_sqlcmd
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not install go-sqlcmd"* ]]
}

@test "require_sqlcmd fails when neither sqlcmd nor mise is available" {
  PATH="$MOCK_BIN:/usr/bin:/bin"
  run require_sqlcmd
  [ "$status" -ne 0 ]
  [[ "$output" == *"mise is not available"* ]]
}

@test "require_sqlcmd fails when mise reports a bin path that has no sqlcmd binary" {
  make_mise_mock_missing_binary
  PATH="$MOCK_BIN:/usr/bin:/bin"
  run require_sqlcmd
  [ "$status" -ne 0 ]
  [[ "$output" == *"sqlcmd is still not in PATH"* ]]
  [ "$(calls_matching '^mise install ')" -eq 1 ]
  [ "$(calls_matching '^mise bin-paths ')" -eq 1 ]
}

@test "instance_name_for joins the slug and the service id" {
  run instance_name_for "payments" "8d18101b-5355-496e-8fb4-6a2af580a6b6"
  [ "$status" -eq 0 ]
  [ "$output" = "payments-8d18101b-5355-496e-8fb4-6a2af580a6b6" ]
}

@test "instance_name_for keeps only lowercase letters digits and single hyphens" {
  run instance_name_for "My__Payments.DB" "8d18101b-5355-496e-8fb4-6a2af580a6b6"
  [ "$output" = "my-payments-db-8d18101b-5355-496e-8fb4-6a2af580a6b6" ]
}

@test "instance_name_for rejects an empty slug" {
  run instance_name_for "" "8d18101b-5355-496e-8fb4-6a2af580a6b6"
  [ "$status" -ne 0 ]
}

@test "read_db_setup_state leaves no temp files behind on success" {
  make_mktemp_mock
  make_aws_mock
  export TFSTATE_BUCKET="acme-tofu-state"
  export TFSTATE_KEY_PREFIX="services/rds-sqlserver/svc-1/"
  export REGION="us-east-1"
  export AWS_MOCK_STATE_FILE="$BATS_TEST_TMPDIR/db_setup.tfstate"
  echo '{"resources":[],"outputs":{}}' > "$AWS_MOCK_STATE_FILE"

  run read_db_setup_state
  [ "$status" -eq 0 ]

  local count=0 path
  while read -r path; do
    count=$((count + 1))
    [ ! -e "$path" ]
  done < <(awk '/^mktemp-created /{print $2}' "$MOCK_LOG")
  [ "$count" -eq 2 ]
}

@test "read_db_setup_state leaves no temp files behind when the key does not exist" {
  make_mktemp_mock
  make_aws_mock
  export TFSTATE_BUCKET="acme-tofu-state"
  export TFSTATE_KEY_PREFIX="services/rds-sqlserver/svc-1/"
  export REGION="us-east-1"
  unset AWS_MOCK_STATE_FILE

  run read_db_setup_state
  [ "$status" -eq 2 ]

  local count=0 path
  while read -r path; do
    count=$((count + 1))
    [ ! -e "$path" ]
  done < <(awk '/^mktemp-created /{print $2}' "$MOCK_LOG")
  [ "$count" -eq 2 ]
}

@test "read_db_setup_state leaves no temp files behind when the read is denied" {
  make_mktemp_mock
  make_aws_mock
  export TFSTATE_BUCKET="acme-tofu-state"
  export TFSTATE_KEY_PREFIX="services/rds-sqlserver/svc-1/"
  export REGION="us-east-1"
  export AWS_MOCK_STATE_FILE="denied"

  run read_db_setup_state
  [ "$status" -eq 1 ]

  local count=0 path
  while read -r path; do
    count=$((count + 1))
    [ ! -e "$path" ]
  done < <(awk '/^mktemp-created /{print $2}' "$MOCK_LOG")
  [ "$count" -eq 2 ]
}
