defmodule Citadel.Billing.ProcessedWebhookEvent do
  @moduledoc """
  Tracks processed Stripe webhook events to prevent replay attacks.

  Each Stripe event has a unique ID. By recording processed event IDs,
  we can detect and ignore duplicate webhook deliveries (which Stripe
  may send if it doesn't receive a timely 2xx response).
  """
  import Ecto.Query

  use Ash.Resource,
    otp_app: :citadel,
    domain: Citadel.Billing,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "processed_webhook_events"
    repo Citadel.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :record do
      accept [:stripe_event_id, :event_type]
    end

    read :by_stripe_event_id do
      argument :stripe_event_id, :string, allow_nil?: false

      filter expr(stripe_event_id == ^arg(:stripe_event_id))
    end

    action :event_processed?, :boolean do
      argument :stripe_event_id, :string, allow_nil?: false

      run fn input, _context ->
        require Ash.Query

        exists =
          __MODULE__
          |> Ash.Query.filter(stripe_event_id == ^input.arguments.stripe_event_id)
          |> Ash.exists?(authorize?: false)

        {:ok, exists}
      end
    end

    action :cleanup_old_events, :integer do
      argument :older_than_days, :integer, default: 30

      run fn input, _context ->
        require Ash.Query

        cutoff =
          DateTime.utc_now()
          |> DateTime.add(-input.arguments.older_than_days, :day)

        {count, _} =
          Citadel.Repo.delete_all(
            from(e in "processed_webhook_events",
              where: e.processed_at < ^cutoff
            )
          )

        {:ok, count}
      end
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :stripe_event_id, :string do
      allow_nil? false
      public? true
    end

    attribute :event_type, :string do
      allow_nil? true
      public? true
    end

    attribute :processed_at, :utc_datetime_usec do
      allow_nil? false
      default &DateTime.utc_now/0
      public? true
    end

    create_timestamp :inserted_at
  end

  identities do
    identity :unique_stripe_event, [:stripe_event_id]
  end
end
