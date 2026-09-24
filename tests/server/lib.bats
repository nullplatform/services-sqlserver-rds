#!/usr/bin/env bats

load '../helpers/common'

setup() {
  setup_mock_bin
  source "$SERVER_SERVICE_PATH/scripts/aws/lib"
}

@test "standard edition below 200 GB is rejected" {
  run validate_edition_constraints "sqlserver-se" 100 false
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least 200 GB"* ]]
}

@test "standard edition at exactly 200 GB is accepted" {
  run validate_edition_constraints "sqlserver-se" 200 false
  [ "$status" -eq 0 ]
}

@test "express edition is allowed below 200 GB" {
  run validate_edition_constraints "sqlserver-ex" 20 false
  [ "$status" -eq 0 ]
}

@test "express edition with high availability is rejected" {
  run validate_edition_constraints "sqlserver-ex" 20 true
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not support High Availability"* ]]
}

@test "standard edition with high availability is accepted" {
  run validate_edition_constraints "sqlserver-se" 200 true
  [ "$status" -eq 0 ]
}

@test "web edition has neither restriction" {
  run validate_edition_constraints "sqlserver-web" 20 true
  [ "$status" -eq 0 ]
}

@test "the error message names the field as the developer sees it" {
  run validate_edition_constraints "sqlserver-se" 50 false
  [[ "$output" == *"'Storage'"* ]]
  [[ "$output" == *"'Edition'"* ]]
}
