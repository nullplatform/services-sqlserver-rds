# rds-sqlserver-server

Provisions an AWS RDS SQL Server instance. It does not create databases —
that is [`rds-sqlserver-db`](../rds-sqlserver-db/README.md)'s job — and it
exposes no link: applications never connect to this service directly.

## What the developer chooses

| Field | Notes |
|---|---|
| Edition | `sqlserver-ex` (default), `sqlserver-web`, `sqlserver-se`. Fixed at create. |
| Workload | Development / testing, Production — light traffic, Production — heavy traffic. |
| Storage | 20 GB to 2 TB. Standard edition requires 200 GB or more. |
| SQL Server Version | 2019 or 2022. Fixed at create. |
| High Availability | Multi-AZ standby. Not available on Express. |

Licensing is always `license-included` and is not exposed: bring-your-own-license
no longer exists for SQL Server on RDS, and offering it invites an expensive
mistake.

## Workload to instance class

The developer states the expected usage; `instance_class_for_workload` in
`scripts/aws/lib` picks the RDS instance class for it, per edition:

| Workload | Express | Web | Standard |
|---|---|---|---|
| Development / testing | `db.t3.small` | `db.t3.medium` | `db.m5.large` |
| Production — light traffic | `db.t3.medium` | `db.m5.large` | `db.m5.xlarge` |
| Production — heavy traffic | `db.t3.xlarge` | `db.m5.xlarge` | `db.m5.2xlarge` |

Collation and timezone are not exposed: the instance uses the AWS default
collation and UTC.

## Constraints validated before Terraform runs

Two rules depend on more than one field, which a static JSON Schema `minimum`
cannot express, so `scripts/aws/build_context` checks them and aborts with a
message naming the field as the developer sees it:

- Standard edition requires at least 200 GB of storage.
- Express edition does not support High Availability.

Everything else is expressed in the schema itself.

## Notes on the RDS resource

- **Resources are named `<service slug>-<service id>`**, e.g.
  `orders-cacb7da7-9e34-4ba3-be7a-c2a149c23ead`. The slug is truncated so the
  RDS identifier stays within 63 characters.
- **`db_name` is deliberately absent.** RDS rejects it for every SQL Server
  edition; leaving it in makes the create fail.
- **The master username is `npmaster`.** RDS rejects `admin`, `sa`, `public`
  and `guest`, and `master` collides with the system database name.
- **Subnets come from `vpc.subnets` of the `vpc` provider.** List private
  subnets in at least two availability zones; RDS rejects a subnet group with
  fewer, and `build_context` stops before tofu when there are not two.
- **The security group opens 1433 to every CIDR associated with the VPC**, not
  only the primary one. EKS clusters commonly add a secondary CIDR for pod
  networking, and restricting to the primary silently blocks agent-to-RDS
  connectivity.

## Terraform state

State lives in the bucket named by `RDS_SQL_SERVER_S3_STATE_BUCKET`, under
`services/rds-sqlserver/<service-id>/`. The variable is required and the bucket must already
exist. See the repository README for the full picture, and pass the same name
as `state_bucket_name` to `specs/requirements/aws`.

## Storage encryption key

By default each instance gets its own customer-managed KMS key. Set
`RDS_SQL_SERVER_KMS_KEY_ARN` on the agent to encrypt new instances with an
existing key instead; no key is created then. The variable only applies while
the tofu state has no instance yet: once it exists, its key comes from the
state, so setting or changing the variable later never re-encrypts (and so
never replaces) an existing instance. List the key in `external_kms_key_arns` of `specs/requirements/aws` so
the role can use it.

## Master secret encryption

The master password secret is encrypted with the KMS key named by the optional
`RDS_SQL_SERVER_SECRET_KMS_KEY_ID` agent variable (key ID or ARN). When it is
unset, Secrets Manager uses the AWS-managed `aws/secretsmanager` key.

## Outputs

`hostname`, `port`, `db_instance_identifier` and `master_secret_arn` are
written back to the service attributes. The last one is what
`rds-sqlserver-db` reads to reach the instance.

## Install in your organization

