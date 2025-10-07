defmodule AetherPDSServer.Repo.Migrations.CreateCommits do
  use Ecto.Migration

  def change do
    create table(:commits) do
      add :repository_did,
          references(:repositories, column: :did, type: :string, on_delete: :delete_all),
          null: false

      add :cid, :string, null: false
      # TID (timestamp identifier)
      add :rev, :string, null: false
      # Previous commit CID (null for genesis)
      add :prev, :string
      # Full commit structure (version, sig, etc.)
      add :data, :map, null: false

      timestamps()
    end

    create unique_index(:commits, [:repository_did, :cid])
    create index(:commits, [:repository_did, :rev])
    create index(:commits, [:cid])
  end
end
