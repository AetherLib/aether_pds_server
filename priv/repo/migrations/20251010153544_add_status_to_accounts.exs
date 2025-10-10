defmodule AetherPDSServer.Repo.Migrations.AddStatusToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :status, :string, default: "active", null: false
      add :deactivated_at, :utc_datetime_usec
    end

    create index(:accounts, [:status])
  end
end
