defmodule CitadelWeb.AuthComponents.PasswordHint do
  @moduledoc false
  use CitadelWeb, :html

  def render(assigns) do
    ~H"""
    <p class="text-xs text-base-content/60 mb-4">
      At least 8 characters with uppercase, lowercase, and a number.
    </p>
    """
  end
end
