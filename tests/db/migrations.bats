#!/usr/bin/env bats

load '../helpers/common'
load '../helpers/migrations'

setup() {
  setup_migrations_env
}

@test "fetch clones main of the sigla repository with a read token scoped to it" {
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  [[ "$output" == *NEXT_STEP_RAN* ]] || false
  run grep -c 'curl-request POST https://api.github.com/app/installations/777/access_tokens {"repositories":\["abc-databases"\],"permissions":{"contents":"read"}}' "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c "git clone --quiet --depth 1 --branch main https://github.com/My-Org/abc-databases.git $OUTPUT_DIR/migrations/repo auth=x-access-token:$TEST_TOKEN" "$MOCK_LOG"
  [ "$output" = "1" ]
  run cat "$OUTPUT_DIR/migrations/commit"
  [ "$output" = "0123456789abcdef0123456789abcdef01234567" ]
}

@test "the GitHub App is matched by org case-insensitively" {
  printf 'migrations_github_org: my-org\n' > "$VALUES"
  set_migration_parameters '{"mode":"preview"}'
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "step crypto jwt sign --key .* --iss 123 " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "preview and apply only ever ask GitHub for a read token" {
  set_migration_parameters '{"mode":"preview"}'
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  set_migration_parameters '{"mode":"apply"}'
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c '"contents":"write"' "$MOCK_LOG"
  [ "$output" = "0" ]
  run grep -c '^curl-request POST .*"permissions":{"contents":"read"}' "$MOCK_LOG"
  [ "$output" = "2" ]
}

@test "a repository containing symbolic links is rejected before any script is read" {
  ln -s /etc/hosts "$FIXTURE_REPO/qas/app_42/03_link.sql"
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"contains symbolic links, which are not allowed: qas/app_42/03_link.sql"* ]] || false
}

@test "a symlinked directory is rejected too" {
  ln -s /tmp "$FIXTURE_REPO/qas/linked"
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"qas/linked"* ]] || false
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
  run grep -c "curl-stdin-auth $TEST_TOKEN" "$MOCK_LOG"
  [ "$output" = "0" ]
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
  [[ "$output" != *"Cloning"* ]] || false
  [[ "$output" != *NEXT_STEP_RAN* ]] || false
  run grep -c "^git clone" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a configured installation id skips the installation lookup" {
  set_migration_parameters '{"mode":"preview"}'
  export NP_GITHUB_APPS="org=my-org,app-id=123,installation-id=999,private-key=${KEY_FILE}"
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "/installation " "$MOCK_LOG"
  [ "$output" = "0" ]
  run grep -c "curl-request POST https://api.github.com/app/installations/999/access_tokens" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a key held in SSM is read with the agent's own credentials, not the service role" {
  set_migration_parameters '{"mode":"preview"}'
  export NP_GITHUB_APPS="org=my-org,app-id=123,private-key-ssm-parameter=/np/gh/key"
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "aws ssm get-parameter --name /np/gh/key --with-decryption .* access_key=unset" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a repository without a main branch says so" {
  export GIT_MISSING_REF="main"
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not clone My-Org/abc-databases at main: check that the repository has a main branch"* ]] || false
}

@test "a missing environment or database directory is reported with its path" {
  set_migration_parameters '{"mode":"apply"}' prd
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"directory prd/app_42 does not exist in My-Org/abc-databases@main"* ]] || false
}

