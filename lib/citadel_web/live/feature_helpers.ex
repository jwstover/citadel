defmodule CitadelWeb.Live.FeatureHelpers do
  @moduledoc """
  Helper functions for checking feature availability in LiveViews.

  ## Usage

  In your LiveView:

      use CitadelWeb, :live_view
      import CitadelWeb.Live.FeatureHelpers

      def mount(_params, _session, socket) do
        socket =
          socket
          |> assign_feature_checks([:data_export, :api_access])

        {:ok, socket}
      end

  In your template:

      <.button :if={@features.data_export} phx-click="export">
        Export Data
      </.button>

      <div :if={!@features.api_access} class="alert">
        Upgrade to Pro to access the API
      </div>

  ## Feature Check Strategies

  This module provides multiple ways to check features:

  1. **Batch Assignment** - Check multiple features at once with `assign_feature_checks/2`
  2. **Single Check** - Check one feature with `has_feature?/2`
  3. **Tier Features** - Get all features for a tier with `assign_tier_features/2`
  """

  import Phoenix.Component, only: [assign: 3]

  alias Citadel.Billing.Plan

  @doc """
  Assigns feature availability for the current organization to socket.

  Creates an `@features` assign with a map of feature => boolean.

  ## Examples

      socket
      |> assign_feature_checks([:data_export, :api_access])

      # In template: @features.data_export => true/false

  ## Organization Resolution

  The function attempts to get the organization_id from:
  1. `socket.assigns.current_scope.organization_id` (workspace-based)
  2. `socket.assigns.current_organization.id` (organization-based)

  If no organization is found, all features default to `false`.
  """
  @spec assign_feature_checks(Phoenix.LiveView.Socket.t(), [atom()]) ::
          Phoenix.LiveView.Socket.t()
  def assign_feature_checks(socket, feature_list) when is_list(feature_list) do
    org_id = get_organization_id(socket)

    features =
      Map.new(feature_list, fn feature ->
        has_feature? =
          case org_id do
            nil ->
              false

            id ->
              case Plan.org_has_feature?(id, feature) do
                {:ok, result} -> result
                _ -> false
              end
          end

        {feature, has_feature?}
      end)

    assign(socket, :features, features)
  end

  @doc """
  Assigns all features for a tier to the socket.

  Useful for pricing/comparison pages where you need to display
  what features are available for each tier.

  ## Examples

      socket
      |> assign_tier_features(:pro)

      # In template: @tier_features => [:basic_ai, :data_export, ...]

  """
  @spec assign_tier_features(Phoenix.LiveView.Socket.t(), Plan.tier()) ::
          Phoenix.LiveView.Socket.t()
  def assign_tier_features(socket, tier) do
    features = Plan.features_for_tier(tier)
    assign(socket, :tier_features, features)
  end

  @doc """
  Checks if the current organization has a specific feature.

  Returns boolean. Useful for conditional logic in event handlers.

  ## Examples

      def handle_event("export", _, socket) do
        if has_feature?(socket, :data_export) do
          # Perform export
        else
          # Show upgrade prompt
        end
      end
  """
  @spec has_feature?(Phoenix.LiveView.Socket.t(), atom()) :: boolean()
  def has_feature?(socket, feature) do
    org_id = get_organization_id(socket)

    case org_id do
      nil ->
        false

      id ->
        case Plan.org_has_feature?(id, feature) do
          {:ok, result} -> result
          _ -> false
        end
    end
  end

  @doc """
  Gets all features available for the current organization.

  Returns a list of feature atoms.

  ## Examples

      features = current_features(socket)
      #=> [:basic_ai, :data_export, :api_access, ...]
  """
  @spec current_features(Phoenix.LiveView.Socket.t()) :: [atom()]
  def current_features(socket) do
    org_id = get_organization_id(socket)

    case org_id do
      nil ->
        []

      id ->
        case Citadel.Billing.get_subscription_by_organization(id, authorize?: false) do
          {:ok, subscription} -> Plan.features_for_tier(subscription.tier)
          _ -> []
        end
    end
  end

  # Private Functions

  defp get_organization_id(socket) do
    # Try to get org_id from current_scope (workspace)
    case socket.assigns do
      %{current_scope: %{organization_id: org_id}} when not is_nil(org_id) ->
        org_id

      %{current_organization: %{id: org_id}} ->
        org_id

      _ ->
        nil
    end
  end
end
