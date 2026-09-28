#!/usr/bin/env bats

load '../helpers/common'

SERVICE_ID="svc-1"
ENTITY_NRN="organization=1:account=2:namespace=3:application=4"
DIMENSIONS="environment:javi-k8s"
REGION_FOR_DIMENSIONS="us-east-1"
REGION_WITHOUT_DIMENSIONS="sa-east-1"

setup() {
  setup_mock_bin

  export SERVICE_PATH="$DB_SERVICE_PATH"
  export VALUES="$BATS_TEST_TMPDIR/values.yaml"
  printf 'region: eu-west-1\n' > "$VALUES"
  export RDS_SQL_SERVER_S3_STATE_BUCKET="acme-tofu-state"

  cat > "$MOCK_BIN/aws" <<MOCK
#!/usr/bin/env bash
echo "aws \$*" >> "$MOCK_LOG"
exit 0
MOCK
  chmod +x "$MOCK_BIN/aws"

  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"
[ "\$1 \$2" = "provider list" ] || exit 0
nrn=""
category=""
dimensions=""
prev=""
for a in "\$@"; do
  case "\$prev" in
    --nrn) nrn="\$a" ;;
    --categories) category="\$a" ;;
    --dimensions) dimensions="\$a" ;;
    --limit) [ -n "\$category" ] && { echo '{"error":"error: cannot use flag limit when using categories flag"}'; exit 1; } ;;
  esac
  prev="\$a"
done
if [[ "\$nrn" != "organization=1:account=2"* ]]; then
  echo '{"results":[]}'
  exit 0
fi
case "\$category:\$dimensions" in
  cloud-providers:$DIMENSIONS) echo '{"results":[{"attributes":{"account":{"region":"$REGION_FOR_DIMENSIONS"}}}]}' ;;
  cloud-providers:*)           echo '{"results":[{"attributes":{"account":{"region":"$REGION_WITHOUT_DIMENSIONS"}}}]}' ;;
  *)                           echo '{"results":[]}' ;;
esac
MOCK
  chmod +x "$MOCK_BIN/np"
}

context_json() {
  jq -nc --arg id "$SERVICE_ID" --arg nrn "$1" --argjson dimensions "$2" \
    '{type: "create", entity_nrn: $nrn, service: {id: $id, slug: "payments", dimensions: $dimensions}}'
}

run_and_dump_region() {
  export CONTEXT="$1"
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_context' >/dev/null 2>&1 || exit 1; echo \"REGION=\$REGION\""
}

@test "the region comes from the cloud-providers provider of the entity nrn and dimensions" {
  run_and_dump_region "$(context_json "$ENTITY_NRN" '{"environment":"javi-k8s"}')"
  [ "$status" -eq 0 ]
  [ "$output" = "REGION=${REGION_FOR_DIMENSIONS}" ]
  run grep -c -- "provider list --nrn ${ENTITY_NRN} --categories cloud-providers --dimensions ${DIMENSIONS}" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "values.yaml no longer decides the region" {
  run_and_dump_region "$(context_json "$ENTITY_NRN" '{"environment":"javi-k8s"}')"
  [[ "$output" != *"eu-west-1"* ]]
}

@test "a service without dimensions omits the dimensions flag" {
  run_and_dump_region "$(context_json "$ENTITY_NRN" '{}')"
  [ "$status" -eq 0 ]
  run grep -c -- "provider list --nrn ${ENTITY_NRN} --categories cloud-providers" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "--dimensions" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "the state bucket is checked in the resolved region" {
  run_and_dump_region "$(context_json "$ENTITY_NRN" '{"environment":"javi-k8s"}')"
  [ "$status" -eq 0 ]
  run grep -c -- "s3api head-bucket --bucket acme-tofu-state --region ${REGION_FOR_DIMENSIONS}" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a missing region provider fails naming the nrn" {
  export CONTEXT="$(context_json "organization=7:account=7" '{}')"
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_context'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"organization=7:account=7"* ]]
}

@test "a context without any nrn fails before listing providers" {
  export CONTEXT="$(jq -nc --arg id "$SERVICE_ID" '{type: "create", service: {id: $id, slug: "payments"}}')"
  run bash -c "source '$DB_SERVICE_PATH/scripts/aws/build_context'"
  [ "$status" -ne 0 ]
  run grep -c "provider list" "$MOCK_LOG"
  [ "$output" = "0" ]
}
