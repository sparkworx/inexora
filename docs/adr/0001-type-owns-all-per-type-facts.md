# Type owns all per-type facts; Variable stays type-agnostic

When extracting the ODPI-C variable lifecycle into `Inexora.Variable`, we chose to keep every per-type fact — encoding, decoding, bind hint, and the Variable Spec (Oracle type, native type, buffer size) — behind `Inexora.Type`'s interface, even though the Variable Spec is consumed only by `Inexora.Variable`. This mirrors Postgrex's extension shape: a future type-extension Hex package (e.g. specialized Oracle domain types) supplies one Type Mapping and attaches at one seam; the lifecycle module never changes. Do not move the allocation table "closer to its caller" — that would split the future extension surface across two modules.

## Considered Options

- **Split by job** — encoding in `Type`, allocation table in `Variable`. Tighter today, but a future extension must attach at two seams and the lifecycle module grows type awareness.
- **Build the extension registry now** — premature; no second adapter exists yet to justify the seam.
