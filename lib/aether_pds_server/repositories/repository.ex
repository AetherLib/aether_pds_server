defmodule AetherPDSServer.Repositories.Repository do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:did, :string, autogenerate: false}
  @derive {Phoenix.Param, key: :did}

  schema "repositories" do
    field :head_cid, :string

    has_many :commits, AetherPDSServer.Repositories.Commit, foreign_key: :repository_did
    has_many :records, AetherPDSServer.Repositories.Record, foreign_key: :repository_did
    has_many :mst_blocks, AetherPDSServer.Repositories.MstBlock, foreign_key: :repository_did
    has_many :events, AetherPDSServer.Repositories.Event, foreign_key: :repository_did
    has_many :blobs, AetherPDSServer.Repositories.Blob, foreign_key: :repository_did

    timestamps()
  end

  @doc false
  def changeset(repository, attrs) do
    repository
    |> cast(attrs, [:did, :head_cid])
    |> validate_required([:did])
    |> unique_constraint(:did, name: :repositories_pkey)
  end
end
