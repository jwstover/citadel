defmodule CitadelWeb.Emails.BaseLayout do
  @moduledoc """
  Base email layout with consistent header and footer.
  All email templates should use this layout via the `:layout` option.
  """
  use MjmlEEx.Layout, mjml_layout: "base_layout.mjml.eex"
end
