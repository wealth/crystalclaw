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
      @sessions_dir : String

      def initialize(workspace : String)
        @sessions_dir = File.join(workspace, "sessions")
        Dir.mkdir_p(@sessions_dir)
      end

      def load_history(session_key : String) : Array(Providers::Message)
        path = session_path(session_key)
        return [] of Providers::Message unless File.exists?(path)

        begin
          data = File.read(path)
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

        path = session_path(session_key)
        Dir.mkdir_p(File.dirname(path))
        File.write(path, entries.to_json)
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
        path = session_path(session_key)
        File.delete(path) if File.exists?(path)
      end

      def list_sessions : Array(String)
        sessions = [] of String
        Dir.glob(File.join(@sessions_dir, "**", "*.json")) do |path|
          rel = path.sub(@sessions_dir + "/", "").sub(".json", "")
          sessions << rel
        end
        sessions
      end

      private def session_path(session_key : String) : String
        # Convert session key like "cli:default" to "cli/default.json"
        parts = session_key.split(":")
        File.join(@sessions_dir, parts.join("/") + ".json")
      end
    end
  end
end
