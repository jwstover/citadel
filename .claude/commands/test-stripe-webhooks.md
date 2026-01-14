---
description: Run end-to-end tests of Stripe webhook integration with real Stripe API calls
---

# Test Stripe Webhook Integration

This command runs automated end-to-end tests of the Stripe webhook integration using real Stripe API calls in test mode.

## Prerequisites

Before running this test:
1. Ensure `STRIPE_SECRET_KEY` is set (test mode key starting with `sk_test_`)
2. Ensure `stripe` CLI is installed and authenticated
3. Ensure Phoenix server is already running on port 4100 (dev server)

## Test Architecture

The test creates real Stripe resources (customers, subscriptions) and uses webhook forwarding to verify our handlers process events correctly. This provides true end-to-end testing rather than mocked unit tests.

---

## Phase 1: Environment Setup

Set up the Stripe webhook forwarder to forward events to the already running Phoenix server.

### 1.1 Start Stripe Webhook Forwarder

In a background process, start the Stripe CLI webhook listener:

```bash
stripe listen --forward-to localhost:4100/webhooks/stripe
```

**Important**: Note the webhook signing secret output by the CLI (starts with `whsec_`). You may need to verify this matches the configured `STRIPE_WEBHOOK_SECRET` or the dev environment's signing secret.

### 1.2 Verify Infrastructure

Wait a few seconds, then verify both services are running:
- Check Phoenix is responding: `curl -s http://localhost:4100/health` or check logs
- Check Stripe CLI is forwarding (it will show "Ready!" in its output)

---

## Phase 2: Create Test Data

Create the necessary database records for testing.

### 2.1 Create Test User, Organization, and Subscription

Use `mcp__tidewave__project_eval` to create test data:

```elixir
# Create a test user
{:ok, user} = Citadel.Accounts.User
|> Ash.Changeset.for_create(:create, %{
  email: "stripe-webhook-test-#{System.unique_integer([:positive])}@test.local",
  name: "Stripe Webhook Test User",
  hashed_password: Bcrypt.hash_pwd_salt("test-password-123")
})
|> Ash.create(authorize?: false)

# Create organization for the user
{:ok, org} = Citadel.Accounts.create_organization!(%{
  name: "Webhook Test Org #{System.unique_integer([:positive])}",
  owner_id: user.id
}, authorize?: false)

# The organization should already have a subscription created automatically
# If not, create one:
subscription = case Citadel.Billing.get_subscription_by_organization(org.id, authorize?: false) do
  {:ok, sub} -> sub
  _ ->
    Citadel.Billing.create_subscription!(org.id, :free, authorize?: false)
end

# Output the IDs we need
%{
  user_id: user.id,
  org_id: org.id,
  subscription_id: subscription.id,
  initial_tier: subscription.tier,
  initial_status: subscription.status
}
```

Store the `org_id` and `subscription_id` for use in subsequent steps.

### 2.2 Create Stripe Customer

Create a real Stripe customer and link it to our subscription:

```elixir
# Create Stripe customer
{:ok, customer} = Stripe.Customer.create(%{
  email: "webhook-test@example.com",
  name: "Webhook Test Customer",
  metadata: %{
    organization_id: org_id,  # Use the org_id from previous step
    test: "true"
  }
})

# Update our subscription with the Stripe customer ID
Citadel.Billing.update_subscription!(subscription, %{
  stripe_customer_id: customer.id
}, authorize?: false)

customer.id
```

Store the `customer_id` (starts with `cus_`).

---

## Phase 3: Test checkout.session.completed

This event activates a Pro subscription after successful payment.

### 3.1 Trigger the Event

Use `stripe trigger` with `--override` to inject our organization ID:

```bash
stripe trigger checkout.session.completed \
  --override checkout_session:metadata.organization_id=<ORG_ID> \
  --override checkout_session:customer=<CUSTOMER_ID> \
  --override checkout_session:subscription=sub_test_webhook_123
```

Replace `<ORG_ID>` and `<CUSTOMER_ID>` with the actual values.

### 3.2 Verify Database State

Wait 2-3 seconds for the webhook to process, then verify:

```elixir
subscription = Citadel.Billing.get_subscription_by_organization!(org_id, authorize?: false)

%{
  tier: subscription.tier,           # Should be :pro
  status: subscription.status,       # Should be :active
  stripe_subscription_id: subscription.stripe_subscription_id,  # Should be set
  stripe_customer_id: subscription.stripe_customer_id           # Should match
}
```

**Expected**: `tier` changed from `:free` to `:pro`, `status` is `:active`.

---

## Phase 4: Test invoice.paid

This event updates subscription period dates after successful payment.

