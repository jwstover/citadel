defmodule Citadel.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive data at rest.

  Used for storing encrypted values like GitHub PATs that need to be
  retrieved (not just verified like hashed passwords).

  ## Configuration

  Configure in `config/runtime.exs`:

      cloak_key = System.get_env("CLOAK_KEY") ||
        raise "CLOAK_KEY environment variable is missing"

      config :citadel, Citadel.Vault,
        ciphers: [
          default: {
            Cloak.Ciphers.AES.GCM,
            tag: "AES.GCM.V1",
            key: Base.decode64!(cloak_key),
            iv_length: 12
          }
        ]

  Generate a key with:

      :crypto.strong_rand_bytes(32) |> Base.encode64()
  """

  use Cloak.Vault, otp_app: :citadel
end
