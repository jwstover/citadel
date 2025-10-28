defmodule Citadel.Chat.Message.Types.Source do
  @moduledoc """
  Enum type for message sources: `:agent` (AI) or `:user` (human).
  """
  use Ash.Type.Enum, values: [:agent, :user]
end
