# Ecto.Adapters.Oracle

An [Ecto](https://github.com/elixir-ecto/ecto) adapter for Oracle Database,
built on the [`inexora`](https://github.com/sparkworx/inexora) driver.

This package was extracted from the `inexora` repository, where the adapter was
originally developed under `lib/ecto/`. History was preserved with
`git filter-repo`; the extraction point was `inexora` commit
`<SOURCE_COMMIT>` (fill in the develop HEAD used for the split).

The split follows the `DBConnection` seam so the driver stays usable without
Ecto and the two packages version independently. Rationale:
[ADR-0002](https://github.com/sparkworx/inexora/blob/develop/docs/adr/0002-split-ecto-adapter-into-ecto-oracle.md)
and the [adapter-split plan](https://github.com/sparkworx/inexora/blob/develop/docs/adapter-split-plan.md).

## Installation

```elixir
def deps do
  [
    {:ecto_oracle, "~> 0.2.0"}
  ]
end
```

`ecto_oracle` pulls in `inexora` (the native driver, which builds an ODPI-C NIF)
and `ecto_sql`. See the driver's README for Oracle Client library requirements.

## Usage

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Oracle
end
```

Configure it like any other Ecto SQL repo:

```elixir
config :my_app, MyApp.Repo,
  username: "inexora",
  password: "Welcome4321",
  database: "localhost:1521/FREEPDB1"
```

## Versioning

Pre-1.0 this adapter tracks the driver's minor version in tight lockstep
(`{:inexora, "~> 0.2.0"}`). Once `inexora` declares its public interface stable
at 1.0, this relaxes to `{:inexora, "~> 1.0"}` and the two version freely.

## Testing

Integration tests need a live Oracle database:

```bash
docker compose up -d
ORACLE_DATABASE_AVAILABLE=1 mix test --include oracle_database
```

The pure SQL-generation tests run without a database:

```bash
mix test
```

## License

Apache-2.0. See [LICENSE](LICENSE).
