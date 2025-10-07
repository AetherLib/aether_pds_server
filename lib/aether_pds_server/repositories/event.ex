defmodule AetherPDSServer.Repositories.Event do
  use Ecto.Schema
  import Ecto.Changeset

  schema "events" do
    field :seq, :integer
    field :repository_did, :string
    field :commit_cid, :string
    field :rev, :string
    field :ops, {:array, :map}
    field :time, :utc_datetime

    belongs_to :repository, AetherPDSServer.Repositories.Repository,
      foreign_key: :repository_did,
      references: :did,
      define_field: false

    timestamps()
  end

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:seq, :repository_did, :commit_cid, :rev, :ops, :time])
    |> validate_required([:repository_did, :commit_cid, :rev, :ops, :time])
    |> unique_constraint(:seq)
  end
end
