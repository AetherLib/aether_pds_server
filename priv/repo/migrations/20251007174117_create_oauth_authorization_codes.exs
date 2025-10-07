defmodule AetherPDSServer.Repo.Migrations.CreateOauthAuthorizationCodes do
  use Ecto.Migration

  def change do
    create table(:oauth_authorization_codes) do
      add :code, :string, null: false
      add :did, :string, null: false
      add :client_id, :string, null: false
      add :redirect_uri, :string, null: false
      add :code_challenge, :string, null: false
      add :scope, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:oauth_authorization_codes, [:code])
    create index(:oauth_authorization_codes, [:did])
    create index(:oauth_authorization_codes, [:expires_at])
    create index(:oauth_authorization_codes, [:used])
  end
end
