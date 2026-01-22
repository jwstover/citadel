# Citadel

Citadel is a task management and AI chat application built with Phoenix LiveView and Ash Framework. It features workspace-based collaboration, AI-powered chat conversations, and intelligent task management.

## Features

### Workspaces
Citadel uses workspace-based multitenancy to enable team collaboration:

- **Multiple Workspaces**: Users can belong to multiple workspaces and switch between them
- **Automatic Personal Workspace**: New users automatically get a "Personal" workspace on registration
- **Team Collaboration**: Invite team members via email to collaborate on tasks and conversations
- **Data Isolation**: Tasks and conversations are scoped to workspaces, ensuring data privacy

### Task Management
- Create and organize tasks with customizable states (To Do, In Progress, Done)
- Drag-and-drop task organization
- AI-powered task parsing from natural language

### AI Chat
- Real-time AI-powered chat conversations
- Automatic conversation naming based on content
- Streaming responses for immediate feedback

### Subscription & Billing
- **Freemium Model**: Free tier with 1,000 AI credits/month, Pro tier with 10,000 credits
- **Stripe Integration**: Seamless payment processing with monthly/annual billing
- **Feature Gating**: Control access to premium features by subscription tier
- **Credit System**: Token-based metering that scales with AI model costs
- **Organization-Based**: Billing and features are scoped to organizations, shared across workspaces

## Getting Started

### Prerequisites
- Elixir 1.17+
- PostgreSQL
- Node.js (for assets)

### Setup

```bash
# Install dependencies and setup database
mix setup

# Start the Phoenix server
mix phx.server

# Or start in IEx for interactive development
iex -S mix phx.server
```

