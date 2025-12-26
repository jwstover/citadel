defmodule Citadel.Accounts.Organization do
  @moduledoc """
  An organization is the top-level entity that owns workspaces and has a subscription.
  Users must be members of an organization before they can be added to any of its workspaces.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organizations"
    repo Citadel.Repo
  end

  code_interface do
    define :create, args: [:name]
    define :list, action: :read
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_slug, action: :read, get_by: [:slug]
    define :update
    define :destroy
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name]

      change relate_actor(:owner)
      change Citadel.Accounts.Organization.Changes.GenerateSlug
      change Citadel.Accounts.Organization.Changes.CreateStripeCustomer

      change fn changeset, context ->
        Ash.Changeset.after_action(changeset, fn _changeset, organization ->
          # Automatically create membership for the owner with :owner role
          Citadel.Accounts.add_organization_member!(
            organization.id,
            organization.owner_id,
            :owner,
            authorize?: false
          )

          {:ok, organization}
        end)
      end
    end

    update :update do
      accept [:name]
    end
  end

  policies do
    policy action_type(:create) do
      authorize_if actor_present()
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if expr(exists(memberships, user_id == ^actor(:id)))
    end

    policy action_type(:update) do
      authorize_if relates_to_actor_via(:owner)
      authorize_if expr(exists(memberships, user_id == ^actor(:id) and role in [:owner, :admin]))
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true

      constraints min_length: 1,
                  max_length: 100,
                  trim?: true
    end

    attribute :slug, :string do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :owner, Citadel.Accounts.User do
      allow_nil? false
      attribute_writable? true
      public? true
    end

    has_many :memberships, Citadel.Accounts.OrganizationMembership do
      public? true
    end

    many_to_many :members, Citadel.Accounts.User do
      through Citadel.Accounts.OrganizationMembership
      source_attribute_on_join_resource :organization_id
      destination_attribute_on_join_resource :user_id
      public? true
    end

    has_many :workspaces, Citadel.Accounts.Workspace do
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
