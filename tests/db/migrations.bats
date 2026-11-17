#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/migrations'

setup() {
  setup_migrations_env
}

@test "fetch clones the ref with a read token scoped to the repository" {
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c 'curl-request POST https://api.github.com/app/installations/777/access_tokens {"repositories":\["abc-databases"\],"permissions":{"contents":"read"}}' "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c "git clone --quiet --depth 1 --branch v1.0.0 https://github.com/My-Org/abc-databases.git $OUTPUT_DIR/migrations/repo auth=x-access-token:$TEST_TOKEN" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "the GitHub App is matched by org case-insensitively" {
  set_migration_parameters '{"repository_url":"git@github.com:my-org/abc-databases.git","ref":"v1.0.0","environment_directory":"qas","mode":"apply"}'
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "step crypto jwt sign --key .* --iss 123 " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "neither the token nor the JWT ever appears on a command line" {
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -E "^(curl|git) " "$MOCK_LOG"
  [[ "$output" != *"$TEST_JWT"* ]] || false
  run grep -E "^curl " "$MOCK_LOG"
  [[ "$output" != *"$TEST_TOKEN"* ]] || false
  run grep -c "^git .*$TEST_TOKEN.* auth=" "$MOCK_LOG"
  [ "$output" = "0" ]
  run grep -c "curl-stdin-auth $TEST_JWT" "$MOCK_LOG"
  [ "$output" = "2" ]
}

@test "an agent without GitHub Apps fails before calling GitHub" {
  unset NP_GITHUB_APPS
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"NP_GITHUB_APPS is not set on the agent"* ]] || false
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an org without a GitHub App names the configured ones" {
  export NP_GITHUB_APPS="org=other-org,app-id=1,private-key=${KEY_FILE}"
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"no GitHub App configured for org 'My-Org'"* ]] || false
  [[ "$output" == *"configured: other-org"* ]] || false
}

@test "a repository that does not exist or lacks the App is reported as such" {
  export CURL_INSTALLATION_STATUS=404
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"repository My-Org/abc-databases does not exist, or GitHub App 123 is not installed on it"* ]] || false
  run grep -c "^git clone" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a configured installation id skips the installation lookup" {
  export NP_GITHUB_APPS="org=my-org,app-id=123,installation-id=999,private-key=${KEY_FILE}"
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "/installation " "$MOCK_LOG"
  [ "$output" = "0" ]
  run grep -c "curl-request POST https://api.github.com/app/installations/999/access_tokens" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a key held in SSM is read with the agent's own credentials, not the service role" {
  export NP_GITHUB_APPS="org=my-org,app-id=123,private-key-ssm-parameter=/np/gh/key"
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "aws ssm get-parameter --name /np/gh/key --with-decryption .* access_key=unset" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a missing tag or branch fails with the ref in the message" {
  export GIT_MISSING_REF="v9.9.9"
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v9.9.9","environment_directory":"qas","mode":"apply"}'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not clone My-Org/abc-databases at 'v9.9.9'"* ]] || false
}

@test "a missing environment or database directory is reported with its path" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"prd","mode":"apply"}'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"directory prd/app_42 does not exist in My-Org/abc-databases@v1.0.0"* ]] || false
}

@test "a service without the migrations user asks for an update before touching GitHub" {
  export MIGRATOR_SECRET_ARN=""
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"run its update action once to create it"* ]] || false
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "parameters that could inject options or paths are rejected" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"--upload-pack=touch","environment_directory":"qas","mode":"apply"}'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"ref '--upload-pack=touch' is not a valid tag or branch name"* ]] || false

  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"../etc","mode":"apply"}'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"environment_directory '../etc' must be a single directory name"* ]] || false

  set_migration_parameters '{"repository_url":"https://gitlab.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"qas","mode":"apply"}'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a github.com repository"* ]] || false
}

@test "an unknown mode is rejected" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"qas","mode":"force"}'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"mode 'force' is not valid"* ]] || false
}

@test "prepare picks pending scripts in order and skips history and old changelogs" {
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run cat "$MIGRATIONS_DIR/pending.txt"
  [ "$output" = $'01_create_t1.sql\n02_alter_t1.sql' ]
}

@test "outside dev the changeset id carries the ref and scripts never re-run on change" {
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run jq -c '[.databaseChangeLog[].changeSet | {id, runOnChange, logicalFilePath}]' "$MIGRATIONS_DIR/changelog.json"
  [ "$output" = '[{"id":"01_create_t1_v1.0.0","runOnChange":false,"logicalFilePath":"qas/app_42/changelog"},{"id":"02_alter_t1_v1.0.0","runOnChange":false,"logicalFilePath":"qas/app_42/changelog"}]' ]
}

