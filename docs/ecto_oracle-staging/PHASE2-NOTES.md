# Phase 2 — stand up the `ecto_oracle` package

These files are the Phase 2 additions (plan steps 8–9). Drop them into the repo
produced by the Phase 1 `git filter-repo` extraction, apply the three test
fixups below, then build and verify.

## Files to add (this directory)

```
mix.exs                          # package ecto_oracle, adapter Ecto.Adapters.Oracle
.formatter.exs
.gitignore
README.md                        # fill in <SOURCE_COMMIT> with the extraction HEAD
CHANGELOG.md
LICENSE                          # COPY VERBATIM from inexora (Apache-2.0) — not reproduced here
docker-compose.yaml              # container_name: ecto-oracle-test
docker/init/01_create_user.sql   # seeds the INEXORA test schema owner
test/test_helper.exs             # NLS_LANG pin + client warm-load + :oracle_database gate
test/support/test_helpers.ex     # EctoOracle.TestHelpers.test_connection_opts/0
```

Already present from the filter-repo extraction (do not recreate):

```
lib/ecto/adapters/oracle.ex
lib/ecto/adapters/oracle/connection.ex
test/ecto/adapters/oracle_test.exs              # no edits needed (pure SQL-gen, async)
test/ecto/adapters/oracle_integration_test.exs  # 3 edits — see below
```

Relocated from the driver during Phase 3 (this staging dir also carries it):

```
test/ecto/adapters/oracle_ddl_types_test.exs    # the 4 per-datatype "Ecto DDL"
                                                 # blocks (float/interval/raw/rowid)
                                                 # moved out of inexora's driver tests
```

## Required fixups to the extracted integration test

`test/ecto/adapters/oracle_integration_test.exs` — the only extracted file that
references the old app. Three edits:

| Line | From | To |
|------|------|----|
| 4  | `import Inexora.TestHelpers` | `import EctoOracle.TestHelpers` |
| 11 | `otp_app: :inexora,` | `otp_app: :ecto_oracle,` |
| 32 | `Application.put_env(:inexora, TestRepo, opts)` | `Application.put_env(:ecto_oracle, TestRepo, opts)` |

`oracle_test.exs` needs no changes (it only touches `Ecto.*` / the adapter).

## Notes / decisions baked in

- **Pure-Elixir package.** No `elixir_make`, Makefile, `c_src/`, or `priv/` — the
  native ODPI-C NIF lives in the `inexora` dependency. `mix.exs` has no
  `compilers`/`make_targets`.
- **Deps:** `{:inexora, "~> 0.2.0"}` (tight lockstep), `{:ecto, "~> 3.12"}`,
  `{:ecto_sql, "~> 3.12"}`, `ex_doc` (dev). `db_connection` and `decimal` arrive
  transitively.
- **Test helper slimmed.** Only `test_connection_opts/0` is carried (the sole
  helper the integration test uses); the driver's `connect_test_db*`/`cleanup_nif`
  helpers stay in `inexora`. Renamed `Inexora.TestHelpers` → `EctoOracle.TestHelpers`.
- **`test/support` compiled via `elixirc_paths(:test)`**, so no `Code.require_file`
  in `test_helper.exs` (unlike the driver's harness).
- **Harness not carried by filter-repo.** docker-compose, docker/init, and the
  helpers are duplicated here fresh (plan step 9) — filter-repo only moved the
  4 adapter code/test files, preserving their blame.
- **`test/support/sql/`** (DropTest/SetupTest/TestEnv) is NOT copied — those are
  driver-specific ODPI-C scripts; the integration test creates its own GTT inline.
- **No `config/` dir** — `TestRepo` config is injected at runtime in `setup_all`
  via `Application.put_env/3`.

## Lockstep with the driver's 0.3.0 (Phase 3)

`ecto_oracle` 0.2.0 pins `{:inexora, "~> 0.2.0"}` — correct at creation, when
`inexora` 0.2.0 still bundles the adapter. When `inexora` 0.3.0 lands (Phase 3
removes the bundled adapter), `~> 0.2.0` **excludes** 0.3.0, so `ecto_oracle`
must ship a matching **0.3.0** that re-pins `{:inexora, "~> 0.3.0"}`. Bump both
the mix.exs pin and version, and add a CHANGELOG entry, at that point.

## Build & verify

```bash
mix deps.get
mix compile
mix test                                              # pure SQL-gen tests, no DB
docker compose up -d
ORACLE_DATABASE_AVAILABLE=1 mix test --include oracle_database   # full suite
mix format --check-formatted
mix hex.build --unpack        # inspect package contents before publishing
```
