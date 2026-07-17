# CLAUDE.md

## Project Overview

**Project Name**: inexora

**Purpose**: An Oracle Database driver and Ecto adapter for Elixir applications.

**Target Users**: Any Elixir developer that uses Oracle Databases with `Ecto`.

**Current Status**: Active development - core driver functionality implemented

---

## Tech Stack

**Primary Language(s)**: Elixir, C

**Framework(s)**: Ecto

**Database**: Oracle (12c+)

**Key Dependencies**:
- ODPI-C: latest - This is the key dependency for which we will build our NIF implementation upon (git submodule)
- db_connection: latest - Database connection behaviour for database transactions and connection pooling
- decimal: latest - package for arbitrary precision decimal arithmetic for database `NUMBER` types
- elixir_make: latest - Elixir-managed build of NIF targets in project `Makefile`

**Development Tools**:
- Package Manager: hex
- Build Tool: mix, make
- Testing: mix test

---

## Project Structure

```
/
├── mix.exs
├── Makefile
├── lib/
│   ├── inexora.ex
│   └── inexora/
│       ├── connection.ex    # DBConnection implementation
│       ├── error.ex         # Error handling
│       ├── nif.ex           # Elixir NIF bindings
│       ├── query.ex         # Query struct
│       ├── result.ex        # Result struct
│       └── type.ex          # Type conversions
├── c_src/
│   ├── inexora_nif.c        # NIF implementation
│   └── odpi/                # ODPI-C submodule
├── priv/                    # Compiled NIF (.so)
└── test/
    ├── inexora/
    └── support/
        └── sql/             # Oracle test setup scripts
```

**Key Files/Directories**:
- `/c_src/inexora_nif.c`: C NIF implementation wrapping ODPI-C functions
- `/c_src/odpi/`: Git submodule of ODPI-C (https://github.com/oracle/odpi)
- `/lib/inexora/connection.ex`: DBConnection behaviour implementation
- `/lib/inexora/nif.ex`: Elixir function stubs that call into the NIF
- `/test/support/sql/`: Oracle SQL scripts for test schema setup (adapted from ODPI-C)

---

## Architecture & Design

**Architecture Pattern**: Driver

**Key Design Decisions**:
1. Use Erlang NIFs: ODPI-C is our key link to the Oracle Database driver ecosystem, and we do not want to reinvent the wheel. Also, while it might be useful to learn, a native implementation of the Oracle TNS wire protocol would likely be very hard to maintain. Using ODPI-C keeps our driver in line with what Oracle is supporting. We want to track it closely and not duplicate any work that their library can handle for us.
2. Duplicate the ODPI-C test cases in Elixir where possible: In order to test that a) we have covered the library's methods, and b) that we know what remains to be implemented, we can proceed in lock step with ODPI-C, and distinguish which bugs are ours versus which are theirs.
3. Implement data type support incrementally: We want to establish correctness before feature completeness.

