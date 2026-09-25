#!/usr/bin/env bats

load '../helpers/common'

BUCKET="acme-tofu-state"
SERVICE_ID="99999999-8888-7777-6666-555555555555"
ACCOUNT_NRN="organization=1:account=2"
SERVICE_NRN="${ACCOUNT_NRN}:namespace=3:service=4"
REGION="us-east-1"
VPC_ID="vpc-0123456789abcdef0"
OTHER_REGION="sa-east-1"
SUBNETS='["subnet-aaa","subnet-bbb"]'
DIMENSIONS="environment:javi-k8s"

build_context_json() {
  jq -n \
    --arg id "$SERVICE_ID" \
    --arg nrn "$SERVICE_NRN" \
    --argjson attrs "$1" \
    '{entity_nrn: $nrn, service: {id: $id, nrn: $nrn, dimensions: {environment: "javi-k8s"}, attributes: $attrs}, parameters: {}}'
}

setup() {
  setup_mock_bin

  export SERVICE_PATH="$SERVER_SERVICE_PATH"
  export VALUES="$SERVER_SERVICE_PATH/values.yaml"
  export RDS_SQL_SERVER_S3_STATE_BUCKET="$BUCKET"
  unset RDS_SQL_SERVER_SECRET_KMS_KEY_ID
  export MOCK_SUBNETS="$SUBNETS"

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
[ "\$1 \$2" = "provider list" ] || { echo "unexpected np call: \$*" >&2; exit 1; }
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
if [[ "\$nrn" != "$ACCOUNT_NRN"* ]]; then
  echo '{"results":[]}'
  exit 0
fi
case "\$category:\$dimensions" in
  cloud-providers:$DIMENSIONS) echo '{"results":[{"attributes":{"account":{"region":"$REGION"}}}]}' ;;
  cloud-providers:*)           echo '{"results":[{"attributes":{"account":{"region":"$OTHER_REGION"}}}]}' ;;
  vpc:*)                       echo '{"results":[{"attributes":{"vpc":{"id":"$VPC_ID","subnets":'"\$MOCK_SUBNETS"'}}}]}' ;;
  *)                           echo '{"results":[]}' ;;
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

@test "the region and vpc are resolved from the entity nrn and the service dimensions" {
  run_and_dump "$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=region=${REGION} "* ]]
  [[ "$output" == *"-var=vpc_id=${VPC_ID} "* ]]
  run grep -c -- "provider list --nrn ${SERVICE_NRN} --categories cloud-providers --dimensions ${DIMENSIONS}" "$MOCK_LOG"
  [ "$output" = "1" ]
  run grep -c -- "provider list --nrn ${SERVICE_NRN} --categories vpc --dimensions ${DIMENSIONS}" "$MOCK_LOG"
  [ "$output" = "1" ]
}

@test "a service without dimensions omits the dimensions flag" {
  run_and_dump "$(jq -n --arg id "$SERVICE_ID" --arg nrn "$SERVICE_NRN" '{entity_nrn: $nrn, service: {id: $id, attributes: {edition: "sqlserver-ex", allocated_storage: 20, multi_az: false}}, parameters: {}}')"
  [ "$status" -eq 0 ]
  run grep -c -- "--dimensions" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "the entity nrn wins over the service nrn" {
  run_and_dump "$(jq -n --arg id "$SERVICE_ID" --arg nrn "$SERVICE_NRN" '{entity_nrn: $nrn, service: {id: $id, nrn: "organization=9:account=9", attributes: {edition: "sqlserver-ex", allocated_storage: 20, multi_az: false}}, parameters: {}}')"
  [ "$status" -eq 0 ]
  run grep -c -- "--nrn organization=9:account=9" "$MOCK_LOG"
  [ "$output" = "0" ]
}

@test "a missing region provider fails naming the nrn" {
  run bash -c "export CONTEXT='$(jq -nc --arg id "$SERVICE_ID" '{entity_nrn: "organization=7:account=7", service: {id: $id, attributes: {edition: "sqlserver-ex", allocated_storage: 20, multi_az: false}}, parameters: {}}')'; source '$SERVER_SERVICE_PATH/scripts/aws/build_context'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"organization=7:account=7"* ]]
}

@test "the entity nrn alone is enough to resolve the providers" {
  run_and_dump "$(jq -n --arg id "$SERVICE_ID" --arg nrn "$SERVICE_NRN" '{entity_nrn: $nrn, service: {id: $id, dimensions: {environment: "javi-k8s"}, attributes: {edition: "sqlserver-ex", allocated_storage: 20, multi_az: false}}, parameters: {}}')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-var=region=${REGION}"* ]]
}

@test "a context without any nrn fails before listing providers" {
  run_and_dump "$(jq -n --arg id "$SERVICE_ID" '{service: {id: $id, attributes: {edition: "sqlserver-ex", allocated_storage: 20, multi_az: false}}, parameters: {}}')"
  [ "$status" -ne 0 ]
  run grep -c "provider list" "$MOCK_LOG"
  [ "$output" = "0" ]
}

run_and_read_network_tfvars() {
  export CONTEXT="$1"
  run bash -c "source '$SERVER_SERVICE_PATH/scripts/aws/build_context' >/dev/null 2>&1 || exit 1; cat \"\$OUTPUT_DIR/network.auto.tfvars.json\""
}

@test "the vpc provider subnets reach tofu through an auto tfvars file" {
  run_and_read_network_tfvars "$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.subnet_ids')" = "$SUBNETS" ]
}

@test "a vpc provider without subnets fails before tofu" {
  export MOCK_SUBNETS='[]'
  run bash -c "export CONTEXT='$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')'; source '$SERVER_SERVICE_PATH/scripts/aws/build_context'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vpc.subnets"* ]]
}

@test "a single subnet is rejected because rds needs two availability zones" {
  export MOCK_SUBNETS='["subnet-aaa"]'
  run bash -c "export CONTEXT='$(build_context_json '{"edition":"sqlserver-ex","allocated_storage":20,"multi_az":false}')'; source '$SERVER_SERVICE_PATH/scripts/aws/build_context'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"at least two"* ]]
}
