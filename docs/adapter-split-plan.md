# Adapter split — handoff plan

The locked plan for splitting the Ecto adapter out of `inexora` into a standalone `ecto_oracle` package. Every decision below is resolved; an executor can follow this without deciding anything. Charted on wayfinder map [#5](https://github.com/sparkworx/inexora/issues/5); rationale in [ADR-0002](adr/0002-split-ecto-adapter-into-ecto-oracle.md) and [ADR-0001](adr/0001-type-owns-all-per-type-facts.md).

## Decisions (locked)

| # | Decision | Answer |
|---|----------|--------|
| [#9](https://github.com/sparkworx/inexora/issues/9) | Package name / module | `ecto_oracle` / `Ecto.Adapters.Oracle` |
| [#10](https://github.com/sparkworx/inexora/issues/10) | Repo topology | Separate GitHub repo, hard dep on `inexora` |
| [#8](https://github.com/sparkworx/inexora/issues/8) | Driver public interface | Structs + `DBConnection` + storage hooks public; internals private |
| [#7](https://github.com/sparkworx/inexora/issues/7) | Pre-split refactors | None block the split; freeze the struct contracts instead |
| [#11](https://github.com/sparkworx/inexora/issues/11) | Versioning contract | Pre-1.0 tight lockstep; `{:inexora, "~> 0.2.0"}` at first release |
| [#12](https://github.com/sparkworx/inexora/issues/12) | Git history | Preserve via `git filter-repo` |
| [#6](https://github.com/sparkworx/inexora/issues/6) | Ecosystem precedent | Separate repo/package on the `DBConnection` seam (exqlite→ecto_sqlite3) |

## The frozen public interface

`ecto_oracle` may depend only on these; everything else in `inexora` is private.

- `DBConnection` behaviour via `Inexora.Connection` (the pool connection module)
- `Inexora.Query.new/2` (`sql`, `returning`) — the **only** way to build a query; struct fields are private
- `%Inexora.Result{}`
- `%Inexora.Error{oracle_code, message}` — the sole error shape the adapter reads (in `to_constraints`)
- Connect options (passed through `child_spec`)
- `Inexora.Connection.connect/1` + `disconnect/2` — for Ecto `storage_up`/`storage_down`, which open a connection outside the pool

Private (not part of the contract): `Inexora.Nif`, `Inexora.Batch`, `Inexora.Cursor`, `Inexora.Type` internals, the C layer. Per ADR-0001, value-type knowledge stays driver-side; the adapter keeps its own DDL type-name map (`ecto_to_db`) for `CREATE TABLE`.

**Frozen struct contracts:**
- `%Inexora.Query{}` `returning` field: `%{columns: [{atom, type}], start_pos: integer}`
- `%Inexora.Error{oracle_code, message}`
- `%Inexora.Result{}`

**Known limitation:** the returning-type is hardcoded to `{col, :id}` (adapter `connection.ex:52`, "default to :id for now"). Documented so a later type-carrying fix doesn't silently change the frozen `returning` shape.

## Execution steps

### Phase 0 — in the `inexora` repo, before extraction

1. Add `Inexora.Query.new/2`; make `%Inexora.Query{}` fields private (constructor is the only public entry point).
2. Switch the adapter's three query-construction sites — `lib/ecto/adapters/oracle/connection.ex:26, 91, 106` — to `Inexora.Query.new/2`.
3. Document `Inexora.Connection.connect/1` + `disconnect/2` as public storage-callback entry points.
4. Document/freeze the three struct contracts above; note the `{col, :id}` returning-type limitation.
5. Release `inexora 0.2.0` (ships the public interface).

### Phase 1 — create the `ecto_oracle` repo

6. `git filter-repo` this repo down to the adapter's paths — `lib/ecto/**`, `test/ecto/**`, plus shared commits that touched them — into a new `ecto_oracle` repository, retaining authorship/blame.
7. First README/commit points back to the `inexora` source commit it was extracted from.

### Phase 2 — stand up the adapter package

8. `mix.exs`: package `ecto_oracle`, module `Ecto.Adapters.Oracle`, deps `{:inexora, "~> 0.2.0"}` (tight lockstep) + `{:ecto_sql, ...}`.
9. Duplicate the live-Oracle test harness: docker-compose, `test/support/sql/` setup scripts, `TestRepo`, `:oracle_database` tagging, the `ORACLE_DATABASE_AVAILABLE` gate. CI stands up its own Oracle instance.

### Phase 3 — clean up the `inexora` repo

10. Remove `lib/ecto/**` and `test/ecto/**` from `inexora`; drop `ecto_sql` from its deps if only the adapter used it.
11. Update `inexora`'s README/docs to point at `ecto_oracle`.

## After the split (unconstrained)

The four architecture-review refactors are all post-split-safe and gate nothing here — land them anytime, on either side:
- Variable extraction (`Inexora.Variable`) — see the deferred design and ADR-0001
- Error seam (normalize at the NIF boundary)
- RETURNING structurally (adapter-internal; preserves the frozen `returning` shape)
- One C decoder (fold the fetch switch into `data_to_term`)

## Versioning going forward

Driver bumps its **minor** on any public-interface change; adapter ships a matching release pinned to that minor. At `inexora 1.0` (interface declared stable), relax the adapter to `{:inexora, "~> 1.0"}` and let the two version independently.
