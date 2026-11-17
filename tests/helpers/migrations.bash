#!/usr/bin/env bash

TEST_TOKEN="ghs_testinstallationtoken0123456789"
TEST_JWT="eyJhbGciOiJSUzI1NiJ9.eyJpc3MiOiIxMjMifQ.c2lnbmF0dXJl"

setup_migrations_env() {
  setup_mock_bin

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$DB_SERVICE_PATH/values.yaml"
  export OUTPUT_DIR="$BATS_TEST_TMPDIR/work"
  mkdir -p "$OUTPUT_DIR"
  export SERVER_HOSTNAME="db.example.rds.amazonaws.com"
  export SERVER_PORT="1433"
  export DB_NAME="app_42"
  export DB_USERNAME="app_42"
  export MIGRATOR_SECRET_ARN="arn:aws:secretsmanager:us-east-1:1:secret:nullplatform/rds-sqlserver/np-x/migrator"
  export AWS_ACCESS_KEY_ID="ASIASERVICEROLE"
  export AWS_SECRET_ACCESS_KEY="service-role-secret"
  export AWS_SESSION_TOKEN="service-role-session"

  KEY_FILE="$BATS_TEST_TMPDIR/app.pem"
  printf -- '-----BEGIN RSA PRIVATE KEY-----\nfake\n-----END RSA PRIVATE KEY-----\n' > "$KEY_FILE"
  export NP_GITHUB_APPS="org=other-org,app-id=1,private-key=/nowhere.pem;org=My-Org,app-id=123,private-key=${KEY_FILE}"

  FIXTURE_REPO="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$FIXTURE_REPO/qas/app_42/history" "$FIXTURE_REPO/dev/app_42"
  printf 'CREATE TABLE t1 (id INT);\nGO\n' > "$FIXTURE_REPO/qas/app_42/01_create_t1.sql"
  printf 'ALTER TABLE t1 ADD name NVARCHAR(10);\n' > "$FIXTURE_REPO/qas/app_42/02_alter_t1.sql"
  printf 'SELECT 1;\n' > "$FIXTURE_REPO/qas/app_42/history/00_old_v0_20260101000000.sql"
  printf 'old generated changelog\n' > "$FIXTURE_REPO/qas/app_42/changelog_v0.sql"
  printf 'CREATE TABLE d1 (id INT);\n' > "$FIXTURE_REPO/dev/app_42/01_dev.sql"
  export FIXTURE_REPO

  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"qas","mode":"apply"}'

  make_step_mock
  make_curl_mock
  make_git_mock
  make_migrations_aws_mock
  make_liquibase_mock
  make_np_log_mock
}

set_migration_parameters() {
  CONTEXT=$(jq -nc --argjson parameters "$1" '{service: {id: "svc-1"}, parameters: $parameters}')
  export CONTEXT
}

run_step() {
  run "$DB_SERVICE_PATH/scripts/aws/$1"
}

run_step_with_mocked_liquibase() {
  run bash -c "
    require_liquibase() {
      export JAVA_HOME='$BATS_TEST_TMPDIR/java'
      export MIGRATIONS_LIQUIBASE_BIN='$MOCK_BIN/liquibase'
      export MSSQL_JDBC_JAR='$BATS_TEST_TMPDIR/mssql.jar'
    }
    export -f require_liquibase
    '$DB_SERVICE_PATH/scripts/aws/$1'
  "
}

make_step_mock() {
  cat > "$MOCK_BIN/step" <<MOCK
#!/usr/bin/env bash
echo "step \$*" >> "$MOCK_LOG"
prev=""
for arg in "\$@"; do
  if [ "\$prev" = "--key" ] && [ ! -s "\$arg" ]; then
    echo "step: key file \$arg is missing or empty" >&2
    exit 1
  fi
  prev="\$arg"
done
echo "$TEST_JWT"
MOCK
  chmod +x "$MOCK_BIN/step"
}

make_curl_mock() {
  cat > "$MOCK_BIN/curl" <<MOCK
#!/usr/bin/env bash
echo "curl \$*" >> "$MOCK_LOG"
config=\$(cat)
case "\$config" in
  *"Authorization: Bearer "*) echo "curl-stdin-auth \${config#*Bearer }" >> "$MOCK_LOG" ;;
  *) echo "curl: no Authorization header on stdin" >&2; exit 2 ;;
esac
method="GET"; body=""; prev=""; url=""
for arg in "\$@"; do
  [ "\$prev" = "-X" ] && method="\$arg"
  [ "\$prev" = "--data-binary" ] && body="\$arg"
  prev="\$arg"
  url="\$arg"
done
echo "curl-request \$method \$url \$body" >> "$MOCK_LOG"
case "\$method \$url" in
  "GET https://api.github.com/repos/"*"/installation")
    status="\${CURL_INSTALLATION_STATUS:-200}"
    [ "\$status" = "200" ] && printf '{"id": 777}\n%s' "\$status" || printf '{"message": "Not Found"}\n%s' "\$status"
    ;;
  "POST https://api.github.com/app/installations/"*"/access_tokens")
    status="\${CURL_TOKEN_STATUS:-201}"
    case "\$body" in *'"contents":"write"'*) status="\${CURL_WRITE_TOKEN_STATUS:-\$status}" ;; esac
    [ "\$status" = "201" ] && printf '{"token": "$TEST_TOKEN"}\n%s' "\$status" || printf '{"message": "The permissions requested are not granted to this installation."}\n%s' "\$status"
    ;;
  "GET https://api.github.com/repos/"*)
    printf '{"default_branch": "master"}\n200'
    ;;
  *)
    echo "curl mock: unexpected request \$method \$url" >&2
    exit 22
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/curl"
}

