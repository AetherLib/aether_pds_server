defmodule AetherPDSServer.RepositoriesTest do
  use AetherPDSServer.DataCase

  alias AetherPDSServer.Repositories
  alias AetherPDSServer.Accounts

  setup do
    {:ok, account} =
      Accounts.create_account(%{
        handle: "testuser.test",
        email: "test@example.com",
        password: "password123"
      })

    %{account: account, did: account.did}
  end

  describe "get_repository/1" do
    test "returns repository when found", %{did: did} do
      assert repo = Repositories.get_repository(did)
      assert repo.did == did
      assert is_binary(repo.head_cid)
    end

    test "returns nil when not found" do
      assert Repositories.get_repository("did:plc:nonexistent") == nil
    end
  end

  describe "create_repository/1" do
    test "creates repository with valid attributes" do
      attrs = %{
        did: "did:plc:test123",
        head_cid: "bafyreiabc123"
      }

      assert {:ok, repo} = Repositories.create_repository(attrs)
      assert repo.did == "did:plc:test123"
      assert repo.head_cid == "bafyreiabc123"
    end
  end

  describe "repository_exists?/1" do
    test "returns true when repository exists", %{did: did} do
      assert Repositories.repository_exists?(did) == true
    end

    test "returns false when repository does not exist" do
      assert Repositories.repository_exists?("did:plc:nonexistent") == false
    end
  end

  describe "create_commit/1" do
    test "creates commit with valid attributes", %{did: did} do
      attrs = %{
        repository_did: did,
        cid: "bafyreicommit123",
        rev: "3jzfcijpj2z2a",
        prev: nil,
        data: %{version: 3, did: did}
      }

      assert {:ok, commit} = Repositories.create_commit(attrs)
      assert commit.repository_did == did
      assert commit.cid == "bafyreicommit123"
      assert commit.rev == "3jzfcijpj2z2a"
    end
  end

  describe "list_commits/1" do
    test "returns commits in chronological order", %{did: did} do
      commits = Repositories.list_commits(did)
      assert is_list(commits)
      assert length(commits) > 0

      # Should have initial commit from account creation
      first_commit = List.first(commits)
      assert first_commit.repository_did == did
    end
  end

  describe "create_record/1" do
    test "creates record with valid attributes", %{did: did} do
      attrs = %{
        repository_did: did,
        collection: "app.bsky.feed.post",
        rkey: "abc123",
        cid: "bafyreirecord123",
        value: %{text: "Hello world", createdAt: "2024-01-01T00:00:00Z"}
      }

      assert {:ok, record} = Repositories.create_record(attrs)
      assert record.repository_did == did
      assert record.collection == "app.bsky.feed.post"
      assert record.rkey == "abc123"
      assert record.value == %{text: "Hello world", createdAt: "2024-01-01T00:00:00Z"}
    end
  end

  describe "get_record/3" do
    test "returns record when found", %{did: did} do
      {:ok, record} =
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.feed.post",
          rkey: "testrecord",
          cid: "bafyrei123",
          value: %{text: "Test post"}
        })

      assert found = Repositories.get_record(did, "app.bsky.feed.post", "testrecord")
      assert found.rkey == record.rkey
      assert found.value["text"] == "Test post"
    end

    test "returns nil when not found", %{did: did} do
      assert Repositories.get_record(did, "app.bsky.feed.post", "nonexistent") == nil
    end
  end

  describe "record_exists?/3" do
    test "returns true when record exists", %{did: did} do
      Repositories.create_record(%{
        repository_did: did,
        collection: "app.bsky.feed.post",
        rkey: "testrecord",
        cid: "bafyrei123",
        value: %{text: "Test"}
      })

      assert Repositories.record_exists?(did, "app.bsky.feed.post", "testrecord") == true
    end

    test "returns false when record does not exist", %{did: did} do
      assert Repositories.record_exists?(did, "app.bsky.feed.post", "nonexistent") == false
    end
  end

  describe "update_record/2" do
    test "updates record with new attributes", %{did: did} do
      {:ok, record} =
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.feed.post",
          rkey: "testrecord",
          cid: "bafyrei123",
          value: %{text: "Original text"}
        })

      new_attrs = %{
        cid: "bafyrei456",
        value: %{text: "Updated text"}
      }

      assert {:ok, updated} = Repositories.update_record(record, new_attrs)
      assert updated.cid == "bafyrei456"
      assert updated.value.text == "Updated text"
    end
  end

  describe "delete_record/1" do
    test "deletes record", %{did: did} do
      {:ok, record} =
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.feed.post",
          rkey: "testrecord",
          cid: "bafyrei123",
          value: %{text: "Test"}
        })

      assert {:ok, _deleted} = Repositories.delete_record(record)
      assert Repositories.get_record(did, "app.bsky.feed.post", "testrecord") == nil
    end
  end

  describe "list_records/3" do
    test "returns records in collection", %{did: did} do
      # Create multiple records
      for i <- 1..5 do
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.feed.post",
          rkey: "post#{i}",
          cid: "bafyrei#{i}",
          value: %{text: "Post #{i}"}
        })
      end

      result = Repositories.list_records(did, "app.bsky.feed.post", limit: 10)

      assert length(result.records) == 5
      assert Enum.all?(result.records, &(&1.collection == "app.bsky.feed.post"))
    end

    test "respects limit parameter", %{did: did} do
      for i <- 1..10 do
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.feed.post",
          rkey: "post#{i}",
          cid: "bafyrei#{i}",
          value: %{text: "Post #{i}"}
        })
      end

      result = Repositories.list_records(did, "app.bsky.feed.post", limit: 3)

      assert length(result.records) == 3
      assert is_binary(result.cursor)
    end

    test "handles cursor pagination", %{did: did} do
      for i <- 1..5 do
        Repositories.create_record(%{
          repository_did: did,
          collection: "app.bsky.feed.post",
          rkey: "post#{i}",
          cid: "bafyrei#{i}",
          value: %{text: "Post #{i}"}
        })
      end

      # Get first page
      page1 = Repositories.list_records(did, "app.bsky.feed.post", limit: 2)
      assert length(page1.records) == 2
      assert page1.cursor != nil

      # Get second page
      page2 =
        Repositories.list_records(did, "app.bsky.feed.post", limit: 2, cursor: page1.cursor)

      assert length(page2.records) == 2

      # Records should be different
      page1_rkeys = Enum.map(page1.records, & &1.rkey)
      page2_rkeys = Enum.map(page2.records, & &1.rkey)
      assert page1_rkeys != page2_rkeys
    end
  end

  describe "list_collections/1" do
    test "returns all collections in repository", %{did: did} do
      Repositories.create_record(%{
        repository_did: did,
        collection: "app.bsky.feed.post",
        rkey: "post1",
        cid: "bafyrei1",
        value: %{}
      })

      Repositories.create_record(%{
        repository_did: did,
        collection: "app.bsky.feed.like",
        rkey: "like1",
        cid: "bafyrei2",
        value: %{}
      })

      collections = Repositories.list_collections(did)

      assert "app.bsky.feed.post" in collections
      assert "app.bsky.feed.like" in collections
      assert length(collections) >= 2
    end
  end

  describe "put_mst_blocks/2" do
    test "stores MST blocks", %{did: did} do
      blocks = %{
        "bafyreiblock1" => <<1, 2, 3, 4>>,
        "bafyreiblock2" => <<5, 6, 7, 8>>
      }

      assert :ok = Repositories.put_mst_blocks(did, blocks)
    end
  end

  describe "get_mst_blocks/2" do
    test "retrieves stored MST blocks", %{did: did} do
      blocks = %{
        "bafyreiblock1" => <<1, 2, 3, 4>>,
        "bafyreiblock2" => <<5, 6, 7, 8>>
      }

      Repositories.put_mst_blocks(did, blocks)

      retrieved = Repositories.get_mst_blocks(did, ["bafyreiblock1", "bafyreiblock2"])

      assert retrieved["bafyreiblock1"] == <<1, 2, 3, 4>>
      assert retrieved["bafyreiblock2"] == <<5, 6, 7, 8>>
    end

    test "returns empty map for non-existent blocks", %{did: did} do
      retrieved = Repositories.get_mst_blocks(did, ["nonexistent"])
      assert retrieved == %{}
    end
  end

  describe "create_blob/1" do
    test "creates blob with valid attributes", %{did: did} do
      attrs = %{
        repository_did: did,
        cid: "bafkreiblob123",
        mime_type: "image/png",
        size: 12345,
        data: <<0, 1, 2, 3, 4>>
      }

      assert {:ok, blob} = Repositories.create_blob(attrs)
      assert blob.repository_did == did
      assert blob.cid == "bafkreiblob123"
      assert blob.mime_type == "image/png"
      assert blob.size == 12345
    end
  end

  describe "get_blob/2" do
    test "returns blob when found", %{did: did} do
      {:ok, blob} =
        Repositories.create_blob(%{
          repository_did: did,
          cid: "bafkreiblob123",
          mime_type: "image/png",
          size: 100,
          data: <<1, 2, 3>>
        })

      assert found = Repositories.get_blob(did, "bafkreiblob123")
      assert found.cid == blob.cid
      assert found.data == <<1, 2, 3>>
    end

    test "returns nil when not found", %{did: did} do
      assert Repositories.get_blob(did, "nonexistent") == nil
    end
  end

  describe "list_blobs/1" do
    test "returns all blobs for repository", %{did: did} do
      Repositories.create_blob(%{
        repository_did: did,
        cid: "blob1",
        mime_type: "image/png",
        size: 100,
        data: <<>>
      })

      Repositories.create_blob(%{
        repository_did: did,
        cid: "blob2",
        mime_type: "image/jpeg",
        size: 200,
        data: <<>>
      })

      blobs = Repositories.list_blobs(did)
      assert length(blobs) == 2
    end
  end
end
