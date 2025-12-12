defmodule CitadelWeb.Emails.EmailConfirmation do
  @moduledoc """
  MJML template for email confirmation emails.
  Uses the base layout for consistent header/footer.
  """
  use MjmlEEx,
    mjml_template: "email_confirmation.mjml.eex",
    layout: CitadelWeb.Emails.BaseLayout
end
