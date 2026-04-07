defmodule CitadelWeb.BillingLive.PricingSection do
  @moduledoc false

  use CitadelWeb, :html

  alias Citadel.Billing.Plan

  attr :subscription, :map, required: true
  attr :billing_period, :atom, required: true
  attr :member_count, :integer, required: true

  def pricing_section(assigns) do
    additional_members = max(assigns.member_count - 1, 0)

    pro_monthly_base = Plan.base_price_cents(:pro, :monthly) |> div(100)
    pro_monthly_seat = Plan.per_member_price_cents(:pro, :monthly) |> div(100)
    pro_annual_base = Plan.base_price_cents(:pro, :annual) |> div(100)
    pro_annual_seat = Plan.per_member_price_cents(:pro, :annual) |> div(100)

    assigns =
      assigns
      |> assign(
        :pro_price,
        if(assigns.billing_period == :monthly,
          do: pro_monthly_base + additional_members * pro_monthly_seat,
          else: div(pro_annual_base + additional_members * pro_annual_seat, 12)
        )
      )
      |> assign(
        :pro_price_label,
        if(assigns.billing_period == :monthly, do: "/month", else: "/month, billed annually")
      )
      |> assign(:free_features, [
        "#{Plan.monthly_credits(:free)} AI credits/month",
        "#{Plan.max_members(:free)} team member",
        "#{Plan.max_workspaces(:free)} workspace",
        "Basic AI models"
      ])
      |> assign(:pro_features, [
        "#{format_number(Plan.monthly_credits(:pro))} AI credits/month",
        "Up to #{Plan.max_members(:pro)} team members",
        "Up to #{Plan.max_workspaces(:pro)} workspaces",
        "Advanced AI models",
        "Bring your own API key",
        "Data export & bulk import",
        "API access & webhooks",
        "Priority support"
      ])

    ~H"""
    <div class="py-16 sm:py-24">
      <div class="mx-auto max-w-7xl px-6 lg:px-8">
        <div class="mx-auto max-w-4xl text-center">
          <h2 class="text-base/7 font-semibold text-indigo-400">Pricing</h2>
          <p class="mt-2 text-balance text-4xl font-semibold tracking-tight text-white sm:text-5xl">
            Pricing that grows with you
          </p>
        </div>
        <p class="mx-auto mt-6 max-w-2xl text-center text-lg font-medium text-gray-400 sm:text-xl/8">
          Choose a plan packed with the best features for AI-powered task management,
          team collaboration, and productivity.
        </p>

        <%!-- Billing Period Toggle --%>
        <div class="mt-10 flex justify-center">
          <div class="inline-flex items-center rounded-full bg-gray-800 p-1">
            <button
              type="button"
              phx-click="toggle_billing_period"
              phx-value-period="monthly"
              class={[
                "rounded-full px-4 py-2 text-sm font-semibold transition-colors",
                if(@billing_period == :monthly,
                  do: "bg-indigo-500 text-white",
                  else: "text-gray-400 hover:text-white"
                )
              ]}
            >
              Monthly
            </button>
            <button
              type="button"
              phx-click="toggle_billing_period"
              phx-value-period="annual"
              class={[
                "rounded-full px-4 py-2 text-sm font-semibold transition-colors",
                if(@billing_period == :annual,
                  do: "bg-indigo-500 text-white",
                  else: "text-gray-400 hover:text-white"
                )
              ]}
            >
              Annually
            </button>
          </div>
        </div>

        <%!-- Pricing Cards --%>
        <div class="mx-auto mt-12 grid max-w-lg grid-cols-1 gap-8 lg:max-w-none lg:grid-cols-2">
          <%!-- Free Tier Card --%>
          <div class="rounded-3xl bg-gray-800/60 p-8 ring-1 ring-gray-700 xl:p-10">
            <h3 class="text-lg/8 font-semibold text-white">Free</h3>
            <p class="mt-4 text-sm/6 text-gray-400">
              Get started with AI-powered task management at no cost.
            </p>
            <p class="mt-6 flex items-baseline gap-x-1">
              <span class="text-4xl font-semibold tracking-tight text-white">$0</span>
              <span class="text-sm/6 font-semibold text-gray-400">/month</span>
            </p>

            <%= if @subscription.tier == :free do %>
              <div class="mt-6 rounded-md bg-gray-700 px-3 py-2 text-center text-sm/6 font-semibold text-gray-300">
                Current plan
              </div>
            <% else %>
              <div class="mt-6 rounded-md bg-gray-700 px-3 py-2 text-center text-sm/6 font-semibold text-gray-400">
                Free tier
              </div>
            <% end %>

            <ul role="list" class="mt-8 space-y-3 text-sm/6 text-gray-300">
              <li :for={feature <- @free_features} class="flex gap-x-3">
                <svg
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true"
                  class="h-6 w-5 flex-none text-indigo-400"
                >
                  <path
                    d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z"
                    clip-rule="evenodd"
                    fill-rule="evenodd"
                  />
                </svg>
                {feature}
              </li>
            </ul>
          </div>

          <%!-- Pro Tier Card (Featured) --%>
          <div class="relative rounded-3xl bg-gray-800/60 p-8 ring-2 ring-indigo-500 xl:p-10">
            <div class="absolute -top-4 left-1/2 -translate-x-1/2">
              <span class="inline-flex items-center rounded-full bg-indigo-500 px-3 py-1 text-xs font-semibold text-white">
                Most popular
              </span>
            </div>

            <h3 class="text-lg/8 font-semibold text-indigo-400">Pro</h3>
            <p class="mt-4 text-sm/6 text-gray-400">
              Everything you need for serious AI-powered productivity.
            </p>
            <p class="mt-6 flex items-baseline gap-x-1">
              <span class="text-4xl font-semibold tracking-tight text-white">
                ${@pro_price}
              </span>
              <span class="text-sm/6 font-semibold text-gray-400">{@pro_price_label}</span>
            </p>

            <%= if @subscription.tier == :free do %>
              <form method="post" action={~p"/billing/checkout"}>
                <input
                  type="hidden"
                  name="_csrf_token"
                  value={Phoenix.Controller.get_csrf_token()}
                />
                <input type="hidden" name="billing_period" value={to_string(@billing_period)} />
                <button
                  type="submit"
                  class="mt-6 w-full rounded-md bg-indigo-500 px-3 py-2 text-center text-sm/6 font-semibold text-white shadow-xs hover:bg-indigo-400 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-500 transition-colors cursor-pointer"
                >
                  Upgrade to Pro
                </button>
              </form>
            <% else %>
              <.link
                href={~p"/billing/portal"}
                class="mt-6 block w-full rounded-md bg-indigo-500 px-3 py-2 text-center text-sm/6 font-semibold text-white shadow-xs hover:bg-indigo-400 transition-colors"
              >
                Manage Billing
              </.link>
            <% end %>

            <ul role="list" class="mt-8 space-y-3 text-sm/6 text-gray-300">
              <li :for={feature <- @pro_features} class="flex gap-x-3">
                <svg
                  viewBox="0 0 20 20"
                  fill="currentColor"
                  aria-hidden="true"
                  class="h-6 w-5 flex-none text-indigo-400"
                >
                  <path
                    d="M16.704 4.153a.75.75 0 0 1 .143 1.052l-8 10.5a.75.75 0 0 1-1.127.075l-4.5-4.5a.75.75 0 0 1 1.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 0 1 1.05-.143Z"
                    clip-rule="evenodd"
                    fill-rule="evenodd"
                  />
                </svg>
                {feature}
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_number(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_number(_), do: "0"
end
