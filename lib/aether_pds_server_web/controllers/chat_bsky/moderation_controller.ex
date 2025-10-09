defmodule AetherPDSServerWeb.ChatBsky.ModerationController do
  use AetherPDSServerWeb, :controller

  def get_actor_metadata do
    "chat.bsky.moderation.getActorMetadata"
  end

  def get_message_context do
    "chat.bsky.moderation.getMessageContext"
  end

  def update_actor do
    "chat.bsky.moderation.updateActor"
  end
end
