# Force US English for Oracle error messages so assertions on message text are
# stable regardless of the developer/CI locale. OCI reads NLS_LANG once per OS
# process, when the first ODPI-C context is created (inside the `inexora`
# driver); set it before any test connects. A meaningful explicit NLS_LANG is
# respected; unset or blank falls through to the default (note "" is truthy in
# Elixir, so test for it). Mirrors the driver's own harness.
if System.get_env("NLS_LANG") in [nil, ""] do
  System.put_env("NLS_LANG", "AMERICAN_AMERICA.AL32UTF8")
end

# Optionally warm-load the Oracle Client library from a custom directory before
# the first driver context is created. macOS Instant Client is often not on the
# default loader path, and SIP strips DYLD_LIBRARY_PATH from the BEAM. No-op
# unless ORACLE_CLIENT_LIB_DIR is set. Uses the `inexora` driver NIF directly.
if dir = System.get_env("ORACLE_CLIENT_LIB_DIR") do
  case Inexora.Nif.context_create(oracle_client_lib_dir: dir) do
    {:ok, _ctx} -> :ok
    {:error, reason} -> IO.warn("ORACLE_CLIENT_LIB_DIR warm-load failed: #{inspect(reason)}")
  end
end

# Integration tests are tagged `:oracle_database` and need a live Oracle
# instance; they are excluded unless ORACLE_DATABASE_AVAILABLE is set.
exclusions = if System.get_env("ORACLE_DATABASE_AVAILABLE"), do: [], else: [:oracle_database]

ExUnit.start(exclude: exclusions)
