defmodule Citadel.Encrypted.Binary do
  @moduledoc """
  An Ash type for encrypted binary data.

  Uses `Citadel.Vault` to encrypt/decrypt values at rest.
  Values are encrypted before storage and decrypted when loaded.

  ## Usage in Ash Resources

      attribute :secret_token, Citadel.Encrypted.Binary do
        sensitive? true
        allow_nil? false
      end
  """

  use Ash.Type

  @impl Ash.Type
  def storage_type(_constraints), do: :binary

  @impl Ash.Type
  def cast_input(nil, _constraints), do: {:ok, nil}

  def cast_input(value, _constraints) when is_binary(value) do
    {:ok, value}
  end

  def cast_input(_, _constraints), do: :error

  @impl Ash.Type
  def cast_stored(nil, _constraints), do: {:ok, nil}

  def cast_stored(value, _constraints) when is_binary(value) do
    Citadel.Vault.decrypt(value)
  end

  def cast_stored(_, _constraints), do: :error

  @impl Ash.Type
  def dump_to_native(nil, _constraints), do: {:ok, nil}

  def dump_to_native(value, _constraints) when is_binary(value) do
    Citadel.Vault.encrypt(value)
  end

  def dump_to_native(_, _constraints), do: :error
end
