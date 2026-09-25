#!/usr/bin/env bats

load '../helpers/common'

BUCKET="acme-tofu-state"
SERVICE_ID="99999999-8888-7777-6666-555555555555"
ACCOUNT_NRN="organization=1:account=2"
REGION="us-east-1"
VPC_ID="vpc-0123456789abcdef0"

build_context_json() {
  jq -n \
    --arg id "$SERVICE_ID" \
    --arg nrn "${ACCOUNT_NRN}:namespace=3:service=4" \
    --argjson attrs "$1" \
    '{service: {id: $id, nrn: $nrn, attributes: $attrs}, parameters: {}}'
}

setup() {
  setup_mock_bin

  export SERVICE_PATH="$SERVER_SERVICE_PATH"
  export VALUES="$SERVER_SERVICE_PATH/values.yaml"
  export RDS_SQL_SERVER_S3_STATE_BUCKET="$BUCKET"
  unset RDS_SQL_SERVER_SECRET_KMS_KEY_ID

  cat > "$MOCK_BIN/aws" <<MOCK
#!/usr/bin/env bash
echo "aws \$*" >> "$MOCK_LOG"
case "\$1 \$2" in
  "s3api head-bucket")
    exit 0
    ;;
esac
exit 0
MOCK
  chmod +x "$MOCK_BIN/aws"

  cat > "$MOCK_BIN/np" <<MOCK
#!/usr/bin/env bash
echo "np \$*" >> "$MOCK_LOG"
case "\$1 \$2" in
  "provider list")
    cat <<'JSON'
{"results":[
  {"id":"prov-region","data_source":{"stored_keys":["account.region"]}},
  {"id":"prov-vpc","data_source":{"stored_keys":["vpc.id"]}}
]}
JSON
    ;;
  "provider read")
    id=""
    prev=""
    for a in "\$@"; do
      if [ "\$prev" = "--id" ]; then id="\$a"; fi
      prev="\$a"
    done
    case "\$id" in
      prov-region) echo '{"attributes":{"account":{"region":"$REGION"}}}' ;;
      prov-vpc)    echo '{"attributes":{"vpc":{"id":"$VPC_ID"}}}' ;;
      *) echo '{"attributes":{}}' ;;
    esac
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/np"
}

run_and_dump() {
  export CONTEXT="$1"
  run bash -c "source '$SERVER_SERVICE_PATH/scripts/aws/build_context' >/dev/null 2>&1; \
    echo \"TOFU_VARIABLES=\$TOFU_VARIABLES\""
}

@test "a development workload without an override selects the smallest instance class" {
  run_and_dump "$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=instance_class=db.t3.small"* ]]
}

@test "a production-heavy workload for standard edition selects the largest instance class" {
  run_and_dump "$(build_context_json '{"edition":"sqlserver-se","workload":"production-heavy","allocated_storage":200,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=instance_class=db.m5.2xlarge"* ]]
}

@test "a production-light workload for web edition selects the middle instance class" {
  run_and_dump "$(build_context_json '{"edition":"sqlserver-web","workload":"production-light","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=instance_class=db.m5.large"* ]]
}

@test "an unknown workload attribute fails end-to-end naming the field" {
  export CONTEXT="$(build_context_json '{"edition":"sqlserver-ex","workload":"gigantic","allocated_storage":20,"multi_az":false}')"
  run bash -c "source '$SERVER_SERVICE_PATH/scripts/aws/build_context'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"'Workload'"* ]]
}

@test "the secret kms key id env var adds the terraform variable" {
  export RDS_SQL_SERVER_SECRET_KMS_KEY_ID="arn:aws:kms:us-east-1:1:key/abcd"
  run_and_dump "$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=secret_kms_key_id=arn:aws:kms:us-east-1:1:key/abcd"* ]]
}

@test "an unset secret kms key id omits the terraform variable" {
  unset RDS_SQL_SERVER_SECRET_KMS_KEY_ID
  run_and_dump "$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [[ "$output" != *"secret_kms_key_id"* ]]
}

@test "an empty secret kms key id omits the terraform variable" {
  export RDS_SQL_SERVER_SECRET_KMS_KEY_ID=""
  run_and_dump "$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [[ "$output" != *"secret_kms_key_id"* ]]
}

@test "the account region and vpc are resolved through the np provider list" {
  run_and_dump "$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  run grep -c -- "--nrn ${ACCOUNT_NRN}" "$MOCK_LOG"
  [ "$output" -ge 1 ]
  run grep -c "provider read --id prov-region" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c "provider read --id prov-vpc" "$MOCK_LOG"
  [ "$output" = "1" ]
}
