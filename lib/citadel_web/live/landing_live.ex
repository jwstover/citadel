defmodule CitadelWeb.LandingLive do
  @moduledoc false

  use CitadelWeb, :live_view

  on_mount {CitadelWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI-Powered Task Management")
     |> assign(
       :meta_description,
       "Create tasks with natural language, let AI organize your work into actionable subtasks, and collaborate seamlessly with your team."
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.marketing flash={@flash} current_user={@current_user}>
      <.hero_section current_user={@current_user} />
      <.features_section />
      <.pricing_section />
      <.footer_section />
    </Layouts.marketing>
    """
  end

  defp hero_section(assigns) do
    ~H"""
    <section class="relative min-h-[90vh] flex items-center justify-center overflow-hidden">
      <div class="absolute inset-0 overflow-hidden">
        <div class="absolute top-1/4 left-1/2 -translate-x-1/2 w-[1000px] h-[1000px]">
          <div class="absolute inset-0 bg-gradient-to-r from-primary/10 via-accent/5 to-primary/10 rounded-full blur-3xl animate-pulse" />
        </div>
        <div class="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-base-300 to-transparent" />
      </div>

      <div class="absolute inset-0 overflow-hidden pointer-events-none">
        <svg class="absolute top-20 left-10 w-64 h-64 text-base-300/30" viewBox="0 0 100 100">
          <polygon
            points="50,5 95,25 95,75 50,95 5,75 5,25"
            fill="none"
            stroke="currentColor"
            stroke-width="0.5"
          />
        </svg>
        <svg class="absolute bottom-20 right-10 w-48 h-48 text-base-300/20" viewBox="0 0 100 100">
          <rect
            x="10"
            y="10"
            width="80"
            height="80"
            fill="none"
            stroke="currentColor"
            stroke-width="0.5"
            transform="rotate(15 50 50)"
          />
        </svg>
        <svg class="absolute top-1/3 right-1/4 w-32 h-32 text-primary/10" viewBox="0 0 100 100">
          <circle
            cx="50"
            cy="50"
            r="45"
            fill="none"
            stroke="currentColor"
            stroke-width="1"
            stroke-dasharray="10 5"
          />
        </svg>
      </div>

      <div class="container mx-auto px-6 lg:px-8 relative z-10">
        <div class="max-w-4xl mx-auto text-center">
          <div class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-base-200/80 border border-base-300/50 text-sm text-base-content/70 mb-8 backdrop-blur-sm">
            <span class="relative flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75">
              </span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
            </span>
            AI-powered productivity
          </div>

          <h1 class="text-5xl sm:text-6xl lg:text-7xl font-bold tracking-tight mb-6 leading-[1.1]">
            <span class="block">Task management</span>
            <span class="block bg-gradient-to-r from-primary via-accent to-primary bg-clip-text text-transparent bg-[length:200%_auto] animate-gradient">
              powered by AI
            </span>
          </h1>

          <p class="text-lg sm:text-xl text-base-content/60 max-w-2xl mx-auto mb-10 leading-relaxed">
            Create tasks with natural language, let AI organize your work into actionable subtasks,
            and collaborate seamlessly with your team.
          </p>

          <div class="flex flex-col sm:flex-row gap-4 justify-center items-center">
            <%= if @current_user do %>
              <.link
                navigate={~p"/dashboard"}
                class="group relative inline-flex items-center gap-2 px-8 py-4 bg-primary text-primary-content font-semibold rounded-xl shadow-2xl shadow-primary/25 hover:shadow-primary/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200"
              >
                <span>Go to Dashboard</span>
                <.icon
                  name="hero-arrow-right"
                  class="size-5 group-hover:translate-x-1 transition-transform"
                />
              </.link>
            <% else %>
              <.link
                navigate={~p"/register"}
                class="group relative inline-flex items-center gap-2 px-8 py-4 bg-primary text-primary-content font-semibold rounded-xl shadow-2xl shadow-primary/25 hover:shadow-primary/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200"
              >
                <span>Get Started Free</span>
                <.icon
                  name="hero-arrow-right"
                  class="size-5 group-hover:translate-x-1 transition-transform"
                />
              </.link>
              <a
                href="#features"
                class="inline-flex items-center gap-2 px-8 py-4 text-base-content/70 font-medium hover:text-base-content transition-colors"
              >
                <span>Learn more</span>
                <.icon name="hero-chevron-down" class="size-5 animate-bounce" />
              </a>
            <% end %>
          </div>
        </div>

        <div class="mt-20 flex justify-center gap-8 text-base-content/40 text-sm">
          <div class="flex items-center gap-2">
            <.icon name="hero-check-circle" class="size-5 text-success" />
            <span>Free forever plan</span>
          </div>
          <div class="hidden sm:flex items-center gap-2">
            <.icon name="hero-check-circle" class="size-5 text-success" />
            <span>No credit card required</span>
          </div>
          <div class="hidden md:flex items-center gap-2">
            <.icon name="hero-check-circle" class="size-5 text-success" />
            <span>Cancel anytime</span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp features_section(assigns) do
    features = [
      %{
        icon: "hero-sparkles",
        title: "AI-Powered Organization",
        description:
          "Let artificial intelligence analyze your tasks and automatically organize them into logical groups and priorities."
      },
      %{
        icon: "hero-chat-bubble-left-right",
        title: "Natural Language Input",
        description:
          "Simply describe what you need to do in plain English. Our AI transforms your words into structured, actionable tasks."
      },
      %{
        icon: "hero-user-group",
        title: "Team Workspaces",
        description:
          "Create shared workspaces where your team can collaborate on tasks, track progress, and stay aligned on goals."
      },
      %{
        icon: "hero-queue-list",
        title: "Smart Subtasks",
        description:
          "Complex projects are automatically broken down into manageable subtasks with clear hierarchies and dependencies."
      },
      %{
        icon: "hero-cpu-chip",
        title: "AI Chat Assistant",
        description:
          "Have natural conversations about your tasks. Ask questions, get suggestions, and let AI help you plan your work."
      },
      %{
        icon: "hero-bolt",
        title: "Lightning Fast",
        description:
          "Built for speed with real-time updates. Your changes sync instantly across all devices and team members."
      }
    ]

    assigns = assign(assigns, :features, features)

    ~H"""
    <section id="features" class="py-24 lg:py-32 relative">
      <div class="absolute inset-0 bg-gradient-to-b from-transparent via-base-200/50 to-transparent pointer-events-none" />

      <div class="container mx-auto px-6 lg:px-8 relative">
        <div class="text-center max-w-3xl mx-auto mb-16 lg:mb-20">
          <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-accent/10 text-accent text-sm font-medium mb-6">
            <.icon name="hero-cube-transparent" class="size-4" /> Features
          </div>
          <h2 class="text-4xl lg:text-5xl font-bold tracking-tight mb-6">
            Everything you need to <span class="text-primary">get things done</span>
          </h2>
          <p class="text-lg text-base-content/60">
            Powerful features designed to help you manage tasks efficiently with the intelligence of AI.
          </p>
        </div>

        <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-6 lg:gap-8">
          <div
            :for={{feature, idx} <- Enum.with_index(@features)}
            class="group relative"
            style={"animation-delay: #{idx * 100}ms"}
          >
            <div class="absolute inset-0 bg-gradient-to-br from-primary/5 to-accent/5 rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-500 blur-xl" />
            <div class="relative h-full p-8 rounded-2xl border border-base-300/50 bg-base-100/80 backdrop-blur-sm hover:border-primary/30 transition-all duration-300 hover:-translate-y-1">
              <div class="inline-flex items-center justify-center w-12 h-12 rounded-xl bg-gradient-to-br from-primary/20 to-accent/10 text-primary mb-6 group-hover:scale-110 transition-transform duration-300">
                <.icon name={feature.icon} class="size-6" />
              </div>
              <h3 class="text-xl font-semibold mb-3 group-hover:text-primary transition-colors">
                {feature.title}
              </h3>
              <p class="text-base-content/60 leading-relaxed">
                {feature.description}
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp pricing_section(assigns) do
    plans = [
      %{
        name: "Free",
        price: "$0",
        period: "forever",
        description: "Perfect for individuals getting started with AI-powered task management.",
        features: [
          "Up to 3 workspaces",
          "Unlimited tasks",
          "Basic AI task creation",
          "Sub-task hierarchies",
          "Email support"
        ],
        cta: "Get Started",
        highlighted: false
      },
      %{
        name: "Pro",
        price: "$12",
        period: "per month",
        description: "For power users and teams who need advanced AI features and collaboration.",
        features: [
          "Unlimited workspaces",
          "Advanced AI features",
          "Priority AI processing",
          "Team collaboration",
          "API access",
          "Custom integrations",
          "Priority support"
        ],
        cta: "Start Free Trial",
        highlighted: true
      }
    ]

    assigns = assign(assigns, :plans, plans)

    ~H"""
    <section id="pricing" class="py-24 lg:py-32 relative">
      <div class="container mx-auto px-6 lg:px-8">
        <div class="text-center max-w-3xl mx-auto mb-16 lg:mb-20">
          <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-success/10 text-success text-sm font-medium mb-6">
            <.icon name="hero-currency-dollar" class="size-4" /> Pricing
          </div>
          <h2 class="text-4xl lg:text-5xl font-bold tracking-tight mb-6">
            Simple, transparent <span class="text-primary">pricing</span>
          </h2>
          <p class="text-lg text-base-content/60">
            Start for free, upgrade when you need more. No hidden fees, no surprises.
          </p>
        </div>

        <div class="grid md:grid-cols-2 gap-8 max-w-4xl mx-auto">
          <div
            :for={plan <- @plans}
            class={[
              "relative group rounded-2xl transition-all duration-300",
              if(plan.highlighted,
                do: "md:-mt-4 md:mb-4",
                else: ""
              )
            ]}
          >
            <div
              :if={plan.highlighted}
              class="absolute -inset-px bg-gradient-to-br from-primary via-accent to-primary rounded-2xl opacity-75 blur-sm group-hover:opacity-100 transition-opacity"
            />
            <div
              :if={plan.highlighted}
              class="absolute -top-4 left-1/2 -translate-x-1/2 px-4 py-1 bg-primary text-primary-content text-sm font-medium rounded-full shadow-lg"
            >
              Most Popular
            </div>
            <div class={[
              "relative h-full p-8 rounded-2xl border backdrop-blur-sm",
              if(plan.highlighted,
                do: "bg-base-100 border-transparent",
                else: "bg-base-100/80 border-base-300/50 hover:border-base-300"
              )
            ]}>
              <div class="mb-8">
                <h3 class="text-2xl font-bold mb-2">{plan.name}</h3>
                <p class="text-base-content/60 text-sm">{plan.description}</p>
              </div>

              <div class="mb-8">
                <span class="text-5xl font-bold">{plan.price}</span>
                <span class="text-base-content/60 ml-2">/{plan.period}</span>
              </div>

              <ul class="space-y-4 mb-8">
                <li :for={feature <- plan.features} class="flex items-start gap-3">
                  <.icon name="hero-check" class="size-5 text-success flex-shrink-0 mt-0.5" />
                  <span class="text-base-content/80">{feature}</span>
                </li>
              </ul>

              <.link
                navigate={~p"/register"}
                class={[
                  "block w-full py-3 px-6 text-center font-semibold rounded-xl transition-all duration-200",
                  if(plan.highlighted,
                    do:
                      "bg-primary text-primary-content shadow-lg shadow-primary/25 hover:shadow-primary/40 hover:scale-[1.02] active:scale-[0.98]",
                    else: "bg-base-200 text-base-content hover:bg-base-300 border border-base-300"
                  )
                ]}
              >
                {plan.cta}
              </.link>
            </div>
          </div>
        </div>

        <p class="text-center text-base-content/50 text-sm mt-8">
          All plans include a 14-day free trial of Pro features. No credit card required.
        </p>
      </div>
    </section>
    """
  end

  defp footer_section(assigns) do
    ~H"""
    <footer class="border-t border-base-300/50 bg-base-200/30">
      <div class="container mx-auto px-6 lg:px-8 py-12 lg:py-16">
        <div class="flex flex-col lg:flex-row justify-between items-center gap-8">
          <div class="flex items-center gap-3">
            <div class="btn btn-primary btn-square btn-sm pointer-events-none">
              <.icon name="hero-building-library" class="size-4" />
            </div>
            <span class="text-xl font-bold">Citadel</span>
          </div>

          <nav class="flex flex-wrap justify-center gap-8 text-sm">
            <a
              href="#features"
              class="text-base-content/60 hover:text-base-content transition-colors"
            >
              Features
            </a>
            <a
              href="#pricing"
              class="text-base-content/60 hover:text-base-content transition-colors"
            >
              Pricing
            </a>
            <a href="/terms" class="text-base-content/60 hover:text-base-content transition-colors">
              Terms of Service
            </a>
            <a
              href="/privacy"
              class="text-base-content/60 hover:text-base-content transition-colors"
            >
              Privacy Policy
            </a>
            <a
              href="mailto:support@citadel.app"
              class="text-base-content/60 hover:text-base-content transition-colors"
            >
              Contact
            </a>
          </nav>

          <div class="text-base-content/50 text-sm">
            &copy; {DateTime.utc_now().year} Citadel. All rights reserved.
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
