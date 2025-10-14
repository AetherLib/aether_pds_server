defmodule AetherPDSServer.Accounts.SigningKey do
  @moduledoc """
  Represents a cryptographic signing key for an account.

  Each account has one or more signing keys used for:
  - Signing repository commits
  - Proving control of the DID
  - Verifying record authenticity

  Only one key can be active at a time per account.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "signing_keys" do
    belongs_to :account, AetherPDSServer.Accounts.Account

    field :public_key_multibase, :string
    field :private_key_encrypted, :string
    field :key_type, :string, default: "k256"
    field :status, :string, default: "active"
    field :rotated_at, :utc_datetime_usec

    # Virtual field for decrypted private key (never persisted)
    field :private_key_decrypted, :string, virtual: true

    timestamps()
  end

  @doc """
  Changeset for creating a new signing key.
  """
  def changeset(signing_key, attrs) do
    signing_key
    |> cast(attrs, [
      :account_id,
      :public_key_multibase,
      :private_key_encrypted,
      :key_type,
      :status,
      :rotated_at
    ])
    |> validate_required([
      :account_id,
      :public_key_multibase,
      :private_key_encrypted,
      :key_type,
      :status
    ])
    |> validate_inclusion(:key_type, ["k256", "p256"])
    |> validate_inclusion(:status, ["active", "rotated", "revoked"])
    |> foreign_key_constraint(:account_id)
    |> validate_multibase_format()
    |> unique_constraint(:account_id,
      name: :one_active_key_per_account,
      message: "account already has an active signing key"
    )
  end

  @doc """
  Changeset for rotating a key (marking it as rotated).
  """
  def rotation_changeset(signing_key, attrs \\ %{}) do
    signing_key
    |> cast(attrs, [:status, :rotated_at])
    |> validate_required([:status, :rotated_at])
    |> validate_inclusion(:status, ["rotated", "revoked"])
  end

  defp validate_multibase_format(changeset) do
    validate_change(changeset, :public_key_multibase, fn :public_key_multibase, value ->
      if String.starts_with?(value, "z") and String.length(value) > 10 do
        []
      else
        [public_key_multibase: "must be a valid multibase-encoded public key starting with 'z'"]
      end
    end)
  end
end
