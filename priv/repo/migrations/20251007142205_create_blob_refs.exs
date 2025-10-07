defmodule AetherPDSServer.Repo.Migrations.CreateBlobRefs do
  use Ecto.Migration

  def change do
    create table(:blob_refs) do
      add :blob_cid, :string, null: false
      add :repository_did, :string, null: false
      # at://did/collection/rkey
      add :record_uri, :string, null: false

      timestamps()
    end

    create unique_index(:blob_refs, [:blob_cid, :record_uri])
    create index(:blob_refs, [:blob_cid])
    create index(:blob_refs, [:repository_did])
    create index(:blob_refs, [:record_uri])
  end
end
