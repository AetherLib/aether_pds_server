defmodule AetherPDSServer.Repo.Migrations.CreateOauthAccessTokens do
  use Ecto.Migration

  def change do
    create table(:oauth_access_tokens) do
      add :token, :string, null: false
      add :did, :string, null: false
      add :scope, :string, null: false
      add :jkt, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :revoked, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:oauth_access_tokens, [:token])
    create index(:oauth_access_tokens, [:did])
    create index(:oauth_access_tokens, [:jkt])
    create index(:oauth_access_tokens, [:expires_at])
    create index(:oauth_access_tokens, [:revoked])
  end
end
