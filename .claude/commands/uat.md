---
argument-hint: <scenario description>
description: Run automated UAT testing against the local dev server using Playwright browser automation
---

# UAT: $ARGUMENTS

You are an automated UAT tester for the Citadel application. Your job is to start the necessary services, execute the given scenario using browser automation, and report a clear PASS or FAIL with evidence.

## UAT Credentials

- **Email:** `uat@citadel.test`
- **Password:** `UatTest123!`

---

## Phase 1: Find an Available Port

**Always prefer port 4002** since `.mcp.json` has `citadel-dev` hardcoded to `localhost:4002`. Only use another port if 4002 is occupied.

```bash
if ! lsof -i :4002 -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "AVAILABLE:4002"
else
  for port in 4001 4003 4004 4005; do
    if ! lsof -i :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
      echo "AVAILABLE:$port"
      break
    fi
  done
fi
```

Use the first available port as `$PORT` for all subsequent steps. If none are available, stop and report that all ports are in use.

Also note the port for the agent runner's `CITADEL_URL` — it must match.

---

## Phase 2: Seed the UAT User and API Key

Run this seed script to ensure the UAT user exists, is email-confirmed, has a workspace, and has an active API key:

```bash
PORT=$PORT mix run -e '
  require Ash.Query

  email = "uat@citadel.test"
  password = "UatTest123!"
  port = System.get_env("PORT", "4001")

  # Step 1: Register user (idempotent — fails gracefully if exists)
  user =
    case Citadel.Accounts.User
         |> Ash.Query.filter(email == ^email)
         |> Ash.read_one!(authorize?: false) do
      nil ->
        {:ok, user} =
          Citadel.Accounts.User
          |> Ash.Changeset.for_create(
            :register_with_password,
            %{email: email, password: password, password_confirmation: password},
            authorize?: false
          )
          |> Ash.create(authorize?: false)
        IO.puts("Created UAT user: #{user.id}")
        user

      existing ->
        IO.puts("UAT user already exists: #{existing.id}")
        existing
    end

  # Step 2: Confirm email via direct SQL (bypasses email confirmation flow)
  # Note: UUID columns require $1::uuid cast and Ecto.UUID.dump!/1
  Citadel.Repo.query!(
    "UPDATE users SET confirmed_at = NOW() WHERE id = $1::uuid AND confirmed_at IS NULL",
    [Ecto.UUID.dump!(user.id)]
  )
  IO.puts("Email confirmed")

  # Step 3: Get the user'\''s workspace
  workspace =
    Citadel.Accounts.Workspace
    |> Ash.Query.filter(owner_id == ^user.id)
    |> Ash.read_one!(authorize?: false)

  unless workspace do
    IO.puts("ERROR: No workspace found for UAT user. Registration may not have created one.")
    System.halt(1)
  end

  IO.puts("Workspace: #{workspace.id}")

  # Step 4: Delete existing API key (raw key is not recoverable) and create fresh
  existing_key =
    Citadel.Accounts.ApiKey
    |> Ash.Query.filter(user_id == ^user.id and workspace_id == ^workspace.id)
    |> Ash.read_one!(authorize?: false)

  if existing_key do
    Ash.destroy!(existing_key, authorize?: false)
    IO.puts("Deleted existing API key")
  end

  api_key = Citadel.Accounts.create_api_key!(
    "UAT key",
    DateTime.add(DateTime.utc_now(), 365, :day),
    user.id,
    workspace.id,
    authorize?: false
  )

  # Raw key is stored in metadata by GenerateApiKey change, not as a struct field
  raw_key = Ash.Resource.get_metadata(api_key, :plaintext_api_key)
  IO.puts("UAT_API_KEY=#{raw_key}")
  IO.puts("UAT_WORKSPACE_ID=#{workspace.id}")
  IO.puts("UAT_USER_ID=#{user.id}")
'
```

Capture the output. Extract `UAT_API_KEY` from the output — you will need it for the agent runner.

---

## Phase 3: Start Services

**Phoenix server** — start on the available port found in Phase 1:

```bash
PORT=$PORT mix phx.server
```

Run in background. Poll until the server responds:

```bash
until curl -s -o /dev/null -w "%{http_code}" http://localhost:$PORT | grep -q "200\|302\|301"; do
  sleep 1
done
echo "Server ready on port $PORT"
```

Timeout after 30 seconds — if the server hasn't started by then, stop and report failure.

**Agent runner** — start only if the scenario involves agent task execution.

Run from the `citadel_agent/` subdirectory with these env vars:

```bash
cd citadel_agent && \
env -u ANTHROPIC_API_KEY \
CITADEL_URL=http://localhost:$PORT \
CITADEL_API_KEY=<UAT_API_KEY from Phase 2> \
CITADEL_DEV_API_KEY=<UAT_API_KEY from Phase 2> \
CITADEL_PROJECT_PATH=<project root, not citadel_agent/> \
GITHUB_TOKEN=$(gh auth token) \
mix citadel_agent.run
```

Notes:
- `env -u ANTHROPIC_API_KEY` prevents the agent from using a potentially low-balance key instead of Claude Code's built-in auth
- `CITADEL_DEV_API_KEY` must match `CITADEL_API_KEY` — it authenticates the `citadel-dev` MCP server in `.mcp.json`
- `GITHUB_TOKEN` is required by the agent runner's preflight checks
- The agent runner **must** be started from `citadel_agent/`, not the project root

Run in background.

**App URL** for all browser steps: `http://localhost:$PORT`

---

## Phase 4: Execute the Scenario

Use the `playwright-cli` skill to drive the browser. All navigation uses `http://localhost:$PORT`.

### Login

1. Navigate to `http://localhost:$PORT/sign-in`
2. Fill email: `uat@citadel.test`
3. Fill password: `UatTest123!`
4. Submit the form
5. Verify redirect away from `/sign-in` (should land on home/dashboard)

If login fails, stop and report FAIL with the exact error shown on screen.

### Scenario

Execute the following scenario step by step:

**$ARGUMENTS**

For each step:
- Describe the action
- Perform it
- Record what you observed

Take a screenshot at the start, at key state changes, and at the final state.

---

## Phase 5: Report

Output a structured result:

```
## UAT Result: PASS | FAIL

### Scenario
$ARGUMENTS

### Steps Executed
1. [action] → [observed outcome]
2. ...

### Evidence
- [key elements verified, screenshots taken]

### Notes
- [unexpected behavior, flakiness, environmental issues]
```

PASS if all expected outcomes from the scenario were observed. FAIL if any step produced a result contradicting the scenario's expectations.

---

## Phase 6: Cleanup

Kill the background Phoenix server and agent runner processes once testing is complete.