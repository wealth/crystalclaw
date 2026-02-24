require "json"
require "./base"

module CrystalClaw
  module Tools
    class MessageTool < Tool
      include ContextualTool

      @send_callback : Proc(String, String, String, String?, Nil)?
      @sent_in_round : Bool

      def initialize
        @send_callback = nil
        @sent_in_round = false
      end

      def set_send_callback(&block : String, String, String, String? -> Nil)
        @send_callback = block
      end

      def sent_in_round? : Bool
        @sent_in_round
      end

      def reset_round
        @sent_in_round = false
      end

      def name : String
        "message"
      end

      def description : String
        "Send a message to a specific channel and chat. Use this to communicate with users on different platforms."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"channel":{"type":"string","description":"Target channel (e.g., 'telegram', 'discord', 'cli')"},"chat_id":{"type":"string","description":"Target chat/user ID"},"content":{"type":"string","description":"Message content to send"},"media":{"type":"array","items":{"type":"object","properties":{"type":{"type":"string","description":"'photo' or 'audio'"},"url":{"type":"string","description":"URL or local file path to the media"}},"required":["type", "url"]},"description":"Optional media to attach"}},"required":["content"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        content = args["content"]?.try(&.as_s?) || return ToolResult.error("Missing 'content' argument")
        channel = args["channel"]?.try(&.as_s?) || @context_channel
        chat_id = args["chat_id"]?.try(&.as_s?) || @context_chat_id
        media = args["media"]?.try(&.to_json)

        if channel.empty? || chat_id.empty?
          return ToolResult.error("No target channel/chat_id specified")
        end

        callback = @send_callback
        if callback
          begin
            callback.call(channel, chat_id, content, media)
            @sent_in_round = true
            ToolResult.silent("Message sent to #{channel}:#{chat_id}")
          rescue ex
            ToolResult.error("Failed to send message: #{ex.message}")
          end
        else
          ToolResult.error("Message sending not configured")
        end
      end
    end
  end
end
