defmodule AetherPDSServer.Repositories.Blob do
  use Ecto.Schema
  import Ecto.Changeset

  schema "blobs" do
    field :repository_did, :string
    field :cid, :string
    field :mime_type, :string
    field :size, :integer
    field :storage_key, :string

    belongs_to :repository, AetherPDSServer.Repositories.Repository,
      foreign_key: :repository_did,
      references: :did,
      define_field: false

    timestamps()
  end

  @doc false
  def changeset(blob, attrs) do
    blob
    |> cast(attrs, [:repository_did, :cid, :mime_type, :size, :storage_key])
    |> validate_required([:repository_did, :cid, :mime_type, :size, :storage_key])
    |> unique_constraint([:repository_did, :cid])
  end
end
