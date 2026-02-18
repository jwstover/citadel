defmodule CitadelWeb.BillingLive.Index do
  @moduledoc false

  use CitadelWeb, :live_view

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
     |> assign(:plan, plan)}
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

              <div class="mt-4">
                <%= if @subscription.tier == :free do %>
                  <div class="bg-base-300 rounded-lg p-6 border border-base-content/10">
                    <div class="text-center mb-6">
                      <h4 class="text-xl font-bold mb-2">Upgrade to Pro</h4>
                      <p class="text-sm text-base-content/70">
                        Get more credits, team members, and workspaces
                      </p>
                    </div>

                    <div class="grid grid-cols-3 gap-4 mb-6">
                      <div class="text-center p-3 bg-base-200 rounded-lg">
                        <div class="text-2xl font-bold text-accent">
                          {Plan.monthly_credits(:pro) |> div(1000)}k
                        </div>
                        <div class="text-xs text-base-content/60 uppercase tracking-wide mt-1">
                          Credits
                        </div>
                      </div>
                      <div class="text-center p-3 bg-base-200 rounded-lg">
                        <div class="text-2xl font-bold text-accent">{Plan.max_members(:pro)}</div>
                        <div class="text-xs text-base-content/60 uppercase tracking-wide mt-1">
                          Members
                        </div>
                      </div>
                      <div class="text-center p-3 bg-base-200 rounded-lg">
                        <div class="text-2xl font-bold text-accent">{Plan.max_workspaces(:pro)}</div>
                        <div class="text-xs text-base-content/60 uppercase tracking-wide mt-1">
                          Workspaces
                        </div>
                      </div>
                    </div>

                    {render_pricing_options(assigns)}
                  </div>
                <% else %>
                  <.link href={~p"/billing/portal"} class="btn btn-ghost btn-sm">
                    <.icon name="hero-credit-card" class="h-4 w-4" /> Manage Billing
                  </.link>
                <% end %>
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
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp render_pricing_options(assigns) do
    member_count = length(assigns.memberships)

    assigns =
      if member_count == 1 do
        assign(assigns, :pricing_type, :single)
      else
        additional_members = max(member_count - 1, 0)

        base_monthly = Plan.base_price_cents(:pro, :monthly) |> div(100)
        per_seat_monthly = Plan.per_member_price_cents(:pro, :monthly) |> div(100)
        total_monthly = base_monthly + additional_members * per_seat_monthly

        base_annual = Plan.base_price_cents(:pro, :annual) |> div(100)
        per_seat_annual = Plan.per_member_price_cents(:pro, :annual) |> div(100)
        total_annual = base_annual + additional_members * per_seat_annual
        monthly_equivalent = div(total_annual, 12)

        assigns
        |> assign(:pricing_type, :multi)
        |> assign(:additional_members, additional_members)
        |> assign(:base_monthly, base_monthly)
        |> assign(:per_seat_monthly, per_seat_monthly)
        |> assign(:total_monthly, total_monthly)
        |> assign(:base_annual, base_annual)
        |> assign(:per_seat_annual, per_seat_annual)
        |> assign(:total_annual, total_annual)
        |> assign(:monthly_equivalent, monthly_equivalent)
      end

    ~H"""
    <%= if @pricing_type == :single do %>
      <div class="grid sm:grid-cols-2 gap-3">
        <form method="post" action={~p"/billing/checkout"} class="contents">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="billing_period" value="monthly" />
          <button
            type="submit"
            class="border border-base-content/20 rounded-lg p-4 hover:border-base-content/40 transition-colors cursor-pointer text-left w-full"
          >
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Monthly</div>
            <div class="text-3xl font-bold mb-1">
              ${Plan.base_price_cents(:pro, :monthly) |> div(100)}
            </div>
            <div class="text-xs text-base-content/60 mb-4">per month</div>
            <div class="btn btn-ghost btn-sm w-full pointer-events-none">Choose Monthly</div>
          </button>
        </form>

        <form method="post" action={~p"/billing/checkout"} class="contents">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="billing_period" value="annual" />
          <button
            type="submit"
            class="border-2 border-primary rounded-lg p-4 relative bg-primary/5 hover:bg-primary/10 transition-colors cursor-pointer text-left w-full"
          >
            <div class="absolute -top-2 right-4 bg-primary text-primary-content text-xs font-bold px-2 py-0.5 rounded">
              SAVE 16%
            </div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Annual</div>
            <div class="text-3xl font-bold mb-1">
              ${Plan.base_price_cents(:pro, :annual) |> div(100)}
            </div>
            <div class="text-xs text-base-content/60 mb-4">per year (≈ $16/mo)</div>
            <div class="btn btn-primary btn-sm w-full pointer-events-none">Choose Annual</div>
          </button>
        </form>
      </div>
    <% else %>
      <div class="grid sm:grid-cols-2 gap-3">
        <form method="post" action={~p"/billing/checkout"} class="contents">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="billing_period" value="monthly" />
          <button
            type="submit"
            class="border border-base-content/20 rounded-lg p-4 hover:border-base-content/40 transition-colors cursor-pointer text-left w-full"
          >
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Monthly</div>
            <div class="text-3xl font-bold mb-1">${@total_monthly}</div>
            <div class="text-xs text-base-content/60 mb-3">per month</div>
            <div class="text-xs text-base-content/60 mb-4 p-2 bg-base-100 rounded">
              ${@base_monthly} base
              <%= if @additional_members > 0 do %>
                + ${@per_seat_monthly * @additional_members} for {@additional_members} {if @additional_members ==
                                                                                             1,
                                                                                           do:
                                                                                             "member",
                                                                                           else:
                                                                                             "members"}
              <% end %>
            </div>
            <div class="btn btn-ghost btn-sm w-full pointer-events-none">Choose Monthly</div>
          </button>
        </form>

        <form method="post" action={~p"/billing/checkout"} class="contents">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <input type="hidden" name="billing_period" value="annual" />
          <button
            type="submit"
            class="border-2 border-primary rounded-lg p-4 relative bg-primary/5 hover:bg-primary/10 transition-colors cursor-pointer text-left w-full"
          >
            <div class="absolute -top-2 right-4 bg-primary text-primary-content text-xs font-bold px-2 py-0.5 rounded">
              BEST VALUE
            </div>
            <div class="text-xs text-base-content/60 uppercase tracking-wide mb-1">Annual</div>
            <div class="text-3xl font-bold mb-1">${@total_annual}</div>
            <div class="text-xs text-base-content/60 mb-3">
              per year (≈ ${@monthly_equivalent}/mo)
            </div>
            <div class="text-xs text-base-content/60 mb-4 p-2 bg-base-100 rounded">
              ${@base_annual} base
              <%= if @additional_members > 0 do %>
                + ${@per_seat_annual * @additional_members} for {@additional_members} {if @additional_members ==
                                                                                            1,
                                                                                          do:
                                                                                            "member",
                                                                                          else:
                                                                                            "members"}
              <% end %>
            </div>
            <div class="btn btn-primary btn-sm w-full pointer-events-none">Choose Annual</div>
          </button>
        </form>
      </div>
    <% end %>
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
