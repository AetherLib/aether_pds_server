# lib/aether_pds_server/oauth/refresh_token.ex
defmodule AetherPDSServer.OAuth.RefreshToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth_refresh_tokens" do
    field :token, :string
    field :did, :string
    field :client_id, :string
    field :expires_at, :utc_datetime
    field :revoked, :boolean, default: false

    timestamps()
  end

  def changeset(refresh_token, attrs) do
    refresh_token
    |> cast(attrs, [:token, :did, :client_id, :expires_at, :revoked])
    |> validate_required([:token, :did, :client_id, :expires_at])
    |> unique_constraint(:token)
  end
end