@test "in dev the changeset id carries the run timestamp and runs on change" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"feature/x","environment_directory":"dev","mode":"apply"}'
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  timestamp=$(cat "$MIGRATIONS_DIR/timestamp")
  run jq -r '.databaseChangeLog[0].changeSet | "\(.id) \(.runOnChange)"' "$MIGRATIONS_DIR/changelog.json"
  [ "$output" = "01_dev_${timestamp} true" ]
}

@test "scripts are split only on GO lines and keep their comments" {
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run jq -c '.databaseChangeLog[0].changeSet.changes[0].sqlFile' "$MIGRATIONS_DIR/changelog.json"
  [ "$output" = '{"path":"stage/01_create_t1.sql","relativeToChangelogFile":true,"splitStatements":true,"endDelimiter":"\\nGO","stripComments":false,"encoding":"UTF-8"}' ]
}

@test "an empty script directory fails explaining that history holds what already ran" {
  prepare_fetched_repo
  rm "$MIGRATIONS_DIR"/repo/qas/app_42/0*.sql
  run_step prepare_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"no pending scripts in qas/app_42 at v1.0.0"* ]] || false
}

@test "scripts not named NN_description.sql are listed and rejected" {
  prepare_fetched_repo
  printf 'SELECT 1;\n' > "$MIGRATIONS_DIR/repo/qas/app_42/fix.sql"
  printf 'SELECT 1;\n' > "$MIGRATIONS_DIR/repo/qas/app_42/3_typo.sql"
  run_step prepare_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"3_typo.sql,fix.sql"* ]] || false
}

@test "DROP, TRUNCATE and SELECT * are blocked outside dev" {
  prepare_fetched_repo
  printf 'drop table t1;\nTRUNCATE TABLE t2;\nselect   * from t3;\n' > "$MIGRATIONS_DIR/repo/qas/app_42/03_bad.sql"
  run_step prepare_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"03_bad.sql: DROP, TRUNCATE, SELECT *"* ]] || false
  [ ! -f "$MIGRATIONS_DIR/changelog.json" ]
}

@test "DROP is allowed in dev" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"main","environment_directory":"dev","mode":"apply"}'
  prepare_fetched_repo
  printf 'DROP TABLE d1;\n' > "$MIGRATIONS_DIR/repo/dev/app_42/02_drop.sql"
  run_step prepare_migrations
  [ "$status" -eq 0 ]
}

@test "GRANT CONNECT is blocked even in dev, across lines" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"main","environment_directory":"dev","mode":"apply"}'
  prepare_fetched_repo
  printf 'GRANT\n  CONNECT TO someone;\n' > "$MIGRATIONS_DIR/repo/dev/app_42/02_grant.sql"
  run_step prepare_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"02_grant.sql: GRANT CONNECT"* ]] || false
}

@test "commented-out commands and identifiers that contain them are not flagged" {
  prepare_fetched_repo
  printf -- '-- DROP TABLE t1;\n/* TRUNCATE TABLE t2;\n SELECT * FROM t3; */\nCREATE TABLE DROP_LOG (CONNECTION_ID INT);\nGRANT SELECT ON t1 TO app_role;\n' > "$MIGRATIONS_DIR/repo/qas/app_42/03_ok.sql"
  run_step prepare_migrations
  [ "$status" -eq 0 ]
}

@test "a UTF-8 BOM is removed from the staged copy, not from the repository" {
  prepare_fetched_repo
  printf '\357\273\277CREATE TABLE b (id INT);\n' > "$MIGRATIONS_DIR/repo/qas/app_42/03_bom.sql"
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  [[ "$output" == *"03_bom.sql starts with a UTF-8 BOM"* ]] || false
  run head -c 6 "$MIGRATIONS_DIR/stage/03_bom.sql"
  [ "$output" = "CREATE" ]
  run head -c 3 "$MIGRATIONS_DIR/repo/qas/app_42/03_bom.sql"
  [ "$output" = $'\357\273\277' ]
}

@test "preview validates and renders SQL without applying it" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"qas","mode":"preview"}'
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -eq 0 ]
  run grep -oE "^liquibase .* (validate|status|update-sql|update)( |$)" "$MOCK_LOG"
  [[ "$output" == *" validate"* ]] || false
  [[ "$output" == *" status"* ]] || false
  [[ "$output" == *" update-sql"* ]] || false
  run grep -cE "^liquibase .* update$" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "apply runs update as the migrations user against the service database" {
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -eq 0 ]
  run grep -cE "^liquibase .*--url=jdbc:sqlserver://db.example.rds.amazonaws.com:1433;databaseName=app_42;encrypt=true;.* update$" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c "secretsmanager get-secret-value --secret-id $MIGRATOR_SECRET_ARN" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c "MiGr4t0rPassw0rd" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a failed update says what was recorded and that nothing moved to history" {
  export LIQUIBASE_FAIL_ON="update"
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"recorded in DATABASECHANGELOG and are skipped on retry; nothing was moved to history"* ]] || false
}

