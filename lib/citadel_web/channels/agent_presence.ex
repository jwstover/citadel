defmodule CitadelWeb.AgentPresence do
  @moduledoc false

  use Phoenix.Presence,
    otp_app: :citadel,
    pubsub_server: Citadel.PubSub
end
