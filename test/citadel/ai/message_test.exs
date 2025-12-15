defmodule Citadel.AI.MessageTest do
  use ExUnit.Case, async: true

  alias Citadel.AI.Message

  describe "new/3" do
    test "creates a user message" do
      message = Message.new(:user, "Hello!")
      assert message.role == :user
      assert message.content == "Hello!"
      assert is_binary(message.id)
    end

    test "creates an assistant message" do
      message = Message.new(:assistant, "Hi there!")
      assert message.role == :assistant
      assert message.content == "Hi there!"
      assert is_binary(message.id)
    end

    test "creates a system message" do
      message = Message.new(:system, "You are helpful.")
      assert message.role == :system
      assert message.content == "You are helpful."
      assert is_binary(message.id)
    end

    test "accepts custom id" do
      message = Message.new(:user, "Hello!", id: "custom-123")
      assert message.id == "custom-123"
    end

    test "generates unique ids" do
      message1 = Message.new(:user, "Hello!")
      message2 = Message.new(:user, "Hello!")
      assert message1.id != message2.id
    end
  end

  describe "user/2" do
    test "creates a user message" do
      message = Message.user("Hello!")
      assert message.role == :user
      assert message.content == "Hello!"
    end

    test "accepts custom id" do
      message = Message.user("Hello!", id: "user-123")
      assert message.id == "user-123"
    end
  end

  describe "assistant/2" do
    test "creates an assistant message" do
      message = Message.assistant("Response")
      assert message.role == :assistant
      assert message.content == "Response"
    end

    test "accepts custom id" do
      message = Message.assistant("Response", id: "assistant-123")
      assert message.id == "assistant-123"
    end
  end

  describe "system/2" do
    test "creates a system message" do
      message = Message.system("Instructions")
      assert message.role == :system
      assert message.content == "Instructions"
    end

    test "accepts custom id" do
      message = Message.system("Instructions", id: "system-123")
      assert message.id == "system-123"
    end
  end

  describe "to_langchain/1" do
    test "converts user message to LangChain format" do
      message = Message.user("Hello!")
      langchain_message = Message.to_langchain(message)

      assert langchain_message.role == :user
      assert extract_content(langchain_message) == "Hello!"
    end

    test "converts assistant message to LangChain format" do
      message = Message.assistant("Response")
      langchain_message = Message.to_langchain(message)

      assert langchain_message.role == :assistant
      assert extract_content(langchain_message) == "Response"
    end

    test "converts system message to LangChain format" do
      message = Message.system("Instructions")
      langchain_message = Message.to_langchain(message)

      assert langchain_message.role == :system
      assert extract_content(langchain_message) == "Instructions"
    end
  end

  describe "from_langchain/1" do
    test "converts LangChain user message" do
      langchain_message = LangChain.Message.new_user!("Hello!")
      message = Message.from_langchain(langchain_message)

      assert message.role == :user
      assert message.content == "Hello!"
    end

    test "converts LangChain assistant message" do
      langchain_message = LangChain.Message.new_assistant!("Response")
      message = Message.from_langchain(langchain_message)

      assert message.role == :assistant
      assert message.content == "Response"
    end

    test "converts LangChain system message" do
      langchain_message = LangChain.Message.new_system!("Instructions")
      message = Message.from_langchain(langchain_message)

      assert message.role == :system
      assert message.content == "Instructions"
    end
  end

  defp extract_content(%LangChain.Message{content: [%{content: text}]}), do: text
  defp extract_content(%LangChain.Message{content: content}) when is_binary(content), do: content
end
