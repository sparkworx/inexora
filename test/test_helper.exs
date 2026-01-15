# Configure ExUnit - exclude oracle_client tests by default
ExUnit.start(exclude: [:oracle_client])

# Include oracle_client tests if environment variable is set
if System.get_env("ORACLE_CLIENT_AVAILABLE") do
  ExUnit.configure(exclude: [])
end
