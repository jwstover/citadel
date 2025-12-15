defmodule CitadelWeb.Emails.PasswordReset do
  @moduledoc """
  MJML template for password reset emails.
  Uses the base layout for consistent header/footer.
  """
  use MjmlEEx,
    mjml_template: "password_reset.mjml.eex",
    layout: CitadelWeb.Emails.BaseLayout
end