Visit [`localhost:4000`](http://localhost:4000) to access the application.

### Environment Variables

Configure these in your environment or `.env` file:

```bash
# Database
DATABASE_URL=postgres://user:pass@localhost/citadel_dev

# Authentication (Google OAuth)
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
GOOGLE_REDIRECT_URI=http://localhost:4000/auth/google/callback

# AI Providers (optional - at least one required for AI features)
ANTHROPIC_API_KEY=your_anthropic_key
OPENAI_API_KEY=your_openai_key

# Stripe (for subscription billing)
STRIPE_SECRET_KEY=your_stripe_secret_key
STRIPE_PUBLISHABLE_KEY=your_stripe_publishable_key
STRIPE_WEBHOOK_SECRET=your_webhook_secret
```

## Workspace Invitation Flow

1. **Create Invitation**: Workspace owners/members can invite users via email from the workspace settings page
2. **Email Sent**: An invitation email is sent asynchronously with a secure token link
3. **Accept Invitation**: Recipients click the link and sign in (or create an account) to join the workspace
4. **Access Granted**: Once accepted, the new member has full access to the workspace's tasks and conversations

Invitations expire after 7 days and can be revoked by the workspace owner.

## Development

### Code Quality

```bash
# Run all quality checks (format, compile warnings, credo, sobelow)
mix ck

# Run before committing
mix precommit
```

### Testing

```bash
# Run all tests
mix test

# Run a specific test file
mix test test/path/to/test.exs

# Run a specific test
mix test test/path/to/test.exs:42
```

### Database

```bash
# Generate migrations for resource changes
mix ash.codegen migration_name

# Run migrations
mix ash.migrate

# Reset database
mix ash.reset
```

## Architecture

Citadel is built with:

- **[Phoenix Framework](https://www.phoenixframework.org/)** - Web framework with LiveView for real-time UI
- **[Ash Framework](https://ash-hq.org/)** - Declarative resource modeling and domain-driven design
- **[Oban](https://getoban.pro/)** - Background job processing for emails and AI responses
- **[AshAuthentication](https://hexdocs.pm/ash_authentication/)** - Google OAuth authentication

### Domain Structure

- **Citadel.Accounts** - Users, organizations, workspaces, memberships, and invitations
- **Citadel.Tasks** - Task management with workspace scoping
- **Citadel.Chat** - AI-powered conversations and messages
- **Citadel.Billing** - Subscriptions, credits, and feature gating

### Billing & Feature Gating

Citadel implements a comprehensive subscription billing system with feature gating:

#### Subscription Tiers

| Tier | Price | Credits/Month | Workspaces | Members | Features |
|------|-------|---------------|------------|---------|----------|
| **Free** | $0 | 1,000 | 1 | 1 | Basic AI |
| **Pro (Monthly)** | $19/mo + $5/member | 10,000 | 5 | 5 | All features |
| **Pro (Annual)** | $190/yr + $50/member/yr | 10,000 | 5 | 5 | All features |

#### Feature Catalog

Features are organized into categories:

**AI Features:**
- `:basic_ai` - Standard AI models (Free + Pro)
- `:advanced_ai_models` - Claude Opus, premium models (Pro only)
- `:byok` - Bring Your Own Key for unlimited AI (Pro only)

**Collaboration:**
- `:multiple_workspaces` - Up to 5 workspaces (Pro only)
- `:team_collaboration` - Invite team members (Pro only)

**Data:**
- `:data_export` - Export tasks/conversations (Pro only)
- `:bulk_import` - Import from external tools (Pro only)

**API & Integrations:**
- `:api_access` - REST API access (Pro only)
- `:webhooks` - Event webhooks (Pro only)

**Customization & Support:**
- `:custom_branding` - Custom themes (Pro only)
- `:priority_support` - Priority support channel (Pro only)

#### Using Feature Gates

**In Ash Policies:**
```elixir
# Gate features in resource policies
policies do
  policy action(:export) do
    authorize_if HasFeature, feature: :data_export
  end
end
```

**In LiveViews:**
```elixir
# Check features in LiveView mount
def mount(_params, _session, socket) do
  socket = assign_feature_checks(socket, [:data_export, :api_access])
  {:ok, socket}
end

# Use in templates
<.button :if={@features.data_export} phx-click="export">
  Export Data
</.button>
```

**Direct Queries:**
```elixir
# Check if a tier has a feature
Plan.tier_has_feature?(:pro, :data_export) #=> true

# Check if an organization has a feature
Plan.org_has_feature?(org_id, :api_access) #=> {:ok, true}

# Get all features for a tier
Plan.features_for_tier(:pro)
#=> [:basic_ai, :advanced_ai_models, :data_export, ...]
```

#### Adding New Features

To add a new feature to the system:

1. **Define the feature** in `lib/citadel/billing/features.ex`:
```elixir
new_feature: %{
  name: "Feature Name",
  description: "What this feature does",
  category: :data,  # or :ai, :collaboration, :api, etc.
  type: :binary
}
```

2. **Add to tier(s)** in `lib/citadel/billing/plan.ex`:
```elixir
pro: %{
  # ... other config ...
  features: MapSet.new([
    # ... existing features ...
    :new_feature
  ])
}
```

3. **Gate the feature** using the `HasFeature` policy check:
```elixir
policy action(:use_new_feature) do
  authorize_if HasFeature, feature: :new_feature
end
```

4. **Use in UI** with feature helpers in LiveViews

#### Credit System

Credits scale with AI model costs:

| Model | Input Credits/1K tokens | Output Credits/1K tokens |
|-------|------------------------|--------------------------|
| Haiku 4.5 | 1 | 5 |
| Sonnet 4.5 | 3 | 15 |
| Opus 4.5 | 5 | 25 |

**Formula:** `credits = ceil((input_tokens / 1000 * input_rate) + (output_tokens / 1000 * output_rate))`

**Example:** A typical message with 2,500 input and 400 output tokens costs ~14 credits with Sonnet 4.5

#### Key Modules

- **`Citadel.Billing.Features`** - Feature catalog with metadata
- **`Citadel.Billing.Plan`** - Tier configuration and feature queries
- **`Citadel.Billing.Checks.HasFeature`** - Generic policy check for feature gating
- **`CitadelWeb.Live.FeatureHelpers`** - LiveView helpers for feature checks
- **`Citadel.Billing.Subscription`** - Subscription management per organization
- **`Citadel.Billing.CreditLedger`** - Credit transaction tracking

## License

This project is private and proprietary.
