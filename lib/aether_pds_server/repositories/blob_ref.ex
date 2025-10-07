defmodule AetherPDSServer.Repositories.BlobRef do
  use Ecto.Schema
  import Ecto.Changeset

  schema "blob_refs" do
    field :blob_cid, :string
    field :repository_did, :string
    field :record_uri, :string

    timestamps()
  end

  @doc false
  def changeset(blob_ref, attrs) do
    blob_ref
    |> cast(attrs, [:blob_cid, :repository_did, :record_uri])
    |> validate_required([:blob_cid, :repository_did, :record_uri])
    |> unique_constraint([:blob_cid, :record_uri])
  end
end
