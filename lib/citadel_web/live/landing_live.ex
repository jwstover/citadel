defmodule CitadelWeb.LandingLive do
  @moduledoc false

  use CitadelWeb, :live_view

  on_mount {CitadelWeb.LiveUserAuth, :live_user_optional}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Project Management for the AI Era")
     |> assign(
       :meta_description,
       "AI-native project management for developers. Turn complex features into actionable tasks. Manage everything from your coding assistant."
     )}
  end

  def render(assigns) do
    ~H"""
    <Layouts.marketing flash={@flash} current_user={@current_user}>
      <.hero_section current_user={@current_user} />
      <.problem_section />
      <.solution_section />
      <.features_section />
      <.pricing_section />
      <.cta_section />
      <.footer_section />
    </Layouts.marketing>
    """
  end

  defp hero_section(assigns) do
    ~H"""
    <section class="relative min-h-[90vh] flex items-center justify-center">
      <div class="absolute inset-0 overflow-x-clip">
        <div class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[800px] h-[800px]">
          <div class="absolute inset-0 bg-gradient-to-r from-primary/10 via-accent/5 to-primary/10 rounded-full blur-3xl" />
        </div>
        <div class="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-base-300 to-transparent" />
      </div>

      <div class="container mx-auto px-6 lg:px-8 relative z-10">
        <div class="max-w-4xl mx-auto text-center">
          <div class="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-base-200/80 border border-base-300/50 text-sm text-base-content/70 mb-8 backdrop-blur-sm">
            <span class="relative flex h-2 w-2">
              <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-success opacity-75">
              </span>
              <span class="relative inline-flex rounded-full h-2 w-2 bg-success"></span>
            </span>
            AI-native project management
          </div>

          <h1 class="text-5xl sm:text-6xl lg:text-7xl font-bold tracking-tight mb-6 leading-[1.1]">
            <span class="block">Project management</span>
            <span class="block bg-gradient-to-r from-primary via-accent to-primary bg-clip-text text-transparent">
              for the AI era
            </span>
          </h1>

          <p class="text-lg sm:text-xl text-base-content/60 max-w-2xl mx-auto mb-10 leading-relaxed">
            AI-native project management for developers. Describe what you're building—Citadel creates the plan.
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
                <span>Start Planning Free</span>
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
                <.icon name="hero-chevron-down" class="size-5" />
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
            <span>MCP integration</span>
          </div>
          <div class="hidden md:flex items-center gap-2">
            <.icon name="hero-check-circle" class="size-5 text-success" />
            <span>Works with Claude & Cursor</span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp problem_section(assigns) do
    ~H"""
    <section class="py-24 lg:py-32 relative overflow-hidden">
      <div class="absolute inset-0 pointer-events-none">
        <div class="absolute top-1/4 left-1/4 w-64 h-64 bg-error/5 rounded-full blur-3xl" />
        <div class="absolute bottom-1/4 right-1/4 w-48 h-48 bg-warning/5 rounded-full blur-3xl" />
      </div>

      <div class="container mx-auto px-6 lg:px-8 relative">
        <div class="max-w-4xl mx-auto">
          <div class="text-center mb-16">
            <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-error/10 text-error text-sm font-medium mb-6">
              <.icon name="hero-exclamation-triangle" class="size-4" /> The Problem
            </div>
            <h2 class="text-4xl lg:text-5xl font-bold tracking-tight">
              Project management <span class="text-error">wasn't built</span>
              <br class="hidden sm:block" /> for how you work
            </h2>
          </div>

          <div class="grid md:grid-cols-2 gap-6 mb-12">
            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-error/10 to-error/5 rounded-2xl blur-xl opacity-50" />
              <div class="relative p-6 rounded-2xl border border-error/20 bg-base-100/50 backdrop-blur-sm">
                <div class="flex items-start gap-4">
                  <div class="flex-shrink-0 w-12 h-12 rounded-xl bg-error/10 flex items-center justify-center">
                    <.icon name="hero-rectangle-stack" class="size-6 text-error" />
                  </div>
                  <div>
                    <h3 class="font-semibold text-lg mb-2 flex items-center gap-2">
                      Too Much Process
                      <span class="text-xs px-2 py-0.5 rounded-full bg-error/10 text-error">
                        Jira
                      </span>
                    </h3>
                    <p class="text-base-content/60 text-sm leading-relaxed">
                      Drowning in tickets, sprint ceremonies, and story points. More time managing work than doing it.
                    </p>
                  </div>
                </div>
              </div>
            </div>

            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-warning/10 to-warning/5 rounded-2xl blur-xl opacity-50" />
              <div class="relative p-6 rounded-2xl border border-warning/20 bg-base-100/50 backdrop-blur-sm">
                <div class="flex items-start gap-4">
                  <div class="flex-shrink-0 w-12 h-12 rounded-xl bg-warning/10 flex items-center justify-center">
                    <.icon name="hero-document-text" class="size-6 text-warning" />
                  </div>
                  <div>
                    <h3 class="font-semibold text-lg mb-2 flex items-center gap-2">
                      Too Little Structure
                      <span class="text-xs px-2 py-0.5 rounded-full bg-warning/10 text-warning">
                        Docs
                      </span>
                    </h3>
                    <p class="text-base-content/60 text-sm leading-relaxed">
                      Messy docs and spreadsheets that are already out of date. Things fall through the cracks.
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="text-center">
            <p class="text-lg text-base-content/60 mb-4">
              Meanwhile, AI has changed everything about how you code—
            </p>
            <p class="text-xl font-medium text-base-content/80 mb-4">
              but your project management is stuck in
              <span class="inline-flex items-center gap-1 px-3 py-1 rounded-lg bg-base-200 font-mono text-base-content/50">
                2015
              </span>
            </p>
            <p class="text-base text-base-content/50">
              You shouldn't need a PM certification to track what you're building.
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp solution_section(assigns) do
    ~H"""
    <section class="py-24 lg:py-32 relative overflow-hidden">
      <div class="absolute inset-0 pointer-events-none">
        <div class="absolute top-1/3 right-1/4 w-72 h-72 bg-success/5 rounded-full blur-3xl" />
        <div class="absolute bottom-1/3 left-1/4 w-56 h-56 bg-primary/5 rounded-full blur-3xl" />
      </div>

      <div class="container mx-auto px-6 lg:px-8 relative">
        <div class="max-w-4xl mx-auto">
          <div class="text-center mb-16">
            <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-success/10 text-success text-sm font-medium mb-6">
              <.icon name="hero-sparkles" class="size-4" /> The Solution
            </div>

            <h2 class="text-4xl lg:text-5xl font-bold tracking-tight mb-6">
              Meet your <span class="text-success">AI planning partner</span>
            </h2>

            <p class="text-lg text-base-content/60 max-w-2xl mx-auto">
              Citadel is project management that actually understands what you're building.
            </p>
          </div>

          <div class="grid sm:grid-cols-3 gap-4 mb-12">
            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-success/10 to-success/5 rounded-2xl blur-xl opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
              <div class="relative p-5 rounded-2xl border border-base-300/50 bg-base-100/50 backdrop-blur-sm hover:border-success/30 transition-all duration-300">
                <div class="w-10 h-10 rounded-lg bg-success/10 flex items-center justify-center mb-4">
                  <.icon name="hero-chat-bubble-bottom-center-text" class="size-5 text-success" />
                </div>
                <h3 class="font-semibold mb-2">Describe in plain English</h3>
                <p class="text-sm text-base-content/60">
                  Tell Citadel what you want to build and watch it become an actionable plan.
                </p>
              </div>
            </div>

            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-success/10 to-success/5 rounded-2xl blur-xl opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
              <div class="relative p-5 rounded-2xl border border-base-300/50 bg-base-100/50 backdrop-blur-sm hover:border-success/30 transition-all duration-300">
                <div class="w-10 h-10 rounded-lg bg-success/10 flex items-center justify-center mb-4">
                  <.icon name="hero-code-bracket" class="size-5 text-success" />
                </div>
                <h3 class="font-semibold mb-2">Manage from your IDE</h3>
                <p class="text-sm text-base-content/60">
                  Work with tasks directly from Claude, Cursor, or any MCP-enabled tool.
                </p>
              </div>
            </div>

            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-success/10 to-success/5 rounded-2xl blur-xl opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
              <div class="relative p-5 rounded-2xl border border-base-300/50 bg-base-100/50 backdrop-blur-sm hover:border-success/30 transition-all duration-300">
                <div class="w-10 h-10 rounded-lg bg-success/10 flex items-center justify-center mb-4">
                  <.icon name="hero-light-bulb" class="size-5 text-success" />
                </div>
                <h3 class="font-semibold mb-2">Get smart insights</h3>
                <p class="text-sm text-base-content/60">
                  AI-powered prioritization, progress reports, and retrospectives.
                </p>
              </div>
            </div>
          </div>

          <div class="text-center">
            <p class="text-2xl font-semibold text-base-content">
              No bloat. No busywork. <span class="text-success">Just build.</span>
            </p>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp features_section(assigns) do
    pillars = [
      %{
        icon: "hero-sparkles",
        title: "AI-Native",
        headline: "AI that does, not just suggests.",
        description:
          "Describe a feature and Citadel creates the plan. AI executes—not just recommends.",
        color: "primary"
      },
      %{
        icon: "hero-adjustments-horizontal",
        title: "Right-Sized",
        headline: "Everything you need. Nothing you don't.",
        description:
          "Built for solo devs and small teams. No enterprise bloat, no learning curve.",
        color: "accent"
      },
      %{
        icon: "hero-arrow-path",
        title: "Flow-First",
        headline: "Never leave your workflow.",
        description:
          "Manage projects from Claude, Cursor, or your favorite AI tools via MCP integration.",
        color: "info"
      }
    ]

    assigns = assign(assigns, :pillars, pillars)

    ~H"""
    <section id="features" class="py-24 lg:py-32 relative overflow-hidden">
      <div class="absolute inset-0 pointer-events-none">
        <div class="absolute top-1/4 left-1/3 w-64 h-64 bg-primary/5 rounded-full blur-3xl" />
        <div class="absolute bottom-1/4 right-1/3 w-72 h-72 bg-accent/5 rounded-full blur-3xl" />
      </div>

      <div class="container mx-auto px-6 lg:px-8 relative">
        <div class="max-w-4xl mx-auto">
          <div class="text-center mb-16">
            <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-primary/10 text-primary text-sm font-medium mb-6">
              <.icon name="hero-cube-transparent" class="size-4" /> Why Citadel
            </div>
            <h2 class="text-4xl lg:text-5xl font-bold tracking-tight mb-6">
              Built for how <span class="text-primary">developers actually work</span>
            </h2>
            <p class="text-lg text-base-content/60">
              Three pillars that make Citadel different from everything else.
            </p>
          </div>

          <div class="grid md:grid-cols-3 gap-6">
            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-primary/10 to-primary/5 rounded-2xl blur-xl opacity-50" />
              <div class="relative h-full p-6 rounded-2xl border border-primary/20 bg-base-100/50 backdrop-blur-sm">
                <div class="flex-shrink-0 w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mb-5">
                  <.icon name="hero-sparkles" class="size-6 text-primary" />
                </div>
                <div class="text-sm font-medium text-primary mb-2">AI-Native</div>
                <h3 class="font-semibold text-lg mb-3">AI that does, not just suggests.</h3>
                <p class="text-base-content/60 text-sm leading-relaxed">
                  Describe a feature and Citadel creates the plan. AI executes—not just recommends.
                </p>
              </div>
            </div>

            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-accent/10 to-accent/5 rounded-2xl blur-xl opacity-50" />
              <div class="relative h-full p-6 rounded-2xl border border-accent/20 bg-base-100/50 backdrop-blur-sm">
                <div class="flex-shrink-0 w-12 h-12 rounded-xl bg-accent/10 flex items-center justify-center mb-5">
                  <.icon name="hero-adjustments-horizontal" class="size-6 text-accent" />
                </div>
                <div class="text-sm font-medium text-accent mb-2">Right-Sized</div>
                <h3 class="font-semibold text-lg mb-3">Everything you need. Nothing you don't.</h3>
                <p class="text-base-content/60 text-sm leading-relaxed">
                  Built for solo devs and small teams. No enterprise bloat, no learning curve.
                </p>
              </div>
            </div>

            <div class="group relative">
              <div class="absolute inset-0 bg-gradient-to-br from-info/10 to-info/5 rounded-2xl blur-xl opacity-50" />
              <div class="relative h-full p-6 rounded-2xl border border-info/20 bg-base-100/50 backdrop-blur-sm">
                <div class="flex-shrink-0 w-12 h-12 rounded-xl bg-info/10 flex items-center justify-center mb-5">
                  <.icon name="hero-arrow-path" class="size-6 text-info" />
                </div>
                <div class="text-sm font-medium text-info mb-2">Flow-First</div>
                <h3 class="font-semibold text-lg mb-3">Never leave your workflow.</h3>
                <p class="text-base-content/60 text-sm leading-relaxed">
                  Manage projects from Claude, Cursor, or your favorite AI tools via MCP integration.
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp pricing_section(assigns) do
    ~H"""
    <section id="pricing" class="py-24 lg:py-32 relative overflow-hidden">
      <div class="absolute inset-0 pointer-events-none">
        <div class="absolute top-1/3 left-1/4 w-72 h-72 bg-primary/5 rounded-full blur-3xl" />
        <div class="absolute bottom-1/3 right-1/4 w-64 h-64 bg-accent/5 rounded-full blur-3xl" />
      </div>

      <div class="container mx-auto px-6 lg:px-8 relative">
        <div class="max-w-4xl mx-auto">
          <div class="text-center mb-16">
            <div class="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-primary/10 text-primary text-sm font-medium mb-6">
              <.icon name="hero-currency-dollar" class="size-4" /> Pricing
            </div>
            <h2 class="text-4xl lg:text-5xl font-bold tracking-tight mb-6">
              Simple, transparent <span class="text-primary">pricing</span>
            </h2>
            <p class="text-lg text-base-content/60">
              Start for free, upgrade when you need more. No hidden fees, no surprises.
            </p>
          </div>

          <div class="grid md:grid-cols-2 gap-6 items-stretch">
            <div class="group relative flex">
              <div class="absolute inset-0 bg-gradient-to-br from-base-300/20 to-base-300/10 rounded-2xl blur-xl opacity-50" />
              <div class="relative flex-1 flex flex-col p-6 rounded-2xl border border-base-300/30 bg-base-100/50 backdrop-blur-sm">
                <div class="mb-6">
                  <h3 class="text-xl font-bold mb-1">Free</h3>
                  <p class="text-base-content/60 text-sm">Perfect for individuals getting started.</p>
                </div>

                <div class="mb-6">
                  <span class="text-4xl font-bold">$0</span>
                  <span class="text-base-content/60 ml-1">/forever</span>
                </div>

                <ul class="space-y-3 mb-6 flex-1">
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-success flex-shrink-0" />
                    <span class="text-base-content/70">Up to 3 workspaces</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-success flex-shrink-0" />
                    <span class="text-base-content/70">Unlimited tasks</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-success flex-shrink-0" />
                    <span class="text-base-content/70">Basic AI task creation</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-success flex-shrink-0" />
                    <span class="text-base-content/70">Sub-task hierarchies</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-success flex-shrink-0" />
                    <span class="text-base-content/70">Email support</span>
                  </li>
                </ul>

                <.link
                  navigate={~p"/register"}
                  class="block w-full py-3 px-6 text-center font-semibold rounded-xl bg-base-200 text-base-content hover:bg-base-300 border border-base-300/50 transition-all duration-200 mt-auto"
                >
                  Start Planning
                </.link>
              </div>
            </div>

            <div class="group relative flex">
              <div class="absolute inset-0 bg-gradient-to-br from-primary/20 to-accent/10 rounded-2xl blur-xl opacity-70" />
              <div class="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-1 bg-primary text-primary-content text-xs font-medium rounded-full z-10">
                Most Popular
              </div>
              <div class="relative flex-1 flex flex-col p-6 rounded-2xl border border-primary/30 bg-base-100/50 backdrop-blur-sm">
                <div class="mb-6">
                  <h3 class="text-xl font-bold mb-1">Pro</h3>
                  <p class="text-base-content/60 text-sm">For power users and teams.</p>
                </div>

                <div class="mb-6">
                  <span class="text-4xl font-bold">$12</span>
                  <span class="text-base-content/60 ml-1">/per month</span>
                </div>

                <ul class="space-y-3 mb-6 flex-1">
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-primary flex-shrink-0" />
                    <span class="text-base-content/70">Unlimited workspaces</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-primary flex-shrink-0" />
                    <span class="text-base-content/70">Advanced AI features</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-primary flex-shrink-0" />
                    <span class="text-base-content/70">Priority AI processing</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-primary flex-shrink-0" />
                    <span class="text-base-content/70">Team collaboration</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-primary flex-shrink-0" />
                    <span class="text-base-content/70">API access & integrations</span>
                  </li>
                  <li class="flex items-center gap-3 text-sm">
                    <.icon name="hero-check" class="size-4 text-primary flex-shrink-0" />
                    <span class="text-base-content/70">Priority support</span>
                  </li>
                </ul>

                <.link
                  navigate={~p"/register"}
                  class="block w-full py-3 px-6 text-center font-semibold rounded-xl bg-primary text-primary-content shadow-lg shadow-primary/25 hover:shadow-primary/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200 mt-auto"
                >
                  Start Free Trial
                </.link>
              </div>
            </div>
          </div>

          <p class="text-center text-base-content/50 text-sm mt-10">
            All plans include a 14-day free trial of Pro features. No credit card required.
          </p>
        </div>
      </div>
    </section>
    """
  end

  defp cta_section(assigns) do
    ~H"""
    <section class="py-24 lg:py-32 relative">
      <div class="absolute inset-0 bg-gradient-to-b from-base-200/50 to-transparent pointer-events-none" />

      <div class="container mx-auto px-6 lg:px-8 relative">
        <div class="max-w-3xl mx-auto text-center">
          <h2 class="text-4xl lg:text-5xl font-bold tracking-tight mb-6">
            Stop managing. <span class="text-primary">Start building.</span>
          </h2>
          <p class="text-lg text-base-content/60 mb-10">
            Join developers who've reclaimed their focus with AI-native project management.
          </p>
          <.link
            navigate={~p"/register"}
            class="group relative inline-flex items-center gap-2 px-8 py-4 bg-primary text-primary-content font-semibold rounded-xl shadow-2xl shadow-primary/25 hover:shadow-primary/40 hover:scale-[1.02] active:scale-[0.98] transition-all duration-200"
          >
            <span>Start Planning Free</span>
            <.icon
              name="hero-arrow-right"
              class="size-5 group-hover:translate-x-1 transition-transform"
            />
          </.link>
        </div>
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
