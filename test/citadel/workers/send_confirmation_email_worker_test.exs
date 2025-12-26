defmodule Citadel.Workers.SendConfirmationEmailWorkerTest do
  use Citadel.DataCase, async: true

  import Swoosh.TestAssertions

  alias Citadel.Workers.SendConfirmationEmailWorker

  describe "perform/1" do
    test "sends confirmation email successfully" do
      # Create unconfirmed user directly
      user =
        Ash.Seed.seed!(Citadel.Accounts.User, %{
          email: unique_user_email(),
          confirmed_at: nil
        })

      token = "test_confirm_token_#{System.unique_integer([:positive])}"

      assert :ok = perform_job(SendConfirmationEmailWorker, %{user_id: user.id, token: token})

      assert_email_sent(fn email ->
        assert email.to == [{user.name || "", to_string(user.email)}]
        assert email.subject =~ "Confirm your Citadel email address"
      end)
    end

    test "email contains confirmation link with token" do
      # Create unconfirmed user directly
      user =
        Ash.Seed.seed!(Citadel.Accounts.User, %{
          email: unique_user_email(),
          confirmed_at: nil
        })

      token = "test_confirm_token_#{System.unique_integer([:positive])}"

      assert :ok = perform_job(SendConfirmationEmailWorker, %{user_id: user.id, token: token})

      assert_email_sent(fn email ->
        # The URL should go to the ConfirmLive page which has our styled overrides
        assert email.text_body =~ "/confirm_new_user/#{token}"
        assert email.html_body =~ "/confirm_new_user/#{token}"
      end)
    end

    test "succeeds when user not found" do
      assert :ok =
               perform_job(SendConfirmationEmailWorker, %{
                 user_id: Ash.UUID.generate(),
                 token: "fake_token"
               })

      assert_no_email_sent()
    end

    test "skips email when user already confirmed" do
      # Create a user that's already confirmed using Ash.Seed
      user =
        Ash.Seed.seed!(Citadel.Accounts.User, %{
          email: unique_user_email(),
          confirmed_at: DateTime.utc_now()
        })

      token = "test_confirm_token_#{System.unique_integer([:positive])}"

      assert :ok =
               perform_job(SendConfirmationEmailWorker, %{
                 user_id: user.id,
                 token: token
               })

      assert_no_email_sent()
    end
  end
end
