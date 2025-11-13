# Workspace Multitenancy Implementation Plan

## Overall Goal

Implement workspace/organization functionality to group users together within the Citadel application. Workspaces will enable collaborative work by allowing multiple users to share tasks, conversations, and eventually projects. The implementation will use **attribute-based multitenancy** where users can belong to **multiple workspaces** and switch between them. Initially, workspaces will have a simple ownership model where the owner can invite other users via **email invitations**.

## Architecture Decisions

- **Strategy**: Attribute-based multitenancy (workspace_id column + filters)
- **User Model**: Users can belong to multiple workspaces
- **Authorization**: Owner-only roles initially (all members have equal permissions)
- **Invitations**: Email-based with secure tokens
- **Scoped Resources**: Tasks, Conversations, Messages (through conversation)
- **Shared Resources**: TaskState remains global

---

## Overall Progress

- [x] Phase 1: Core Workspace Resources (1.1 Complete - Workspace Resource, 1.2 Complete - WorkspaceMembership Resource)
- [ ] Phase 2: Add Multitenancy to Existing Resources
- [ ] Phase 3: Authorization & Policies
- [ ] Phase 4: Data Migration
- [ ] Phase 5: UI & LiveViews
- [ ] Phase 6: Background Jobs & Real-time Updates
- [ ] Phase 7: Invitation Flow
- [ ] Phase 8: Testing & Validation
- [ ] Phase 9: Polish & Documentation

---

## Phase 1: Core Workspace Resources

**Goal**: Create the foundational resources for workspace management: Workspace, WorkspaceMembership, and WorkspaceInvitation.

### 1.1 Create Workspace Resource ✅ COMPLETE

- [x] Create `lib/citadel/accounts/workspace.ex`
- [x] Add attributes:
  - [x] `uuid_v7_primary_key :id`
  - [x] `attribute :name, :string` (required, constraints: min_length 1, max_length 100)
  - [x] `timestamps`
- [x] Add relationships:
  - [x] `belongs_to :owner, Citadel.Accounts.User` (required, allow_nil?: false)
  - [x] `has_many :memberships, Citadel.Accounts.WorkspaceMembership`
  - [x] `many_to_many :members, Citadel.Accounts.User`
- [x] Add actions:
  - [x] `create :create` - accept name, set owner from actor
  - [x] `read :read` - default read
  - [x] `update :update` - allow updating name
  - [x] `destroy :destroy` - delete workspace
- [x] Add policies:
  - [x] Owner and members can read workspace
  - [x] Owner can update workspace
  - [x] Owner can destroy workspace
  - [x] Any authenticated user can create workspace
- [x] Add code interface to Citadel.Accounts domain:
  - [x] `define :create_workspace`
  - [x] `define :list_workspaces`
  - [x] `define :get_workspace_by_id`
  - [x] `define :update_workspace`
  - [x] `define :destroy_workspace`
- [x] Add to `lib/citadel/accounts.ex` resources list
- [x] Run `mix ash.codegen --dev workspace_resource`
- [x] Create migration and run `mix ash.migrate`
- [x] Create comprehensive tests (18 tests, all passing)
- [x] Create custom policy check `WorkspaceMember` (for Phase 1.2)
- [x] Fix pre-existing compilation warnings in AI providers

### 1.2 Create WorkspaceMembership Resource ✅ COMPLETE

- [x] Create `lib/citadel/accounts/workspace_membership.ex`
- [x] Add attributes:
  - [x] `uuid_v7_primary_key :id`
  - [x] `timestamps` (inserted_at and updated_at)
- [x] Add relationships:
  - [x] `belongs_to :user, Citadel.Accounts.User` (required, primary_key?: true, public?: true)
  - [x] `belongs_to :workspace, Citadel.Accounts.Workspace` (required, primary_key?: true, public?: true)
- [x] Add identity:
  - [x] `identity :unique_membership, [:user_id, :workspace_id]`
- [x] Add actions:
  - [x] `create :join` - create membership with user_id and workspace_id arguments
  - [x] `read :read` - default read
  - [x] `destroy :leave` - remove membership with validation to prevent owner leaving
- [x] Add policies:
  - [x] Workspace owner or members can create memberships (invite users)
  - [x] Workspace owner can destroy memberships (remove users)
  - [x] Users can read memberships in workspaces they belong to
  - [x] Prevent owner from leaving their own workspace via custom validation
