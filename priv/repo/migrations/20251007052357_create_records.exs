defmodule AetherPDSServer.Repo.Migrations.CreateRecords do
  use Ecto.Migration

  def change do
    create table(:records) do
      add :repository_did,
          references(:repositories, column: :did, type: :string, on_delete: :delete_all),
          null: false

      # e.g., "app.bsky.feed.post"
      add :collection, :string, null: false
      # Record key
      add :rkey, :string, null: false
      # Content identifier
      add :cid, :string, null: false
      # The actual record data (JSON)
      add :value, :map, null: false

      timestamps()
    end

    create unique_index(:records, [:repository_did, :collection, :rkey])
    create index(:records, [:repository_did, :collection])
    create index(:records, [:cid])
  end
end
