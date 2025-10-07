defmodule AetherPDSServer.OAuth.AuthorizationCode do
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth_authorization_codes" do
    field :code, :string
    field :did, :string
    field :client_id, :string
    field :redirect_uri, :string
    field :code_challenge, :string
    field :scope, :string
    field :expires_at, :utc_datetime
    field :used, :boolean, default: false

    timestamps()
  end

  def changeset(auth_code, attrs) do
    auth_code
    |> cast(attrs, [
      :code,
      :did,
      :client_id,
      :redirect_uri,
      :code_challenge,
      :scope,
      :expires_at,
      :used
    ])
    |> validate_required([
      :code,
      :did,
      :client_id,
      :redirect_uri,
      :code_challenge,
      :scope,
      :expires_at
    ])
    |> unique_constraint(:code)
  end
end
