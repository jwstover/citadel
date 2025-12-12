defmodule CitadelWeb.AuthOverrides do
  @moduledoc """
  Configuration module for customizing AshAuthentication Phoenix UI components.
  Styles the auth pages to match the Citadel application design using DaisyUI.
  """
  use AshAuthentication.Phoenix.Overrides

  alias AshAuthentication.Phoenix.Components

  # Root container - dark background with centered content
  override AshAuthentication.Phoenix.SignInLive do
    set :root_class, "grid h-screen place-items-center bg-base-100"
  end

  # Confirmation page - same styling as sign-in
  override AshAuthentication.Phoenix.ConfirmLive do
    set :root_class, "grid h-screen place-items-center bg-base-100"
  end

  override Components.Confirm do
    set :root_class, "w-full max-w-md"
    set :strategy_class, "card bg-base-200 border border-base-300 p-6"
    set :show_banner, false
  end

  override Components.Confirm.Form do
    set :label_class, "text-xl font-bold mb-4"
  end

  override Components.Confirm.Input do
    set :submit_class, "btn btn-primary w-full"
  end

  # Main sign-in component - card styling
  override Components.SignIn do
    set :root_class, "w-full max-w-md card bg-base-200 border border-base-300 p-6"
    set :strategy_class, ""
    set :show_banner, false
  end

  # Password input fields - DaisyUI form styling
  override Components.Password.Input do
    set :input_class, "input input-bordered w-full"
    set :input_class_with_error, "input input-bordered input-error w-full"
    set :field_class, "fieldset mb-4"
    set :label_class, "label"
    set :submit_class, "btn btn-primary w-full"
    set :error_ul, "text-error text-sm mt-1"
    set :error_li, ""
  end

  # Sign-in form styling
  override Components.Password.SignInForm do
    set :slot_class, "flex justify-between text-sm mt-4"
    set :label_class, "text-xl font-bold mb-4"
  end

  # Register form styling
  override Components.Password.RegisterForm do
    set :slot_class, "flex justify-between text-sm mt-4"
    set :label_class, "text-xl font-bold mb-4"
  end

  # Reset form styling
  override Components.Password.ResetForm do
    set :slot_class, "flex justify-between text-sm mt-4"
    set :label_class, "text-xl font-bold mb-4"
  end

  # Password component - toggler links with proper spacing
  override Components.Password do
    set :toggler_class, "link link-primary"
    set :interstitial_class, "flex flex-row justify-between gap-4 text-sm mb-4"
  end

  # OAuth2 button - ghost style for dark background
  override Components.OAuth2 do
    set :root_class, "w-full"

    set :link_class,
        "btn btn-ghost border border-base-content/20 hover:border-base-content/40 w-full gap-2"
  end

  # Horizontal rule divider - override all nested elements to use DaisyUI divider
  override Components.HorizontalRule do
    set :root_class, "divider my-4"
    set :hr_outer_class, "hidden"
    set :hr_inner_class, "hidden"
    set :text_outer_class, ""
    set :text_inner_class, "text-base-content/60"
    set :text, "or"
  end
end
