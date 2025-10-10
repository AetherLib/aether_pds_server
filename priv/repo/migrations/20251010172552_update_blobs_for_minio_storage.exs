defmodule AetherPDSServer.Repo.Migrations.UpdateBlobsForMinioStorage do
  use Ecto.Migration

  def change do
    alter table(:blobs) do
      # Add storage key to track blob location in MinIO
      add :storage_key, :string

      # Remove binary data field - we'll store in MinIO instead
      remove :data
    end

    # Index for efficient lookups by storage key
    create index(:blobs, [:storage_key])
  end
end