- [x] Add code interface to Citadel.Accounts domain:
  - [x] `define :add_workspace_member` (args: [:user_id, :workspace_id])
  - [x] `define :remove_workspace_member`
  - [x] `define :list_workspace_members`
- [x] Add to `lib/citadel/accounts.ex` resources list
- [x] Run `mix ash.codegen --dev workspace_membership`
- [x] Create migration and run `mix ash.migrate`
- [x] Create custom policy check `CanManageWorkspaceMembership`
- [x] Create custom validation `PreventOwnerLeaving` (refactored to avoid deep nesting)
- [x] Create comprehensive tests (15 tests, all passing)
- [x] Update Workspace resource to uncomment membership relationships
- [x] Update Workspace read policy to allow members to read workspace
- [x] Run `mix test` - all 82 tests passing
- [x] Run `mix ck` - all quality checks passing

### 1.3 Create WorkspaceInvitation Resource

- [ ] Create `lib/citadel/accounts/workspace_invitation.ex`
- [ ] Add attributes:
  - [ ] `uuid_v7_primary_key :id`
  - [ ] `attribute :email, :ci_string` (required)
  - [ ] `attribute :token, :string` (required, unique, auto-generated)
  - [ ] `attribute :expires_at, :utc_datetime_usec` (default: 7 days from now)
  - [ ] `attribute :accepted_at, :utc_datetime_usec` (nullable)
  - [ ] `timestamps`
- [ ] Add relationships:
  - [ ] `belongs_to :workspace, Citadel.Accounts.Workspace` (required)
  - [ ] `belongs_to :invited_by, Citadel.Accounts.User` (required)
- [ ] Add calculations:
  - [ ] `calculate :is_expired, :boolean` - check if expires_at < now()
  - [ ] `calculate :is_accepted, :boolean` - check if accepted_at is not nil
- [ ] Add actions:
  - [ ] `create :create` - generate token, set expires_at, set invited_by from actor
  - [ ] `read :read` - default read
  - [ ] `update :accept` - set accepted_at, create workspace membership
  - [ ] `destroy :revoke` - delete invitation
- [ ] Add policies:
  - [ ] Workspace members can create invitations
  - [ ] Workspace members can list invitations for their workspace
  - [ ] Anyone with valid token can read that specific invitation
  - [ ] Anyone with valid token can accept invitation
  - [ ] Workspace owner can revoke invitations
- [ ] Add code interface to Citadel.Accounts domain:
  - [ ] `define :create_invitation`
  - [ ] `define :list_workspace_invitations`
  - [ ] `define :get_invitation_by_token`
  - [ ] `define :accept_invitation`
  - [ ] `define :revoke_invitation`
- [ ] Add to `lib/citadel/accounts.ex` resources list
- [ ] Run `mix ash.codegen --dev workspace_invitation`

---

## Phase 2: Add Multitenancy to Existing Resources

**Goal**: Configure Tasks, Conversations, and Messages to be workspace-scoped using attribute-based multitenancy.

### 2.1 Update Task Resource

- [ ] Open `lib/citadel/tasks/task.ex`
- [ ] Add relationship:
  - [ ] `belongs_to :workspace, Citadel.Accounts.Workspace` (required)
- [ ] Add multitenancy configuration:
  ```elixir
  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end
  ```
- [ ] Update create action to accept workspace or derive from context
- [ ] Keep `belongs_to :user` relationship (tracks who created the task)
- [ ] Run `mix ash.codegen --dev task_workspace`

### 2.2 Update Conversation Resource

- [ ] Open `lib/citadel/chat/conversation.ex`
- [ ] Add relationship:
  - [ ] `belongs_to :workspace, Citadel.Accounts.Workspace` (required)
- [ ] Add multitenancy configuration:
  ```elixir
  multitenancy do
    strategy :attribute
    attribute :workspace_id
  end
  ```
- [ ] Update create action to accept workspace or derive from context
- [ ] Keep `belongs_to :user` relationship (tracks who created the conversation)
- [ ] Run `mix ash.codegen --dev conversation_workspace`

### 2.3 Update Message Resource

- [ ] Open `lib/citadel/chat/message.ex`
- [ ] No direct workspace relationship needed (inherits through conversation)
- [ ] Update queries to ensure conversation is always loaded with workspace context
- [ ] Policies will be updated in Phase 3

