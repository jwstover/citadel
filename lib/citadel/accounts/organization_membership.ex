defmodule Citadel.Accounts.OrganizationMembership do
  @moduledoc """
  Represents a user's membership in an organization.
  Users must be members of an organization before they can be added to any of its workspaces.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "organization_memberships"
    repo Citadel.Repo

    references do
      reference :organization, on_delete: :delete
      reference :user, on_delete: :delete
    end
  end

  code_interface do
    define :join, action: :join
    define :list, action: :read
    define :update_role, action: :update_role
    define :leave, action: :leave
  end

  actions do
    defaults [:read]

    create :join do
      accept []

      argument :organization_id, :uuid do
        allow_nil? false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      argument :role, Citadel.Accounts.OrganizationMembership.Types.Role do
        allow_nil? false
        default :member
      end

      change fn changeset, _ ->
        changeset
        |> Ash.Changeset.force_change_attribute(
          :organization_id,
          Ash.Changeset.get_argument(changeset, :organization_id)
        )
        |> Ash.Changeset.force_change_attribute(
          :user_id,
          Ash.Changeset.get_argument(changeset, :user_id)
        )
        |> Ash.Changeset.force_change_attribute(
          :role,
          Ash.Changeset.get_argument(changeset, :role)
        )
      end

      change Citadel.Accounts.OrganizationMembership.Changes.EnqueueSeatSync
    end

    update :update_role do
      accept [:role]
    end

    destroy :leave do
      require_atomic? false
      validate Citadel.Accounts.OrganizationMembership.Validations.PreventOwnerLeaving
      change Citadel.Accounts.OrganizationMembership.Changes.EnqueueSeatSync
    end
  end

  policies do
    policy action_type(:create) do
      forbid_unless Citadel.Billing.Checks.WithinMemberLimit
      authorize_if Citadel.Accounts.Checks.OrganizationAdminOrOwner
    end

    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
      authorize_if expr(organization.owner_id == ^actor(:id))
      authorize_if expr(exists(organization.memberships, user_id == ^actor(:id)))
    end

    policy action_type(:update) do
      authorize_if expr(organization.owner_id == ^actor(:id))

      authorize_if expr(
                     exists(
                       organization.memberships,
                       user_id == ^actor(:id) and role in [:owner, :admin]
                     )
                   )
    end

    policy action_type(:destroy) do
      authorize_if expr(organization.owner_id == ^actor(:id))
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :role, Citadel.Accounts.OrganizationMembership.Types.Role do
      allow_nil? false
      default :member
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Citadel.Accounts.User do
      primary_key? true
      allow_nil? false
      attribute_writable? true
      public? true
    end

    belongs_to :organization, Citadel.Accounts.Organization do
      primary_key? true
      allow_nil? false
      attribute_writable? true
      public? true
    end
  end

  identities do
    identity :unique_membership, [:user_id, :organization_id]
  end
end
