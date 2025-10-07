defmodule AetherPDSServer.Repositories.Record do
  use Ecto.Schema
  import Ecto.Changeset

  schema "records" do
    field :repository_did, :string
    field :collection, :string
    field :rkey, :string
    field :cid, :string
    field :value, :map

    belongs_to :repository, AetherPDSServer.Repositories.Repository,
      foreign_key: :repository_did,
      references: :did,
      define_field: false

    timestamps()
  end

  @doc false
  def changeset(record, attrs) do
    record
    |> cast(attrs, [:repository_did, :collection, :rkey, :cid, :value])
    |> validate_required([:repository_did, :collection, :rkey, :cid, :value])
    |> unique_constraint([:repository_did, :collection, :rkey])
  end
end
