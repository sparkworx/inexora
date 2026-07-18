# Changelog

All notable changes to `inexora` are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the driver is pre-1.0, its public interface is not yet declared stable;
any change to it bumps the **minor** version (see the versioning contract in
[docs/adapter-split-plan.md](docs/adapter-split-plan.md)).

## [0.3.0] - unreleased

Completes the adapter split: the bundled Ecto adapter is removed from `inexora`
and now ships as the separate [`ecto_oracle`](https://github.com/sparkworx/ecto_oracle)
package. `inexora` is now a pure Oracle **driver**.

### Removed

- **Breaking:** `Ecto.Adapters.Oracle` and `Ecto.Adapters.Oracle.Connection` —
  moved to the `ecto_oracle` package. Ecto users should depend on `ecto_oracle`
  (which depends on this driver). The driver's public interface (`Inexora.Query`,
  `Inexora.Result`, `Inexora.Error`, `Inexora.Connection`) is unchanged.
- Dropped `ecto` and `ecto_sql` dependencies — the driver core never used them.

### Changed

- The per-datatype "Ecto DDL" test blocks moved with the adapter to `ecto_oracle`.

## [0.2.0] - 2026-07-17

Freezes the driver's public interface ahead of splitting the Ecto adapter into
a separate `ecto_oracle` package. This release ships that interface; no runtime
behavior changed. See [ADR-0002](docs/adr/0002-split-ecto-adapter-into-ecto-oracle.md)
and [docs/adapter-split-plan.md](docs/adapter-split-plan.md).

### Added

- `Inexora.Query.new/2` — the sole public constructor for a query, carrying an
  optional `returning` spec. `%Inexora.Query{}` struct fields are now documented
  as private; external callers must build queries through `new/2`.
- `Inexora.Query.returning_type/0` typedoc, documenting the current `{col, :id}`
  returning-type limitation.
- `Inexora.Connection.connect/1` and `disconnect/2` documented as public
  storage-callback entry points (used by Ecto `storage_up`/`storage_down`).
- Frozen-contract documentation on `%Inexora.Result{}` and `%Inexora.Error{}`
  (the adapter reads only `oracle_code` and `message` from errors).

### Changed

- `Inexora.Query.returning_spec/0` type corrected: `columns` is a list of
  `{atom, type}` tuples, not bare atoms — matching the actual `{col, :id}` data
  and the frozen contract.

## [0.1.1]

Baseline release: Oracle driver over ODPI-C (connections, transactions,
statement execution, parameter binding, cursors/streaming, core data types) and
a bundled `Ecto.Adapters.Oracle` adapter (query/DDL generation, `insert_all`,
RETURNING INTO). See the git history for detail.

[0.3.0]: https://github.com/sparkworx/inexora/releases/tag/v0.3.0
[0.2.0]: https://github.com/sparkworx/inexora/releases/tag/v0.2.0
[0.1.1]: https://github.com/sparkworx/inexora/releases/tag/v0.1.1
