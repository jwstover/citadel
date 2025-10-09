defmodule Citadel.Accounts.User do
  @moduledoc """
  The User resource for authentication and authorization.
  """
  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end
    end

    tokens do
      enabled? true
      token_resource Citadel.Accounts.Token
      signing_secret Citadel.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      google do
        client_id Citadel.Secrets
        client_secret Citadel.Secrets
        redirect_uri Citadel.Secrets
      end
    end
  end

  postgres do
    table "users"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    create :register_with_google do
      description "Register or sign in a user with Google OAuth"
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      upsert? true
      upsert_identity :unique_email

      change AshAuthentication.GenerateTokenChange
      change AshAuthentication.Strategy.OAuth2.IdentityChange

      change fn changeset, _ ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        changeset
        |> Ash.Changeset.change_attributes(Map.take(user_info, ["email"]))
      end

      upsert_fields []
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_present()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
