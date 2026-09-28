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

@test "each edition maps every workload to its instance class" {
  while read -r edition workload expected; do
    run instance_class_for_workload "$edition" "$workload"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
  done <<'TABLE'
sqlserver-ex development db.t3.small
sqlserver-ex production-light db.t3.medium
sqlserver-ex production-heavy db.t3.xlarge
sqlserver-web development db.t3.medium
sqlserver-web production-light db.m5.large
sqlserver-web production-heavy db.m5.xlarge
sqlserver-se development db.m5.large
sqlserver-se production-light db.m5.xlarge
sqlserver-se production-heavy db.m5.2xlarge
TABLE
}

@test "an unknown workload is rejected naming the field" {
  run instance_class_for_workload "sqlserver-ex" "huge"
  [ "$status" -ne 0 ]
  [[ "$output" == *"'Workload'"* ]]
}

@test "an unknown edition is rejected" {
  run instance_class_for_workload "sqlserver-ee" "development"
  [ "$status" -ne 0 ]
  [[ "$output" == *"sqlserver-ee"* ]]
}

@test "the instance name is the service slug followed by the service id" {
  run instance_name_for "test-fede" "cacb7da7-9e34-4ba3-be7a-c2a149c23ead"
  [ "$status" -eq 0 ]
  [ "$output" = "test-fede-cacb7da7-9e34-4ba3-be7a-c2a149c23ead" ]
}

@test "the instance name is lowercased and keeps only letters digits and single hyphens" {
  run instance_name_for "My__Orders.DB" "cacb7da7-9e34-4ba3-be7a-c2a149c23ead"
  [ "$output" = "my-orders-db-cacb7da7-9e34-4ba3-be7a-c2a149c23ead" ]
}

@test "a long slug is truncated so the instance name fits the 63 character rds limit" {
  run instance_name_for "a-very-long-service-name-that-keeps-going-and-going" "cacb7da7-9e34-4ba3-be7a-c2a149c23ead"
  [ "${#output}" -le 63 ]
  [[ "$output" == *"-cacb7da7-9e34-4ba3-be7a-c2a149c23ead" ]]
  [[ "$output" != *"--"* ]]
}

@test "a slug that does not start with a letter still yields a valid rds identifier" {
  run instance_name_for "123-orders" "cacb7da7-9e34-4ba3-be7a-c2a149c23ead"
  [[ "$output" =~ ^[a-z] ]]
  [ "${#output}" -le 63 ]
}

@test "an empty slug is rejected" {
  run instance_name_for "" "cacb7da7-9e34-4ba3-be7a-c2a149c23ead"
  [ "$status" -ne 0 ]
}