---

## Phase 3: Authorization & Policies

**Goal**: Implement workspace-based authorization checks to ensure users can only access data within their workspaces.

### 3.1 Create Custom Policy Check

- [ ] Create `lib/citadel/accounts/checks/workspace_member.ex`
- [ ] Implement `Ash.Policy.FilterCheck` behavior
- [ ] Check: `exists(workspace.memberships, user_id == ^actor(:id))`
- [ ] Use this check across workspace-scoped resources

### 3.2 Update Workspace Policies

- [ ] Update `Workspace` policies:
  - [ ] Replace placeholder policies with `WorkspaceMember` check for read
  - [ ] Use `relates_to_actor_via(:owner)` for update/destroy

### 3.3 Update Task Policies

- [ ] Open `lib/citadel/tasks/task.ex`
- [ ] Update policies section:
  - [ ] Read: Change from `relates_to_actor_via(:user)` to `WorkspaceMember` check
  - [ ] Create: Ensure workspace membership
  - [ ] Update: Ensure workspace membership (optionally restrict to task creator)
  - [ ] Destroy: Ensure workspace membership (optionally restrict to task creator)

### 3.4 Update Conversation Policies

- [ ] Open `lib/citadel/chat/conversation.ex`
- [ ] Update policies section:
  - [ ] Read: Change from `relates_to_actor_via(:user)` to `WorkspaceMember` check
  - [ ] Create: Ensure workspace membership
  - [ ] Update: Ensure workspace membership
  - [ ] Destroy: Ensure workspace membership

### 3.5 Update Message Policies

- [ ] Open `lib/citadel/chat/message.ex`
- [ ] Update policies section:
  - [ ] Read: Check workspace membership through `relates_to_actor_via([:conversation, :workspace])`
  - [ ] Create: Check workspace membership through conversation
  - [ ] Update bypass for background jobs should still work

---

## Phase 4: Data Migration

**Goal**: Migrate existing data to the workspace model and run database migrations.

### 4.1 Generate and Review Migrations

- [ ] Run `mix ash.codegen workspace_schema_migration`
- [ ] Review generated migrations in `priv/repo/migrations/`
- [ ] Verify migrations create:
  - [ ] `workspaces` table
  - [ ] `workspace_memberships` table
  - [ ] `workspace_invitations` table
  - [ ] `workspace_id` column on `tasks` table (nullable initially)
  - [ ] `workspace_id` column on `conversations` table (nullable initially)
  - [ ] Foreign key constraints
  - [ ] Indexes

### 4.2 Create Data Migration Script

- [ ] Create data migration to:
  - [ ] Create "Personal" workspace for each existing user
  - [ ] Set user as workspace owner
  - [ ] Create workspace membership for each user
  - [ ] Update all existing tasks with workspace_id
  - [ ] Update all existing conversations with workspace_id
- [ ] Options:
  - [ ] Add to same migration file with `execute/2` callbacks
  - [ ] Create separate `priv/repo/migrations/YYYYMMDDHHMMSS_migrate_to_workspaces.exs`
  - [ ] Create Mix task: `mix citadel.migrate_workspaces`

### 4.3 Run Migrations

- [ ] Run `mix ash.migrate`
- [ ] Verify data:
  - [ ] All users have a personal workspace
  - [ ] All users have workspace membership
  - [ ] All tasks have workspace_id set
  - [ ] All conversations have workspace_id set
- [ ] Add NOT NULL constraints to workspace_id columns (if not already)

---

## Phase 5: UI & LiveViews

**Goal**: Build user interfaces for workspace management, switching, and viewing workspace details.

### 5.1 Create Workspace LiveViews

- [ ] Create `lib/citadel_web/live/workspace_live/index.ex`
  - [ ] List all workspaces user is a member of
  - [ ] Button to create new workspace
  - [ ] Link to workspace details
  - [ ] Show owner badge for workspaces user owns
- [ ] Create `lib/citadel_web/live/workspace_live/show.ex`
  - [ ] Display workspace name
  - [ ] List all members
  - [ ] Show pending invitations
  - [ ] Button to invite new members (owner only)
  - [ ] Button to edit workspace settings (owner only)
  - [ ] Button to leave workspace (non-owners only)
