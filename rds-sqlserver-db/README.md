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
T-SQL under [`sql/`](sql), run with `sqlcmd`. When the agent has no `sqlcmd`
on its `PATH`, the scripts install the pinned go-sqlcmd release with `mise`.
The Secrets Manager secret is named
`nullplatform/rds-sqlserver/<service slug>-<service id>/app`.

| Step | Runs against | Script |
|---|---|---|
| database + login | `master` | `create_database_and_login.sql` |
| database user | the application database | `create_user.sql` |
| migrations login + user | `master`, then the application database | `create_database_and_login.sql`, `create_user.sql` |
| migrations user as `db_owner` | the application database | `add_db_owner.sql` |
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

## Migrations

The `run-migrations` action runs the `.sql` scripts of a GitHub repository with
Liquibase, as a dedicated **migrations user** (`<app user>_mig`) that is
`db_owner` of this database and has no server-level role. Its credentials live
in `nullplatform/rds-sqlserver/<service slug>-<service id>/migrator`. Services
created before this action get the user on their next `update`; until then the
action asks for one.

The repository follows the `<sigla>-databases` layout:

```
<environment>/<database>/NN_description.sql   pending
<environment>/<database>/history/             already ran
```

| Parameter | Meaning |
|---|---|
| `repository_url` | `https://github.com/<org>/<repo>` |
| `ref` | tag or branch to read the scripts from |
| `environment_directory` | e.g. `dev`, `qas`, `prd` |
| `database_directory` | defaults to the database name |
| `mode` | `preview` validates and prints the SQL; `apply` runs it |
| `history_branch` | branch that receives `history/`; defaults to the repository's default branch |

`apply` runs the pending scripts in name order, then moves them to
`history/<name>_<ref>_<timestamp>.sql` on `history_branch` in a single commit.
Each script is one changeset, split into batches on `GO` lines only. The
changeset id is `<script>_<ref>`, or `<script>_<timestamp>` with `runOnChange`
in `dev`, so re-running a tag skips what it already applied. The move to
`history/` is what keeps a script from running again under a new tag: if it
fails, the action lists the scripts to move by hand.

`GRANT CONNECT` is rejected in every environment; `DROP`, `TRUNCATE` and
`SELECT *` everywhere except `dev`. This is a guardrail against mistakes, not a
security boundary: dynamic SQL gets past it, and `db_owner` can do all of it.

`apply` checks that the App can write to the repository before it touches the
database. Liquibase runs with an empty environment, so `${...}` in a script
cannot expand the agent's credentials. Repositories with symbolic links are
rejected. The generated SQL is printed in the action log but never stored in
its results.

A run killed mid-update leaves `DATABASECHANGELOGLOCK` held, and the next run
waits for it. Clear it with `liquibase release-locks` as the migrations user.

The repository is read and written with the agent's GitHub App
(`NP_GITHUB_APPS`), which needs **Contents: Read and write** on it. Java 21,
Liquibase, the `mssql-jdbc` driver and `step` (to sign the App's JWT) are
installed at pinned versions with `mise` on first use.

## What survives a delete

Service delete removes the login, the database user and the Secrets Manager
secret. **The database itself is left in place** so application data is never
destroyed by a service lifecycle action. RDS would require
`rdsadmin.dbo.rds_drop_database` to remove it anyway.

A delete on a service whose create failed before writing its attributes still
cleans up: the connection is recovered from the `db_setup` tofu state. Only a
service with no state is treated as never created.

Unlink removes role memberships only; the database, login and user all
survive, so access can be re-granted later.

## Terraform state

State lives in the bucket named by `RDS_SQL_SERVER_S3_STATE_BUCKET`, under
`services/rds-sqlserver/<service-id>/`. The variable is required and the bucket must already
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

The region comes from the `cloud-providers` provider of the service's NRN and
dimensions, like the server's. `values.yaml` holds an optional local AWS
profile, an optional `server_specification_id`, and `sqlcmd_connect_flags`. The last one exists
because go-sqlcmd has changed how `--encrypt-connection` is spelled between
releases; keeping the flags in one place makes that a configuration fix rather
than a code change.

## Setup

IAM in [`specs/requirements/aws`](specs/requirements/aws), platform
registration in [`specs/install/aws`](specs/install/aws). See
[`specs/install/README.md`](specs/install/README.md).
