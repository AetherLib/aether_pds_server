# lib/aether_pds_server/oauth/access_token.ex
defmodule AetherPDSServer.OAuth.AccessToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth_access_tokens" do
    field :token, :string
    field :did, :string
    field :scope, :string
    field :jkt, :string
    field :expires_at, :utc_datetime
    field :revoked, :boolean, default: false

    timestamps()
  end

  def changeset(access_token, attrs) do
    access_token
    |> cast(attrs, [:token, :did, :scope, :jkt, :expires_at, :revoked])
    |> validate_required([:token, :did, :scope, :jkt, :expires_at])
    |> unique_constraint(:token)
  end
end
