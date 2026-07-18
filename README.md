# Inexora

An Oracle Database driver for Elixir, built on [ODPI-C](https://oracle.github.io/odpi/).

> **Using Ecto?** The Ecto adapter (`Ecto.Adapters.Oracle`) now lives in the
> companion [`ecto_oracle`](https://github.com/sparkworx/ecto_oracle) package,
> which depends on this driver. Add `ecto_oracle` to use Oracle with Ecto.

> **Warning**
> This project is under active development and has not been extensively tested in real-world applications. It likely contains bugs and missing features. Do not use this in production if your livelihood depends on it. Contributions and bug reports are welcome!

## Features

- Native Oracle connectivity via ODPI-C (Oracle Database Programming Interface for C)
- Ecto 3.x support via the companion [`ecto_oracle`](https://github.com/sparkworx/ecto_oracle) package
- Connection pooling via `db_connection`
- Transaction support (begin, commit, rollback)
- Prepared statements with parameter binding
- Cursor/streaming support for large result sets
- Batch insert operations with proper IDENTITY column support
- **RETURNING INTO** support for auto-generated primary keys (Ecto `autogenerate: true`)

### Supported Data Types

| Oracle Type | Elixir Type |
|-------------|-------------|
| VARCHAR2/CHAR | `String.t()` |
| NUMBER | `Decimal.t()` |
| DATE | `Date.t()` |
| TIMESTAMP/TIMESTAMP_TZ/TIMESTAMP_LTZ | `NaiveDateTime.t()` |
| CLOB/NCLOB | `String.t()` |
| BLOB | `binary()` |
| RAW/LONG RAW | `{:raw, binary()}` |
| BINARY_FLOAT/BINARY_DOUBLE | `float()` |
| INTERVAL DAY TO SECOND | `{:interval_ds, days, hours, minutes, seconds, fseconds}` |
| INTERVAL YEAR TO MONTH | `{:interval_ym, years, months}` |
| ROWID/UROWID | `String.t()` |
| NULL | `nil` |

## Requirements

- Elixir 1.14+
- Erlang/OTP 25+
- Oracle Instant Client 19c+ (or Oracle Database Client)

## Installation

Add `inexora` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:inexora, "~> 0.1.0"}
  ]
end
```

Fetch dependencies and compile:

```bash
mix deps.get
mix compile
```

## Configuration

### Direct Connection

```elixir
{:ok, conn} = DBConnection.start_link(Inexora.Connection,
  username: "scott",
  password: "tiger",
  database: "localhost:1521/FREEPDB1"
)
```

### With Ecto

Ecto support has moved to the companion
[`ecto_oracle`](https://github.com/sparkworx/ecto_oracle) package (adapter
`Ecto.Adapters.Oracle`), which depends on this driver. See its README for repo
configuration and usage.

## Usage

### Raw Queries

```elixir
{:ok, conn} = DBConnection.start_link(Inexora.Connection,
  username: "scott",
  password: "tiger",
  database: "localhost:1521/FREEPDB1"
)

# Simple query
{:ok, _query, result} = DBConnection.execute(conn,
  Inexora.Query.new("SELECT * FROM employees WHERE department_id = :1"),
  [10]
)

IO.inspect(result.rows)
```

For Ecto repos, schemas, and `insert_all`, see the
[`ecto_oracle`](https://github.com/sparkworx/ecto_oracle) package.

### Streaming Large Result Sets

```elixir
alias Inexora.Cursor

{:ok, state} = Inexora.Connection.connect(opts)

# Stream results in batches of 100 rows
Cursor.stream(state.conn, "SELECT * FROM large_table", [], max_rows: 100)
|> Stream.each(fn row -> process(row) end)
|> Stream.run()
```

## Development Setup

To contribute or build from source:

```bash
# Clone the repository
git clone https://github.com/your-org/inexora.git
cd inexora

# Initialize the ODPI-C submodule
git submodule update --init --recursive

# Install dependencies and compile
mix deps.get
mix compile
```

## Testing

The test suite includes both unit tests and integration tests against a live Oracle database.

### Running Unit Tests

```bash
mix test
```

### Running Integration Tests

Start an Oracle database using Docker Compose:

```bash
# Start Oracle database (first startup takes a few minutes)
docker compose up -d

# Watch logs until "DATABASE IS READY TO USE!" appears
docker compose logs -f
```

The included `docker-compose.yaml` uses the official Oracle Free image, which requires a one-time login:

```bash
docker login container-registry.oracle.com
```

If you prefer not to create an Oracle account, edit `docker-compose.yaml` to use the commented `gvenzl/oracle-free:23-slim` image instead (no login required, faster startup).

The compose file automatically creates the test user and persists data in a Docker volume.

Run tests with Oracle connection:

```bash
ORACLE_DATABASE_AVAILABLE=1 mix test --include oracle_database
```

Stop the database:

```bash
docker compose down      # Keep data volume
docker compose down -v   # Remove data volume
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ORACLE_USER` | `inexora` | Database username |
| `ORACLE_PASSWORD` | `Welcome4321` | Database password |
| `ORACLE_DATABASE` | `localhost:1521/FREEPDB1` | Connection string |

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [ODPI-C](https://github.com/oracle/odpi) - Oracle Database Programming Interface for C
- [Postgrex](https://github.com/elixir-ecto/postgrex) - Inspiration for driver architecture
- [Exqlite](https://github.com/elixir-sqlite/exqlite) - Inspiration for NIF implementation patterns
