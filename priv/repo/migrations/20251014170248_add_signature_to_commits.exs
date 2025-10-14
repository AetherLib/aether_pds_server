defmodule AetherPDSServer.Repo.Migrations.AddSignatureToCommits do
  use Ecto.Migration

  def change do
    alter table(:commits) do
      add :signature, :text
    end
  end
end
