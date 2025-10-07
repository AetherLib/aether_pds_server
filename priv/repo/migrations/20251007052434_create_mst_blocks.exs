defmodule AetherPDSServer.Repo.Migrations.CreateMstBlocks do
  use Ecto.Migration

  def change do
    create table(:mst_blocks) do
      add :repository_did,
          references(:repositories, column: :did, type: :string, on_delete: :delete_all),
          null: false

      add :cid, :string, null: false
      # Raw encoded MST node data
      add :data, :binary, null: false

      timestamps()
    end

    create unique_index(:mst_blocks, [:repository_did, :cid])
    create index(:mst_blocks, [:cid])
  end
end
