defmodule AetherPDSServer.Repo.Migrations.CreateRepositories do
  use Ecto.Migration

  def change do
    create table(:repositories, primary_key: false) do
      add :did, :string, primary_key: true, null: false
      add :head_cid, :string

      timestamps()
    end

    create index(:repositories, [:head_cid])
  end
end
