# Load test support files
Code.require_file("support/test_helpers.ex", __DIR__)

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
