defmodule Citadel.Workers.SendPasswordResetEmailWorkerTest do
  use Citadel.DataCase, async: true
  use Oban.Testing, repo: Citadel.Repo

  import Swoosh.TestAssertions

  alias Citadel.Workers.SendPasswordResetEmailWorker

  describe "perform/1" do
    test "sends password reset email successfully" do
      user = create_user()
      token = "test_reset_token_#{System.unique_integer([:positive])}"

      assert :ok = perform_job(SendPasswordResetEmailWorker, %{user_id: user.id, token: token})

      assert_email_sent(fn email ->
        assert email.to == [{user.name || "", to_string(user.email)}]
        assert email.subject =~ "Reset your Citadel password"
      end)
    end

    test "email contains reset link with token" do
      user = create_user()
      token = "test_reset_token_#{System.unique_integer([:positive])}"

      assert :ok = perform_job(SendPasswordResetEmailWorker, %{user_id: user.id, token: token})

      assert_email_sent(fn email ->
        assert email.text_body =~ "/password-reset/#{token}"
        assert email.html_body =~ "/password-reset/#{token}"
      end)
    end

    test "succeeds when user not found" do
      assert :ok =
               perform_job(SendPasswordResetEmailWorker, %{
                 user_id: Ash.UUID.generate(),
                 token: "fake_token"
               })

      assert_no_email_sent()
    end
  end
end
