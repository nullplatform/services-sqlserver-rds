# services-sqlserver-rds

nullplatform service definitions for AWS RDS SQL Server:

- [`rds-sqlserver-server/`](rds-sqlserver-server/README.md) — provisions the
  RDS SQL Server instance itself.
- [`rds-sqlserver-db/`](rds-sqlserver-db/README.md) — provisions a database,
  login and application user on an existing `rds-sqlserver` instance, and
  grants access to applications through the `connect` link.

Each service directory is self-contained: `entrypoint/`, `workflows/`,
`scripts/`, `sql/` and `specs/` are read directly by the nullplatform agent at
runtime. `specs/requirements/aws/` and `specs/install/aws/` contain one-time
setup Terraform, applied out-of-band by an account operator — see each
service's own README and `specs/install/README.md`.

## Why a repository per engine

PostgreSQL lives in `services-postgresql-rds`, SQL Server here, and Oracle will
live in `services-oracle-rds`. The engines differ enough that a shared layer
would cost more than the duplication, and one repository and slug per engine
makes "which engines do we support" a matter of reading names rather than
inspecting the attributes of existing services.

The price, accepted deliberately: `assume_role`, `assume_role_lib`,
`assume_role_step`, `do_tofu` and `delete_tfstate_objects` are duplicated across
the engine repositories.

## How this differs from the PostgreSQL services

**Terraform owns AWS, T-SQL owns the engine.** There is no OpenTofu provider
for SQL Server maintained anywhere near the level of `cyrilgdn/postgresql`, so
Terraform provisions the instance, the security group, the KMS key and the
Secrets Manager secrets, while databases, logins, users and role memberships
are created by idempotent T-SQL under [`sql/`](rds-sqlserver-db/sql), driven by
`sqlcmd`.

Two consequences worth knowing before reading the code:

- **There is no per-link tfstate.** `link` and `unlink` run
  `sql/set_role_members.sql` rather than `tofu apply`/`tofu destroy`. The
  script applies the full managed role set declaratively, so downgrading a link
  from `read-write` to `read` really does remove the extra roles.
- **The server exposes no link.** In the PostgreSQL repository the server also
  offers a `connect` link that creates a database and user per link, which
  duplicates what the `db` service does. Applications connect through
  `rds-sqlserver-db` only.

**SQL Server separates logins from users.** A login is a server-level principal
and a user is a database-level one, so the "application user" is two objects
with different lifecycles. That is why provisioning makes two `sqlcmd` calls:
one against `master` for the database and login, one against the application
database for the user.

**Access levels map to fixed database roles**, which cover existing *and*
future objects natively:

| `access_level` | Roles granted |
|---|---|
| `read` | `db_datareader` |
| `write` | `db_datawriter` |
| `read-write` | both, plus `db_ddladmin` so applications can run migrations |

## Engine isolation

An `rds-sqlserver-db` service discovers its server by the prefix of the master
credentials secret: this repository writes
`nullplatform/rds-sqlserver/<name>/master`, while `services-postgresql-rds`
writes `nullplatform/rds/<name>/master`. The prefix is intrinsic to the server
that produced it, so unlike an attribute it cannot drift out of sync.

The same prefix scopes the IAM policy, so the role for one engine cannot read
the other engine's credentials.

Discovery can be narrowed further with `server_specification_id` in
`rds-sqlserver-db/values.yaml`.

## Terraform state

Set `RDS_SQL_SERVER_S3_STATE_BUCKET` on the agent to the name of an existing S3
bucket. Every instance of both services keeps its state there under
`services/<service-id>/`, so one bucket covers the whole repository and the
service id keeps the keys apart.

The variable is **required** — without it every action fails before touching
AWS, so there is no fallback path to keep working. The bucket must already
exist; the service never creates one and assumes nothing about its name. Pass
the same name as `state_bucket_name` to each `specs/requirements/aws` module,
which grants the role access to that bucket and to nothing else.

Deleting a service empties only its own prefix and never removes the bucket.

An earlier draft of these services created one bucket per instance
(`np-service-<service-id>`). That is gone: a bucket per instance is unbounded
sprawl against a hard account limit, needs an `s3:CreateBucket` grant the agent
should not have, and leaves nowhere to apply a single lifecycle or encryption
policy.

## Tests

```bash
bats tests/ --recursive
```

The suite mocks `sqlcmd`, `aws`, `np` and `tofu`. The `sqlcmd` mock checks that
the `-i` file exists and that every `-v` argument is well formed, because a
mock that only logs would pass while the real binary fails.

## Known limitation

Several links to the same service share a single database user, so the last
`access_level` applied wins. This is inherited from the PostgreSQL services and
is not addressed here.
