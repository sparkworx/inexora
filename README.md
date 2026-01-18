# Inexora

An Oracle Database driver and Ecto adapter for Elixir, built on [ODPI-C](https://oracle.github.io/odpi/).

> **Warning**
> This project is under active development and has not been extensively tested in real-world applications. It likely contains bugs and missing features. Do not use this in production if your livelihood depends on it. Contributions and bug reports are welcome!

## Features

- Native Oracle connectivity via ODPI-C (Oracle Database Programming Interface for C)
- Full Ecto 3.x adapter support
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

Configure your repository in `config/config.exs`:

```elixir
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Oracle,
  username: "scott",
  password: "tiger",
  database: "localhost:1521/FREEPDB1",
  pool_size: 10
```

Or using hostname/port/service_name:

```elixir
config :my_app, MyApp.Repo,
  adapter: Ecto.Adapters.Oracle,
  username: "scott",
  password: "tiger",
  hostname: "localhost",
  port: 1521,
  service_name: "FREEPDB1",
  pool_size: 10
```

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
  %Inexora.Query{sql: "SELECT * FROM employees WHERE department_id = :1"},
  [10]
)

IO.inspect(result.rows)
```

### With Ecto

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Oracle
end

defmodule MyApp.Employee do
  use Ecto.Schema

  # Auto-generated IDs work with Oracle IDENTITY columns
  @primary_key {:id, :id, autogenerate: true}
  schema "employees" do
    field :name, :string
    field :salary, :decimal
    field :hire_date, :date
  end
end

# Query
employees = MyApp.Repo.all(
  from e in MyApp.Employee,
  where: e.salary > 50000
)

# Insert - ID is auto-generated and returned via RETURNING INTO
{:ok, employee} = MyApp.Repo.insert(%MyApp.Employee{
  name: "John Doe",
  salary: Decimal.new("75000.00"),
  hire_date: ~D[2024-01-15]
})

# employee.id is now populated with the auto-generated value
IO.puts("Created employee with ID: #{employee.id}")
```

### Bulk Inserts

```elixir
# insert_all works with IDENTITY columns
entries = [
  %{name: "Alice", salary: Decimal.new("60000"), hire_date: ~D[2024-01-01]},
  %{name: "Bob", salary: Decimal.new("65000"), hire_date: ~D[2024-02-01]},
  %{name: "Charlie", salary: Decimal.new("70000"), hire_date: ~D[2024-03-01]}
]

{3, nil} = MyApp.Repo.insert_all(MyApp.Employee, entries)
```

### Streaming Large Result Sets

```elixir
alias Inexora.Cursor

{:ok, state} = Inexora.Connection.connect(opts)

# Stream results in batches of 100 rows
Cursor.stream(state.conn, "SELECT * FROM large_table", [], max_rows: 100)
|> Stream.each(fn row -> process(row) end)
|> Stream.run()
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
