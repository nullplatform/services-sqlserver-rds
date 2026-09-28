#!/usr/bin/env bash

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
export DB_SERVICE_PATH="$REPO_ROOT/rds-sqlserver-db"
export SERVER_SERVICE_PATH="$REPO_ROOT/rds-sqlserver-server"

setup_mock_bin() {
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  MOCK_LOG="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$MOCK_BIN"
  : > "$MOCK_LOG"
  export MOCK_BIN MOCK_LOG
  export PATH="$MOCK_BIN:$PATH"
}

make_sqlcmd_mock() {
  local exit_code="${1:-0}"
  cat > "$MOCK_BIN/sqlcmd" <<MOCK
#!/usr/bin/env bash
echo "sqlcmd \$*" >> "$MOCK_LOG"

prev=""
for arg in "\$@"; do
  if [ "\$prev" = "-i" ]; then
    if [ ! -f "\$arg" ]; then
      echo "sqlcmd: input file not found: \$arg" >&2
      exit 1
    fi
  fi
  if [ "\$prev" = "-v" ]; then
    case "\$arg" in
      *=*) ;;
      *) echo "sqlcmd: malformed scripting variable: \$arg" >&2; exit 1 ;;
    esac
  fi
  prev="\$arg"
done

if [ -z "\${SQLCMDPASSWORD:-}" ]; then
  echo "sqlcmd: no password in environment" >&2
  exit 1
fi

exit $exit_code
MOCK
  chmod +x "$MOCK_BIN/sqlcmd"
}

make_mise_mock() {
  local install_exit="${1:-0}"
  MISE_INSTALLS="$BATS_TEST_TMPDIR/mise-installs"
  export MISE_INSTALLS
  cat > "$MOCK_BIN/mise" <<MOCK
#!/usr/bin/env bash
echo "mise \$*" >> "$MOCK_LOG"
dir="$MISE_INSTALLS/\${2//[:\/@]/-}"
case "\$1" in
  install)
    [ "$install_exit" -eq 0 ] || { echo "mise ERROR failed to install \$2" >&2; exit $install_exit; }
    mkdir -p "\$dir"
    printf '#!/usr/bin/env bash\necho "sqlcmd \$*" >> "$MOCK_LOG"\n' > "\$dir/sqlcmd"
    chmod +x "\$dir/sqlcmd"
    ;;
  bin-paths)
    [ -d "\$dir" ] || { echo "mise ERROR \$2 is not installed" >&2; exit 1; }
    echo "\$dir"
    ;;
  *)
    echo "mise ERROR unexpected subcommand \$1" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/mise"
}

make_mise_mock_missing_binary() {
  MISE_INSTALLS="$BATS_TEST_TMPDIR/mise-installs"
  export MISE_INSTALLS
  cat > "$MOCK_BIN/mise" <<MOCK
#!/usr/bin/env bash
echo "mise \$*" >> "$MOCK_LOG"
dir="$MISE_INSTALLS/\${2//[:\/@]/-}"
case "\$1" in
  install)
    mkdir -p "\$dir"
    ;;
  bin-paths)
    [ -d "\$dir" ] || { echo "mise ERROR \$2 is not installed" >&2; exit 1; }
    echo "\$dir"
    ;;
  *)
    echo "mise ERROR unexpected subcommand \$1" >&2
    exit 1
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/mise"
}

make_mktemp_mock() {
  cat > "$MOCK_BIN/mktemp" <<MOCK
#!/usr/bin/env bash
path=\$(/usr/bin/mktemp "\$@")
echo "mktemp-created \$path" >> "$MOCK_LOG"
echo "\$path"
MOCK
  chmod +x "$MOCK_BIN/mktemp"
}

make_aws_mock() {
  local username="${1:-npmaster}" password="${2:-s3cr3t}"
  cat > "$MOCK_BIN/aws" <<MOCK
#!/usr/bin/env bash
echo "aws \$*" >> "$MOCK_LOG"
case "\$1 \$2" in
  "secretsmanager get-secret-value")
    echo '{"username":"$username","password":"$password"}'
    ;;
  "s3api get-object")
    key=""; prev=""
    for arg in "\$@"; do
      [ "\$prev" = "--key" ] && key="\$arg"
      prev="\$arg"
    done
    outfile="\${!#}"
    case "\${AWS_MOCK_STATE_FILE:-}" in
      "")
        echo "An error occurred (NoSuchKey) when calling the GetObject operation: The specified key does not exist." >&2
        exit 254
        ;;
      denied)
        echo "An error occurred (AccessDenied) when calling the GetObject operation: Access Denied" >&2
        exit 254
        ;;
      *)
        echo "get-object key=\$key" >> "$MOCK_LOG"
        cp "\$AWS_MOCK_STATE_FILE" "\$outfile"
        echo '{"ContentType":"application/json"}'
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/aws"
}

make_tofu_mock() {
  local password="${1-appsecret}"
  cat > "$MOCK_BIN/tofu" <<MOCK
#!/usr/bin/env bash
echo "tofu \$*" >> "$MOCK_LOG"
if [ "\$1" = "output" ]; then
  echo "$password"
fi
exit 0
MOCK
  chmod +x "$MOCK_BIN/tofu"
}

make_np_mock() {
  local payload="$1"
  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"
cat <<'PAYLOAD'
$payload
PAYLOAD
MOCK
  chmod +x "$MOCK_BIN/np"
}

calls_matching() {
  grep -c "$1" "$MOCK_LOG" || true
}
