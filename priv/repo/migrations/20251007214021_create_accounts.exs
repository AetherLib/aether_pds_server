defmodule AetherPDSServer.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :did, :string, null: false
      add :handle, :string, null: false
      add :email, :string, null: false
      add :password_hash, :string, null: false

      timestamps()
    end

    create unique_index(:accounts, [:did])
    create unique_index(:accounts, [:handle])
    create unique_index(:accounts, [:email])
  end
end
