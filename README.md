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

- **Citadel.Accounts** - Users, workspaces, memberships, and invitations
- **Citadel.Tasks** - Task management with workspace scoping
- **Citadel.Chat** - AI-powered conversations and messages

## License

This project is private and proprietary.