### 4.1 Create a Real Stripe Subscription

For invoice events to work, we need a real Stripe subscription:

```elixir
# First, get a price ID from your Stripe account (or create one)
# You can list prices with: Stripe.Price.list(%{limit: 5})

# Create a subscription (this will also trigger webhooks)
{:ok, stripe_sub} = Stripe.Subscription.create(%{
  customer: customer_id,
  items: [%{price: "price_xxx"}],  # Use a real test price ID
  metadata: %{organization_id: org_id}
})

# Update our DB subscription with the Stripe subscription ID
Citadel.Billing.update_subscription!(subscription, %{
  stripe_subscription_id: stripe_sub.id
}, authorize?: false)

stripe_sub.id
```

**Note**: Creating the subscription will automatically trigger `invoice.paid` and other webhooks.

### 4.2 Verify Period Dates Updated

```elixir
subscription = Citadel.Billing.get_subscription_by_organization!(org_id, authorize?: false)

%{
  current_period_start: subscription.current_period_start,  # Should be set
  current_period_end: subscription.current_period_end       # Should be set
}
```

---

## Phase 5: Test invoice.payment_failed

This event sets subscription status to `past_due`.

### 5.1 Trigger the Event

```bash
stripe trigger invoice.payment_failed \
  --override invoice:subscription=<STRIPE_SUBSCRIPTION_ID> \
  --override invoice:customer=<CUSTOMER_ID>
```

### 5.2 Verify Status Changed

```elixir
subscription = Citadel.Billing.get_subscription_by_organization!(org_id, authorize?: false)

subscription.status  # Should be :past_due
```

### 5.3 Reset Status for Next Test

```elixir
Citadel.Billing.update_subscription!(subscription, %{status: :active}, authorize?: false)
```

---

## Phase 6: Test customer.subscription.updated

This event syncs subscription changes from Stripe.

### 6.1 Trigger the Event

```bash
stripe trigger customer.subscription.updated \
  --override subscription:id=<STRIPE_SUBSCRIPTION_ID> \
  --override subscription:customer=<CUSTOMER_ID> \
  --override subscription:status=active
```

### 6.2 Verify Sync

```elixir
subscription = Citadel.Billing.get_subscription_by_organization!(org_id, authorize?: false)

%{
  status: subscription.status,
  current_period_start: subscription.current_period_start,
  current_period_end: subscription.current_period_end
}
```

---

## Phase 7: Test customer.subscription.deleted

This event cancels the subscription.

### 7.1 Trigger the Event

```bash
stripe trigger customer.subscription.deleted \
  --override subscription:id=<STRIPE_SUBSCRIPTION_ID> \
  --override subscription:customer=<CUSTOMER_ID>
```

### 7.2 Verify Cancellation

```elixir
subscription = Citadel.Billing.get_subscription_by_organization!(org_id, authorize?: false)

subscription.status  # Should be :canceled
```

---

## Phase 8: Cleanup

### 8.1 Delete Stripe Resources

```elixir
# Cancel the Stripe subscription if it exists
if stripe_subscription_id do
  Stripe.Subscription.cancel(stripe_subscription_id)
end

# Delete the Stripe customer
Stripe.Customer.delete(customer_id)
```

### 8.2 Delete Test Database Records

```elixir
# Delete in reverse order of creation
Ash.destroy!(subscription, authorize?: false)
Ash.destroy!(org, authorize?: false)
Ash.destroy!(user, authorize?: false)
```

### 8.3 Stop Background Processes

Stop the Stripe CLI webhook forwarder process that was started in Phase 1.

---

## Phase 9: Report Results

Summarize the test results:

| Event | Expected Outcome | Actual Outcome | Status |
|-------|------------------|----------------|--------|
| `checkout.session.completed` | tier → :pro, status → :active | | |
| `invoice.paid` | period dates updated | | |
| `invoice.payment_failed` | status → :past_due | | |
| `customer.subscription.updated` | subscription synced | | |
| `customer.subscription.deleted` | status → :canceled | | |

Report any failures with error details and relevant log output.

---

## Troubleshooting

### Webhook signature verification failed
- Ensure the Stripe CLI's signing secret matches your config
- You may need to set `STRIPE_WEBHOOK_SECRET` to the CLI's secret

### Subscription not found errors
- Verify the `stripe_subscription_id` in the database matches the one in the webhook
- Check that the `--override` flags are using the correct IDs

### Events not reaching the server
- Verify Phoenix is running on port 4100
- Verify Stripe CLI shows "Forwarding to localhost:4100"
- Check for firewall or network issues

### Database not updating
- Check Phoenix logs for errors in webhook processing
- Verify the organization_id in the webhook metadata matches your test org