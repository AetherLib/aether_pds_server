#!/usr/bin/env elixir

# Script to migrate existing did:plc DIDs to did:web format
# Run with: mix run priv/repo/migrate_dids_to_web.exs

alias AetherPDSServer.Repo
alias AetherPDSServer.Accounts.Account
alias AetherPDSServer.Repositories.Repository

import Ecto.Query

IO.puts("Migrating DIDs from did:plc to did:web format...")

# Get all accounts with did:plc DIDs
accounts = Repo.all(from a in Account, where: like(a.did, "did:plc:%"))

IO.puts("Found #{length(accounts)} accounts to migrate")

Enum.each(accounts, fn account ->
  old_did = account.did
  new_did = "did:web:#{account.handle}"

  IO.puts("  #{account.handle}: #{old_did} -> #{new_did}")

  # Update account DID
  {:ok, _} =
    account
    |> Ecto.Changeset.change(%{did: new_did})
    |> Repo.update()

  # Update repository DID if it exists
  case Repo.get_by(Repository, did: old_did) do
    nil ->
      :ok

    repository ->
      repository
      |> Ecto.Changeset.change(%{did: new_did})
      |> Repo.update()

      # Update all records in this repository
      from(r in AetherPDSServer.Repositories.Record, where: r.repository_did == ^old_did)
      |> Repo.update_all(set: [repository_did: new_did])

      # Update all commits in this repository
      from(c in AetherPDSServer.Repositories.Commit, where: c.repository_did == ^old_did)
      |> Repo.update_all(set: [repository_did: new_did])

      # Update all events in this repository
      from(e in AetherPDSServer.Repositories.Event, where: e.repository_did == ^old_did)
      |> Repo.update_all(set: [repository_did: new_did])

      # Update all MST blocks in this repository
      from(m in AetherPDSServer.Repositories.MstBlock, where: m.repository_did == ^old_did)
      |> Repo.update_all(set: [repository_did: new_did])
  end
end)

IO.puts("Migration complete!")
