defmodule Citadel.Chat.Conversation.Changes.GenerateNameTest do
  use Citadel.DataCase, async: false

  import Mox

  alias Citadel.AI.MockProvider

  setup :set_mox_global
  setup :verify_on_exit!

  describe "change/3" do
    test "generates title from AI response" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      conversation =
        generate(
          conversation([workspace_id: workspace.id, title: nil],
            actor: user,
            tenant: workspace.id
          )
        )

      _message1 =
        Ash.Seed.seed!(Citadel.Chat.Message, %{
          conversation_id: conversation.id,
          text: "Hello, how can I help?",
          source: :agent
        })

      _message2 =
        Ash.Seed.seed!(Citadel.Chat.Message, %{
          conversation_id: conversation.id,
          text: "I need help with my code",
          source: :user
        })

      MockProvider
      |> expect(:default_model, fn -> "gpt-4o" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:send_message, fn prompt, _actor, _config ->
        assert prompt =~ "Based on this conversation"
        assert prompt =~ "Hello, how can I help?"
        assert prompt =~ "I need help with my code"
        {:ok, "  Code Assistance Chat  "}
      end)

      updated_conversation =
        conversation
        |> Ash.Changeset.for_update(:generate_name, %{})
        |> Ash.update!(actor: user, tenant: workspace.id)

      assert updated_conversation.title == "Code Assistance Chat"
    end

    test "returns error when AI fails so Oban can retry" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      conversation =
        generate(
          conversation([workspace_id: workspace.id, title: nil],
            actor: user,
            tenant: workspace.id
          )
        )

      _message =
        Ash.Seed.seed!(Citadel.Chat.Message, %{
          conversation_id: conversation.id,
          text: "Hello",
          source: :user
        })

      MockProvider
      |> expect(:default_model, fn -> "gpt-4o" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:send_message, fn _prompt, _actor, _config ->
        {:error, :api_error, "AI service unavailable"}
      end)

      assert {:error, %Ash.Error.Invalid{}} =
               conversation
               |> Ash.Changeset.for_update(:generate_name, %{})
               |> Ash.update(actor: user, tenant: workspace.id)
    end

    test "fetches last 10 messages sorted by inserted_at" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      conversation =
        generate(
          conversation([workspace_id: workspace.id, title: nil],
            actor: user,
            tenant: workspace.id
          )
        )

      for i <- 1..12 do
        Ash.Seed.seed!(Citadel.Chat.Message, %{
          conversation_id: conversation.id,
          text: "Message #{i}",
          source: :user
        })
      end

      MockProvider
      |> expect(:default_model, fn -> "gpt-4o" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:send_message, fn prompt, _actor, _config ->
        # Use word boundaries to avoid "Message 1" matching "Message 10"
        refute prompt =~ "Message 1\n"
        refute prompt =~ "Message 2\n"
        assert prompt =~ "Message 3\n"
        assert prompt =~ "Message 12\n"
        {:ok, "Long Chat Thread"}
      end)

      conversation
      |> Ash.Changeset.for_update(:generate_name, %{})
      |> Ash.update!(actor: user, tenant: workspace.id)
    end

    test "formats messages with correct role labels" do
      user = generate(user())
      workspace = generate(workspace([], actor: user))

      conversation =
        generate(
          conversation([workspace_id: workspace.id, title: nil],
            actor: user,
            tenant: workspace.id
          )
        )

      _user_msg =
        Ash.Seed.seed!(Citadel.Chat.Message, %{
          conversation_id: conversation.id,
          text: "User question",
          source: :user
        })

      _agent_msg =
        Ash.Seed.seed!(Citadel.Chat.Message, %{
          conversation_id: conversation.id,
          text: "Agent response",
          source: :agent
        })

      MockProvider
      |> expect(:default_model, fn -> "gpt-4o" end)
      |> expect(:validate_config, fn _ -> :ok end)
      |> expect(:send_message, fn prompt, _actor, _config ->
        assert prompt =~ "User: User question"
        assert prompt =~ "Assistant: Agent response"
        {:ok, "Q&A Session"}
      end)

      conversation
      |> Ash.Changeset.for_update(:generate_name, %{})
      |> Ash.update!(actor: user, tenant: workspace.id)
    end
  end
end
