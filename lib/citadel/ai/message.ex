defmodule Citadel.AI.Message do
  @moduledoc """
  Standardized message format for AI interactions across different providers.

  This struct provides a common interface for messages regardless of the underlying
  LLM provider (Anthropic, OpenAI, etc.).
  """

  @type role :: :user | :assistant | :system
  @type t :: %__MODULE__{
          role: role(),
          content: String.t(),
          id: String.t()
        }

  @enforce_keys [:role, :content]
  defstruct [:role, :content, :id]

  @doc """
  Creates a new message struct.

  ## Parameters
    - role: The role of the message sender (:user, :assistant, or :system)
    - content: The message content
    - opts: Optional keyword list, may include:
      - :id - Custom message ID (auto-generated if not provided)

  ## Examples

      iex> Citadel.AI.Message.new(:user, "Hello!")
      %Citadel.AI.Message{role: :user, content: "Hello!", id: "..."}

      iex> Citadel.AI.Message.new(:assistant, "Hi there!", id: "msg-123")
      %Citadel.AI.Message{role: :assistant, content: "Hi there!", id: "msg-123"}
  """
  @spec new(role(), String.t(), keyword()) :: t()
  def new(role, content, opts \\ []) when role in [:user, :assistant, :system] do
    %__MODULE__{
      role: role,
      content: content,
      id: Keyword.get_lazy(opts, :id, &generate_id/0)
    }
  end

  @doc """
  Creates a user message.

  ## Examples

      iex> Citadel.AI.Message.user("What's the weather?")
      %Citadel.AI.Message{role: :user, content: "What's the weather?", id: "..."}
  """
  @spec user(String.t(), keyword()) :: t()
  def user(content, opts \\ []), do: new(:user, content, opts)

  @doc """
  Creates an assistant message.

  ## Examples

      iex> Citadel.AI.Message.assistant("It's sunny today!")
      %Citadel.AI.Message{role: :assistant, content: "It's sunny today!", id: "..."}
  """
  @spec assistant(String.t(), keyword()) :: t()
  def assistant(content, opts \\ []), do: new(:assistant, content, opts)

  @doc """
  Creates a system message.

  ## Examples

      iex> Citadel.AI.Message.system("You are a helpful assistant.")
      %Citadel.AI.Message{role: :system, content: "You are a helpful assistant.", id: "..."}
  """
  @spec system(String.t(), keyword()) :: t()
  def system(content, opts \\ []), do: new(:system, content, opts)

  @doc """
  Converts a LangChain message to a Citadel.AI.Message.
  """
  @spec from_langchain(LangChain.Message.t()) :: t()
  def from_langchain(%LangChain.Message{role: role, content: content}) do
    new(String.to_existing_atom(role), content)
  end

  @doc """
  Converts a Citadel.AI.Message to a LangChain message.
  """
  @spec to_langchain(t()) :: LangChain.Message.t()
  def to_langchain(%__MODULE__{role: role, content: content}) do
    case role do
      :user -> LangChain.Message.new_user!(content)
      :assistant -> LangChain.Message.new_assistant!(content)
      :system -> LangChain.Message.new_system!(content)
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