@test "preview never asks GitHub for a write token" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"qas","mode":"preview"}'
  prepare_fetched_repo
  run_step prepare_migrations
  run_step move_migrations_to_history
  [ "$status" -eq 0 ]
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "apply moves the executed scripts to history on the default branch in one push" {
  prepare_fetched_repo
  run_step prepare_migrations
  timestamp=$(cat "$MIGRATIONS_DIR/timestamp")
  run_step move_migrations_to_history
  [ "$status" -eq 0 ]
  run grep -c '^curl-request POST .*"permissions":{"contents":"write"}' "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c "git clone --quiet --depth 1 --branch master " "$MOCK_LOG"
  [ "$output" = "1" ]
  [ -f "$MIGRATIONS_DIR/history-repo/qas/app_42/history/01_create_t1_v1.0.0_${timestamp}.sql" ]
  [ -f "$MIGRATIONS_DIR/history-repo/qas/app_42/history/02_alter_t1_v1.0.0_${timestamp}.sql" ]
  [ ! -f "$MIGRATIONS_DIR/history-repo/qas/app_42/01_create_t1.sql" ]
  [ ! -f "$MIGRATIONS_DIR/history-repo/qas/app_42/02_alter_t1.sql" ]
  run grep -c "push --quiet origin HEAD:refs/heads/master auth=x-access-token:$TEST_TOKEN" "$MOCK_LOG"
  [ "$output" = "1" ]
  run cat "$MIGRATIONS_DIR/history_commit"
  [ "$output" = "0123456789abcdef0123456789abcdef01234567" ]
}

@test "history_branch overrides the default branch" {
  set_migration_parameters '{"repository_url":"https://github.com/My-Org/abc-databases","ref":"v1.0.0","environment_directory":"qas","mode":"apply","history_branch":"develop"}'
  prepare_fetched_repo
  run_step prepare_migrations
  run_step move_migrations_to_history
  [ "$status" -eq 0 ]
  run grep -c "curl-request GET https://api.github.com/repos/My-Org/abc-databases " "$MOCK_LOG"
  [ "$output" = "0" ]
  run grep -c "push --quiet origin HEAD:refs/heads/develop " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a rejected push is retried from a fresh clone" {
  export GIT_PUSH_FAILURES=1
  make_git_mock
  prepare_fetched_repo
  run_step prepare_migrations
  run_step move_migrations_to_history
  [ "$status" -eq 0 ]
  run grep -c "^git clone .*history-repo" "$MOCK_LOG"
  [ "$output" = "2" ]
}

@test "a push that keeps failing lists the scripts to move by hand" {
  export GIT_PUSH_FAILURES=5
  make_git_mock
  prepare_fetched_repo
  run_step prepare_migrations
  run_step move_migrations_to_history
  [ "$status" -ne 0 ]
  [[ "$output" == *"  - 01_create_t1.sql"* ]] || false
  [[ "$output" == *"move them by hand before the next run"* ]] || false
  run grep -c "push --quiet" "$MOCK_LOG"
  [ "$output" = "3" ]
}

@test "an App without write access fails the move with GitHub's reason" {
  export CURL_TOKEN_STATUS=422
  prepare_fetched_repo
  run_step prepare_migrations
  run_step move_migrations_to_history
  [ "$status" -ne 0 ]
  [[ "$output" == *"GitHub refused a contents:write token for My-Org/abc-databases: The permissions requested are not granted to this installation"* ]] || false
}

@test "results report the mode, ref, scripts and history commit, then clean the work dir" {
  prepare_fetched_repo
  run_step prepare_migrations
  echo "0123456789abcdef" > "$MIGRATIONS_DIR/history_commit"
  echo "CREATE TABLE t1 (id INT);" > "$MIGRATIONS_DIR/preview.sql"
  run_step write_migration_results
  [ "$status" -eq 0 ]
  run grep -c 'np service action update --results {"mode":"apply","ref":"v1.0.0","scripts":\["01_create_t1.sql","02_alter_t1.sql"\],"history_commit":"0123456789abcdef","preview_sql":"CREATE TABLE t1 (id INT);"}' "$MOCK_LOG"
  [ "$output" = "1" ]
  [ ! -d "$MIGRATIONS_DIR" ]
}
