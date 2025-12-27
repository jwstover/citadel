defmodule CitadelWeb.BillingController do
  @moduledoc """
  Controller for Stripe billing operations: checkout and billing portal.
  """

  use CitadelWeb, :controller

  alias Citadel.Accounts
  alias Citadel.Billing
  alias Citadel.Billing.Stripe, as: StripeService

  def create_checkout(conn, %{"billing_period" => billing_period}) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, workspace} <- get_current_workspace(conn, user),
         {:ok, subscription} <- get_subscription(workspace.organization_id, user),
         {:ok, seat_count} <- get_member_count(workspace.organization_id, user) do
      success_url = url(conn, ~p"/preferences?checkout=success")
      cancel_url = url(conn, ~p"/preferences?checkout=cancelled")

      case StripeService.create_checkout_session(
             subscription,
             :pro,
             String.to_existing_atom(billing_period),
             seat_count,
             success_url,
             cancel_url
           ) do
        {:ok, checkout_url} ->
          redirect(conn, external: checkout_url)

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Failed to create checkout session")
          |> redirect(to: ~p"/preferences")
      end
    else
      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "You must be logged in")
        |> redirect(to: ~p"/sign-in")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to initiate checkout")
        |> redirect(to: ~p"/preferences")
    end
  end

  def billing_portal(conn, _params) do
    with {:ok, user} <- get_current_user(conn),
         {:ok, workspace} <- get_current_workspace(conn, user),
         {:ok, subscription} <- get_subscription(workspace.organization_id, user) do
      return_url = url(conn, ~p"/preferences")

      case StripeService.create_portal_session(subscription.stripe_customer_id, return_url) do
        {:ok, portal_url} ->
          redirect(conn, external: portal_url)

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Failed to access billing portal")
          |> redirect(to: ~p"/preferences")
      end
    else
      {:error, :unauthorized} ->
        conn
        |> put_flash(:error, "You must be logged in")
        |> redirect(to: ~p"/sign-in")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Failed to access billing portal")
        |> redirect(to: ~p"/preferences")
    end
  end

  defp get_current_user(conn) do
    case conn.assigns[:current_user] do
      nil -> {:error, :unauthorized}
      user -> {:ok, user}
    end
  end

  defp get_current_workspace(conn, user) do
    workspace_id = get_session(conn, "current_workspace_id")

    if workspace_id do
      case Accounts.get_workspace_by_id(workspace_id, actor: user, load: [:organization]) do
        {:ok, workspace} -> {:ok, workspace}
        {:error, _} -> {:error, :workspace_not_found}
      end
    else
      {:error, :no_workspace_selected}
    end
  end

  defp get_subscription(organization_id, user) do
    case Billing.get_subscription_by_organization(organization_id, actor: user) do
      {:ok, subscription} -> {:ok, subscription}
      {:error, _} -> {:error, :subscription_not_found}
    end
  end

  defp get_member_count(organization_id, user) do
    case Accounts.list_organization_members(
           query: [filter: [organization_id: organization_id]],
           actor: user
         ) do
      {:ok, memberships} -> {:ok, length(memberships)}
      {:error, _} -> {:error, :failed_to_count_members}
    end
  end
end
