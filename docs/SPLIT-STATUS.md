# Adapter split — status & handoff

Live status of splitting the Ecto adapter out of `inexora` into a standalone
`ecto_oracle` package. Read this first; the frozen decisions and step list are in
[adapter-split-plan.md](adapter-split-plan.md), rationale in
[ADR-0002](adr/0002-split-ecto-adapter-into-ecto-oracle.md).

_Last updated: 2026-07-17._

## Phase status

| Phase | What | Status | Where |
|-------|------|--------|-------|
| 0 | Freeze the driver's public interface | ✅ **done, merged to `develop`, tagged `v0.2.0`** | commits `fd80db0`, `6ba64e6`; release prep `0fa6bf6`, `df52473` |
| 1 | `git filter-repo` extraction spec | ✅ **dry-run validated** (71→14 commits, blame preserved) | spec below |
| 2 | Stand up the `ecto_oracle` package | ✅ **drafted** (files ready to drop in) | [`ecto_oracle-staging/`](ecto_oracle-staging/) |
| 3 | Remove the bundled adapter from `inexora` | ✅ **drafted, NOT merged** (breaking; gated on ecto_oracle publish) | branch `phase3-remove-adapter` |

Nothing outward-facing has happened yet: `v0.2.0` is **not** pushed or published,
the `ecto_oracle` repo does **not** exist, and `phase3-remove-adapter` is **not**
merged. All remaining steps are manual/outward-facing (below).

## The frozen driver interface (shipped in 0.2.0)

`ecto_oracle` may depend only on these; everything else in `inexora` is private.

- `DBConnection` behaviour via `Inexora.Connection`
- `Inexora.Query.new/2` — the sole public query constructor (struct fields private)
- `%Inexora.Result{}`
- `%Inexora.Error{}` — the adapter reads only `oracle_code` + `message`
- `Inexora.Connection.connect/1` + `disconnect/2` — for Ecto `storage_up`/`storage_down`

Private: `Inexora.Nif`, `Inexora.Batch`, `Inexora.Cursor`, `Inexora.Type` internals,
the C layer.

## Phase 1 — the filter-repo spec (validated)

```bash
git clone --no-local https://github.com/sparkworx/inexora ecto_oracle
cd ecto_oracle
git filter-repo \
  --path lib/ecto/ \
  --path test/ecto/ \
  --prune-degenerate always
```

Result: 14 commits, the 4 adapter files, authorship/blame preserved, `origin`
auto-removed. No `--path-rename` needed (module stays `Ecto.Adapters.Oracle`).
Output is adapter code only — no mix.exs/README/harness; those come from Phase 2.

## Phase 2 — the staged package (`ecto_oracle-staging/`)

These files were drafted in this repo as a durable copy; move them into the
extracted repo. **`ecto_oracle-staging/` is transient handoff material — delete it
from `inexora` once the real repo is stood up.**

- `mix.exs` — `app: :ecto_oracle`, adapter `Ecto.Adapters.Oracle`, deps
  `{:inexora, "~> 0.2.0"}` + `ecto`/`ecto_sql`, pure Elixir (no NIF toolchain)
- `test/test_helper.exs`, `test/support/test_helpers.ex` (`EctoOracle.TestHelpers`)
- `test/ecto/adapters/oracle_ddl_types_test.exs` — the 4 per-datatype DDL blocks
  relocated from the driver (float/interval/raw/rowid)
- `docker-compose.yaml` + `docker/init/01_create_user.sql`
- `.formatter.exs`, `.gitignore`, `README.md`, `CHANGELOG.md`
- `PHASE2-NOTES.md` — manifest, the 3 required fixups to the extracted
  integration test, and build/verify steps

Still needed by hand: copy `inexora`'s `LICENSE` verbatim; fill the
`<SOURCE_COMMIT>` back-pointer in `README.md`.

## Phase 3 — the driver cleanup (branch `phase3-remove-adapter`)

Drafted and verified (70 non-DB tests pass, compiles/formats clean), **held off
`develop`** because it removes `Ecto.Adapters.Oracle` (breaking):

- deletes `lib/ecto/**` + `test/ecto/**`
- relocates the 4 DDL test blocks out of the driver datatype tests (→ Phase 2)
- drops `ecto` + `ecto_sql` deps
- bumps **0.2.0 → 0.3.0** + docs repointed at `ecto_oracle`

## Versioning / lockstep

Pre-1.0, the adapter pins the driver's **minor** in tight lockstep:

- `ecto_oracle` 0.2.0 pins `{:inexora, "~> 0.2.0"}` (correct while `inexora` 0.2.0
  still bundles the adapter).
- When `inexora` 0.3.0 lands (Phase 3), `~> 0.2.0` **excludes** it — so
  `ecto_oracle` must ship a matching **0.3.0** re-pinned `{:inexora, "~> 0.3.0"}`.
- At `inexora` 1.0 (interface declared stable), relax to `{:inexora, "~> 1.0"}`
  and let the two version independently.

## Trigger order (what's left — all manual)

1. **Publish the driver:** push `develop` + `v0.2.0`
   (`git push --no-recurse-submodules origin develop && … v0.2.0`),
   then `mix hex.user auth` → `mix hex.publish`.
2. **Extract:** run the Phase 1 filter-repo spec → new `ecto_oracle` repo; create it
   on GitHub (`sparkworx/ecto_oracle`) and push.
3. **Scaffold:** drop in `ecto_oracle-staging/` files, apply the 3 test fixups
   (`PHASE2-NOTES.md`), add `LICENSE`, fill `<SOURCE_COMMIT>`; `mix test` +
   `mix hex.publish` for `ecto_oracle` 0.2.0.
4. **Clean up the driver:** merge `phase3-remove-adapter` → `develop`, delete
   `docs/ecto_oracle-staging/`, release `inexora` 0.3.0.
5. **Re-lockstep:** release `ecto_oracle` 0.3.0 pinned `{:inexora, "~> 0.3.0"}`.