The service is published once as the package `np-rds-sqlserver` (specification "RDS SQL Server"), visible to every organization. You do not copy its specs: you install the package and use it read-only. How installing a package works, how it coexists with a copy you registered, how to upgrade, and when to fork instead are in the [package installation guide](https://docs.nullplatform.com/docs/packages/install); this section has what is specific to this service.

Already registered a copy from the former `specs/install`? It keeps working: it called tofu-modules' `service_definition` on specs that stay in every release, and the package installs next to it, as the guide explains. If you sourced that directory as a module, pin its `?ref` to a release that still has it.

Installing it touches the same three layers as registering a service yourself, and only the nullplatform layer changes:

| Layer | What | Module |
|---|---|---|
| infrastructure (AWS credentials) | The IAM role the service assumes, with access to the state bucket | [`specs/requirements/aws`](specs/requirements/aws) |
| nullplatform (nullplatform API key) | The installation of the package and the agent channel | tofu-modules' `service_package_installation` |
| bindings | The role under selector `rds-sqlserver-server` in your IAM provider | your `aws-iam-configuration` provider |

Pick ONE release of this repository (the latest is on its [releases page](https://github.com/nullplatform/services-sqlserver-rds/releases)) and use its version in both places below: the IAM role is the one the worker of that same release expects. Both services of this repository share the release, so install them at the same version.

```hcl
# ── infrastructure layer ─────────────────────────────────────────────
module "rds_sqlserver_server_requirements" {
  source            = "git::https://github.com/nullplatform/services-sqlserver-rds.git//rds-sqlserver-server/specs/requirements/aws?ref=vX.Y.Z"
  cluster_name      = "<nullplatform agent cluster>"
  state_bucket_name = "<existing S3 bucket for the tofu state>"
}

# The agent role must be allowed to assume it: add it to the assume_role_arns
# of tofu-modules' infrastructure/aws/iam/agent.
#   assume_role_arns = [..., module.rds_sqlserver_server_requirements.permissions_role_arn]

# ── nullplatform layer ───────────────────────────────────────────────
# For a service the installation is the whole nullplatform side, channel included.
module "rds_sqlserver_server" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_package_installation?ref=v9.16.0"

  nrn                  = var.nrn
  package_slug         = "np-rds-sqlserver"
  package_version      = "X.Y.Z" # the same release, without the v
  agent_tags_selectors = { cluster = "runtime" } # must match the agent's TAGS
}
# Keeping channels in a separate bindings layer instead? Use
# nullplatform/package_installation here and service_definition_agent_association
# there, with package_slug = "np-rds-sqlserver".

# ── bindings layer ───────────────────────────────────────────────────
# One aws-iam-configuration per NRN and dimensions, at the account level: add
# the entry to the list your IAM provider already has. Both services of this
# repository go in the SAME provider, one selector each.
#   { selector = "rds-sqlserver-server", arn = module.rds_sqlserver_server_requirements.permissions_role_arn }
```

**The state bucket.** Set `RDS_SQL_SERVER_S3_STATE_BUCKET` on the worker (a per-package env patch in tofu-modules' `nullplatform/agent`) to the name of an existing S3 bucket, and pass the same name to the requirements module as `state_bucket_name`; see "Terraform state" above for the layout. Both services share the bucket. The bucket must already exist: the service never creates or deletes it, and without the variable every action fails before touching AWS.

The service assumes the role it finds under selector `rds-sqlserver-server` in the IAM provider closest to its NRN. To upgrade, move the release in both layers: `ref` of the requirements module and `package_version` of the installation. See tofu-modules' [`service_package_installation`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/service_package_installation) for its inputs and outputs. The channel it creates subscribes to `service` and `telemetry` notifications; without `telemetry` the service shows no metrics.

Prerequisites: an agent whose `TAGS` match the channel's `tags_selectors`, with `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries` and `np-rds-sqlserver` in its `worker_orchestrated_packages` (the worker then runs with the agent's identity, the one the role trusts), and an AWS cloud provider exposing `account.region` at the NRN or above it.

## How the package is published

Every release publishes a new revision of the package from this repository, in the same run that pushes the worker image ([`.github/workflows/release.yml`](../.github/workflows/release.yml)): the `publish-package` job applies [`rds-sqlserver-server/publish`](publish), a stack on tofu-modules' `service_package_publish`, which pins this tag's specs and the image by digest. The package version is the release tag, as for the image. The stack keeps its state where the organization secrets `PACKAGE_STATE_AWS_ACCOUNT_ID`, `PACKAGE_TFSTATE_BUCKET` and `PACKAGE_TFSTATE_REGION` point; the state role is `github-actions-<repository>-package-state` in that account, by convention.
