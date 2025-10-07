defmodule AetherPDSServer.Repositories.Commit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "commits" do
    field :repository_did, :string
    field :cid, :string
    field :rev, :string
    field :prev, :string
    field :data, :map

    belongs_to :repository, AetherPDSServer.Repositories.Repository,
      foreign_key: :repository_did,
      references: :did,
      define_field: false

    timestamps()
  end

  @doc false
  def changeset(commit, attrs) do
    commit
    |> cast(attrs, [:repository_did, :cid, :rev, :prev, :data])
    |> validate_required([:repository_did, :cid, :rev, :data])
    |> unique_constraint([:repository_did, :cid])
  end
end
