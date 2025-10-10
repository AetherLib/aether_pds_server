# lib/aether_pds_server/accounts/account.ex
defmodule AetherPDSServer.Accounts.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "accounts" do
    field :did, :string
    field :handle, :string
    field :email, :string
    field :password_hash, :string
    field :status, :string, default: "active"
    field :deactivated_at, :utc_datetime_usec

    # Virtual field for password input
    field :password, :string, virtual: true

    timestamps()
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:did, :handle, :email, :password_hash, :status, :deactivated_at])
    |> validate_required([:did, :handle, :email, :password_hash])
    |> validate_format(:email, ~r/@/)
    |> validate_format(:handle, ~r/^[a-zA-Z0-9._-]+$/)
    |> validate_inclusion(:status, ["active", "deactivated", "deleted"])
    |> unique_constraint(:did)
    |> unique_constraint(:handle)
    |> unique_constraint(:email)
  end
end
