# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## ⚠️ CRITICAL: Read This First


**You MUST read `/AGENTS.md` FIRST before:**
- Writing ANY database queries (including MCP SQL queries)
- Using ANY MCP tools
- Implementing ANY features
- Modifying ANY existing code
- Making ANY architectural decisions
- Answering questions about data

**This is NOT optional. This is NOT a suggestion. Read AGENTS.md FIRST, ALWAYS.**

**Skipping this step WILL result in incorrect code that violates project conventions.**
**BEFORE doing ANY work in this repository, you MUST:**

2. **Ask for permission** before changing plans or trying new approaches
3. **Follow TDD** - Write tests before writing code (when applicable)

---

## Additional Rules

- AVOID leaving comments in code unless it's for a specific reason or to call out especially complex logic

## Project Overview

Citadel is a task management and AI chat application built with Phoenix LiveView and Ash Framework. The application features workspace-based collaboration, AI-powered chat conversations, intelligent task management, and comprehensive authentication via AshAuthentication.

## Essential Commands

### Development Setup
```bash
mix setup                    # Install dependencies, setup database, build assets
mix phx.server              # Start Phoenix server (http://localhost:4000)
iex -S mix phx.server       # Start server in IEx REPL
```

### Code Quality & Testing
```bash
mix ck                      # Run all quality checks (format, compile, credo, sobelow)
mix test                    # Run all tests (includes ash.setup)
mix test test/path/file.exs # Run a single test file
mix test test/path/file.exs:42 # Run a specific test at line 42
```

### Database & Migrations
```bash
mix ash.codegen name        # Generate migrations for Ash resource changes
mix ash.codegen --dev       # Generate development migrations (recommended during iteration)
mix ash.migrate             # Run pending migrations
mix ash.setup               # Create database and run migrations
mix ash.reset               # Drop, recreate, and migrate database
MIX_ENV=test mix ash.reset  # Reset test database
```

### Asset Management
```bash
mix assets.setup            # Install tailwind and esbuild
mix assets.build            # Build assets (tailwind + esbuild)
mix assets.deploy           # Build minified assets for production
```

### Development Tools (accessible in browser)
- `/dev/dashboard` - Phoenix LiveDashboard with metrics
- `/dev/mailbox` - Swoosh email preview
- `/oban` - Oban job dashboard
- `/admin` - AshAdmin interface for all resources

## Architecture

### Domain-Driven Design with Ash Framework

Citadel is organized around three main Ash domains located in `lib/citadel/`:

1. **Citadel.Accounts** - User authentication, workspaces, and workspace memberships
   - Manages user registration via Google OAuth
   - Handles workspace creation (auto-created on user registration)
   - Workspace invitations and memberships for collaboration
   - Custom policy checks in `lib/citadel/accounts/checks/`

2. **Citadel.Tasks** - Task management with workspace-scoped tasks
   - Tasks belong to workspaces (multitenancy via `:workspace_id` attribute)
   - Task states (To Do, In Progress, Done)
   - AI-powered task parsing via `parse_task_from_text` action
   - Tools exposed for AI agents via `AshAi` extension

3. **Citadel.Chat** - AI-powered chat conversations
   - Conversations with automatic AI-generated naming (via Oban background jobs)
   - Messages with AI responses via streaming
   - Workspace-scoped with PubSub notifications
   - Background naming triggered after 3+ messages or 10 minutes

### Multitenancy

All user-facing resources (tasks, conversations, messages) use **attribute-based multitenancy** with `:workspace_id`:

```elixir
multitenancy do
  strategy :attribute
  attribute :workspace_id
end
```

This ensures data isolation between workspaces. The workspace is automatically set via the scope in LiveViews.

### AI Integration

The `Citadel.AI` module (`lib/citadel/ai.ex`) provides a unified interface for AI providers:

- **Supported providers**: Anthropic (Claude), OpenAI (GPT)
- **Key modules**:
  - `Citadel.AI.Client` - Core client for sending messages
  - `Citadel.AI.Config` - Provider configuration
  - `Citadel.AI.Provider` - Provider behavior and implementations
  - `Citadel.AI.Helpers` - Helper functions for AI features
- **Usage**: Configured via environment variables (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)
- **Features**: Streaming responses, conversation chains, tool calling (via AshAi)

### Background Jobs with Oban

Oban handles async processing configured in `config/config.exs`:

- **Queues**:
  - `default` (limit: 10)
  - `chat_responses` (limit: 10) - AI chat message processing
  - `conversations` (limit: 10) - Conversation naming jobs

Conversation naming is triggered via AshOban triggers defined in resources using the `oban` DSL.

### Authentication Flow

Using AshAuthentication with Google OAuth:

1. User signs in with Google → `register_with_google` action
2. User upserted by email (`:unique_email` identity)
3. Personal workspace auto-created if user has no workspaces
4. JWT tokens stored in `Citadel.Accounts.Token` resource

LiveViews use `CitadelWeb.LiveUserAuth` on_mount hooks for auth:
- `:live_user_required` - Must be authenticated
- `:live_user_optional` - Auth optional
- `:live_no_user` - Must not be authenticated

### Web Layer Structure

Located in `lib/citadel_web/`:

- **Router** (`router.ex`) - Defines routes with auth pipelines
- **LiveViews**:
  - `HomeLive` - Dashboard/home page
  - `ChatLive` - AI chat interface
  - `TaskLive` - Task management
  - `PreferencesLive` - User preferences
- **Components** (`components/`) - Reusable UI components
- **Controllers** (`controllers/`) - Auth controller for OAuth callbacks

### Policy-Based Authorization

All resources use `Ash.Policy.Authorizer` with policies defined in the resource:

- Workspace-scoped reads: User must own workspace OR be a member
- Creates: User must be a workspace member (via custom checks)
- Updates/Destroys: Same as reads
- Bypass policies for admin actions (e.g., AI actors for background jobs)

Example policy pattern:
```elixir
policy action_type(:read) do
  authorize_if expr(
    workspace.owner_id == ^actor(:id) or
    exists(workspace.memberships, user_id == ^actor(:id))
  )
end
```

### Testing Structure

Tests in `test/` mirror the `lib/` structure:

- Always use `authorize?: false` in tests unless testing authorization
- Use globally unique values for identity attributes to prevent deadlocks in concurrent tests
- Prefer raising functions (`!`) over pattern matching in tests
- Use `Ash.load!/2` to load relationships before assertions
- **Always use generators from `Citadel.Generator`** instead of manually creating test data
  - Available via `use CitadelWeb.ConnCase` or `use Citadel.DataCase`
  - Example: `user = generate(user())` instead of `create_user()`
  - Example: `workspace = generate(workspace([], actor: user))`
  - Generators provide consistent, valid test data and handle all required attributes

## Key Development Patterns

### Working with Resources

1. **Always use code interfaces** defined in domains, never call `Ash.create!/2` directly
2. **Load relationships** before using them: `Citadel.Accounts.get_user_by_id!(id, load: [:workspaces])`
3. **Pass actor** via options, not when calling the action: `Citadel.Tasks.create_task!(..., actor: user)`
4. **Scopes in LiveViews**: Use `socket.assigns.scope` for workspace-scoped operations

### Migrations Workflow

After modifying resources:

1. During development: `mix ash.codegen --dev` to generate dev migrations
2. Continue iterating with `--dev` flag
3. When feature complete: `mix ash.codegen feature_name` to squash into named migration
4. Review generated migrations in `priv/repo/migrations/`
5. Run `mix ash.migrate` to apply

### Adding New Features

1. Define resources in appropriate domain module
2. Add code interfaces in the domain's `resources` block
3. Generate migrations with `mix ash.codegen`
4. Add LiveView routes in `router.ex` (note: scopes are aliased)
5. Create LiveView in `lib/citadel_web/live/`
6. Add on_mount hook for auth requirement
7. Run `mix ck` to verify code quality
8. Write tests with globally unique identity values

### Working with AI Features

The `AshAi` extension exposes domain actions as tools for AI agents:

- Defined in `tools` blocks in domain modules
- Automatically available to AI agents via `Citadel.AI`
- Used for task parsing, conversation responses, etc.

Example from `Citadel.Tasks`:
```elixir
tools do
  tool :create_task, Citadel.Tasks.Task, :create do
    description "Creates a new task with a title, optional description, and task state"
  end
end
```

## Configuration

### Required Environment Variables

Set these in `config/runtime.exs`:

- `DATABASE_URL` - PostgreSQL connection string
- `SECRET_KEY_BASE` - Phoenix secret key base
- `ANTHROPIC_API_KEY` - For Claude AI (optional)
- `OPENAI_API_KEY` - For GPT AI (optional)
- `GOOGLE_CLIENT_ID` - Google OAuth client ID
- `GOOGLE_CLIENT_SECRET` - Google OAuth client secret
- `GOOGLE_REDIRECT_URI` - OAuth redirect URI

### Ash Configuration

Key Ash config in `config/config.exs`:

- Default actions require atomic operations (`default_actions_require_atomic?: true`)
- Keyset pagination by default (`default_page_type: :keyset`)
- Policies don't filter static forbidden reads (`no_filter_static_forbidden_reads?: false`)

### Oban Configuration

Configure queues and plugins in `config/config.exs` under `:citadel, Oban`.

## Common Pitfalls

1. **Don't forget to require `Ash.Query`** when using `Ash.Query.filter/2` (it's a macro)
2. **Don't use generic CRUD** - Create specific, well-named actions for business logic
3. **Don't access changesets in templates** - Always use `to_form/2` and `@form` assigns
4. **Don't use fixed identity values in tests** - Use `System.unique_integer([:positive])` to avoid deadlocks
5. **Don't skip `mix ck`** - Always run before committing to catch issues early
6. **Always explicitly load calculations** - Ash calculations return `%Ash.NotLoaded{}` structs unless explicitly loaded in the query:
   ```elixir
   # ❌ Wrong - calculations will be NotLoaded
   Accounts.get_invitation_by_token(token)

   # ✅ Correct - explicitly load calculations
   Accounts.get_invitation_by_token(token, load: [:is_accepted, :is_expired])
   ```
   This applies to all calculated fields (defined with `calculate` in resources). Always include them in the `load:` option when querying.