@test "a service without the migrations user asks for an update before touching GitHub" {
  export MIGRATOR_SECRET_ARN=""
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"run its update action once to create it"* ]] || false
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an environment or database directory that could escape the repository is rejected" {
  set_migration_parameters '{"mode":"apply"}' '../etc'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"environment dimension '../etc' must be a single directory name"* ]] || false

  set_migration_parameters '{"mode":"apply"}'
  MIGRATIONS_DIRECTORY="../x" run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"migrations_directory attribute '../x' must be a single directory name"* ]] || false
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a service without an environment dimension cannot run migrations" {
  CONTEXT=$(jq -c 'del(.service.dimensions)' <<< "$CONTEXT")
  export CONTEXT
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"the service has no environment dimension"* ]] || false
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "without migrations_github_org the only org with a GitHub App holds the repository" {
  : > "$VALUES"
  export NP_GITHUB_APPS="org=Solo-Org,app-id=123,private-key=${KEY_FILE}"
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "git clone .* https://github.com/Solo-Org/abc-databases.git " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "without migrations_github_org several GitHub Apps are ambiguous" {
  : > "$VALUES"
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"set migrations_github_org in values.yaml (the agent has GitHub Apps for: other-org,My-Org)"* ]] || false
  [[ "$output" != *"Migrations: "* ]] || false
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "an unknown mode is rejected" {
  set_migration_parameters '{"mode":"force"}'
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"mode 'force' is not valid"* ]] || false
}

@test "prepare lists every script in order and skips subdirectories and old changelogs" {
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run cat "$MIGRATIONS_DIR/scripts.txt"
  [ "$output" = $'01_create_t1.sql\n02_alter_t1.sql' ]
}

@test "outside dev the changeset id is the script name and scripts never re-run on change" {
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run jq -c '[.databaseChangeLog[].changeSet | {id, runOnChange, logicalFilePath}]' "$MIGRATIONS_DIR/changelog.json"
  [ "$output" = '[{"id":"01_create_t1","runOnChange":false,"logicalFilePath":"qas/app_42/changelog"},{"id":"02_alter_t1","runOnChange":false,"logicalFilePath":"qas/app_42/changelog"}]' ]
}

@test "in dev the changeset id is the script name too and runs on change" {
  set_migration_parameters '{"mode":"apply"}' dev
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run jq -r '.databaseChangeLog[0].changeSet | "\(.id) \(.runOnChange)"' "$MIGRATIONS_DIR/changelog.json"
  [ "$output" = "01_dev true" ]
}

@test "scripts are split only on GO lines and keep their comments" {
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run jq -c '.databaseChangeLog[0].changeSet.changes[0].sqlFile' "$MIGRATIONS_DIR/changelog.json"
  [ "$output" = '{"path":"stage/01_create_t1.sql","relativeToChangelogFile":true,"splitStatements":true,"endDelimiter":"\\nGO","stripComments":false,"encoding":"UTF-8"}' ]
}

@test "an empty script directory succeeds saying there is nothing to apply" {
  prepare_fetched_repo
  rm "$MIGRATIONS_DIR"/repo/qas/app_42/0*.sql
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  [[ "$output" == *"No scripts in qas/app_42 at main (0123456789ab): nothing to apply."* ]] || false
  [[ "$output" == *NEXT_STEP_RAN* ]] || false
  [ ! -f "$MIGRATIONS_DIR/changelog.json" ]
}

@test "with no scripts apply never touches the database nor the repository and reports no scripts" {
  prepare_fetched_repo
  rm "$MIGRATIONS_DIR"/repo/qas/app_42/0*.sql
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -eq 0 ]
  [[ "$output" == *NEXT_STEP_RAN* ]] || false
  run grep -cE "^(liquibase|aws|curl|git) " "$MOCK_LOG"
  [ "$output" = "0" ]
  run_step write_migration_results
  [ "$status" -eq 0 ]
  run grep -c 'np service action update --results {"mode":"apply","commit":"0123456789abcdef0123456789abcdef01234567","scripts":\[\]}$' "$MOCK_LOG"
  [ "$output" = "1" ]
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
  set_migration_parameters '{"mode":"apply"}' dev
  prepare_fetched_repo
  printf 'DROP TABLE d1;\n' > "$MIGRATIONS_DIR/repo/dev/app_42/02_drop.sql"
  run_step prepare_migrations
  [ "$status" -eq 0 ]
}

