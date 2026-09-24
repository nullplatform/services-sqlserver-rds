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
