defmodule AetherPDSServer.Repo.Migrations.CreateSigningKeys do
  use Ecto.Migration

  def change do
    create table(:signing_keys) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :public_key_multibase, :text, null: false
      add :private_key_encrypted, :text, null: false
      add :key_type, :string, null: false, default: "k256"
      add :status, :string, null: false, default: "active"
      add :rotated_at, :utc_datetime_usec

      timestamps()
    end

    create index(:signing_keys, [:account_id])
    create index(:signing_keys, [:account_id, :status])
    create unique_index(:signing_keys, [:account_id], where: "status = 'active'", name: :one_active_key_per_account)
  end
end