@test "GRANT CONNECT is blocked even in dev, across lines" {
  set_migration_parameters '{"mode":"apply"}' dev
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

@test "a comment marker inside a string literal does not hide what follows" {
  prepare_fetched_repo
  printf "SELECT 'a--b' AS x; DROP TABLE t1;\nSELECT 'it''s /* fine' AS y;\n" > "$MIGRATIONS_DIR/repo/qas/app_42/03_tricky.sql"
  run_step prepare_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"03_tricky.sql: DROP"* ]] || false
}

@test "dynamic SQL in a string literal is still checked" {
  prepare_fetched_repo
  printf "EXEC('DROP TABLE t1');\n" > "$MIGRATIONS_DIR/repo/qas/app_42/03_dynamic.sql"
  run_step prepare_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"03_dynamic.sql: DROP"* ]] || false
}

@test "a quote inside a bracketed or double-quoted identifier does not open a string" {
  prepare_fetched_repo
  printf 'SELECT 1 AS [it'"'"'s], 2 AS "o'"'"'brien"; -- DROP TABLE t1;\nSELECT 3;\n' > "$MIGRATIONS_DIR/repo/qas/app_42/03_ident.sql"
  run_step prepare_migrations
  [ "$status" -eq 0 ]

  printf 'SELECT 1 AS [it'"'"'s]; DROP TABLE t1;\n' > "$MIGRATIONS_DIR/repo/qas/app_42/03_ident.sql"
  run_step prepare_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"03_ident.sql: DROP"* ]] || false
}

@test "the repository name comes from the sigla, lowercased" {
  CONTEXT=$(jq -c '.tags.namespace = "XYZ-payments"' <<< "$CONTEXT")
  export CONTEXT
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "git clone .* https://github.com/My-Org/xyz-databases.git " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "namespace.slug wins over tags.namespace for the sigla" {
  CONTEXT=$(jq -c '.namespace.slug = "Abc-core" | .tags.namespace = "xyz-other"' <<< "$CONTEXT")
  export CONTEXT
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run grep -c "git clone .* https://github.com/My-Org/abc-databases.git " "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "an application without a namespace cannot run migrations" {
  CONTEXT=$(jq -c '.tags = {}' <<< "$CONTEXT")
  export CONTEXT
  run_step fetch_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot resolve the application's sigla"* ]] || false
  run grep -c "^curl " "$MOCK_LOG"
  [ "$output" = "0" ]
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
  set_migration_parameters '{"mode":"preview"}'
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

@test "liquibase never sees the agent's credentials, so scripts cannot expand them" {
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -eq 0 ]
  run grep -c "^liquibase-env aws_secret=unset github_apps=unset java_home=$BATS_TEST_TMPDIR/java$" "$MOCK_LOG"
  [ "$output" = "4" ]
}

@test "a failed update says that what ran is recorded and skipped on retry" {
  echo "update" > "$BATS_TEST_TMPDIR/liquibase-fail-on"
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"recorded in DATABASECHANGELOG and are skipped on retry"* ]] || false
}