**Sources of Inspiration**:
- Postgrex (https://github.com/elixir-ecto/postgrex) - the "definitive" database driver for Elixir. I don't know what else to say other than it is quite revered in the Elixir community for its robustness and reliability, plus demonstrating the use of Ecto Adapter Plugins for extending supported data types in the database.
- Exqlite (https://github.com/elixir-sqlite/exqlite) - an Elixir database driver and Ecto adapter for SQLite3. It is implemented using Erlang NIFs to communicate with the underlying `libsqlite` library. I feel this is an admirable pattern to replicate (C NIFs) while leveraging ODPI-C's strengths.

---

## Development Guidelines

### Coding Standards

**Style Guide**:
- Elixir community standard
- (optional) Git pre-commit hook to run `mix format` over staged files; any deviation would be an error

**Naming Conventions**:
- Variables: Elixir standard
- Functions: Elixir standard
- Classes/Modules/Structs: Elixir standard
- Files: Elixir standard

**Code Organization Preferences**:
- Separate modules based on areas of concern (e.g. Elixir NIF stubs, Ecto Adapter, Ecto Datatype adpater)
- Follow community standards

### Testing Approach

**Testing Strategy**: Elixir standard practices:
1. Unit tests for low-level "data shuffling" code and handling of Erlang Resources (which might contain C lang opaque pointers).
2. Integration tests to be run periodically against a live Oracle Database instance, which will be provided "just in time" by way of a Docker Compose configuration.
3. Unit & Integration tests should mirror wherever possible the kinds of tests that ODPI-C performs, ensuring correctness and feature parity. This will be a work in progress as we complete

**Test Location**: Elixir standard practices for tests (/test)

**Coverage Goals**: Critical paths must be tested

### Error Handling

**Error Strategy**:
1. Errors that originate in the NIF/C layer need to be gracefully surfaced to the Elixir/Erlang/OTP layer for applications to handle. This should conform to the `db_connection` Elixir behaviour. These are not database errors, they are runtime/platform errors.
2. SQL runtime errors should be treated the same for any database: we pass an informative error to the Ecto Adapter, which then passes it on to the application.

**Logging**:
- Elixir standard logging
- Elixir/Erlang/OTP standard Telemetry highly encouraged

---

## Current Implementation Status

**Completed**:
- [core] NIF infrastructure with ODPI-C integration
- [core] Context creation/destruction and client version retrieval
- [core] Database connections (create, close, ping, health check) with Oracle Wallet support (optional username/password)
- [core] Transaction support (begin, commit, rollback)
- [core] SQL statement preparation and execution
- [core] Result set fetching with column metadata
- [core] Parameter binding with positional placeholders (:1, :2, etc.)
- [core] Named parameter binding (:name style) with map params
- [core] Batch/array binding via Variable API (`conn_new_var`, `stmt_execute_many`)
- [core] RETURNING INTO support via `var_get_returned_data`
- [datatype] VARCHAR2/CHAR → binary (String)
- [datatype] NUMBER → Decimal (with full precision)
- [datatype] DATE → Date
- [datatype] TIMESTAMP/TIMESTAMP_TZ/TIMESTAMP_LTZ → NaiveDateTime
- [datatype] CLOB → binary (String)
- [datatype] BLOB → binary (raw)
- [datatype] RAW/LONG RAW → binary (using `{:raw, binary}` wrapper for binding)
- [datatype] BINARY_FLOAT/BINARY_DOUBLE → float
- [datatype] INTERVAL DAY TO SECOND → `{:interval_ds, days, hours, minutes, seconds, fseconds}`
- [datatype] INTERVAL YEAR TO MONTH → `{:interval_ym, years, months}`
- [datatype] ROWID/UROWID → binary (String) - use `CHARTOROWID(:1)` for binding
- [datatype] NULL handling
- [ecto] Ecto adapter (`Ecto.Adapters.Oracle`)
- [ecto] SQL query generation (SELECT, INSERT, UPDATE, DELETE)
- [ecto] DDL generation (CREATE TABLE, DROP TABLE, ALTER TABLE, indexes, constraints)
- [ecto] Integration tests with Ecto Repo
- [ecto] Bulk insert via `insert_all` using Oracle's `INSERT ALL` syntax
- [ecto] High-level batch operations via `Inexora.Batch` module
- [core] Cursor/streaming support for large result sets (`Inexora.Cursor`, DBConnection cursor callbacks)
- [core] Cursor NIF functions (`stmt_fetch_rows`, `stmt_set_fetch_array_size`, `stmt_set_prefetch_rows`)
- [core] Auto-incrementing ID columns (Oracle IDENTITY) for test tables
- [ecto] RETURNING INTO support for Ecto autogenerate (single-row inserts)

**In Progress**:
- None

**TODO/Upcoming**:
- [datatype] Native BOOLEAN type (Oracle 23c+) - requires newer Oracle client driver
- [datatype] JSON/JSON_OBJECT/JSON_ARRAY types (Oracle 21c+)
- [ecto] Implement Ecto migrations (runtime testing)
- [ecto] Batch insert_all with RETURNING (requires special adapter handling)
- [ecto] insert_all with nil values (Oracle UNION ALL requires type consistency)

---

## How to Work with This Project

### Setup Instructions
```bash
1. Clone the repo
2. Initialize submodules: `git submodule update --init --recursive`
3. Install dependencies: `mix deps.get`
4. Set up environment: `mix setup && mix deps.compile`
5. For testing, spin up an Oracle database: `docker compose up`
6. Run tests: `mix test`
```

### Environment Variables

For running integration tests against Oracle:
- `ORACLE_USER` - Database username (default: `inexora`)
- `ORACLE_PASSWORD` - Database password (default: `Welcome4321`)
- `ORACLE_DATABASE` - Connection string (default: `localhost:1521/FREEPDB1`)

Tests tagged `:oracle_database` are excluded by default. To run them:
```bash
# Set env vars and remove exclusion, or use:
ORACLE_DATABASE_AVAILABLE=1 mix test
```

The test harness (`test/test_helper.exs`) pins `NLS_LANG` to `AMERICAN_AMERICA.AL32UTF8`
before the first ODPI-C context is created, so Oracle error messages come back in US English
and assertions on message text stay stable regardless of the developer/CI locale. A meaningful
explicit `NLS_LANG` is respected (unset or blank falls through to the default).

---

## Constraints & Preferences

**Performance Considerations**:
- TBD

**Security Requirements**:
- TBD

**Do's**:
- TBD

**Don'ts**:
- TBD

---

## Additional Context

**Related Documentation**:
- [ODPI-C API](https://oracle.github.io/odpi/)
- [DBConnection behaviour](https://hexdocs.pm/db_connection/)

---

## Bash Execution Rules

When running multi-line scripts or code snippets:
- NEVER use heredoc piping (e.g., `cat <<EOF | mix run`)
- Write scripts to `tmp/` in the project root with descriptive names (e.g., `tmp/test_boolean_encoding.exs`)
- Execute the file directly (e.g., `mix run tmp/test_boolean_encoding.exs`)
- Do NOT auto-delete tmp files — leave them for debugging
- Always use `--no-recurse-submodules` when doing `git push` to origin

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (github.com/sparkworx/inexora), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
