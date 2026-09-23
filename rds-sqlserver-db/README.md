# rds-sqlserver-db

Provisions a database, a server login and a database user on an existing
[`rds-sqlserver`](../rds-sqlserver-server/README.md) instance, and grants
applications access to it through the `connect` link.

The developer configures nothing at create time: the database and user names
are derived from the application ID, and the server is discovered
automatically.

## Server discovery

`scripts/aws/build_db_setup_context` lists active dependency services at the
service's NRN and keeps those whose `master_secret_arn` starts with
`nullplatform/rds-sqlserver/`, matching the service's own dimensions. That
prefix is what a `rds-sqlserver-server` writes and a `rds-postgres-server` does
not, so it distinguishes the engines without any attribute that could drift.

Zero matches and more than one match are both errors — the second lists the
candidates rather than picking one. Set `server_specification_id` in
`values.yaml` to narrow the search when an account runs several SQL Server
instances at the same NRN.

## How provisioning works

Terraform (`db_setup/`) generates the application password and mirrors the
credentials into Secrets Manager. Everything inside the engine is idempotent
T-SQL under [`sql/`](sql), run with `sqlcmd`:

| Step | Runs against | Script |
|---|---|---|
| database + login | `master` | `create_database_and_login.sql` |
| database user | the application database | `create_user.sql` |
| role membership | the application database | `set_role_members.sql` |
| user cleanup | the application database | `drop_user.sql` |
| login cleanup | `master` | `drop_login.sql` |

Because the SQL is idempotent, re-creating a service whose database already
exists needs no state import — the engine itself is the state.

## Access levels

`set_role_members.sql` applies the managed role set **declaratively**: it adds
the roles the level requires and removes the ones it does not. That is what
makes downgrading a link from `read-write` to `read` actually drop the extra
roles, and it is why `revoke_access` is the same script with every flag at 0.

| `access_level` | `db_datareader` | `db_datawriter` | `db_ddladmin` |
|---|---|---|---|
| `read` | yes | — | — |
| `write` | — | yes | — |
| `read-write` | yes | yes | yes |

`db_ddladmin` is included in `read-write` so applications can run their own
schema migrations.

## What survives a delete

Service delete removes the login, the database user and the Secrets Manager
secret. **The database itself is left in place** so application data is never
destroyed by a service lifecycle action. RDS would require
`rdsadmin.dbo.rds_drop_database` to remove it anyway.

Unlink removes role memberships only; the database, login and user all
survive, so access can be re-granted later.

## Terraform state

State lives in the bucket named by `RDS_SQL_SERVER_S3_STATE_BUCKET`, under
`services/<service-id>/`. The variable is required and the bucket must already
exist. See the repository README for the full picture, and pass the same name
as `state_bucket_name` to `specs/requirements/aws`.

## SQL safety

- `DB_NAME` and `DB_USERNAME` are validated against
  `^[A-Za-z][A-Za-z0-9_]{0,63}$` in shell before they reach the engine, and
  wrapped in `QUOTENAME()` inside the T-SQL.
- The master password travels in `SQLCMDPASSWORD`, never in argv, so it does
  not appear in the process list.
- The application password is interpolated with `QUOTENAME(@pwd, '''')`, which
  escapes embedded quotes.
- Every invocation passes `-b`, without which a failed T-SQL script returns 0
  and the workflow step passes.

## Configuration

`values.yaml` holds the region, an optional local AWS profile, an optional
`server_specification_id`, and `sqlcmd_connect_flags`. The last one exists
because go-sqlcmd has changed how `--encrypt-connection` is spelled between
releases; keeping the flags in one place makes that a configuration fix rather
than a code change.

## Setup

IAM in [`specs/requirements/aws`](specs/requirements/aws), platform
registration in [`specs/install/aws`](specs/install/aws). See
[`specs/install/README.md`](specs/install/README.md).
