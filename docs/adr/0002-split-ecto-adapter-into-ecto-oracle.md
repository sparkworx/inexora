# Split the Ecto adapter into a separate `ecto_oracle` package

The Ecto adapter currently bundled under `lib/ecto/` will move to its own GitHub repository, published as the Hex package `ecto_oracle` (module `Ecto.Adapters.Oracle`), depending on the `inexora` driver as a hard dependency across the `DBConnection` seam. This mirrors the ecosystem norm (postgrex, myxql, and the closest analog exqlite→ecto_sqlite3 all split driver from adapter into separate repos/packages) and makes the seam real: `inexora` stays a driver usable without Ecto, and the two version and release independently. The full route and the per-decision detail are recorded on wayfinder map [#5](https://github.com/sparkworx/inexora/issues/5); the executable plan is [docs/adapter-split-plan.md](../adapter-split-plan.md).

## Considered Options

- **One repo, two Hex packages** — keeps driver and adapter in lockstep with shared CI/test harness, but the split would be only nominal: no repo boundary enforces the seam, and it departs from the ecosystem norm.

## Consequences

- The adapter repo duplicates `inexora`'s live-Oracle test harness (docker-compose + `ORACLE_DATABASE_AVAILABLE`); the Postgrex/MyXQL/Tds precedent shows test infra is duplicated per-repo, not shared.
- Pre-1.0, the adapter pins to the driver's minor (tight lockstep); this relaxes to `~> 1.0` once `inexora`'s public interface is declared stable.
- The driver's public interface is now a frozen contract (see the plan): `%Inexora.Query{}` via `Inexora.Query.new/2`, `%Inexora.Result{}`, `%Inexora.Error{}`, `DBConnection` via `Inexora.Connection`, and `connect/1`+`disconnect/2` for storage callbacks. `Nif`, `Batch`, `Cursor`, `Type` internals, and the C layer stay private (ADR-0001 keeps value-type knowledge driver-side).
