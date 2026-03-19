defmodule CitadelWeb.Auth.SignInFormComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  alias AshAuthentication.Phoenix.Components.Password.SignInForm

  @impl true
  def update(assigns, socket), do: SignInForm.update(assigns, socket)

  @impl true
  def render(assigns) do
    SignInForm.render(Map.put(assigns, :label, "Sign in to Pyllar"))
  end

  @impl true
  def handle_event(event, params, socket),
    do: SignInForm.handle_event(event, params, socket)
end

defmodule CitadelWeb.Auth.RegisterFormComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  alias AshAuthentication.Phoenix.Components.Password.RegisterForm

  @impl true
  def update(assigns, socket), do: RegisterForm.update(assigns, socket)

  @impl true
  def render(assigns) do
    RegisterForm.render(Map.put(assigns, :label, "Create your account"))
  end

  @impl true
  def handle_event(event, params, socket),
    do: RegisterForm.handle_event(event, params, socket)
end