make_git_mock() {
  PUSH_FAILURES_FILE="$BATS_TEST_TMPDIR/push-failures"
  echo "${GIT_PUSH_FAILURES:-0}" > "$PUSH_FAILURES_FILE"
  cat > "$MOCK_BIN/git" <<MOCK
#!/usr/bin/env bash
auth=""
if [ -n "\${GIT_CONFIG_VALUE_0:-}" ]; then
  auth=\$(printf '%s' "\${GIT_CONFIG_VALUE_0#AUTHORIZATION: basic }" | base64 -d 2>/dev/null)
fi
echo "git \$* auth=\$auth" >> "$MOCK_LOG"
dir="."
while [ \$# -gt 0 ]; do
  case "\$1" in
    -C) dir="\$2"; shift 2 ;;
    -c) shift 2 ;;
    *) break ;;
  esac
done
sub="\$1"; shift
case "\$sub" in
  clone)
    ref=""; prev=""; args=()
    for arg in "\$@"; do
      [ "\$prev" = "--branch" ] && ref="\$arg"
      prev="\$arg"; args+=("\$arg")
    done
    dest="\${args[\${#args[@]}-1]}"
    if [ "\$ref" = "\${GIT_MISSING_REF:-}" ]; then
      echo "fatal: Remote branch \$ref not found in upstream origin" >&2
      exit 128
    fi
    mkdir -p "\$dest" && cp -R "$FIXTURE_REPO/." "\$dest/"
    ;;
  rev-parse) echo "0123456789abcdef0123456789abcdef01234567" ;;
  add)
    for arg in "\$@"; do
      case "\$arg" in -*) ;; *) [ -e "\$dir/\$arg" ] || { echo "fatal: pathspec \$arg did not match" >&2; exit 128; } ;; esac
    done
    ;;
  rm)
    for arg in "\$@"; do
      case "\$arg" in -*) ;; *) rm -f "\$dir/\$arg" ;; esac
    done
    ;;
  diff)
    [ "\${GIT_NOTHING_STAGED:-0}" = "1" ] && exit 0
    exit 1
    ;;
  commit) ;;
  push)
    left=\$(cat "$PUSH_FAILURES_FILE")
    if [ "\$left" -gt 0 ]; then
      echo \$((left - 1)) > "$PUSH_FAILURES_FILE"
      echo "! [rejected] HEAD -> master (fetch first)" >&2
      exit 1
    fi
    ;;
  *) echo "git mock: unexpected subcommand \$sub" >&2; exit 1 ;;
esac
MOCK
  chmod +x "$MOCK_BIN/git"
}

make_migrations_aws_mock() {
  cat > "$MOCK_BIN/aws" <<MOCK
#!/usr/bin/env bash
echo "aws \$* access_key=\${AWS_ACCESS_KEY_ID:-unset}" >> "$MOCK_LOG"
case "\$1 \$2" in
  "secretsmanager get-secret-value")
    echo '{"username":"app_42_mig","password":"MiGr4t0rPassw0rd"}'
    ;;
  "ssm get-parameter")
    printf -- '-----BEGIN RSA PRIVATE KEY-----\nfromssm\n-----END RSA PRIVATE KEY-----\n'
    ;;
  *) exit 0 ;;
esac
MOCK
  chmod +x "$MOCK_BIN/aws"
}

make_liquibase_mock() {
  cat > "$MOCK_BIN/liquibase" <<MOCK
#!/usr/bin/env bash
echo "liquibase \$*" >> "$MOCK_LOG"
echo "liquibase-env aws_secret=\${AWS_SECRET_ACCESS_KEY:-unset} github_apps=\${NP_GITHUB_APPS:-unset} java_home=\${JAVA_HOME:-unset}" >> "$MOCK_LOG"
if [ -z "\${LIQUIBASE_COMMAND_PASSWORD:-}" ] || [ -z "\${LIQUIBASE_COMMAND_USERNAME:-}" ]; then
  echo "liquibase: no credentials in environment" >&2
  exit 1
fi
search=""; changelog=""; output_file=""; command=""
for arg in "\$@"; do
  case "\$arg" in
    --search-path=*) search="\${arg#*=}" ;;
    --changelog-file=*) changelog="\${arg#*=}" ;;
    --output-file=*) output_file="\${arg#*=}" ;;
    --*) ;;
    *) [ -z "\$command" ] && command="\$arg" ;;
  esac
done
[ -f "\$search/\$changelog" ] || { echo "liquibase: changelog \$search/\$changelog not found" >&2; exit 1; }
if [ -f "$BATS_TEST_TMPDIR/liquibase-fail-on" ] && [ "\$command" = "\$(cat "$BATS_TEST_TMPDIR/liquibase-fail-on")" ]; then
  echo "liquibase: \$command failed" >&2
  exit 1
fi
[ -n "\$output_file" ] && echo "CREATE TABLE t1 (id INT);" > "\$output_file"
exit 0
MOCK
  chmod +x "$MOCK_BIN/liquibase"
}

make_np_log_mock() {
  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"
MOCK
  chmod +x "$MOCK_BIN/np"
}

prepare_fetched_repo() {
  export MIGRATIONS_DIR="$OUTPUT_DIR/migrations"
  mkdir -p "$MIGRATIONS_DIR/repo"
  cp -R "$FIXTURE_REPO/." "$MIGRATIONS_DIR/repo/"
  echo "${1:-master}" > "$MIGRATIONS_DIR/history_branch"
}