@test "scripts that already ran are skipped and only the pending ones are applied and reported" {
  echo "qas/app_42/changelog::01_create_t1::nullplatform" > "$BATS_TEST_TMPDIR/liquibase-applied"
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scripts not yet applied on app_42:"$'\n'"  - 02_alter_t1.sql"$'\n'"SQL that the update runs:"* ]] || false
  [ "$(calls_matching '^liquibase .* update$')" -eq 1 ]
  run_step write_migration_results
  [ "$status" -eq 0 ]
  run grep -c 'np service action update --results {"mode":"apply","commit":"0123456789abcdef0123456789abcdef01234567","scripts":\["02_alter_t1.sql"\]}$' "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "when every script already ran apply succeeds without rendering or updating anything" {
  printf 'qas/app_42/changelog::01_create_t1::nullplatform\nqas/app_42/changelog::02_alter_t1::nullplatform\n' > "$BATS_TEST_TMPDIR/liquibase-applied"
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to apply: every script in qas/app_42 already ran on app_42."* ]] || false
  [[ "$output" == *NEXT_STEP_RAN* ]] || false
  [ "$(calls_matching '^liquibase .* update')" -eq 0 ]
  run_step write_migration_results
  run grep -c '"scripts":\[\]}$' "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a liquibase status that cannot be read fails instead of applying nothing" {
  printf 'something unexpected\n     qas/app_42/changelog::01_create_t1::nullplatform\n' > "$BATS_TEST_TMPDIR/liquibase-status"
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read the pending changesets from liquibase status"* ]] || false
  [ "$(calls_matching '^liquibase .* update')" -eq 0 ]
}

@test "a liquibase status whose count disagrees with the listed changesets fails" {
  printf '2 changesets have not been applied to @jdbc:sqlserver://db\n     qas/app_42/changelog::01_create_t1::nullplatform\n' > "$BATS_TEST_TMPDIR/liquibase-status"
  prepare_fetched_repo
  run_step prepare_migrations
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read the pending changesets from liquibase status"* ]] || false
  [ "$(calls_matching '^liquibase .* update')" -eq 0 ]
}

@test "results report the mode, commit and scripts, never the SQL, then clean the work dir" {
  prepare_fetched_repo
  run_step prepare_migrations
  printf '01_create_t1.sql\n02_alter_t1.sql\n' > "$MIGRATIONS_DIR/pending.txt"
  echo "CREATE LOGIN x WITH PASSWORD = 'secret';" > "$MIGRATIONS_DIR/preview.sql"
  run_step write_migration_results
  [ "$status" -eq 0 ]
  run grep -c 'np service action update --results {"mode":"apply","commit":"0123456789abcdef0123456789abcdef01234567","scripts":\["01_create_t1.sql","02_alter_t1.sql"\]}$' "$MOCK_LOG"
  [ "$output" = "1" ]
  [ ! -d "$MIGRATIONS_DIR" ]
}

@test "a long app user still yields a valid migrations user, so delete never blocks on it" {
  long_user="a$(printf 'b%.0s' $(seq 1 63))"
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/lib'; migrator_username_for '$long_user'"
  [ "$status" -eq 0 ]
  [ "${#output}" -eq 64 ]
  [[ "$output" == *_mig ]]
}

make_liquibase_mise_mock() {
  MISE_INSTALLS="$BATS_TEST_TMPDIR/mise-installs"
  export MISE_INSTALLS
  cat > "$MOCK_BIN/mise" <<MOCK
#!/usr/bin/env bash
echo "mise \$*" >> "$MOCK_LOG"
dir="$MISE_INSTALLS/\${2//[:\/@]/-}"
case "\$1" in
  install)
    mkdir -p "\$dir/bin"
    printf '#!/usr/bin/env bash\n' > "\$dir/bin/java"
    printf '#!/usr/bin/env bash\n' > "\$dir/bin/liquibase"
    chmod +x "\$dir/bin/java" "\$dir/bin/liquibase"
    ;;
  where)
    [ -d "\$dir" ] || { echo "mise ERROR \$2 is not installed" >&2; exit 1; }
    echo "\$dir"
    ;;
  bin-paths)
    [ -d "\$dir" ] || { echo "mise ERROR \$2 is not installed" >&2; exit 1; }
    echo "\$dir/bin"
    ;;
  *)
    echo "mise ERROR unexpected subcommand \$1" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/mise"
}

@test "the migrations_directory attribute replaces the database name as the scripts directory" {
  mkdir -p "$FIXTURE_REPO/qas/custom_dir"
  printf 'SELECT 1;\n' > "$FIXTURE_REPO/qas/custom_dir/01_custom.sql"
  export MIGRATIONS_DIRECTORY="custom_dir"
  set_migration_parameters '{"mode":"preview","database_directory":"ignored_dir"}'
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  [[ "$output" == *"directory qas/custom_dir,"* ]] || false
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  [ "$(cat "$OUTPUT_DIR/migrations/scripts.txt")" = "01_custom.sql" ]
}

