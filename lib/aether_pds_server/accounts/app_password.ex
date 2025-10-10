# lib/aether_pds_server/accounts/app_password.ex
defmodule AetherPDSServer.Accounts.AppPassword do
  use Ecto.Schema
  import Ecto.Changeset

  alias AetherPDSServer.Accounts.Account

  @primary_key {:id, :id, autogenerate: true}
  schema "app_passwords" do
    field :name, :string
    field :password_hash, :string
    field :privileged, :boolean, default: false
    field :created_at, :utc_datetime_usec

    # Virtual field for password input
    field :password, :string, virtual: true

    belongs_to :account, Account

    timestamps(updated_at: false)
  end

  @doc """
  Changeset for creating an app password
  """
  def changeset(app_password, attrs) do
    app_password
    |> cast(attrs, [:account_id, :name, :password_hash, :privileged, :created_at])
    |> validate_required([:account_id, :name, :password_hash])
    |> validate_length(:name, min: 1, max: 255)
    |> unique_constraint([:account_id, :name])
  end

  @doc """
  Changeset for creating an app password with plaintext password
  """
  def create_changeset(app_password, attrs) do
    app_password
    |> cast(attrs, [:account_id, :name, :password, :privileged])
    |> validate_required([:account_id, :name, :password])
    |> validate_length(:name, min: 1, max: 255)
    |> put_password_hash()
    |> put_created_at()
    |> unique_constraint([:account_id, :name])
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end

  defp put_created_at(changeset) do
    put_change(changeset, :created_at, DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end
end