- [ ] Create `lib/citadel_web/live/workspace_live/form_component.ex`
  - [ ] Form for creating/editing workspace
  - [ ] Input for workspace name
  - [ ] Handle create/update actions
- [ ] Create `lib/citadel_web/live/workspace_live/invite_component.ex`
  - [ ] Form to send email invitation
  - [ ] Input for email address
  - [ ] Display list of pending invitations
  - [ ] Button to revoke invitations

### 5.2 Create Invitation Acceptance LiveView

- [ ] Create `lib/citadel_web/live/invitation_live/accept.ex`
  - [ ] Public page (no auth required initially)
  - [ ] Load invitation by token from URL
  - [ ] Display workspace name and inviter
  - [ ] Show error if invitation expired or already accepted
  - [ ] Accept button (checks if user is logged in)
  - [ ] Redirect to login if not authenticated
  - [ ] Create membership and redirect to workspace if authenticated

### 5.3 Create Workspace Switcher Component

- [ ] Create `lib/citadel_web/components/workspace_switcher.ex`
- [ ] Dropdown/modal showing all user's workspaces
- [ ] Display current workspace
- [ ] Click to switch to different workspace
- [ ] Link to workspace management
- [ ] Add to navbar in `lib/citadel_web/components/layouts/app.html.heex`

### 5.4 Update Router

- [ ] Add workspace routes to `lib/citadel_web/router.ex`:
  ```elixir
  scope "/workspaces", CitadelWeb do
    pipe_through [:browser, :require_authenticated_user]

    live "/", WorkspaceLive.Index, :index
    live "/new", WorkspaceLive.Index, :new
    live "/:id", WorkspaceLive.Show, :show
    live "/:id/edit", WorkspaceLive.Show, :edit
    live "/:id/invite", WorkspaceLive.Show, :invite
  end

  scope "/invitations", CitadelWeb do
    pipe_through :browser

    live "/:token", InvitationLive.Accept, :show
  end
  ```

### 5.5 Update Existing LiveViews

- [ ] Update `lib/citadel_web/live/task_live/*`
  - [ ] Load current_workspace in mount
  - [ ] Set tenant on all queries: `|> Ash.Query.set_tenant(current_workspace.id)`
  - [ ] Set tenant on all changesets: `|> Ash.Changeset.set_tenant(current_workspace.id)`
  - [ ] Update navigation/breadcrumbs to include workspace context
- [ ] Update `lib/citadel_web/live/chat_live.ex`
  - [ ] Load current_workspace in mount
  - [ ] Set tenant on all queries and changesets
  - [ ] Update PubSub subscriptions (see Phase 6)

### 5.6 Session Management

- [ ] Update authentication hooks to set default workspace
- [ ] Store `current_workspace_id` in session
- [ ] Create helper to load workspace: `on_mount :load_workspace`
- [ ] Add workspace switcher that updates session
- [ ] Redirect to workspace selection if user has no default workspace set

---

## Phase 6: Background Jobs & Real-time Updates

**Goal**: Update Oban jobs and PubSub topics to respect workspace boundaries.

### 6.1 Update Oban Jobs

- [ ] Update `lib/citadel/chat/workers/conversation_namer.ex`
  - [ ] Add `workspace_id` to job args
  - [ ] Set tenant when loading conversation: `Ash.Query.set_tenant(workspace_id)`
  - [ ] Ensure job passes workspace context through actor persister
- [ ] Review any other background jobs for workspace context needs

### 6.2 Update PubSub Topics

- [ ] Update conversation broadcasts in `lib/citadel/chat/conversation.ex`:
  - [ ] Change topic from `"conversations:#{id}"` to `"workspace:#{workspace_id}:conversation:#{id}"`
- [ ] Update message broadcasts in `lib/citadel/chat/message.ex`:
  - [ ] Change topic from `"conversations:#{conversation_id}"` to `"workspace:#{workspace_id}:conversation:#{conversation_id}"`
- [ ] Update subscriptions in `lib/citadel_web/live/chat_live.ex`:
  - [ ] Subscribe to workspace-scoped topics
  - [ ] Load workspace from conversation/message for topic construction

### 6.3 Verify Real-time Updates

- [ ] Test conversation updates are workspace-isolated
- [ ] Test message streaming works within workspace context
- [ ] Verify users in different workspaces don't see each other's updates

---

## Phase 7: Invitation Flow

