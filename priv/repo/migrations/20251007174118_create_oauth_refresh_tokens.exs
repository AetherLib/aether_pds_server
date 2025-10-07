defmodule AetherPDSServer.Repo.Migrations.CreateOauthRefreshTokens do
  use Ecto.Migration

  def change do
    create table(:oauth_refresh_tokens) do
      add :token, :string, null: false
      add :did, :string, null: false
      add :client_id, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:oauth_refresh_tokens, [:token])
    create index(:oauth_refresh_tokens, [:did])
    create index(:oauth_refresh_tokens, [:client_id])
    create index(:oauth_refresh_tokens, [:expires_at])
    create index(:oauth_refresh_tokens, [:revoked])
  end
end
