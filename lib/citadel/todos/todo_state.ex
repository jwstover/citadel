defmodule Citadel.Todos.TodoState do
  @moduledoc """
  Represents the possible states a todo item can be in (e.g., "To Do", "In Progress", "Done").
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Todos,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "todo_states"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*]

    update :update do
      primary? true
      accept [:name, :description, :order, :is_complete]
    end
  end

  policies do
    policy do
      condition always()
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    attribute :description, :string, public?: true
    attribute :order, :integer, public?: true, allow_nil?: false
    attribute :is_complete, :boolean, public?: true, default: false

    timestamps()
  end
end
