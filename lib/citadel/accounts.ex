defmodule Citadel.Accounts do
  use Ash.Domain, otp_app: :citadel, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Citadel.Accounts.Token
    resource Citadel.Accounts.User
  end
end
