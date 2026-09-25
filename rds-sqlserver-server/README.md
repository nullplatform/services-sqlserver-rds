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

## Master secret encryption

The master password secret is encrypted with the KMS key named by the optional
`RDS_SQL_SERVER_SECRET_KMS_KEY_ID` agent variable (key ID or ARN). When it is
unset, Secrets Manager uses the AWS-managed `aws/secretsmanager` key.

## Outputs

`hostname`, `port`, `db_instance_identifier` and `master_secret_arn` are
written back to the service attributes. The last one is what
`rds-sqlserver-db` reads to reach the instance.

## Setup

The AssumeRole IAM role and policies live in
[`specs/requirements/aws`](specs/requirements/aws), and the platform
registration in [`specs/install/aws`](specs/install/aws). Both are applied
out-of-band by an account operator — see
[`specs/install/README.md`](specs/install/README.md).
