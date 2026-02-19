module CrystalClaw
  module Routing
    struct RouteResult
      property agent_id : String
      property session_key : String

      def initialize(@agent_id = "default", @session_key = "cli:default")
      end
    end

    def self.resolve(channel : String, sender_id : String, chat_id : String, metadata : Hash(String, String) = {} of String => String) : RouteResult
      # Build session key from channel + chat context
      session_key = build_session_key(channel, sender_id, chat_id)
      RouteResult.new(agent_id: "default", session_key: session_key)
    end

    private def self.build_session_key(channel : String, sender_id : String, chat_id : String) : String
      case channel
      when "cli"
        "cli:#{chat_id.empty? ? "default" : chat_id}"
      when "telegram"
        "telegram:#{chat_id}"
      when "discord"
        "discord:#{chat_id}"
      when "slack"
        "slack:#{chat_id}"
      when "system"
        "system:#{chat_id}"
      else
        "#{channel}:#{chat_id.empty? ? sender_id : chat_id}"
      end
    end
  end
end
