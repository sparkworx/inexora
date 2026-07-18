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
| 1 | `git filter-repo` extraction | ✅ **executed locally** (71→14 commits, blame preserved) | ran into `../ecto_oracle` |
| 2 | Stand up the `ecto_oracle` package | ✅ **published to GitHub** (`sparkworx/ecto_oracle`, 29 non-DB tests pass) | pushed; not yet on Hex |
| 3 | Remove the bundled adapter from `inexora` | ✅ **merged to `develop`, tagged `v0.3.0`** | driver is now 0.3.0, adapter-free |

`sparkworx/ecto_oracle` is on GitHub (14 extracted commits + scaffolding
`1b60ed8`); the superseded `ecto_oracle-staging/` backup has been deleted from
`inexora`. **What's left is Hex publishing only:** `develop`/`v0.3.0` is committed
locally but **not pushed**, `inexora` 0.3.0 is **not on Hex**, and `ecto_oracle`
0.3.0 is **not on Hex** (its `~> 0.3.0` pin needs `inexora` 0.3.0 published first).

## Correction — the 0.2.0 pairing collides

Implementing Phase 2 surfaced a flaw in the original lockstep note: `ecto_oracle`
**cannot** depend on `inexora` 0.2.0. Both define `Ecto.Adapters.Oracle` (0.2.0
still bundles the adapter), so co-installing them is a module-redefinition
collision. The first adapter-free driver is **0.3.0**, so:

- `ecto_oracle`'s first release is **0.3.0**, pinning `{:inexora, "~> 0.3.0"}`
  (there is no `ecto_oracle` 0.2.0).
- `inexora` 0.2.0 is an **internal interface-freeze milestone only** — not an
  `ecto_oracle` dependency target.
- Verified: `ecto_oracle` compiles with no collision and 29 non-DB tests pass
  against a driver-only `inexora` (path dep to the `phase3-remove-adapter` state).

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

These were the pre-implementation drafts. The real `../ecto_oracle` repo already
incorporates them **plus** the finished work the drafts left open: `LICENSE`
copied, `README` `<SOURCE_COMMIT>` filled (`2c53741`), the 3 integration-test
fixups applied, and the `~> 0.3.0` pin / 0.3.0 version. Prefer `../ecto_oracle`;
this staging dir is a backup only.

## Phase 3 — the driver cleanup (branch `phase3-remove-adapter`)

Drafted and verified (70 non-DB tests pass, compiles/formats clean), **held off
`develop`** because it removes `Ecto.Adapters.Oracle` (breaking):

- deletes `lib/ecto/**` + `test/ecto/**`
- relocates the 4 DDL test blocks out of the driver datatype tests (→ Phase 2)
- drops `ecto` + `ecto_sql` deps
- bumps **0.2.0 → 0.3.0** + docs repointed at `ecto_oracle`

## Versioning / lockstep

Pre-1.0, the adapter pins the driver's **minor** in tight lockstep — but the
first pairing is **0.3.0**, not 0.2.0 (see the collision correction above):

- `inexora` 0.2.0 — interface-freeze milestone, still bundles the adapter.
  Optional to publish (for existing bundled-adapter users); **not** an
  `ecto_oracle` dependency target.
- `inexora` 0.3.0 (Phase 3) — first adapter-free driver.
- `ecto_oracle` 0.3.0 — first release, pins `{:inexora, "~> 0.3.0"}`.
- At `inexora` 1.0 (interface declared stable), relax to `{:inexora, "~> 1.0"}`
  and let the two version independently.

Because `ecto_oracle` needs an adapter-free driver, **Phase 3 (inexora 0.3.0)
must publish before `ecto_oracle` can** — the reverse of the original plan's
ordering.

## Trigger order (what's left — Hex publishing only)

Done: Phase 1 extraction, the `../ecto_oracle` package (Phase 2, pushed to
GitHub), Phase 3 merged to `develop` + tagged `v0.3.0`, staging deleted.
Remaining steps are all outward-facing Hex/push work:

1. ~~Push the adapter repo to GitHub~~ — **done** (`sparkworx/ecto_oracle`).
2. **(Optional) Publish inexora 0.2.0** for existing bundled-adapter users, from
   the `v0.2.0` tag: `mix hex.user auth` → `mix hex.publish`. Skippable — nothing
   in the split depends on it.
3. **Release the adapter-free driver:** push `develop` + `v0.3.0`
   (`git push --no-recurse-submodules origin develop v0.3.0`), then
   `mix hex.publish` → `inexora` 0.3.0 on Hex.
4. **Publish the adapter:** once `inexora` 0.3.0 is on Hex, in `../ecto_oracle`
   run `mix deps.get` (resolves the `~> 0.3.0` pin), `mix test`, `mix hex.publish`
   → `ecto_oracle` 0.3.0.
