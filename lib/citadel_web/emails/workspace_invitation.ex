defmodule CitadelWeb.Emails.WorkspaceInvitation do
  @moduledoc """
  MJML template for workspace invitation emails.
  Uses the base layout for consistent header/footer.
  """
  use MjmlEEx,
    mjml_template: "workspace_invitation.mjml.eex",
    layout: CitadelWeb.Emails.BaseLayout
end
