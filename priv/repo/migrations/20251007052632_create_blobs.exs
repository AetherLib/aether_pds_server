defmodule AetherPDSServer.Repo.Migrations.CreateBlobs do
  use Ecto.Migration

  def change do
    create table(:blobs) do
      add :repository_did,
          references(:repositories, column: :did, type: :string, on_delete: :delete_all),
          null: false

      add :cid, :string, null: false
      add :mime_type, :string, null: false
      add :size, :integer, null: false

      # Actual blob data (or null if using external storage like S3)
      add :data, :binary

      timestamps()
    end

    create unique_index(:blobs, [:repository_did, :cid])
    create index(:blobs, [:cid])
  end
end
