defmodule Citadel.Generator do
  @moduledoc """
  Generators for test data using Ash.Generator.

  This module provides reusable generators for all Citadel resources.

  ## Usage

      import Citadel.Generator

      # Generate a single user
      user = generate(user())

      # Generate with custom attributes
      workspace = generate(workspace(actor: user))

      # Generate a complete workspace setup
      setup = generate(workspace_with_owner())
  """
  use Ash.Generator

  @doc """
  Generates a user for testing.

  ## Parameters

    * `overrides` - Field values to override (e.g., [email: "custom@example.com"])
    * `generator_opts` - Options passed to seed_generator (e.g., [tenant: workspace_id])

  ## Examples

      user = generate(user())
      user = generate(user([email: "custom@example.com"]))
  """
  def user(overrides \\ [], generator_opts \\ []) do
    seed_generator(
      {Citadel.Accounts.User,
       %{
         email: sequence(:user_email, &"user-#{&1}@example.com"),
         hashed_password: "hashed_password_123"
       }},
      Keyword.merge([overrides: overrides], generator_opts)
    )
  end

  @doc """
  Generates an organization using changeset_generator.

  ## Parameters

    * `overrides` - Field values to override (e.g., [name: "Custom Org"])
    * `generator_opts` - Options passed to changeset_generator (e.g., [actor: owner])

  ## Examples

      owner = generate(user())
      organization = generate(organization([], actor: owner))
      organization = generate(organization([name: "My Org"], actor: owner))
  """
  def organization(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Accounts.Organization,
      :create,
      Keyword.merge(
        [
          defaults: [
            name: sequence(:organization_name, &"Organization #{&1}")
          ],
          overrides: overrides
        ],
        generator_opts
      )
    )
  end

  @doc """
  Generates an organization membership.

  ## Parameters

    * `overrides` - Field values to override (e.g., [organization_id: org_id, user_id: user_id, role: :admin])
    * `generator_opts` - Options passed to changeset_generator

  ## Examples

      membership = generate(organization_membership(
        [organization_id: org.id, user_id: user.id, role: :member],
        authorize?: false
      ))
  """
  def organization_membership(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Accounts.OrganizationMembership,
      :join,
      Keyword.merge(
        [
          defaults: [
            role: :member
          ],
          overrides: overrides
        ],
        generator_opts
      )
    )
  end

  @doc """
  Generates a workspace using changeset_generator.

  ## Parameters

    * `overrides` - Field values to override (e.g., [name: "Custom Name", organization_id: org_id])
    * `generator_opts` - Options passed to changeset_generator (e.g., [actor: owner])

  ## Examples

      owner = generate(user())
      org = generate(organization([], actor: owner))
      workspace = generate(workspace([organization_id: org.id], actor: owner))
  """
  def workspace(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Accounts.Workspace,
      :create,
      Keyword.merge(
        [
          defaults: [
            name: sequence(:workspace_name, &"Workspace #{&1}"),
            organization_id: nil
          ],
          overrides: overrides
        ],
        generator_opts
      )
    )
  end

  @doc """
  Generates a workspace membership.

  ## Parameters

    * `overrides` - Field values to override (e.g., [user_id: user_id, workspace_id: workspace_id])
    * `generator_opts` - Options passed to changeset_generator (e.g., [actor: owner])

  ## Examples

      membership = generate(workspace_membership(
        [user_id: user.id, workspace_id: workspace.id],
        actor: owner
      ))
  """
  def workspace_membership(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Accounts.WorkspaceMembership,
      :join,
      Keyword.merge([overrides: overrides], generator_opts)
    )
  end

  @doc """
  Generates a workspace invitation.

  ## Parameters

    * `overrides` - Field values to override (e.g., [email: "custom@example.com", workspace_id: workspace_id])
    * `generator_opts` - Options passed to changeset_generator (e.g., [actor: owner])

  ## Examples

      invitation = generate(workspace_invitation(
        [workspace_id: workspace.id],
        actor: owner
      ))
      invitation = generate(workspace_invitation(
        [email: "custom@example.com", workspace_id: workspace.id],
        actor: owner
      ))
  """
  def workspace_invitation(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Accounts.WorkspaceInvitation,
      :create,
      Keyword.merge(
        [
          defaults: [
            email: sequence(:invitation_email, &"invite-#{&1}@example.com")
          ],
          overrides: overrides
        ],
        generator_opts
      )
    )
  end

  @doc """
  Generates a task.

  ## Parameters

    * `overrides` - Field values to override (e.g., [workspace_id: workspace_id, task_state_id: state_id])
    * `generator_opts` - Options passed to changeset_generator (e.g., [actor: user, tenant: workspace_id])

  ## Examples

      task = generate(task(
        [workspace_id: workspace.id, task_state_id: task_state.id],
        actor: user, tenant: workspace.id
      ))
  """
  def task(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Tasks.Task,
      :create,
      Keyword.merge(
        [
          defaults: [
            title: sequence(:task_title, &"Task #{&1}"),
            description: "Test task description",
            parent_task_id: nil
          ],
          overrides: overrides
        ],
        generator_opts
      )
    )
  end

  @doc """
  Generates a conversation.

  ## Parameters

    * `overrides` - Field values to override (e.g., [workspace_id: workspace_id, title: "Custom"])
    * `generator_opts` - Options passed to changeset_generator (e.g., [actor: user, tenant: workspace_id])

  ## Examples

      conversation = generate(conversation(
        [workspace_id: workspace.id],
        actor: user, tenant: workspace.id
      ))
  """
  def conversation(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Chat.Conversation,
      :create,
      Keyword.merge(
        [
          defaults: [
            title: sequence(:conversation_title, &"Conversation #{&1}")
          ],
          overrides: overrides
        ],
        generator_opts
      )
    )
  end

  @doc """
  Generates a message.

  ## Parameters

    * `overrides` - Field values to override (e.g., [text: "Custom message", conversation_id: conv_id])
    * `generator_opts` - Options passed to changeset_generator (e.g., [actor: user])

  ## Examples

      message = generate(message(
        [conversation_id: conversation.id],
        actor: user
      ))
      message = generate(message(
        [text: "Hello", conversation_id: conversation.id],
        actor: user
      ))
  """
  def message(overrides \\ [], generator_opts \\ []) do
    changeset_generator(
      Citadel.Chat.Message,
      :create,
      Keyword.merge(
        [
          defaults: [
            text: sequence(:message_text, &"Message #{&1}")
          ],
          overrides: overrides
        ],
        generator_opts
      )
    )
  end
end