@test "preview results list the scripts that would run" {
  set_migration_parameters '{"mode":"preview"}'
  run_step fetch_migrations
  [ "$status" -eq 0 ]
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -eq 0 ]
  run_step write_migration_results
  [ "$status" -eq 0 ]
  run grep -c 'np service action update --results {"mode":"preview","commit":"0123456789abcdef0123456789abcdef01234567","scripts":\["01_create_t1.sql","02_alter_t1.sql"\]}$' "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "require_liquibase installs the glibc java and the pinned liquibase with mise" {
  make_liquibase_mise_mock
  run bash -c "
    source '$DB_SERVICE_PATH/scripts/aws/lib'
    source '$DB_SERVICE_PATH/scripts/aws/migrations_lib'
    is_musl() { return 1; }
    require_mssql_jdbc() { echo '$BATS_TEST_TMPDIR/mssql.jar'; }
    require_liquibase
    echo \"bin=\$MIGRATIONS_LIQUIBASE_BIN java=\$JAVA_HOME\"
  "
  [ "$status" -eq 0 ]
  grep -q "^mise install java@zulu-21.54.109.0$" "$MOCK_LOG"
  grep -q "^mise install liquibase@5.0.2$" "$MOCK_LOG"
  [[ "$output" == *"bin=$MISE_INSTALLS/liquibase-5.0.2/bin/liquibase"* ]] || false
}

@test "require_liquibase picks the musl java build on musl hosts" {
  make_liquibase_mise_mock
  run bash -c "
    source '$DB_SERVICE_PATH/scripts/aws/lib'
    source '$DB_SERVICE_PATH/scripts/aws/migrations_lib'
    is_musl() { return 0; }
    require_mssql_jdbc() { echo '$BATS_TEST_TMPDIR/mssql.jar'; }
    require_liquibase
  "
  [ "$status" -eq 0 ]
  grep -q "^mise install java@zulu-musl-21.54.109.0$" "$MOCK_LOG"
}

@test "require_liquibase fails naming the tool when mise is missing" {
  run bash -c "
    PATH='/usr/bin:/bin'
    source '$DB_SERVICE_PATH/scripts/aws/lib'
    source '$DB_SERVICE_PATH/scripts/aws/migrations_lib'
    require_liquibase
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"mise is not available to install java@"* ]] || false
}

@test "a jdbc driver that fails its pinned sha256 is rejected and not cached" {
  cat > "$MOCK_BIN/curl" <<MOCK
#!/usr/bin/env bash
echo "curl \$*" >> "$MOCK_LOG"
out=""; prev=""
for arg in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$arg"
  prev="\$arg"
done
echo "tampered" > "\$out"
MOCK
  chmod +x "$MOCK_BIN/curl"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  run bash -c "
    source '$DB_SERVICE_PATH/scripts/aws/lib'
    source '$DB_SERVICE_PATH/scripts/aws/migrations_lib'
    require_mssql_jdbc
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not match its pinned sha256"* ]] || false
  [ -z "$(ls "$XDG_CACHE_HOME/np-rds-sqlserver")" ]
}

@test "a failed jdbc driver download is reported" {
  cat > "$MOCK_BIN/curl" <<MOCK
#!/usr/bin/env bash
exit 22
MOCK
  chmod +x "$MOCK_BIN/curl"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  run bash -c "
    source '$DB_SERVICE_PATH/scripts/aws/lib'
    source '$DB_SERVICE_PATH/scripts/aws/migrations_lib'
    require_mssql_jdbc
  "
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not download mssql-jdbc"* ]] || false
}

@test "a failed validate stops the run before status and update" {
  echo validate > "$BATS_TEST_TMPDIR/liquibase-fail-on"
  prepare_fetched_repo
  run_step prepare_migrations
  [ "$status" -eq 0 ]
  run_step_with_mocked_liquibase run_migrations
  [ "$status" -ne 0 ]
  [[ "$output" == *"liquibase validate failed"* ]] || false
  [ "$(calls_matching '^liquibase .* update')" -eq 0 ]
  [ "$(calls_matching '^liquibase .* status')" -eq 0 ]
}
