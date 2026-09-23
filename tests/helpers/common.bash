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

make_aws_mock() {
  local username="${1:-npmaster}" password="${2:-s3cr3t}"
  cat > "$MOCK_BIN/aws" <<MOCK
#!/usr/bin/env bash
echo "aws \$*" >> "$MOCK_LOG"
case "\$1 \$2" in
  "secretsmanager get-secret-value")
    echo '{"username":"$username","password":"$password"}'
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
