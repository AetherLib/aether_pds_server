defmodule AetherPDSServer.Repositories.MstBlock do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mst_blocks" do
    field :repository_did, :string
    field :cid, :string
    field :data, :binary

    belongs_to :repository, AetherPDSServer.Repositories.Repository,
      foreign_key: :repository_did,
      references: :did,
      define_field: false

    timestamps()
  end

  @doc false
  def changeset(mst_block, attrs) do
    mst_block
    |> cast(attrs, [:repository_did, :cid, :data])
    |> validate_required([:repository_did, :cid, :data])
    |> unique_constraint([:repository_did, :cid])
  end
end
