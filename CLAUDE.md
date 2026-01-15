# CLAUDE.md Template

## Project Overview

**Project Name**: inexora

**Purpose**: An Oracle Database driver and Ecto adapter for Elixir applications.

**Target Users**: Any Elixir developer that uses Oracle Databases with `Ecto`.

**Current Status**: Just started

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
Standard Elixir project structure is used:
/
├── mix.exs
├── Makefile
├── lib/
│   ├── inexora.ex
│   └── inexora/
├── c_src/
├── test/
│   └── sql/
└── guides/
```

**Key Files/Directories**:
- `/c_src/`: C-language NIF source, plus Git submodule of ODPI-C (https://github.com/oracle/odpi)
- `/test/sql`: Oracle SQL scripts that the developer must run to create schema and objects for integration testing. It should definitely reflect what's in ODPI-C's own /test/sql directory (https://github.com/oracle/odpi/tree/main/test/sql). ([TODO] this part may need to go into our project's `/priv` directory, but i think it's OK to start here.)

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
- nothing yet

**In Progress**:
- initial development and driver structure

**TODO/Upcoming**:
- [core] implement context support and driver initialization
- [core] implement database connections & properties
- [core] implement SQL statements & execution
- [core] implement result set handling including metadata
- [datatype] implement VARCHAR2/NVARCHAR2
- [datatype] implement NUMBER & friends
- [datatype] implement DATE/TIMESTAMP & friends
- [ecto] implement Ecto adapter functions

---

## How to Work with This Project

### Setup Instructions
```bash
1. Clone the repo
2. Install dependencies: `mix deps.get`
3. Set up environment: `mix setup && mix deps.compile`
4. For testing, spin up an Oracle database: `docker compose up`
5. Run tests: `mix test`
```

### Environment Variables (TBD)

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
