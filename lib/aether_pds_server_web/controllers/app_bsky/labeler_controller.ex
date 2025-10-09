defmodule AetherPDSServerWeb.AppBsky.LabelerController do
  use AetherPDSServerWeb, :controller

  alias AetherPDSServer.{Accounts, Repositories}

  @doc """
  GET /xrpc/app.bsky.labeler.getServices

  Get information about labeler services.
  Parameters:
  - dids: Array of DIDs for labeler services (required)
  - detailed: Whether to return detailed information (optional, default: false)
  """
  def get_services(conn, %{"dids" => dids} = params) when is_list(dids) do
    current_did = conn.assigns[:current_did]
    detailed = Map.get(params, "detailed", "false") |> parse_boolean(false)

    views =
      dids
      |> Enum.map(fn did ->
        build_labeler_view(did, detailed, current_did)
      end)
      |> Enum.reject(&is_nil/1)

    json(conn, %{views: views})
  end

  # Handle single DID (when Phoenix doesn't parse as list)
  def get_services(conn, %{"dids" => did} = params) when is_binary(did) do
    get_services(conn, Map.put(params, "dids", [did]))
  end

  # Handle missing dids parameter
  def get_services(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "InvalidRequest", message: "Missing required parameter: dids"})
  end

  # Build labeler view
  defp build_labeler_view(did, detailed, current_did) do
    # Try to get the labeler service record
    case Repositories.get_record(did, "app.bsky.labeler.service", "self") do
      nil ->
        nil

      record ->
        # Get the creator profile
        creator = build_labeler_creator_profile(did, current_did)

        # Build base view
        base_view = %{
          uri: "at://#{did}/app.bsky.labeler.service/self",
          cid: record.cid,
          creator: creator,
          likeCount: 0,
          viewer: %{},
          indexedAt: format_timestamp(DateTime.utc_now()),
          labels: []
        }

        # Add policies if detailed view requested
        view =
          if detailed do
            policies = build_labeler_policies(record)

            base_view
            |> Map.put(:policies, policies)
            |> Map.put(:"$type", "app.bsky.labeler.defs#labelerViewDetailed")
          else
            Map.put(base_view, :"$type", "app.bsky.labeler.defs#labelerView")
          end

        view
    end
  end

  # Build creator profile for labeler
  defp build_labeler_creator_profile(did, current_did) do
    case Accounts.get_account_by_did(did) do
      nil ->
        %{
          did: did,
          handle: "unknown.handle",
          viewer: %{
            muted: false,
            blockedBy: false
          },
          labels: []
        }

      account ->
        profile = get_profile_record(did)

        profile_map = %{
          did: account.did,
          handle: account.handle,
          displayName: profile["displayName"],
          description: profile["description"],
          avatar: profile["avatar"],
          indexedAt: format_timestamp(DateTime.utc_now()),
          viewer: build_viewer_state(current_did, did),
          labels: []
        }

        # Add createdAt if available
        profile_map =
          if account.inserted_at do
            created_at =
              account.inserted_at
              |> DateTime.from_naive!("Etc/UTC")
              |> format_timestamp()

            Map.put(profile_map, :createdAt, created_at)
          else
            profile_map
          end

        # Add associated field for labeler
        profile_map =
          Map.put(profile_map, :associated, %{
            labeler: true,
            activitySubscription: %{
              allowSubscriptions: "followers"
            }
          })

        # Add verification (stubbed)
        profile_map =
          Map.put(profile_map, :verification, %{
            verifications: [],
            verifiedStatus: "none",
            trustedVerifierStatus: "none"
          })

        # Remove nil values except for viewer, labels, associated, verification
        profile_map
        |> Enum.reject(fn
          {:viewer, _} -> false
          {:labels, _} -> false
          {:associated, _} -> false
          {:verification, _} -> false
          {_k, v} -> is_nil(v)
        end)
        |> Map.new()
    end
  end

  # Build viewer state
  defp build_viewer_state(nil, _profile_did) do
    %{
      muted: false,
      blockedBy: false
    }
  end

  defp build_viewer_state(current_did, profile_did) when current_did == profile_did do
    %{
      muted: false,
      blockedBy: false
    }
  end

  defp build_viewer_state(current_did, profile_did) do
    # Check if current user follows this profile
    following_uri = check_if_following(current_did, profile_did)
    followed_by_uri = check_if_following(profile_did, current_did)

    viewer = %{
      muted: false,
      blockedBy: false
    }

    viewer = if following_uri, do: Map.put(viewer, :following, following_uri), else: viewer
    viewer = if followed_by_uri, do: Map.put(viewer, :followedBy, followed_by_uri), else: viewer

    viewer
  end

  # Check if follower_did follows subject_did
  defp check_if_following(follower_did, subject_did) do
    case Repositories.list_records(follower_did, "app.bsky.graph.follow", limit: 1000) do
      %{records: records} ->
        records
        |> Enum.find(fn record ->
          record.value["subject"] == subject_did
        end)
        |> case do
          nil -> nil
          record -> "at://#{record.repository_did}/app.bsky.graph.follow/#{record.rkey}"
        end

      _ ->
        nil
    end
  end

  # Build labeler policies
  defp build_labeler_policies(_record) do
    # Get custom label definitions from the record if they exist
    # For now, return the standard Bluesky moderation labels
    %{
      labelValues: [
        "!hide",
        "!warn",
        "porn",
        "sexual",
        "nudity",
        "sexual-figurative",
        "graphic-media",
        "self-harm",
        "sensitive",
        "extremist",
        "intolerant",
        "threat",
        "rude",
        "illicit",
        "security",
        "unsafe-link",
        "impersonation",
        "misinformation",
        "scam",
        "engagement-farming",
        "spam",
        "rumor",
        "misleading",
        "inauthentic"
      ],
      labelValueDefinitions: get_standard_label_definitions()
    }
  end

  # Standard label definitions matching Bluesky's moderation service
  defp get_standard_label_definitions do
    [
      %{
        identifier: "spam",
        severity: "inform",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Spam",
            description: "Unwanted, repeated, or unrelated actions that bother users."
          }
        ]
      },
      %{
        identifier: "impersonation",
        severity: "inform",
        blurs: "none",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Impersonation",
            description: "Pretending to be someone else without permission."
          }
        ]
      },
      %{
        identifier: "scam",
        severity: "alert",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Scam",
            description: "Scams, phishing & fraud."
          }
        ]
      },
      %{
        identifier: "intolerant",
        severity: "alert",
        blurs: "content",
        defaultSetting: "warn",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Intolerance",
            description: "Discrimination against protected groups."
          }
        ]
      },
      %{
        identifier: "self-harm",
        severity: "alert",
        blurs: "content",
        defaultSetting: "warn",
        adultOnly: true,
        locales: [
          %{
            lang: "en",
            name: "Self-Harm",
            description:
              "Promotes self-harm, including graphic images, glorifying discussions, or triggering stories."
          }
        ]
      },
      %{
        identifier: "security",
        severity: "alert",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Security Concerns",
            description:
              "May be unsafe and could harm your device, steal your info, or get your account hacked."
          }
        ]
      },
      %{
        identifier: "misleading",
        severity: "alert",
        blurs: "content",
        defaultSetting: "warn",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Misleading",
            description: "Altered images/videos, deceptive links, or false statements."
          }
        ]
      },
      %{
        identifier: "threat",
        severity: "inform",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Threats",
            description:
              "Promotes violence or harm towards others, including threats, incitement, or advocacy of harm."
          }
        ]
      },
      %{
        identifier: "unsafe-link",
        severity: "alert",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Unsafe link",
            description:
              "Links to harmful sites with malware, phishing, or violating content that risk security and privacy."
          }
        ]
      },
      %{
        identifier: "illicit",
        severity: "alert",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Illicit",
            description: "Promoting or selling potentially illicit goods, services, or activities."
          }
        ]
      },
      %{
        identifier: "misinformation",
        severity: "inform",
        blurs: "content",
        defaultSetting: "warn",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Misinformation",
            description:
              "Spreading false or misleading info, including unverified claims and harmful conspiracy theories."
          }
        ]
      },
      %{
        identifier: "rumor",
        severity: "inform",
        blurs: "none",
        defaultSetting: "warn",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Unconfirmed",
            description: "This claim has not been confirmed by a credible source yet."
          }
        ]
      },
      %{
        identifier: "rude",
        severity: "inform",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Rude",
            description:
              "Rude or impolite, including crude language and disrespectful comments, without constructive purpose."
          }
        ]
      },
      %{
        identifier: "extremist",
        severity: "alert",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Extremist",
            description:
              "Radical views advocating violence, hate, or discrimination against individuals or groups."
          }
        ]
      },
      %{
        identifier: "sensitive",
        severity: "alert",
        blurs: "content",
        defaultSetting: "warn",
        adultOnly: true,
        locales: [
          %{
            lang: "en",
            name: "Sensitive",
            description:
              "May be upsetting, covering topics like substance abuse or mental health issues, cautioning sensitive viewers."
          }
        ]
      },
      %{
        identifier: "engagement-farming",
        severity: "alert",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Engagement Farming",
            description:
              "Insincere content or bulk actions aimed at gaining followers, including frequent follows, posts, and likes."
          }
        ]
      },
      %{
        identifier: "inauthentic",
        severity: "alert",
        blurs: "content",
        defaultSetting: "hide",
        adultOnly: false,
        locales: [
          %{
            lang: "en",
            name: "Inauthentic Account",
            description: "Bot or a person pretending to be someone else."
          }
        ]
      },
      %{
        identifier: "sexual-figurative",
        severity: "none",
        blurs: "media",
        defaultSetting: "show",
        adultOnly: true,
        locales: [
          %{
            lang: "en",
            name: "Sexually Suggestive (Cartoon)",
            description:
              "Art with explicit or suggestive sexual themes, including provocative imagery or partial nudity."
          }
        ]
      }
    ]
  end

  # Get profile record
  defp get_profile_record(did) do
    case Repositories.get_record(did, "app.bsky.actor.profile", "self") do
      nil -> %{}
      record -> record.value
    end
  end

  # Parse boolean with default fallback
  defp parse_boolean("true", _default), do: true
  defp parse_boolean("false", _default), do: false
  defp parse_boolean(value, _default) when is_boolean(value), do: value
  defp parse_boolean(_, default), do: default

  # Format timestamp to ISO8601 with milliseconds
  defp format_timestamp(datetime) do
    datetime
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end
end
