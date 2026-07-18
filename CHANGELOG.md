# Changelog

All notable changes to `inexora` are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

While the driver is pre-1.0, its public interface is not yet declared stable;
any change to it bumps the **minor** version (see the versioning contract in
[docs/adapter-split-plan.md](docs/adapter-split-plan.md)).

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

[0.2.0]: https://github.com/sparkworx/inexora/releases/tag/v0.2.0
[0.1.1]: https://github.com/sparkworx/inexora/releases/tag/v0.1.1
