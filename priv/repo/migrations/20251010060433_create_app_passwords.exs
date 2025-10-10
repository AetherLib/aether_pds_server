defmodule AetherPDSServer.Repo.Migrations.CreateAppPasswords do
  use Ecto.Migration

  def change do
    create table(:app_passwords) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :password_hash, :string, null: false
      add :privileged, :boolean, default: false, null: false
      add :created_at, :utc_datetime_usec, null: false

      timestamps(updated_at: false)
    end

    create index(:app_passwords, [:account_id])
    create unique_index(:app_passwords, [:account_id, :name])
  end
end
