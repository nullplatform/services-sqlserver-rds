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

The scripts always come from the `main` branch of the application's own
`<org>/<sigla>-databases` repository. The sigla is the namespace slug up to its
first `-` (namespace `abcd-payments` → `abcd-databases`), and the org is
`migrations_github_org` in `values.yaml`, or the only org the agent has a
GitHub App for. The environment directory is the service's `environment`
dimension. The repository follows this layout:

```
<environment>/<database>/NN_description.sql   pending
<environment>/<database>/history/             already ran
```

| Parameter | Meaning |
|---|---|
| `mode` | `preview` validates and prints the SQL; `apply` runs it |
| `database_directory` | defaults to the database name |

`apply` runs the pending scripts in name order, then moves them to
`history/<name>_<commit>_<timestamp>.sql` on `main` in a single commit. Each
script is one changeset, split into batches on `GO` lines only. The changeset
id is `<script>_<commit>`, or `<script>_<timestamp>` with `runOnChange` in
`dev`, so re-running the same commit skips what it already applied. The move to
`history/` is what keeps a script from running again after a new commit: if it
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

## Install in your organization

The service is published once as the package `np-rds-sqlserver-db` (specification "RDS SQL Server DB"), visible to every organization. You do not copy its specs: you install the package and use it read-only. How installing a package works, how it coexists with a copy you registered, how to upgrade, and when to fork instead are in the [package installation guide](https://docs.nullplatform.com/docs/packages/install); this section has what is specific to this service.

Already registered a copy from the former `specs/install`? It keeps working: it called tofu-modules' `service_definition` on specs that stay in every release, and the package installs next to it, as the guide explains. If you sourced that directory as a module, pin its `?ref` to a release that still has it.

Installing it touches the same three layers as registering a service yourself, and only the nullplatform layer changes:

| Layer | What | Module |
|---|---|---|
| infrastructure (AWS credentials) | The IAM role the service assumes, with access to the state bucket | [`specs/requirements/aws`](specs/requirements/aws) |
| nullplatform (nullplatform API key) | The installation of the package and the agent channel | tofu-modules' `service_package_installation` |
| bindings | The role under selector `rds-sqlserver-db` in your IAM provider | your `aws-iam-configuration` provider |

Pick ONE release of this repository (the latest is on its [releases page](https://github.com/nullplatform/services-sqlserver-rds/releases)) and use its version in both places below: the IAM role is the one the worker of that same release expects. Both services of this repository share the release, so install them at the same version.

```hcl
# ── infrastructure layer ─────────────────────────────────────────────
module "rds_sqlserver_db_requirements" {
  source            = "git::https://github.com/nullplatform/services-sqlserver-rds.git//rds-sqlserver-db/specs/requirements/aws?ref=vX.Y.Z"
  cluster_name      = "<nullplatform agent cluster>"
  state_bucket_name = "<existing S3 bucket for the tofu state>"
}

# The agent role must be allowed to assume it: add it to the assume_role_arns
# of tofu-modules' infrastructure/aws/iam/agent.
#   assume_role_arns = [..., module.rds_sqlserver_db_requirements.permissions_role_arn]

# ── nullplatform layer ───────────────────────────────────────────────
# For a service the installation is the whole nullplatform side, channel included.
module "rds_sqlserver_db" {
  source = "git::https://github.com/nullplatform/tofu-modules.git//nullplatform/service_package_installation?ref=v9.16.0"

  nrn                  = var.nrn
  package_slug         = "np-rds-sqlserver-db"
  package_version      = "X.Y.Z" # the same release, without the v
  agent_tags_selectors = { cluster = "runtime" } # must match the agent's TAGS
}
# Keeping channels in a separate bindings layer instead? Use
# nullplatform/package_installation here and service_definition_agent_association
# there, with package_slug = "np-rds-sqlserver-db".

# ── bindings layer ───────────────────────────────────────────────────
# One aws-iam-configuration per NRN and dimensions, at the account level: add
# the entry to the list your IAM provider already has. Both services of this
# repository go in the SAME provider, one selector each.
#   { selector = "rds-sqlserver-db", arn = module.rds_sqlserver_db_requirements.permissions_role_arn }
```

**The state bucket.** Set `RDS_SQL_SERVER_S3_STATE_BUCKET` on the worker (a per-package env patch in tofu-modules' `nullplatform/agent`) to the name of an existing S3 bucket, and pass the same name to the requirements module as `state_bucket_name`; see "Terraform state" above for the layout. Both services share the bucket. The bucket must already exist: the service never creates or deletes it, and without the variable every action fails before touching AWS.

The service assumes the role it finds under selector `rds-sqlserver-db` in the IAM provider closest to its NRN. To upgrade, move the release in both layers: `ref` of the requirements module and `package_version` of the installation. See tofu-modules' [`service_package_installation`](https://github.com/nullplatform/tofu-modules/tree/main/nullplatform/service_package_installation) for its inputs and outputs. The channel it creates subscribes to `service` and `telemetry` notifications; without `telemetry` the service shows no metrics.

Prerequisites: an agent whose `TAGS` match the channel's `tags_selectors`, with `public.ecr.aws/nullplatform/*` in `worker.allowedRegistries` and `np-rds-sqlserver-db` in its `worker_orchestrated_packages` (the worker then runs with the agent's identity, the one the role trusts); it also needs an active `rds-sqlserver` service with matching dimensions in the same namespace.

## How the package is published

Every release publishes a new revision of the package from this repository, in the same run that pushes the worker image ([`.github/workflows/release.yml`](../.github/workflows/release.yml)): the `publish-package` job applies [`rds-sqlserver-db/publish`](publish), a stack on tofu-modules' `service_package_publish`, which pins this tag's specs and the image by digest. The package version is the release tag, as for the image. The stack keeps its state where the organization secrets `PACKAGE_STATE_AWS_ACCOUNT_ID`, `PACKAGE_TFSTATE_BUCKET` and `PACKAGE_TFSTATE_REGION` point; the state role is `github-actions-<repository>-package-state` in that account, by convention.
