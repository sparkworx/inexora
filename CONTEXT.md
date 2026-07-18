# Inexora

An Oracle Database driver for Elixir. The domain is the translation between Elixir values and Oracle's wire representations, and the lifecycle of the native resources that carry them. The Ecto adapter lives in the companion [`ecto_oracle`](https://github.com/sparkworx/ecto_oracle) repo (see [ADR-0002](docs/adr/0002-split-ecto-adapter-into-ecto-oracle.md)).

## Language

**Variable**:
A driver-owned Oracle bind variable (ODPI-C's `dpiVar`) used for array binding and RETURNING INTO; it is created, filled, bound, read, and released as one lifecycle.
_Avoid_: var, bind handle, output binding

**Variable Spec**:
The allocation description — Oracle type, native transfer type, and buffer size — required to create a Variable for a given Elixir value.
_Avoid_: type table, sizing table, ODPI types

**Type Mapping**:
The complete set of per-type facts the driver holds for one Elixir↔Oracle type pair: how to encode it for binding, decode it after fetch, its bind hint, and its Variable Spec. The unit a future type-extension package would supply.
_Avoid_: per-type row, type support, conversion table

**Value Binding**:
Binding a parameter directly by value into a statement placeholder; the ordinary single-execution path, distinct from binding through a Variable.
_Avoid_: positional binding (that's the placeholder style, not the mechanism)
