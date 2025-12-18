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

      confirmation :confirm_new_user do
        monitor_fields [:email]
        confirm_on_create? true
        confirm_on_update? false
        require_interaction? true
        confirmed_at_field :confirmed_at

        auto_confirm_actions [
          :sign_in_with_magic_link,
          :reset_password_with_token,
          :register_with_google
        ]

        sender Citadel.Accounts.User.Senders.SendNewUserConfirmationEmail
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

      api_key :api_key do
        api_key_relationship :valid_api_keys
        api_key_hash_attribute :api_key_hash
      end

      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider

        resettable do
          sender Citadel.Accounts.User.Senders.SendPasswordResetEmail
          # these configurations will be the default in a future release
          password_reset_action_name :reset_password_with_token
          request_password_reset_action_name :request_password_reset_token
        end
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
        |> Ash.Changeset.change_attributes(Map.take(user_info, ["email", "name"]))
      end

      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, user ->
          existing_orgs = Citadel.Accounts.list_organizations!(actor: user)

          if Enum.empty?(existing_orgs) do
            # Create a personal organization for the user
            organization =
              Citadel.Accounts.create_organization!(
                "Personal",
                actor: user
              )

            # Create a personal workspace under that organization
            _workspace =
              Citadel.Accounts.Workspace
              |> Ash.Changeset.for_create(
                :create,
                %{name: "Personal", organization_id: organization.id},
                actor: user
              )
              |> Ash.create!()
          end

          {:ok, user}
        end)
      end

      upsert_fields []
    end

    read :sign_in_with_api_key do
      argument :api_key, :string, allow_nil?: false
      prepare AshAuthentication.Strategy.ApiKey.SignInPreparation
    end

    update :change_password do
      # Use this action to allow users to change their password by providing
      # their current password and a new password.

      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      # validates password complexity (8+ chars, uppercase, lowercase, number)
      validate Citadel.Accounts.User.Validations.PasswordComplexity

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    update :set_password do
      description "Set a password for an OAuth-only account"

      require_atomic? false
      accept []

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      # Only allow if user doesn't have a password yet
      validate fn changeset, _context ->
        user = changeset.data

        if user.hashed_password do
          {:error, message: "You already have a password. Use 'Change Password' instead."}
        else
          :ok
        end
      end

      # validates password complexity (8+ chars, uppercase, lowercase, number)
      validate Citadel.Accounts.User.Validations.PasswordComplexity

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # validates the provided email and password and generates a token
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      # In the generated sign in components, we validate the
      # email and password directly in the LiveView
      # and generate a short-lived token that can be used to sign in over
      # a standard controller action, exchanging it for a standard token.
      # This action performs that exchange. If you do not use the generated
      # liveviews, you may remove this action, and set
      # `sign_in_tokens_enabled? false` in the password strategy.

      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      # validates the provided sign in token and generates a token
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Register a new user with a email and password."

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # Sets the email from the argument
      change set_attribute(:email, arg(:email))

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      # validates password complexity (8+ chars, uppercase, lowercase, number)
      validate Citadel.Accounts.User.Validations.PasswordComplexity

      # Create a personal organization and workspace for new users
      change fn changeset, _context ->
        Ash.Changeset.after_action(changeset, fn _changeset, user ->
          existing_orgs = Citadel.Accounts.list_organizations!(actor: user)

          if Enum.empty?(existing_orgs) do
            # Create a personal organization for the user
            organization =
              Citadel.Accounts.create_organization!(
                "Personal",
                actor: user
              )

            # Create a personal workspace under that organization
            _workspace =
              Citadel.Accounts.Workspace
              |> Ash.Changeset.for_create(
                :create,
                %{name: "Personal", organization_id: organization.id},
                actor: user
              )
              |> Ash.create!()
          end

          {:ok, user}
        end)
      end

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    action :request_password_reset_token do
      description "Send password reset instructions to a user if they exist."

      argument :email, :ci_string do
        allow_nil? false
      end

      # creates a reset token and invokes the relevant senders
      run {AshAuthentication.Strategy.Password.RequestPasswordReset, action: :get_by_email}
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get_by :email
    end

    update :reset_password_with_token do
      require_atomic? false

      argument :reset_token, :string do
        allow_nil? false
        sensitive? true
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # validates the provided reset token
      validate AshAuthentication.Strategy.Password.ResetTokenValidation

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      # validates password complexity (8+ chars, uppercase, lowercase, number)
      validate Citadel.Accounts.User.Validations.PasswordComplexity

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if actor_present()
    end

    policy action(:set_password) do
      authorize_if expr(id == ^actor(:id))
    end

    policy action(:change_password) do
      authorize_if expr(id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :name, :string, public?: true

    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end

    attribute :confirmed_at, :utc_datetime_usec
  end

  relationships do
    has_many :valid_api_keys, Citadel.Accounts.ApiKey do
      filter expr(valid)
    end

    has_many :organization_memberships, Citadel.Accounts.OrganizationMembership do
      public? true
    end

    many_to_many :organizations, Citadel.Accounts.Organization do
      through Citadel.Accounts.OrganizationMembership
      source_attribute_on_join_resource :user_id
      destination_attribute_on_join_resource :organization_id
      public? true
    end
  end

  identities do
    identity :unique_email, [:email]
  end
end
