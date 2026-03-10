defmodule CitadelWeb.BillingLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

  import CitadelWeb.BillingLive.PricingSection
  import CitadelWeb.Live.FeatureHelpers

  alias Citadel.Accounts
  alias Citadel.Billing
  alias Citadel.Billing.Plan

  on_mount {CitadelWeb.LiveUserAuth, :live_user_required}
  on_mount {CitadelWeb.LiveUserAuth, :load_workspace}

  def mount(_params, _session, socket) do
    organization_id = socket.assigns.current_workspace.organization_id
    user = socket.assigns.current_user

    organization =
      Accounts.get_organization_by_id!(organization_id, actor: user, load: [:memberships])

    subscription = get_subscription(organization_id, user)
    balance = get_balance(organization_id, user)
    memberships = get_memberships(organization_id, user)
    plan = Plan.get(subscription.tier)

    {:ok,
     socket
     |> assign_feature_checks([:ai_chat])
     |> assign(:organization, organization)
     |> assign(:subscription, subscription)
     |> assign(:balance, balance)
     |> assign(:memberships, memberships)
     |> assign(:plan, plan)
     |> assign(:billing_period, :monthly)}
  end

  def handle_params(params, _uri, socket) do
    socket =
      case Map.get(params, "checkout") do
        "success" ->
          put_flash(socket, :info, "Successfully upgraded! Your subscription is now active.")

        "cancelled" ->
          put_flash(socket, :info, "Checkout cancelled.")

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("toggle_billing_period", %{"period" => period}, socket) do
    billing_period = if period == "annual", do: :annual, else: :monthly
    {:noreply, assign(socket, :billing_period, billing_period)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_workspace={@current_workspace} workspaces={@workspaces}>
      <div class="relative h-full overflow-hidden">
        <div class="h-full overflow-auto p-6">
          <h1 class="text-2xl mb-4">Billing</h1>

          <div class="space-y-6">
            <.card class="bg-base-200 border-base-300">
              <:title>Subscription</:title>

              <div class="grid grid-cols-2 gap-4">
                <div>
                  <span class="text-sm text-base-content/70">Plan</span>
                  <p class="font-medium">
                    {@plan.name}
                    <span :if={@subscription.billing_period} class="text-sm text-base-content/70">
                      ({format_billing_period(@subscription.billing_period)})
                    </span>
                  </p>
                </div>
                <div>
                  <span class="text-sm text-base-content/70">Status</span>
                  <p>
                    <span class={[
                      "badge",
                      @subscription.status == :active && "badge-success",
                      @subscription.status == :past_due && "badge-warning",
                      @subscription.status == :canceled && "badge-error"
                    ]}>
                      {format_status(@subscription.status)}
                    </span>
                  </p>
                </div>
                <div :if={@subscription.current_period_end}>
                  <span class="text-sm text-base-content/70">Renewal Date</span>
                  <p class="font-medium">{format_date(@subscription.current_period_end)}</p>
                </div>
                <div>
                  <span class="text-sm text-base-content/70">Seats</span>
                  <p class="font-medium">{length(@memberships)} / {@plan.max_members}</p>
                </div>
              </div>

              <div :if={@subscription.tier != :free} class="mt-4">
                <.link href={~p"/billing/portal"} class="btn btn-ghost btn-sm">
                  <.icon name="hero-credit-card" class="h-4 w-4" /> Manage Billing
                </.link>
              </div>
            </.card>

            <.card :if={@features.ai_chat} class="bg-base-200 border-base-300">
              <:title>Credits</:title>

              <div class="space-y-2">
                <div class="flex justify-between text-sm">
                  <span>
                    {format_number(@balance)} / {format_number(@plan.monthly_credits)} remaining
                  </span>
                  <span>{calculate_usage_percent(@balance, @plan.monthly_credits)}% used</span>
                </div>
                <progress
                  class={[
                    "progress w-full",
                    progress_color(@balance, @plan.monthly_credits)
                  ]}
                  value={@plan.monthly_credits - @balance}
                  max={@plan.monthly_credits}
                >
                </progress>
                <p :if={@subscription.current_period_end} class="text-xs text-base-content/70">
                  Resets: {format_date(@subscription.current_period_end)}
                </p>
              </div>
            </.card>
          </div>

          <.pricing_section
            subscription={@subscription}
            billing_period={@billing_period}
            member_count={length(@memberships)}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp get_subscription(organization_id, user) do
    case Billing.get_subscription_by_organization(organization_id, actor: user) do
      {:ok, subscription} -> subscription
      {:error, _} -> %{tier: :free, status: :active, billing_period: nil, current_period_end: nil}
    end
  end

  defp get_balance(organization_id, user) do
    case Billing.get_organization_balance(organization_id, actor: user) do
      {:ok, balance} when is_integer(balance) -> balance
      _ -> 0
    end
  end

  defp get_memberships(organization_id, user) do
    Accounts.list_organization_members!(
      query: [filter: [organization_id: organization_id]],
      actor: user,
      load: [:user]
    )
  end

  defp format_billing_period(:monthly), do: "Monthly"
  defp format_billing_period(:annual), do: "Annual"
  defp format_billing_period(_), do: ""

  defp format_status(:active), do: "Active"
  defp format_status(:past_due), do: "Past Due"
  defp format_status(:canceled), do: "Canceled"
  defp format_status(_), do: "Unknown"

  defp format_date(nil), do: "N/A"

  defp format_date(datetime) do
    Calendar.strftime(datetime, "%b %d, %Y")
  end

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(_), do: "0"

  defp calculate_usage_percent(balance, total) when total > 0 do
    used = total - balance
    round(used / total * 100)
  end

  defp calculate_usage_percent(_, _), do: 0

  defp progress_color(balance, total) do
    percent = calculate_usage_percent(balance, total)

    cond do
      percent >= 90 -> "progress-error"
      percent >= 75 -> "progress-warning"
      true -> "progress-success"
    end
  end
end
