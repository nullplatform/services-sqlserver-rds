#!/usr/bin/env bats

load '../helpers/common'

PINNED="1.12.6"

setup() {
  setup_mock_bin
  export TOFU_CACHE_ROOT="$BATS_TEST_TMPDIR/np-tofu-bin"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$OUTPUT_DIR"
  export TOFU_MODULE_DIR="$BATS_TEST_TMPDIR/module"
  mkdir -p "$TOFU_MODULE_DIR"
  : > "$TOFU_MODULE_DIR/main.tf"
  export TOFU_INIT_VARIABLES=""
  export TOFU_VARIABLES=""
}

# Stands in for a tofu binary reporting an arbitrary version, so the resolution
# logic can be driven without downloading anything.
fake_tofu_at() {
  local path="$1" version="$2"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<MOCK
#!/usr/bin/env bash
if [ "\$1" = "version" ]; then
  echo "OpenTofu v${version}"
  exit 0
fi
echo "tofu \$*" >> "$MOCK_LOG"
exit 0
MOCK
  chmod +x "$path"
}

# The script hardcodes /tmp/np-tofu-bin; rewrite it to a sandbox so a real
# cached binary on the developer's machine cannot influence the result, and
# make curl fail loudly so an accidental download shows up as a failure.
script_under_test() {
  local service="$1" copy="$BATS_TEST_TMPDIR/do_tofu_${service}"
  sed "s#/tmp/np-tofu-bin#${TOFU_CACHE_ROOT}#" \
    "$REPO_ROOT/${service}/scripts/aws/do_tofu" > "$copy"
  chmod +x "$copy"
  echo "$copy"
}

setup_no_download() {
  cat > "$MOCK_BIN/curl" <<MOCK
#!/usr/bin/env bash
echo "curl \$*" >> "$MOCK_LOG"
exit 1
MOCK
  chmod +x "$MOCK_BIN/curl"
}

@test "a PATH tofu newer than the pin is used as is" {
  setup_no_download
  fake_tofu_at "$MOCK_BIN/tofu" "1.13.0"
  run "$(script_under_test rds-sqlserver-db)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using tofu v1.13.0"* ]]
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a PATH tofu at exactly the pin is accepted" {
  setup_no_download
  fake_tofu_at "$MOCK_BIN/tofu" "$PINNED"
  run "$(script_under_test rds-sqlserver-db)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using tofu v${PINNED}"* ]]
}

@test "a PATH tofu older than the pin is not used" {
  setup_no_download
  fake_tofu_at "$MOCK_BIN/tofu" "1.9.0"
  run "$(script_under_test rds-sqlserver-db)"
  [ "$status" -ne 0 ]
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "an older binary another service cached is never reused" {
  setup_no_download
  fake_tofu_at "${TOFU_CACHE_ROOT}/tofu" "1.9.0"
  run "$(script_under_test rds-sqlserver-db)"
  [ "$status" -ne 0 ]
  [[ "$output" != *"Using tofu v1.9.0"* ]]
}

@test "the cache is keyed by version so each pin gets its own directory" {
  setup_no_download
  fake_tofu_at "${TOFU_CACHE_ROOT}/${PINNED}/tofu" "$PINNED"
  run "$(script_under_test rds-sqlserver-db)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using tofu v${PINNED}"* ]]
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a cached binary newer than the pin is accepted" {
  setup_no_download
  fake_tofu_at "${TOFU_CACHE_ROOT}/${PINNED}/tofu" "1.14.2"
  run "$(script_under_test rds-sqlserver-db)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using tofu v1.14.2"* ]]
}

@test "minor versions compare numerically, not lexically" {
  setup_no_download
  fake_tofu_at "$MOCK_BIN/tofu" "1.9.9"
  run "$(script_under_test rds-sqlserver-db)"
  [ "$status" -ne 0 ]
}

@test "the server package resolves versions the same way" {
  setup_no_download
  fake_tofu_at "$MOCK_BIN/tofu" "1.9.0"
  run "$(script_under_test rds-sqlserver-server)"
  [ "$status" -ne 0 ]
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "both packages pin the same tofu version as the Dockerfiles" {
  for f in rds-sqlserver-db rds-sqlserver-server; do
    run grep -c "TOFU_VERSION=\"${PINNED}\"" "$REPO_ROOT/${f}/scripts/aws/do_tofu"
    [ "$output" = "1" ]
  done
  for f in Dockerfile.rds-sqlserver-db Dockerfile.rds-sqlserver-server; do
    run grep -c "TOFU_VERSION=${PINNED}" "$REPO_ROOT/${f}"
    [ "$output" = "1" ]
  done
}