**Goal**: Implement complete email invitation workflow from sending to acceptance.

### 7.1 Email Integration

- [ ] Create email template in `lib/citadel_web/emails/workspace_invitation.ex`
  - [ ] Include workspace name
  - [ ] Include inviter name
  - [ ] Include invitation link with token
  - [ ] Include expiration date
- [ ] Update invitation create action to send email:
  - [ ] Use `Ash.Changeset.after_action` to send email after creation
  - [ ] Pass invitation details to mailer
- [ ] Configure email delivery (if not already configured)

### 7.2 Acceptance Flow Implementation

- [ ] Implement acceptance logic in invitation resource:
  - [ ] Validate token hasn't expired
  - [ ] Validate invitation hasn't been accepted
  - [ ] Set accepted_at timestamp
  - [ ] Create workspace membership
  - [ ] Use transaction to ensure atomicity
- [ ] Update `InvitationLive.Accept`:
  - [ ] Handle acceptance success/failure
  - [ ] Show appropriate messages
  - [ ] Redirect flow based on auth state

### 7.3 Edge Cases

- [ ] Handle invitation to existing workspace member (show friendly message)
- [ ] Handle expired invitations (show can't accept)
- [ ] Handle already accepted invitations (show already accepted)
- [ ] Handle invalid tokens (404 or error page)
- [ ] Handle user already logged in when accepting (auto-accept)

---

## Phase 8: Testing & Validation

**Goal**: Comprehensive testing of workspace functionality and data isolation.

### 8.1 Create Test Helpers

- [ ] Create workspace generator in test support:
  - [ ] Generate workspace with unique name
  - [ ] Generate workspace membership
  - [ ] Generate workspace invitation
- [ ] Update existing test helpers:
  - [ ] Add workspace context to task generators
  - [ ] Add workspace context to conversation generators

### 8.2 Resource Tests

- [ ] Test `Workspace` resource:
  - [ ] Create workspace
  - [ ] Update workspace name
  - [ ] Delete workspace
  - [ ] List user's workspaces
- [ ] Test `WorkspaceMembership` resource:
  - [ ] Add member to workspace
  - [ ] Remove member from workspace
  - [ ] List workspace members
  - [ ] Prevent duplicate memberships
- [ ] Test `WorkspaceInvitation` resource:
  - [ ] Create invitation with valid email
  - [ ] Accept invitation creates membership
  - [ ] Expired invitations can't be accepted
  - [ ] Already accepted invitations can't be re-accepted

### 8.3 Multitenancy Tests

- [ ] Test Task multitenancy:
  - [ ] Users can only see tasks in their workspaces
  - [ ] Users can't access tasks in other workspaces
  - [ ] Queries without tenant raise error
- [ ] Test Conversation multitenancy:
  - [ ] Users can only see conversations in their workspaces
  - [ ] Users can't access conversations in other workspaces
- [ ] Test Message multitenancy:
  - [ ] Messages respect workspace boundaries through conversation
  - [ ] Can't access messages from other workspace conversations

### 8.4 Authorization Tests

- [ ] Test workspace authorization:
  - [ ] Only members can read workspace
  - [ ] Only owner can update workspace
  - [ ] Only owner can delete workspace
- [ ] Test membership authorization:
  - [ ] Only workspace owner can add members
  - [ ] Only workspace owner can remove members
  - [ ] Owner can't remove themselves
- [ ] Test invitation authorization:
  - [ ] Only members can create invitations
  - [ ] Anyone with token can accept
  - [ ] Only owner can revoke invitations

### 8.5 LiveView Tests

- [ ] Test `WorkspaceLive.Index`:
  - [ ] Lists user's workspaces
  - [ ] Create new workspace
  - [ ] Navigate to workspace details
- [ ] Test `WorkspaceLive.Show`:
  - [ ] Displays workspace details
  - [ ] Lists members
  - [ ] Invite new members (owner)
  - [ ] Leave workspace (non-owner)
- [ ] Test `InvitationLive.Accept`:
  - [ ] Displays invitation details
  - [ ] Accepts valid invitation
  - [ ] Rejects expired invitation
  - [ ] Rejects already accepted invitation

### 8.6 Update Existing Tests

- [ ] Update all task tests to include workspace context
- [ ] Update all conversation tests to include workspace context
- [ ] Update all message tests to include workspace context
- [ ] Fix any broken tests due to multitenancy requirements

### 8.7 Run Full Test Suite

- [ ] Run `mix test`
- [ ] Fix all failing tests
- [ ] Ensure 100% test passage

---

## Phase 9: Polish & Documentation

**Goal**: Add validation, error handling, and documentation to complete the feature.

### 9.1 Add Validation & Constraints

- [ ] Workspace validations:
  - [ ] Name required, 1-100 characters
  - [ ] Owner required
- [ ] Invitation validations:
  - [ ] Email format validation
  - [ ] Can't invite existing members
  - [ ] Check invitation limit per workspace (optional)
- [ ] Membership validations:
  - [ ] Owner can't leave workspace
  - [ ] Must transfer ownership before leaving (future feature)

### 9.2 Error Handling

- [ ] Add friendly error messages for:
  - [ ] Workspace not found
  - [ ] Invitation expired
  - [ ] Not a workspace member
  - [ ] Not workspace owner
  - [ ] Invalid invitation token
- [ ] Update LiveViews to display errors properly
- [ ] Add flash messages for success/error cases

### 9.3 UI Polish

- [ ] Add workspace badge/indicator to navbar
- [ ] Style workspace switcher dropdown
- [ ] Add empty states:
  - [ ] No workspaces
  - [ ] No members
  - [ ] No pending invitations
  - [ ] No tasks in workspace
  - [ ] No conversations in workspace
- [ ] Add loading states for async operations
- [ ] Add confirmation dialogs for destructive actions

### 9.4 Run Code Quality Checks

- [ ] Run `mix ck` (format, lint, security)
- [ ] Fix all warnings and issues
- [ ] Run `mix test` one final time
- [ ] Ensure all tests pass

### 9.5 Documentation

- [ ] Update README.md with workspace feature description
- [ ] Add workspace usage examples
- [ ] Document invitation flow
- [ ] Add screenshots (optional)
- [ ] Update any API documentation

---

## Key Implementation Notes

### Always Set Tenant
Every query and changeset for workspace-scoped resources (Task, Conversation) must call `set_tenant(workspace_id)`:

```elixir
# Queries
Task
|> Ash.Query.for_read(:read)
|> Ash.Query.set_tenant(workspace_id)
|> Ash.read!()

# Changesets
Task
|> Ash.Changeset.for_create(:create, params)
|> Ash.Changeset.set_tenant(workspace_id)
|> Ash.create!()
```

### TaskState Remains Global
Task states (statuses) are shared across all workspaces. This allows consistency in task management. Future enhancement could make them workspace-specific if needed.

### Session Management Pattern
Store `current_workspace_id` in session and load the workspace in `on_mount`:

```elixir
def on_mount(:load_workspace, _params, session, socket) do
  workspace_id = session["current_workspace_id"]
  workspace = Accounts.get_workspace!(workspace_id, actor: socket.assigns.current_user)
  {:cont, assign(socket, current_workspace: workspace)}
end
```

### Migration Safety
Create personal workspaces for existing users BEFORE adding NOT NULL constraints to `workspace_id` columns. The migration should:
1. Add nullable `workspace_id` columns
2. Run data migration to populate values
3. Add NOT NULL constraint
4. Add foreign key constraint

### PubSub Scoping Pattern
Workspace-scoped topics follow the pattern:
```
"workspace:#{workspace_id}:resource:#{resource_id}"
```

This ensures real-time updates are isolated to workspace members.

---

## Success Criteria

- [ ] Users can create workspaces
- [ ] Users can invite others via email
- [ ] Users can accept invitations and join workspaces
- [ ] Users can switch between workspaces
- [ ] Tasks are scoped to workspaces
- [ ] Conversations are scoped to workspaces
- [ ] Users cannot access data from workspaces they're not members of
- [ ] All tests pass
- [ ] Code quality checks pass (mix ck)
- [ ] Existing data migrated successfully
- [ ] Real-time updates respect workspace boundaries

---

## Future Enhancements (Out of Scope)

- Role-based permissions (Admin, Member, Viewer)
- Workspace billing/subscriptions
- Workspace settings and customization
- Transfer workspace ownership
- Workspace usage analytics
- Workspace templates
- Bulk member import
- SSO/SAML integration
- Audit logs for workspace actions
- Workspace-specific task states
- Projects (future feature to group tasks)