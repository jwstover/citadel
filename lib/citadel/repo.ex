defmodule Citadel.Repo do
  use Ecto.Repo,
    otp_app: :citadel,
    adapter: Ecto.Adapters.Postgres
end
