defmodule AetherPDSServer.OAuth.PushedAuthorizationRequest do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "pushed_authorization_requests" do
    field :request_uri, :string
    field :client_id, :string
    field :redirect_uri, :string
    field :response_type, :string
    field :state, :string
    field :code_challenge, :string
    field :code_challenge_method, :string
    field :scope, :string
    field :expires_at, :utc_datetime_usec
    field :used, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(par, attrs) do
    par
    |> cast(attrs, [
      :request_uri,
      :client_id,
      :redirect_uri,
      :response_type,
      :state,
      :code_challenge,
      :code_challenge_method,
      :scope,
      :expires_at,
      :used
    ])
    |> validate_required([
      :request_uri,
      :client_id,
      :redirect_uri,
      :response_type,
      :state,
      :code_challenge,
      :code_challenge_method,
      :scope,
      :expires_at
    ])
    |> unique_constraint(:request_uri)
  end
end
