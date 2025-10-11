defmodule AetherPDSServer.Repo.Migrations.CreatePushedAuthorizationRequests do
  use Ecto.Migration

  def change do
    create table(:pushed_authorization_requests) do
      add :request_uri, :string, null: false
      add :client_id, :string, null: false
      add :redirect_uri, :text, null: false
      add :response_type, :string, null: false
      add :state, :string, null: false
      add :code_challenge, :string, null: false
      add :code_challenge_method, :string, null: false
      add :scope, :string, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :used, :boolean, default: false, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:pushed_authorization_requests, [:request_uri])
    create index(:pushed_authorization_requests, [:expires_at])
    create index(:pushed_authorization_requests, [:used])
  end
end
