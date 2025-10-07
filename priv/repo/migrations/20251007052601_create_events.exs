defmodule AetherPDSServer.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      # Auto-incrementing sequence number
      add :seq, :bigserial, null: false

      add :repository_did,
          references(:repositories, column: :did, type: :string, on_delete: :delete_all),
          null: false

      add :commit_cid, :string, null: false
      # Revision (TID)
      add :rev, :string, null: false
      # Array of operations (create/update/delete)
      add :ops, {:array, :map}, null: false
      add :time, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:events, [:seq])
    create index(:events, [:repository_did, :time])
    create index(:events, [:time])
  end
end
