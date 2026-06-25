# Load test support files
Code.require_file("support/test_helpers.ex", __DIR__)

# Force US English for Oracle error messages so assertions on message text are stable
# regardless of the developer/CI locale. OCI reads NLS_LANG once per OS process, when the
# first ODPI-C context is created; setting it here (before the warm-load below and any test)
# guarantees AMERICAN error text. The .AL32UTF8 charset half matches how inexora already
# treats all column data as UTF-8 binaries. A meaningful explicit NLS_LANG is respected;
# unset or blank falls through to the default (note "" is truthy in Elixir, so test for it).
if System.get_env("NLS_LANG") in [nil, ""] do
  System.put_env("NLS_LANG", "AMERICAN_AMERICA.AL32UTF8")
end

# Optionally warm-load the Oracle Client library from a custom directory.
# macOS Instant Client is often not on the default loader path, and SIP strips
# DYLD_LIBRARY_PATH from the BEAM. ODPI-C loads the client once per OS process, so
# this single call makes every later context_create/0 (no opts) succeed.
# No-op unless ORACLE_CLIENT_LIB_DIR is set.
if dir = System.get_env("ORACLE_CLIENT_LIB_DIR") do
  case Inexora.Nif.context_create(oracle_client_lib_dir: dir) do
    {:ok, _ctx} -> :ok
    {:error, reason} -> IO.warn("ORACLE_CLIENT_LIB_DIR warm-load failed: #{inspect(reason)}")
  end
end

# Configure ExUnit exclusions based on environment
# - oracle_client: tests that need Oracle client libraries installed
# - oracle_database: tests that need a live Oracle database connection
exclusions =
  cond do
    System.get_env("ORACLE_DATABASE_AVAILABLE") -> []
    System.get_env("ORACLE_CLIENT_AVAILABLE") -> [:oracle_database]
    true -> [:oracle_client, :oracle_database]
  end

ExUnit.start(exclude: exclusions)
