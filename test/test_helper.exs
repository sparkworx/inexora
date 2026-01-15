# Configure ExUnit - exclude tests requiring Oracle by default
ExUnit.start(exclude: [:oracle_client, :oracle_database])

# Include oracle_client tests if Oracle client libraries are available
if System.get_env("ORACLE_CLIENT_AVAILABLE") do
  ExUnit.configure(exclude: [:oracle_database])
end

# Include oracle_database tests if a live database is available
if System.get_env("ORACLE_DATABASE_AVAILABLE") do
  ExUnit.configure(exclude: [])
end
