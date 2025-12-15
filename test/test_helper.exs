# Limit concurrent test cases to prevent database connection pool exhaustion
# during property tests that create many records
ExUnit.start(max_cases: System.schedulers_online(), capture_log: true)
Ecto.Adapters.SQL.Sandbox.mode(Citadel.Repo, :manual)

# Set Mox to private mode for concurrent testing
Mox.defmock(Citadel.AI.MockProvider, for: Citadel.AI.Provider)
