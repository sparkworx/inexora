# Changelog

All notable changes to `ecto_oracle` are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Pre-1.0, this adapter tracks the `inexora` driver's minor version in tight
lockstep (see the versioning contract in
[ADR-0002](https://github.com/sparkworx/inexora/blob/develop/docs/adr/0002-split-ecto-adapter-into-ecto-oracle.md)).

## [0.2.0] - unreleased

Initial release as a standalone package, extracted from `inexora` (where the
adapter lived under `lib/ecto/`). No functional change from the adapter as it
shipped bundled in `inexora` 0.2.0; this release only makes it a separate,
independently versioned package depending on the driver across the
`DBConnection` seam.

### Added

- `Ecto.Adapters.Oracle` and `Ecto.Adapters.Oracle.Connection`, depending on
  `{:inexora, "~> 0.2.0"}` and `{:ecto_sql, "~> 3.12"}`.
- Live-Oracle integration test harness (docker-compose + `docker/init` seed +
  `ORACLE_DATABASE_AVAILABLE` gate), duplicated from the driver.

[0.2.0]: https://github.com/sparkworx/ecto_oracle/releases/tag/v0.2.0
