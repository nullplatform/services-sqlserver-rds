# rds-sqlserver-server

Provisions an AWS RDS SQL Server instance. It does not create databases —
that is [`rds-sqlserver-db`](../rds-sqlserver-db/README.md)'s job — and it
exposes no link: applications never connect to this service directly.

## What the developer chooses

| Field | Notes |
|---|---|
| Edition | `sqlserver-ex` (default), `sqlserver-web`, `sqlserver-se`. Fixed at create. |
| Instance Class | `db.t3.small` upward. SQL Server has no `db.t3.micro`. |
| Storage | 20 GB to 2 TB. Standard edition requires 200 GB or more. |
| SQL Server Version | 2019 or 2022. Fixed at create. |
| High Availability | Multi-AZ standby. Not available on Express. |
| Server Collation / Timezone | Optional, fixed at create. |
| Secret Encryption Key | Optional KMS key for the master secret. |

Licensing is always `license-included` and is not exposed: bring-your-own-license
no longer exists for SQL Server on RDS, and offering it invites an expensive
mistake.

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
- **The security group opens 1433 to every CIDR associated with the VPC**, not
  only the primary one. EKS clusters commonly add a secondary CIDR for pod
  networking, and restricting to the primary silently blocks agent-to-RDS
  connectivity.

## Terraform state

State lives in the bucket named by `RDS_SQL_SERVER_S3_STATE_BUCKET`, under
`services/rds-sqlserver/<service-id>/`. The variable is required and the bucket must already
exist. See the repository README for the full picture, and pass the same name
as `state_bucket_name` to `specs/requirements/aws`.

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
