require "json"

module CrystalClaw
  module Session
    struct SessionEntry
      include JSON::Serializable

      property role : String
      property content : String?
      property tool_calls : String? # serialized JSON of tool calls
      property tool_call_id : String?
      property timestamp : Int64

      def initialize(@role, @content = nil, @tool_calls = nil, @tool_call_id = nil, @timestamp = Time.utc.to_unix)
      end
    end

    class Manager
      SESSION_PREFIX = "_sessions/"
      @store : Memory::Store

      def initialize(@store)
      end

      def load_history(session_key : String) : Array(Providers::Message)
        data = @store.get(session_store_key(session_key))
        return [] of Providers::Message if data.empty?

        begin
          entries = Array(SessionEntry).from_json(data)
          entries.map do |entry|
            tool_calls = if tc = entry.tool_calls
                           begin
                             Array(Providers::ToolCall).from_json(tc)
                           rescue
                             nil
                           end
                         end
            Providers::Message.new(
              role: entry.role,
              content: entry.content,
              tool_calls: tool_calls,
              tool_call_id: entry.tool_call_id
            )
          end
        rescue
          [] of Providers::Message
        end
      end

      def save_history(session_key : String, messages : Array(Providers::Message))
        entries = messages.map do |msg|
          tc_json = if tc = msg.tool_calls
                      tc.to_json unless tc.empty?
                    end
          SessionEntry.new(
            role: msg.role,
            content: msg.content,
            tool_calls: tc_json,
            tool_call_id: msg.tool_call_id
          )
        end

        @store.set(session_store_key(session_key), entries.to_json)
      end

      def append_message(session_key : String, msg : Providers::Message)
        history = load_history(session_key)
        history << msg
        # Keep history manageable — keep last 100 messages
        if history.size > 100
          history = history.last(100)
        end
        save_history(session_key, history)
      end

      def clear_session(session_key : String)
        @store.delete(session_store_key(session_key))
      end

      def list_sessions : Array(String)
        @store.list_keys(SESSION_PREFIX).map do |key|
          key.sub(SESSION_PREFIX, "").sub(".json", "")
        end
      end

      private def session_store_key(session_key : String) : String
        # Convert session key like "cli:default" to "_sessions/cli/default"
        parts = session_key.split(":")
        SESSION_PREFIX + parts.join("/")
      end
    end
  end
end
