defmodule Citadel.Settings do
  @moduledoc """
  Domain for global application settings and feature flags.

  This domain manages system-wide configuration that affects all users
  and organizations, including feature flags that can override subscription
  tier-based feature access.
  """
  use Ash.Domain, otp_app: :citadel, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Citadel.Settings.FeatureFlag do
      define :list_feature_flags, action: :read
      define :get_feature_flag, args: [:id], action: :read, get?: true
      define :get_feature_flag_by_key, args: [:key], action: :by_key, get?: true
      define :create_feature_flag, action: :create
      define :update_feature_flag, action: :update
      define :delete_feature_flag, action: :destroy
    end
  end
end
